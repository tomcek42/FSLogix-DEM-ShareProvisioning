<#
    HostFacts -- die Umgebungs-Seams: sieben fuer das Preflight, fuenf fuer den
    Freigabepfad.

    JEDE FUNKTION IST DUENN UND MACHT GENAU EINEN AUSSENKONTAKT. Das ist kein
    Stil, sondern die technische Umsetzung von D-14: nur so laesst sich jede
    Umgebungstatsache im Test per Mock ersetzen, und nur so kommt die
    Standardsuite ohne UAC-Bestaetigung, ohne Domaenencontroller und ohne ein
    FAT-Volume aus. Waere auch nur eine dieser Abfragen in
    Test-ProvisioningPreflight eingebaut, kostete jede Schnellrueckmeldung
    waehrend der Entwicklung eine Rechteerhoehung.

    Die Aufteilung ist dieselbe wie bei Get-ActualAceSet und
    ConvertTo-ActualAceSet: der Aussenkontakt hier, die Entscheidung daneben.
    Die ENTSCHEIDUNGSLOGIK steht ausschliesslich im Gate und laeuft im Test
    echt; ersetzt wird nur, was die Maschine sagt.

    LOKALISIERUNG: keine dieser Funktionen gibt einen Prinzipalnamen oder einen
    uebersetzten Text weiter. Get-HeldPrivilege liefert Konstantennamen,
    Get-OperatorSid liefert SIDs, Get-VolumeFormat liefert einen .NET-Wert.
    Damit arbeitet das Gate auf deutschem und englischem Server identisch.

    Kein icacls.exe, kein Write-Host, kein Read-Host: die Funktionen geben
    zurueck oder werfen.

    Test-TargetWritable ist die einzige des Preflight-Teils mit einem
    SCHREIBENDEN Aussenkontakt. Sie steht hier und nicht im Gate, damit
    Test-ProvisioningPreflight selbst rein lesend bleibt.

    DIESE DATEI IST ZUGLEICH DIE EINZIGE DES MODULS, IN DER EIN SMB-CMDLET
    VORKOMMT -- genau wie Get-ActualAceSet die einzige ACL-Lesestelle und
    Set-DirectoryAcl die einzige ACL-Schreibstelle ist.
    Tests/ShareWriteSeam.Tests.ps1 nagelt das ueber den AST fest. Ein zweiter
    Freigabeschreibweg hiesse, dass einer von beiden nie gemessen wurde -- das
    Gegenteil dessen, wofuer der Spike aus Plan 03-01 existiert (D-04).

    PHASE 5 (Bestandspruefung) ergaenzt zwei LESENDE Seams: Get-ChildDirectory
    listet die unmittelbaren Unterordner fuer die Erkennung der Ordnerarten,
    Get-ShareList die Freigaben des Servers. Beide ohne try/catch -- die
    Entscheidung ueber einen Fehlschlag trifft der Aufrufer, wie bei
    Get-TargetEntryCount.

    PHASE 7 (Redirections-Ablage) ergaenzt die LESENDE Seam Get-ServerDnsName:
    der Servername fuer den UNC-Hinweis zu RedirXMLSourceFolder (RDX-06). Ein
    reiner Anzeigefall ohne Netzabfrage und ohne Entscheidung.
#>

function Test-IsElevated {
    <#
    .SYNOPSIS
        PRE-01: wahr, wenn die laufende Sitzung erhoeht ist.

    .DESCRIPTION
        Geprueft wird ueber das ENUMGLIED der Rolle, nie ueber einen
        Rollennamen als Zeichenkette: der Name der vordefinierten
        Verwaltungsgruppe ist auf deutschem Windows ein anderer, und ein
        Literal traefe zusaetzlich die IDENT-08-Pruefung.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identitaet = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prinzipal = [System.Security.Principal.WindowsPrincipal]::new($identitaet)

    return [bool] $prinzipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-HeldPrivilege {
    <#
    .SYNOPSIS
        PRE-02: die Namen der Privilegienkonstanten, die die laufende Sitzung
        fuehrt.

    .DESCRIPTION
        AUSGEWERTET WIRD AUSSCHLIESSLICH DIE ERSTE SPALTE (D-12). Die
        Beschreibungsspalte daneben ist lokalisiert und damit unbrauchbar; die
        Konstantennamen sind es nicht.

        Das CSV-Format und nicht die Tabellenform: die Tabellenbreite haengt von
        der Laenge der uebersetzten Beschreibungen ab, und eine spaltenbasierte
        Zerlegung schnitte auf einem deutschen Server anders als auf einem
        englischen. Genau dieser Fehler ist der Grund, warum es dieses Werkzeug
        gibt.

        Zerlegt wird ueber ein Muster auf das erste Anfuehrungszeichenpaar und
        nicht ueber ein Cmdlet der Utility-Sammlung: deren Version wechselt
        unter Windows PowerShell 5.1 je nach geerbtem Modulpfad.

        AUFGERUFEN WIRD MIT VOLLEM PFAD AUS DEM SYSTEMVERZEICHNIS, nicht mit
        dem blossen Namen. Hier gemessen: laeuft die Shell unter einer
        POSIX-Umgebung, stellt deren geerbte PATH-Variable ein gleichnamiges
        Werkzeug mit voellig anderer Argumentsprache voran, und die Abfrage
        liefert stillschweigend nichts. Das Verzeichnis kommt zur Laufzeit aus
        der Umgebung -- kein Pfadliteral, und damit auf jeder Lokalisierung
        richtig.

        Ein fehlgeschlagener Aufruf liefert eine leere Liste. Das ist die
        vorsichtige Richtung: fehlende Konstanten sind ein Abbruchbefund, und
        das Gate haelt lieber zu frueh an als zu spaet.

    .OUTPUTS
        [string[]] -- Konstantennamen, etwa SeRestorePrivilege.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $namen = New-Object System.Collections.Generic.List[string]

    $werkzeug = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, 'whoami.exe')

    $zeilen = @()
    $vorherigeFehlerpolitik = $ErrorActionPreference

    try {
        # Fehlerzeilen wandern in denselben Strom; das Muster unten laesst sie
        # fallen, weil sie nicht mit einem Anfuehrungszeichen beginnen.
        $ErrorActionPreference = 'Continue'
        $zeilen = @(& $werkzeug '/priv' '/fo' 'csv' '/nh' 2>&1)
    }
    catch {
        $zeilen = @()
    }
    finally {
        $ErrorActionPreference = $vorherigeFehlerpolitik
    }

    foreach ($zeile in $zeilen) {

        $text = [string] $zeile

        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $treffer = [System.Text.RegularExpressions.Regex]::Match($text, '^\s*"([^"]+)"')

        if ($treffer.Success) {
            $namen.Add($treffer.Groups[1].Value)
        }
    }

    return $namen.ToArray()
}

function Get-VolumeFormat {
    <#
    .SYNOPSIS
        PRE-03: die Dateisystembezeichnung des Volumes, auf dem der Pfad liegt.

    .DESCRIPTION
        Ueber DriveInfo und ausdruecklich nicht ueber ein Werkzeug mit
        lokalisierter Ausgabe: DriveFormat ist ein .NET-Wert und wird nicht
        uebersetzt.

        DriveInfo braucht eine Laufwerkswurzel. Deshalb laeuft PRE-04 im Gate
        VOR PRE-03 -- auf einem Netzwerkpfad wirft diese Abfrage, statt ihn
        sauber abzuweisen.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $wurzel = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($LiteralPath))

    return [string] ([System.IO.DriveInfo]::new($wurzel).DriveFormat)
}

function Get-ExistingShare {
    <#
    .SYNOPSIS
        PRE-05: der bestehende Freigabeeintrag zu einem Namen, oder nichts.

    .DESCRIPTION
        Ein nicht auffindbarer Name ist KEIN Ausnahmefall, sondern die
        Normalsituation: Fehler werden verschluckt und als "nicht vorhanden"
        gewertet. Die Unterscheidung gleicher gegen anderer Pfad trifft das
        Gate, nicht diese Funktion.

    .OUTPUTS
        Der Freigabeeintrag oder $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    try {
        $treffer = @(Get-SmbShare -Name $Name -ErrorAction SilentlyContinue)
    }
    catch {
        return $null
    }

    if ($treffer.Count -eq 0) { return $null }

    return $treffer[0]
}

function New-ProvisionedShare {
    <#
    .SYNOPSIS
        SHARE-04, SHARE-06: legt die Freigabe mit einem fertigen
        Sicherheitsdeskriptor und abgeschaltetem Offline-Caching an.

    .DESCRIPTION
        GENAU DIE AUFRUFFORM, DIE DIE MESSUNG ALS TRAGEND AUSWEIST:
        Tests/Fixtures/SmbShareSddl.Measured.psd1 belegt auf einem deutsch
        lokalisierten Windows Server, dass -SecurityDescriptor ein SID-basiertes
        SDDL annimmt und dass -CachingMode im selben Aufruf mitgeht. Beides ist
        gemessen und nicht vermutet.

        Der Deskriptor kommt fertig herein. Diese Funktion baut nichts, prueft
        nichts und entscheidet nichts -- sie ist der Aussenkontakt und sonst
        gar nichts, damit Tests/ShareProvisioner.Tests.ps1 sie unprivilegiert
        ersetzen kann (D-14).

        Der Parametername lautet -LiteralPath wie ueberall im Werkzeug (C-09);
        das Cmdlet dahinter kennt nur -Path, weshalb die Uebersetzung genau
        hier und nur hier stattfindet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [string] $SecurityDescriptor,

        [Parameter()]
        [string] $CachingMode = 'None'
    )

    return New-SmbShare -Name $Name -Path $LiteralPath `
        -SecurityDescriptor $SecurityDescriptor -CachingMode $CachingMode -ErrorAction Stop
}

function Set-ProvisionedShare {
    <#
    .SYNOPSIS
        SHARE-08: bringt eine bestehende Freigabe auf denselben
        Sicherheitsdeskriptor und Cachingmodus.

    .DESCRIPTION
        Der Angleichweg zu New-ProvisionedShare. Dieselbe Zusage, dieselbe
        Aufrufform, nur auf einem vorhandenen Eintrag -- eine bestehende
        Freigabe soll angeglichen und nicht entfernt und neu angelegt werden
        (D-07: Entfernen kappte laufende Zugriffe).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $SecurityDescriptor,

        [Parameter()]
        [string] $CachingMode = 'None'
    )

    return Set-SmbShare -Name $Name -SecurityDescriptor $SecurityDescriptor `
        -CachingMode $CachingMode -Force -ErrorAction Stop
}

function Get-ShareAccessEntry {
    <#
    .SYNOPSIS
        SHARE-07: die zurueckgelesenen Freigabeberechtigungen, unveraendert
        durchgereicht.

    .DESCRIPTION
        DIE EINZIGE STELLE DES WERKZEUGS, AN DER UEBERHAUPT EIN LOKALISIERTER
        PRINZIPALNAME AUFTAUCHT -- und sie reicht ihn nur weiter. Die Messung
        haelt fest, dass das Cmdlet Kontonamen in der Sprache der Maschine
        liefert und keine SIDs. Die Uebersetzung in SID-Form macht der Aufrufer
        sofort ueber Resolve-TrusteeSid; hier wird nichts gedeutet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return Get-SmbShareAccess -Name $Name -ErrorAction Stop
}

function Revoke-ShareAccessEntry {
    <#
    .SYNOPSIS
        SHARE-05: entzieht einen Freigabeeintrag ueber seinen Kontonamen.

    .DESCRIPTION
        DER KONTONAME IST EIN DURCHGEREICHTER DATENWERT, KEIN LITERAL UND KEIN
        HERGELEITETER NAME. Der Aufrufer uebergibt genau den Wert, den
        Get-ShareAccessEntry im selben Lauf geliefert hat. Damit faengt das
        Werkzeug die per Default gesetzte Leseberechtigung, ohne ihren
        lokalisierten Namen ueberhaupt kennen zu muessen.

        Das ist ausdruecklich NICHT der in D-04 verworfene zweite Mechanismus:
        dort wuerde ein ERWARTETER Prinzipalname vorwaerts hergeleitet und an
        Grant-SmbShareAccess gegeben. Dieses Cmdlet kommt im Werkzeug nicht vor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $AccountName
    )

    return Revoke-SmbShareAccess -Name $Name -AccountName $AccountName -Force -ErrorAction Stop
}

function Remove-ProvisionedShare {
    <#
    .SYNOPSIS
        SHARE-09: entfernt eine Freigabe.

    .DESCRIPTION
        AUFGERUFEN WIRD SIE AUSSCHLIESSLICH FUER EINE FREIGABE, DIE DERSELBE
        LAUF SELBST ANGELEGT HAT (D-07). Die Entscheidung darueber faellt in
        Invoke-ShareApply am Merkmal CreatedByThisRun -- diese Funktion kennt
        sie nicht und darf sie nicht kennen; sie ist der Aussenkontakt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return Remove-SmbShare -Name $Name -Force -ErrorAction Stop
}

function Get-OperatorSid {
    <#
    .SYNOPSIS
        PRE-06: die SID-Menge der laufenden Identitaet -- Benutzer-SID und alle
        Tokengruppen.

    .DESCRIPTION
        SIDS, KEINE NAMEN. Damit funktioniert die Aussperrungspruefung auf
        beiden Lokalisierungen identisch; ein Namensvergleich schlaege auf
        deutschem Windows fehl, und zwar still.

    .OUTPUTS
        [System.Security.Principal.SecurityIdentifier[]]
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Principal.SecurityIdentifier[]])]
    param()

    $identitaet = [System.Security.Principal.WindowsIdentity]::GetCurrent()

    $menge = New-Object System.Collections.Generic.List[System.Security.Principal.SecurityIdentifier]
    $menge.Add($identitaet.User)

    foreach ($gruppe in @($identitaet.Groups)) {

        if ($gruppe -is [System.Security.Principal.SecurityIdentifier]) {
            $menge.Add($gruppe)
            continue
        }

        try { $menge.Add($gruppe.Translate([System.Security.Principal.SecurityIdentifier])) }
        catch { }
    }

    return $menge.ToArray()
}

function Test-TargetWritable {
    <#
    .SYNOPSIS
        PRE-07: die Schreibprobe -- ist der Zielordner ueberhaupt anlegbar?

    .DESCRIPTION
        DER ZIELORDNER EXISTIERT AN DIESER STELLE NOCH NICHT. PRE-07 laeuft
        ausdruecklich, BEVOR die Struktur angelegt wird; geprobt wird deshalb
        im tiefsten bereits existierenden Verzeichnis-Vorfahren.

        Der Ablauf:

        1. Vom Zielpfad aus aufwaerts, bis ein Vorfahre existiert. EXISTIERT ER
           ALS DATEI UND NICHT ALS VERZEICHNIS, ist der Zielordner nicht
           anlegbar -- Rueckgabe falsch, und es wird nichts angelegt. Ohne
           diesen Zweig liefe der Aufstieg an der Datei vorbei bis zum naechsten
           Verzeichnis, meldete "beschreibbar" und liesse den Lauf erst beim
           eigentlichen Anlegen auflaufen. Also genau nach dem Zeitpunkt, fuer
           den PRE-07 existiert.
        2. Sonst ein Element mit festem Praefix und Zufallsanteil anlegen und im
           finally-Block entfernen. DER ZUFALLSANTEIL IST KEIN SCHMUCK: ein
           fester Name kollidierte mit einem parallelen Lauf und machte aus
           einer Schreibprobe einen Fehlalarm.
        3. Scheitert das Anlegen, ist das ein MESSERGEBNIS und kein Abbruch:
           Rueckgabe falsch, der Grund wandert in das Feld Reason.

        Die Kindzahl des geprueften Vorfahren ist vor und nach dem Aufruf
        dieselbe -- die Probe hinterlaesst nichts.

    .OUTPUTS
        [pscustomobject] mit Writable und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $voll = ''
    try { $voll = [System.IO.Path]::GetFullPath($LiteralPath) }
    catch {
        return [pscustomobject] @{
            Writable = $false
            Reason   = ('Der Zielpfad ist nicht auswertbar: {0}' -f $_.Exception.Message)
        }
    }

    $aktuell = $voll
    $vorfahre = ''

    while (-not [string]::IsNullOrEmpty($aktuell)) {

        if ([System.IO.File]::Exists($aktuell)) {
            return [pscustomobject] @{
                Writable = $false
                Reason   = ('Der Bestandteil "{0}" des Zielpfades existiert als Datei. Unterhalb einer Datei lässt sich kein Ordner anlegen; es wurde nichts angelegt.' -f $aktuell)
            }
        }

        if ([System.IO.Directory]::Exists($aktuell)) {
            $vorfahre = $aktuell
            break
        }

        $aktuell = [System.IO.Path]::GetDirectoryName($aktuell)
    }

    if ([string]::IsNullOrEmpty($vorfahre)) {
        return [pscustomobject] @{
            Writable = $false
            Reason   = ('Zum Zielpfad "{0}" existiert kein einziger Verzeichnis-Vorfahre. Ist das Laufwerk vorhanden und eingebunden?' -f $voll)
        }
    }

    $probe = [System.IO.Path]::Combine($vorfahre,
        ('DemFsAcl-Schreibprobe-' + [guid]::NewGuid().ToString('N')))

    try {
        $null = [System.IO.Directory]::CreateDirectory($probe)
        return [pscustomobject] @{ Writable = $true; Reason = '' }
    }
    catch {
        return [pscustomobject] @{
            Writable = $false
            Reason   = ('Im Ordner "{0}" ließ sich nichts anlegen: {1}' -f $vorfahre, $_.Exception.Message)
        }
    }
    finally {
        try {
            if ([System.IO.Directory]::Exists($probe)) {
                [System.IO.Directory]::Delete($probe, $false)
            }
        }
        catch { }
    }
}

function Get-TargetEntryCount {
    <#
    .SYNOPSIS
        PRE-08: die Zahl der unmittelbaren Kindelemente eines Zielordners --
        ohne Abstieg.

    .DESCRIPTION
        Existiert der Ordner nicht, 0. Sonst die Zahl der Dateien und Ordner
        direkt darunter; ein Abstieg waere der erste Schritt zu der rekursiven
        Reparatur, die das Projekt ausdruecklich ausschliesst.

        KEIN try/catch. Auf einem Ordner ohne Leserecht wirft die Aufzaehlung
        -- Lauf 4 auf dem Zielserver --, und das ist eine Umgebungstatsache,
        keine Entscheidung. Die Entscheidung trifft das Gate: sein Ausnahmenetz
        je Ziel macht daraus einen Befund fuer genau dieses Ziel. Als Seam ist
        der Fall im Test ohne einen Deny-ACE herstellbar.

    .OUTPUTS
        [int]
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    if (-not [System.IO.Directory]::Exists($LiteralPath)) { return 0 }

    return [int] @([System.IO.Directory]::GetFileSystemEntries($LiteralPath)).Count
}

function Get-ChildDirectory {
    <#
    .SYNOPSIS
        Die unmittelbaren Unterordner eines Ordners, ohne Abstieg, sortiert
        ohne Beachtung der Gross-/Kleinschreibung (Phase 5, D-06).

    .DESCRIPTION
        KEIN try/catch -- dasselbe Muster wie Get-TargetEntryCount. Auf einem
        Ordner ohne Leserecht wirft die Aufzaehlung; das ist eine
        Umgebungstatsache, keine Entscheidung. Find-AuditTarget und die
        Orchestrierung entscheiden, was daraus wird.

        Sortiert, damit die Nummerierung im Zuordnungsdialog reproduzierbar
        ist: der Operator waehlt ueber die Nummer.

        Ordner, die zugleich versteckt und Systemordner sind ($RECYCLE.BIN,
        System Volume Information), fehlen (Serverlauf 2026-09-25): sie sind
        nie eine Ablage und fuellten nur die Auswahlliste.

    .OUTPUTS
        [string[]] -- die vollen Pfade.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    # Hidden (2) und System (4) als Zahl: das Enumglied System erschiene im
    # Syntaxbaum als Zeichenkette und traefe die IDENT-08-Pruefung.
    $systemVersteckt = [System.IO.FileAttributes] 6
    $liste = New-Object System.Collections.Generic.List[string]

    foreach ($ordner in [System.IO.DirectoryInfo]::new($LiteralPath).GetDirectories()) {
        if (($ordner.Attributes -band $systemVersteckt) -eq $systemVersteckt) { continue }
        $liste.Add([System.IO.Path]::Combine($LiteralPath, $ordner.Name))
    }

    $pfade = [string[]] $liste.ToArray()
    [System.Array]::Sort($pfade, [System.StringComparer]::OrdinalIgnoreCase)

    return $pfade
}

function Get-ShareList {
    <#
    .SYNOPSIS
        Alle Freigaben des Servers, unveraendert durchgereicht (Phase 5,
        Bestandspruefung).

    .DESCRIPTION
        Ein Fehlschlag WIRFT. Die Orchestrierung faengt ihn, merkt sich den
        Grund und laeuft ohne Freigabeliste weiter (D-15) -- ein nicht
        lesbarer Freigabestand ist ein Befund, kein Abbruchgrund.

        Die Seam steht hier, weil nur diese Datei ein SMB-Cmdlet enthalten
        darf (Tests/ShareWriteSeam.Tests.ps1).
    #>
    [CmdletBinding()]
    param()

    return @(Get-SmbShare -ErrorAction Stop)
}

function Get-ServerDnsName {
    <#
    .SYNOPSIS
        Der Name dieses Servers fuer den UNC-Hinweis zu RedirXMLSourceFolder
        (RDX-06) -- voll qualifiziert, wenn ein primaeres DNS-Suffix besteht.

    .DESCRIPTION
        Ein Anzeigefall und keine Entscheidung: der Formatierer bekommt den
        Namen als Parameter und fragt die Maschine nie selbst (OUT-06).

        Hostname und primaeres DNS-Suffix kommen aus den lokalen
        Netzwerkeigenschaften, ohne Netzabfrage. Fehlt das Suffix, oder
        scheitert das Lesen, gilt der NetBIOS-Name -- eine Anzeige darf den
        Lauf nicht beenden.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $eigenschaften = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        $rechner = [string] $eigenschaften.HostName
        $suffix = [string] $eigenschaften.DomainName

        if ((-not [string]::IsNullOrWhiteSpace($rechner)) -and (-not [string]::IsNullOrWhiteSpace($suffix))) {
            return ('{0}.{1}' -f $rechner.Trim(), $suffix.Trim())
        }
    }
    catch {
        # Anzeige: weiter mit dem NetBIOS-Namen.
    }

    return [System.Environment]::MachineName
}
