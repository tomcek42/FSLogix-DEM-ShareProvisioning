<#
    Test-UserFolder -- der Lesekern des Benutzerordner-Berichts (Phase 8,
    USR-02 bis USR-07).

    Je Profilablage (FSLogix-Profiles, DEMProfiles) wird die erste Ebene unter
    der Freigabewurzel aufgelistet, jeder Ordner seinem Nutzer zugeordnet, sein
    Sicherheitsdeskriptor gelesen und auf drei Befundarten geprueft: Besitzer
    ungleich Nutzer (USR-04), Vererbung abgeschaltet (USR-05), fremder
    expliziter Eintrag (USR-06). Dazu die Zustaende "nicht zuordenbar" und
    "nicht lesbar" (USR-03, USR-07).

    GELESEN WIRD AUSSCHLIESSLICH UEBER Get-ActualAceSet, die eine Lesestelle
    des Werkzeugs; sie liefert Owner und IsProtected bereits mit. Aufgelistet
    wird ausschliesslich ueber die Seam Get-ChildDirectory.

    KEIN ABSTIEG UNTER DIE ERSTE EBENE, KEINE DATEIEN. Unter einem
    Benutzerordner liegen Profilcontainer und Archive; sie werden nie
    aufgelistet, nie gelesen, nie geoeffnet. Gelesen wird nur der
    Sicherheitsdeskriptor des Benutzerordners selbst.

    NICHTS WIRD GESCHRIEBEN -- kein ACL, kein Besitzer, keine Freigabe, keine
    Datei, auch nicht "harmlos" bei einem Befund. Das nachtraegliche Setzen
    unterhalb der Wurzel ist das Sicherheitsverbot Nummer eins und bleibt
    OPS-03 vorbehalten. Tests/UserFolderReadOnly.Tests.ps1 belegt das ueber
    die Aufrufhuelle.

    SIDS WERDEN ALS SIDS VERGLICHEN, nie ueber lokalisierte Namen. Namen
    entstehen erst in der Orchestrierung und nur zur Anzeige.

    Kein Eingabe- und kein Ausgabe-Cmdlet: die Funktionen geben zurueck oder
    werfen.

    DIE VERWALTUNGSREGEL (Entscheidung Projektinhaber 2026-09-29, "Dulden,
    aber anzeigen"). Jeder explizite Eintrag mit einer SID ungleich der des
    Nutzers ist ein fremder Eintrag -- mit genau einer Ausnahme: ein
    ZULASSENDER expliziter Eintrag des Systemkontos, der lokalen
    Administratorengruppe oder der gebundenen Gruppe der Administratoren ist
    geduldet, kein Befund, wird aber je Konto gezaehlt und mit Namen
    angezeigt. Begruendung: Microsofts eigenes SIDDirSDDL-Beispiel fuer FSLogix
    schreibt genau diese Konten explizit in jeden Benutzerordner, und diese
    Konten haben ueber die Wurzel bzw. ihre Privilegien ohnehin Vollzugriff --
    ein expliziter Eintrag erweitert keinen Zugriff. Ein verweigernder Eintrag
    faellt nie unter die Duldung. Die Menge der Verwaltungskonten ist dieselbe
    wie die der erwarteten Wurzelbesitzer (Test-AuditOwnerExpected), eine
    Wahrheit. Aenderung nur durch den Projektinhaber.

    Widerspricht die Messung im Serverlauf der Regel -- setzen FSLogix oder
    FlexEngine regelmaessig einen expliziten Eintrag fuer ein anderes Konto
    oder einen anderen Besitzer als den Nutzer --, bleibt der Bericht laut:
    jeder betroffene Ordner ist auffaellig, das Konto steht mit Namen in der
    Tabelle, der Rueckgabewert ist 2. Die Regel wird dann nicht still
    erweitert; eine Erweiterung ist eine eigene Entscheidung des
    Projektinhabers nach Sichtung der Mitschrift.

    Der Besitzer bekommt keine Duldung: Besitzer ungleich Nutzer ist immer ein
    Befund, auch fuer ein Verwaltungskonto -- genau das ist der Fall "Ordner
    vorab vom Admin angelegt".
#>

function Select-UserFolderRoot {
    <#
    .SYNOPSIS
        Die Profilablagen einer Zielliste: die Ziele der Ordnerarten
        FSLogix-Profiles und DEMProfiles, in unveraenderter Reihenfolge.

    .OUTPUTS
        [object[]] -- auch leer; der Aufrufer fasst in @(...).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target
    )

    $auswahl = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in @($Target)) {

        if ($null -eq $ziel) { continue }

        $art = [string] $ziel.Kind
        if ([string]::Equals($art, 'FSLogix-Profiles', [System.StringComparison]::Ordinal) -or
            [string]::Equals($art, 'DEMProfiles', [System.StringComparison]::Ordinal)) {
            $auswahl.Add($ziel)
        }
    }

    return $auswahl.ToArray()
}

function Get-UserFolderAssignment {
    <#
    .SYNOPSIS
        Ordnet einen Benutzerordner ueber seinen Namen einem Nutzer zu
        (USR-03).

    .DESCRIPTION
        FSLogix: <SID>_<Name> oder <Name>_<SID>, die SID ohne Beachtung der
        Gross-/Kleinschreibung; passt die erste Form, gilt sie. Die SID wird
        nur syntaktisch geprueft, nicht aufgeloest -- ein geloeschter Nutzer
        bleibt zuordenbar. Jeder andere Name (auch eine nackte SID oder ein
        eigenes SIDDirNamePattern) ist nicht zuordenbar.

        DEMProfiles: der Ordnername ist der Kontoname und geht unveraendert an
        Resolve-TrusteeSid. Jede Ausnahme heisst nicht zuordenbar -- kein
        Sonderpfad fuer einen nicht erreichbaren Domaenencontroller.

    .OUTPUTS
        [pscustomobject] mit Sid (leer, wenn nicht zuordenbar), Label und
        Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'DEMProfiles')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ([string]::Equals($Kind, 'DEMProfiles', [System.StringComparison]::Ordinal)) {
        try {
            $sid = Resolve-TrusteeSid -InputValue $Name
            return [pscustomobject] @{ Sid = [string] $sid.Value; Label = $Name; Reason = '' }
        }
        catch {
            return [pscustomobject] @{
                Sid    = ''
                Label  = $Name
                Reason = ('Kontoname nicht auflösbar: {0}' -f $_.Exception.Message)
            }
        }
    }

    $optionen = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant

    $sidText = ''
    $label = ''

    $vorn = [regex]::Match($Name, '^(S-1-\d+(?:-\d+)+)_(.+)$', $optionen)
    if ($vorn.Success) {
        $sidText = $vorn.Groups[1].Value
        $label = $vorn.Groups[2].Value
    }
    else {
        $hinten = [regex]::Match($Name, '^(.+)_(S-1-\d+(?:-\d+)+)$', $optionen)
        if ($hinten.Success) {
            $sidText = $hinten.Groups[2].Value
            $label = $hinten.Groups[1].Value
        }
    }

    if ([string]::IsNullOrEmpty($sidText)) {
        return [pscustomobject] @{
            Sid    = ''
            Label  = $Name
            Reason = 'kein SID im Namen (erwartet <SID>_<Name> oder <Name>_<SID>)'
        }
    }

    try {
        $sid = [System.Security.Principal.SecurityIdentifier]::new($sidText.ToUpperInvariant())
    }
    catch {
        return [pscustomobject] @{
            Sid    = ''
            Label  = $Name
            Reason = ('ungültige SID im Namen: {0}' -f $_.Exception.GetBaseException().Message)
        }
    }

    # Rueckweg (gemessen): der Konstruktor kappt eine zu grosse
    # Unterautoritaet still, S-1-5-4294967296 wird zu S-1-5-4294967295 --
    # das waere ein anderer Nutzer. Nur eine SID, die sich unveraendert
    # zurueckliest, ordnet zu.
    $gelesen = [string] $sid.Value
    if (-not [string]::Equals($gelesen, $sidText.ToUpperInvariant(), [System.StringComparison]::Ordinal)) {
        return [pscustomobject] @{
            Sid    = ''
            Label  = $Name
            Reason = ('ungültige SID im Namen: "{0}" liest sich als {1} zurück' -f $sidText, $gelesen)
        }
    }

    return [pscustomobject] @{ Sid = $gelesen; Label = $label; Reason = '' }
}

function Test-UserFolderAdminSid {
    <#
    .SYNOPSIS
        Die Verwaltungsregel (USR-06): wahr fuer das Systemkonto, die lokale
        Administratorengruppe und die gebundene Gruppe der Administratoren.

    .DESCRIPTION
        Dieselbe Menge wie die erwarteten Wurzelbesitzer der
        Bestandspruefung -- deshalb ein Aufruf von Test-AuditOwnerExpected und
        kein zweites Verzeichnis. Entscheidung Projektinhaber 2026-09-29;
        Aenderung nur durch den Projektinhaber.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [string] $Sid
    )

    return [bool] (Test-AuditOwnerExpected -Target $Target -Sid $Sid)
}

function Test-UserFolder {
    <#
    .SYNOPSIS
        Bewertet einen Benutzerordner: Zuordnung, Lesen, Besitzer, Vererbung,
        fremde explizite Eintraege (USR-03 bis USR-07).

    .DESCRIPTION
        Genau ein Zustand je Ordner: Clean, Finding, Unassigned oder
        Unreadable. Ein nicht zuordenbarer Ordner wird nicht gelesen und ist
        kein Befund. Ein Lesefehler wird zum Zustand Unreadable mit Grund; der
        Aufrufer macht mit dem naechsten Ordner weiter.

        Gelesen wird mit -ErrorAction Stop: im Modullauf gilt die
        Stop-Vorgabe des Einstiegsskripts nicht, und ein "Pfad nicht gefunden"
        kaeme sonst als nicht abbrechender Fehler auf die Konsole.

    .OUTPUTS
        [pscustomobject] -- der Ordnersatz mit Name, Path, State, UserSid,
        UserLabel, OwnerSid, Finding, ForeignSid, ToleratedSid, Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $vergleich = [System.StringComparison]::Ordinal
    $zuordnung = Get-UserFolderAssignment -Kind ([string] $Target.Kind) -Name $Name

    $satz = [ordered] @{
        Name         = $Name
        Path         = $LiteralPath
        State        = ''
        UserSid      = [string] $zuordnung.Sid
        UserLabel    = [string] $zuordnung.Label
        OwnerSid     = ''
        Finding      = [string[]] @()
        ForeignSid   = [string[]] @()
        ToleratedSid = [string[]] @()
        Reason       = ''
    }

    if ([string]::IsNullOrEmpty([string] $zuordnung.Sid)) {
        $satz.State = 'Unassigned'
        $satz.Reason = [string] $zuordnung.Reason
        return [pscustomobject] $satz
    }

    try {
        $ist = Get-ActualAceSet -LiteralPath $LiteralPath -ErrorAction Stop
    }
    catch {
        $satz.State = 'Unreadable'
        $satz.Reason = [string] $_.Exception.Message
        return [pscustomobject] $satz
    }

    $nutzer = [string] $zuordnung.Sid
    $befunde = New-Object System.Collections.Generic.List[string]
    $fremd = New-Object System.Collections.Generic.List[string]
    $geduldet = New-Object System.Collections.Generic.List[string]

    if ($null -ne $ist.Owner) { $satz.OwnerSid = [string] $ist.Owner.Value }
    if (-not [string]::Equals([string] $satz.OwnerSid, $nutzer, $vergleich)) { $befunde.Add('Owner') }

    if ([bool] $ist.IsProtected) { $befunde.Add('InheritanceDisabled') }

    $zulassend = [System.Security.AccessControl.AccessControlType]::Allow

    foreach ($eintrag in @($ist.Aces)) {

        if ($null -eq $eintrag) { continue }

        $sid = [string] $eintrag.IdentityReference.Value
        if ([string]::Equals($sid, $nutzer, $vergleich)) { continue }

        if (($eintrag.AccessControlType -eq $zulassend) -and (Test-UserFolderAdminSid -Target $Target -Sid $sid)) {
            if (-not $geduldet.Contains($sid)) { $geduldet.Add($sid) }
            continue
        }

        if (-not $fremd.Contains($sid)) { $fremd.Add($sid) }
    }

    if ($fremd.Count -gt 0) { $befunde.Add('ForeignAce') }

    $satz.Finding = $befunde.ToArray()
    $satz.ForeignSid = $fremd.ToArray()
    $satz.ToleratedSid = $geduldet.ToArray()

    if ($befunde.Count -gt 0) { $satz.State = 'Finding' }
    else { $satz.State = 'Clean' }

    return [pscustomobject] $satz
}

function Test-UserFolderSet {
    <#
    .SYNOPSIS
        Bewertet die erste Ebene unter einer Profilablage (USR-02, USR-07).

    .DESCRIPTION
        Aufgelistet wird genau einmal, ueber Get-ChildDirectory: unmittelbare
        Unterordner, keine Dateien, sortiert ordinal ohne Beachtung der
        Gross-/Kleinschreibung. Wirft schon das Auflisten, traegt der
        Ablagebericht ListError und keine Ordner.

        Ein Unterordner, dessen Pfad gleich dem Pfad eines ausgenommenen Ziels
        ist, ist selbst eine Ablage und kein Benutzerordner: er wird
        uebersprungen und nicht gezaehlt. Verglichen wird ueber
        ConvertTo-PfadPraefix, ohne Beachtung der Gross-/Kleinschreibung.

    .OUTPUTS
        [pscustomobject] -- der Ablagebericht mit Kind, Path, ListError und
        Folder (die Ordnersaetze in Listenreihenfolge).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $ExcludePath = @()
    )

    $art = [string] $Target.Kind
    if (-not ([string]::Equals($art, 'FSLogix-Profiles', [System.StringComparison]::Ordinal) -or
            [string]::Equals($art, 'DEMProfiles', [System.StringComparison]::Ordinal))) {
        throw [System.ArgumentException]::new(
            ('Benutzerordner gibt es nur unter FSLogix-Profiles und DEMProfiles, nicht unter "{0}".' -f $art))
    }

    $ablage = [string] $Target.Path

    try {
        $pfade = @(Get-ChildDirectory -LiteralPath $ablage)
    }
    catch {
        return [pscustomobject] @{
            Kind      = $art
            Path      = $ablage
            ListError = [string] $_.Exception.Message
            Folder    = [object[]] @()
        }
    }

    $ausgenommen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pfad in @($ExcludePath)) {
        if ([string]::IsNullOrWhiteSpace($pfad)) { continue }
        $null = $ausgenommen.Add((ConvertTo-PfadPraefix -LiteralPath $pfad))
    }

    $ordner = New-Object System.Collections.Generic.List[object]

    foreach ($pfad in $pfade) {

        if ([string]::IsNullOrEmpty($pfad)) { continue }
        if ($ausgenommen.Contains((ConvertTo-PfadPraefix -LiteralPath $pfad))) { continue }

        $blatt = [System.IO.Path]::GetFileName($pfad)
        $ordner.Add((Test-UserFolder -Target $Target -LiteralPath $pfad -Name $blatt))
    }

    return [pscustomobject] @{
        Kind      = $art
        Path      = $ablage
        ListError = ''
        Folder    = $ordner.ToArray()
    }
}

function Get-UserFolderCount {
    <#
    .SYNOPSIS
        Die Zahlen eines Ablageberichts: geprueft, je Zustand, geduldet
        (USR-08).

    .DESCRIPTION
        Checked ist die Summe der vier Zustaende -- jeder aufgelistete, nicht
        ausgenommene Ordner genau einmal. Tolerated ist die Zahl der Ordner mit
        mindestens einem geduldeten Eintrag. ToleratedAccount zaehlt JE KONTO
        die Ordner, in denen es geduldet vorkommt, in der Reihenfolge des
        ersten Vorkommens (Entscheidung Projektinhaber 2026-09-29: je Konto,
        nie als eine Gesamtzahl).

    .OUTPUTS
        [pscustomobject] mit Checked, Clean, Finding, Unassigned, Unreadable,
        Tolerated und ToleratedAccount (Array aus Sid und Count).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Report
    )

    $zahl = @{ Clean = 0; Finding = 0; Unassigned = 0; Unreadable = 0 }
    $geduldet = 0
    $jeKonto = @{}
    $reihe = New-Object System.Collections.Generic.List[string]

    foreach ($ordner in @($Report.Folder)) {

        if ($null -eq $ordner) { continue }

        $zustand = [string] $ordner.State
        if ($zahl.ContainsKey($zustand)) { $zahl[$zustand] = [int] $zahl[$zustand] + 1 }

        $sids = @($ordner.ToleratedSid | Where-Object { -not [string]::IsNullOrEmpty([string] $_) } | Select-Object -Unique)
        if ($sids.Count -gt 0) { $geduldet++ }

        foreach ($sid in $sids) {
            $schluessel = [string] $sid
            if (-not $jeKonto.ContainsKey($schluessel)) {
                $jeKonto[$schluessel] = 0
                $reihe.Add($schluessel)
            }
            $jeKonto[$schluessel] = [int] $jeKonto[$schluessel] + 1
        }
    }

    $konten = New-Object System.Collections.Generic.List[object]
    foreach ($sid in $reihe) {
        $konten.Add([pscustomobject] @{ Sid = $sid; Count = [int] $jeKonto[$sid] })
    }

    return [pscustomobject] @{
        Checked          = [int] ($zahl.Clean + $zahl.Finding + $zahl.Unassigned + $zahl.Unreadable)
        Clean            = [int] $zahl.Clean
        Finding          = [int] $zahl.Finding
        Unassigned       = [int] $zahl.Unassigned
        Unreadable       = [int] $zahl.Unreadable
        Tolerated        = [int] $geduldet
        ToleratedAccount = $konten.ToArray()
    }
}

function Get-UserFolderDisplaySid {
    <#
    .SYNOPSIS
        Die SIDs, fuer die der Bericht einen Anzeigenamen braucht: Besitzer mit
        Besitzerbefund, fremde und geduldete Konten.

    .DESCRIPTION
        Eindeutig und ordinal sortiert. Aufgeloest wird hier nichts -- die
        Namen entstehen in der Orchestrierung und nur zur Anzeige (IDENT-06).

    .OUTPUTS
        [string[]] -- auch leer; der Aufrufer fasst in @(...).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Report
    )

    $menge = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    foreach ($bericht in @($Report)) {

        if ($null -eq $bericht) { continue }

        foreach ($ordner in @($bericht.Folder)) {

            if ($null -eq $ordner) { continue }

            if ((@($ordner.Finding) -ccontains 'Owner') -and -not [string]::IsNullOrEmpty([string] $ordner.OwnerSid)) {
                $null = $menge.Add([string] $ordner.OwnerSid)
            }
            foreach ($sid in @($ordner.ForeignSid) + @($ordner.ToleratedSid)) {
                if (-not [string]::IsNullOrEmpty([string] $sid)) { $null = $menge.Add([string] $sid) }
            }
        }
    }

    $liste = New-Object System.Collections.Generic.List[string]
    foreach ($sid in $menge) { $liste.Add($sid) }

    $sids = $liste.ToArray()
    [System.Array]::Sort($sids, [System.StringComparer]::Ordinal)

    return $sids
}

function ConvertTo-UserFolderResult {
    <#
    .SYNOPSIS
        Die Ergebnissaetze der Stufe UserFolder fuer den Rueckgabewert
        (USR-07, Vorarbeit USR-10).

    .DESCRIPTION
        Je Ordner ein Satz mit der Ordnerart der Ablage und dem Pfad des
        Ordners. Error fuer Finding und Unreadable -- wie ein nicht lesbares
        Ziel in der Bestandspruefung --, OK fuer Clean und Unassigned (USR-03:
        ein nicht zuordenbarer Ordner ist kein Befund). Eine nicht
        auflistbare Ablage ergibt einen Error-Satz mit dem Pfad der Ablage.

        Detail traegt je Befund einen Datensatz mit Finding, Reason und
        Message; Owner zusaetzlich Expected und Actual, ForeignAce je fremder
        SID einen eigenen Datensatz mit Sid.

    .OUTPUTS
        [object[]] -- die Ergebnissaetze in Ablage- und Ordnerreihenfolge.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Report
    )

    $saetze = New-Object System.Collections.Generic.List[object]

    foreach ($bericht in @($Report)) {

        if ($null -eq $bericht) { continue }

        $art = [string] $bericht.Kind

        if (-not [string]::IsNullOrEmpty([string] $bericht.ListError)) {
            $text = 'Die Ablage "{0}" lässt sich nicht auflisten: {1}' -f [string] $bericht.Path, [string] $bericht.ListError
            $saetze.Add((New-ProvisioningResult -Kind $art -Path ([string] $bericht.Path) -Stage 'UserFolder' -Status 'Error' -Message $text -Detail @(
                        [pscustomobject] @{ Finding = 'Unreadable'; Reason = 'ListNotReadable'; Message = $text })))
            continue
        }

        foreach ($ordner in @($bericht.Folder)) {

            if ($null -eq $ordner) { continue }

            $pfad = [string] $ordner.Path
            $zustand = [string] $ordner.State

            if ([string]::Equals($zustand, 'Unassigned', [System.StringComparison]::Ordinal)) {
                $text = 'Benutzerordner "{0}" ist keinem Nutzer zuzuordnen: {1}' -f $pfad, [string] $ordner.Reason
                $saetze.Add((New-ProvisioningResult -Kind $art -Path $pfad -Stage 'UserFolder' -Status 'OK' -Message $text))
                continue
            }

            if ([string]::Equals($zustand, 'Unreadable', [System.StringComparison]::Ordinal)) {
                $text = 'Benutzerordner "{0}" ist nicht lesbar: {1}' -f $pfad, [string] $ordner.Reason
                $saetze.Add((New-ProvisioningResult -Kind $art -Path $pfad -Stage 'UserFolder' -Status 'Error' -Message $text -Detail @(
                            [pscustomobject] @{ Finding = 'Unreadable'; Reason = 'FolderNotReadable'; Message = $text })))
                continue
            }

            if (-not [string]::Equals($zustand, 'Finding', [System.StringComparison]::Ordinal)) {
                $text = 'Benutzerordner "{0}" (Nutzer {1}) ist unauffällig.' -f $pfad, [string] $ordner.UserLabel
                $saetze.Add((New-ProvisioningResult -Kind $art -Path $pfad -Stage 'UserFolder' -Status 'OK' -Message $text))
                continue
            }

            $teile = New-Object System.Collections.Generic.List[string]
            $detail = New-Object System.Collections.Generic.List[object]
            $befunde = @($ordner.Finding)

            if ($befunde -ccontains 'Owner') {
                $besitzer = [string] $ordner.OwnerSid
                if ([string]::IsNullOrEmpty($besitzer)) { $besitzer = '(nicht gelesen)' }
                $teil = 'Besitzer ist {0} statt {1}' -f $besitzer, [string] $ordner.UserSid
                $teile.Add($teil)
                $detail.Add([pscustomobject] @{
                        Finding  = 'Owner'
                        Reason   = 'OwnerNotUser'
                        Expected = [string] $ordner.UserSid
                        Actual   = [string] $ordner.OwnerSid
                        Message  = $teil
                    })
            }

            if ($befunde -ccontains 'InheritanceDisabled') {
                $teil = 'Vererbung abgeschaltet -- die Rechte der Wurzel kommen nicht an (gewollt nur, wenn FSLogix die Ordner über SIDDirSDDL anlegt)'
                $teile.Add($teil)
                $detail.Add([pscustomobject] @{ Finding = 'InheritanceDisabled'; Reason = 'DaclProtected'; Message = $teil })
            }

            if ($befunde -ccontains 'ForeignAce') {
                $fremd = @($ordner.ForeignSid | ForEach-Object { [string] $_ })
                $teile.Add(('fremder expliziter Eintrag für {0}' -f ($fremd -join ', ')))
                foreach ($sid in $fremd) {
                    $detail.Add([pscustomobject] @{
                            Finding = 'ForeignAce'
                            Reason  = 'ExplicitForeignSid'
                            Sid     = $sid
                            Message = ('fremder expliziter Eintrag für {0}' -f $sid)
                        })
                }
            }

            $text = 'Benutzerordner "{0}" (Nutzer {1}): {2}.' -f $pfad, [string] $ordner.UserLabel, ($teile.ToArray() -join '; ')
            $saetze.Add((New-ProvisioningResult -Kind $art -Path $pfad -Stage 'UserFolder' -Status 'Error' -Message $text -Detail $detail.ToArray()))
        }
    }

    return $saetze.ToArray()
}
