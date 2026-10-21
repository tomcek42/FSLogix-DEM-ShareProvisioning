<#
    Read-ProvisioningTarget -- die Zielerhebung von Weg 1 (FLOW-01 bis
    FLOW-06, SHARE-02, D-05, D-06, D-07, D-08; Phase 9: NAV-01, NAV-02,
    ERF-01 bis ERF-05).

    ERST ALLES ERHEBEN, DANN GENAU EIN PLAN (D-06). Nicht je Ordnerart
    durchfragen und einzeln bestaetigen -- der Operator soll die vollstaendige
    Auswirkung sehen, bevor irgendetwas geschrieben wird (FLOW-07).

    FUENF SCHRITTE MIT KOPF "[Schritt x/y]" (Phase 9, NAV-01, NAV-02):
    Komponenten, Gruppen, FSLogix konfigurieren, DEM konfigurieren, Pruefung
    und Ausfuehrung. Die Schrittfolge der gewaehlten Auswahl liefert
    Get-WizardStepSequence; ein Schritt ohne gewaehlte Ordnerart entfaellt
    und zaehlt nicht mit. Die Gruppen stehen seit Phase 9 in EINEM Schritt
    vor allen Pfaden (Read-GroupStep), je Produkt jede Rolle genau einmal --
    FSLogix und DEM behalten getrennte Rollenspeicher, und DEM bietet die
    FSLogix-Wahl weiterhin sichtbar an (G-04-4a). Nach jeder erfassten
    Ordnerart steht ein Kurzueberblick direkt auf der Ausgabenaht (ERF-05).
    Die Koepfe reisen als Promptkontext mit der ersten Frage ihres Schritts
    (G-04-3a, G-04-4d); die Kanalregel steht in Read-WizardStep.ps1.

    KOLLISIONEN IM LAUF WERDEN SOFORT ERNEUT ERFRAGT (G-04-1b, Dialogseite).
    Ein Pfad, der mit einem bereits erhobenen Ziel zusammenfaellt oder mit ihm
    ineinander liegt, und ein bereits vergebener Freigabename werden ueber
    Get-TargetConflict erkannt -- dieselbe Funktion, die das Preflight
    benutzt. Preflight und Dialog fragen dieselbe Regel, nur die Darstellung
    ist verschieden: das Preflight behaelt den Satz aus Message, der Dialog
    baut mit Format-ConflictHint aus den Feldern desselben Datensatzes einen
    gegliederten Hinweis in kurzen Zeilen (G-04-4f) -- fuer einen Pfad mit
    [FEHLER] (VAL-01), fuer einen Freigabenamen als HINWEIS. Die Belegung auf
    dem SERVER entscheidet weiterhin PRE-05 im Preflight.

    DIE RUECKGABE TRAEGT KEIN Desired. Die Dialogschicht rechnet nichts
    ACL-Fachliches; Expand-AclTemplate ruft die Orchestrierung. Damit bleibt
    diese Schicht duenn genug fuer den spaeter nachruestbaren unattended Modus.

    JEDE PFADEINGABE LAEUFT DURCH Resolve-OperatorPath und durch nichts anderes
    (FLOW-05) -- die Neuanlage, die Bestandswurzel UND der aus der
    Nummernliste zusammengesetzte Pfad. Ob ein Freigabeziel taugt, fragt der
    Dialog seit Phase 9 (VAL-01) FRUEH ueber Get-TargetPathInputError --
    DIESELBEN Praedikate wie das Preflight (Test-TargetPathSafety,
    Get-VolumeFormat, Get-TargetConflict), keine eigene Pfadrechnung. Das
    Preflight bleibt unveraendert die Instanz vor dem Schreiben (VAL-02).
    Nicht geprueft wird der Startpfad des Bestandswegs: er ist Ausgangspunkt
    einer Auflistung, kein Freigabeziel.

    AUS DER ORDNERSTRUKTUR WIRD NICHTS GERATEN (D-08). Ein leerer
    Bestandsordner ist genau der Greenfield-Normalfall und wuerde von jeder
    Heuristik falsch eingeordnet -- und ein falsch geratener Wurzelpfad ist bei
    einem Werkzeug, das ACLs setzt, teuer. Ohne FSLogix-Profiles bekommt die
    Redirections-Ablage deshalb keinen Pfadvorschlag.
#>

function Read-ProvisioningTarget {
    <#
    .SYNOPSIS
        Erhebt die zu provisionierenden Ziele in den Schritten 1 bis 4 von
        Weg 1 (Phase 9, NAV-01, NAV-02, ERF-01 bis ERF-05).

    .DESCRIPTION
        Je Ziel entsteht ein Datensatz mit Kind, Path, ShareName, IsExisting,
        Binding, AclOptGroup und ShareOptGroup -- ausdruecklich OHNE Desired.

        1. Komponenten: die Umschaltliste (Read-ProvisioningKind).
        2. Gruppen: jede noetige Rolle je Produkt genau einmal, Uebersicht,
           "Weiter? [J/n]" (Read-GroupStep).
        3. FSLogix konfigurieren (nur mit FSLogix-Ordnerart): mit
           FSLogix-Profiles die Opt-in-Frage, dann Bestand, Pfad und
           Freigabename; mit FSLogix-Redirections deren Ablage -- mit
           Profilablage schlaegt sie den Nachbarordner FSLogix-Redirections
           vor, ohne sie gibt es keinen Vorschlag (D-08).
        4. DEM konfigurieren (nur mit DEM-Ordnerart): je DEM-Ordnerart in
           fester Reihenfolge Bestand, Pfad und Freigabename, zwischen zweien
           eine Leerzeile.

        Nach jedem erfassten Ziel der Kurzueberblick direkt auf der
        Ausgabenaht (ERF-05, Entscheidung Projektinhaber 2026-09-30). Den
        Kopf von Schritt 5 schreibt Invoke-DemFsRunMode vor dem Plan. Die
        Rueckgabe behaelt die Auswahlreihenfolge.

    .PARAMETER Capability
        Die vorab erhobene Konsolenkapazitaet des Laufs (D-14) fuer den
        Kurzueberblick auf der Ausgabenaht. Fehlt sie, waehlt
        Write-OperatorLine selbst.

    .OUTPUTS
        Sammlung von Zieldatensaetzen. Leer, wenn keine Ordnerart gewaehlt wurde.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    $kapazitaet = $Capability

    # --- Schritt 1: Komponenten --------------------------------------------
    $auswahl = @(Read-ProvisioningKind -Capability $kapazitaet)

    if ($auswahl.Count -eq 0) {
        # Ein Ergebnis, keine Rueckfrage: es gehoert in die Ausgabe und damit
        # in eine umgeleitete Datei.
        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Severity 'Warning' -Text 'Es wurde keine Ordnerart gewählt. Es wird nichts angelegt und nichts geändert.')
        )
        return @()
    }

    $folge = @(Get-WizardStepSequence -Mode Provision -Kind $auswahl)

    # --- Schritt 2: Gruppen ------------------------------------------------
    Read-GroupStep -Kind $auswahl -Sequence $folge

    $ziele = New-Object System.Collections.Generic.List[object]

    # --- Schritt 3: FSLogix konfigurieren ----------------------------------
    $mitProfil = $auswahl -ccontains 'FSLogix-Profiles'
    $mitRedirections = $auswahl -ccontains 'FSLogix-Redirections'

    if ($mitProfil -or $mitRedirections) {

        Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'ConfigFSLogix' -Sequence $folge)

        $profilZiel = $null

        if ($mitProfil) {
            $profilZiel = Read-KindTarget -Kind 'FSLogix-Profiles' -AclOptGroup @(Read-AclOptGroup -Kind 'FSLogix-Profiles') -Target $ziele.ToArray()
            $ziele.Add($profilZiel)
            Write-OperatorLine -Capability $kapazitaet -Line @(Format-KindCaptureSummary -Target $profilZiel)
        }

        if ($mitRedirections) {
            if ($mitProfil) { Add-PromptContext -Line @('') }

            # RDX-03, ERF-02: mit Profilablage der Nachbarordner als Vorschlag,
            # ohne sie keiner. Die Gruppen stammen aus dem FSLogix-Rollenspeicher.
            $redirZiel = Read-RedirectionsTarget -ProfileTarget $profilZiel -Target $ziele.ToArray()
            $ziele.Add($redirZiel)
            Write-OperatorLine -Capability $kapazitaet -Line @(Format-KindCaptureSummary -Target $redirZiel)
        }
    }

    # --- Schritt 4: DEM konfigurieren --------------------------------------
    $dem = @(@('DEMConfig', 'DEMProfiles', 'DEMComputerLogs') | Where-Object { $auswahl -contains $_ })

    if ($dem.Count -gt 0) {

        Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'ConfigDEM' -Sequence $folge)

        for ($i = 0; $i -lt $dem.Count; $i++) {

            # Eine Leerzeile trennt die Ordnerarten; jede Frage nennt ihre
            # Ordnerart woertlich.
            if ($i -gt 0) { Add-PromptContext -Line @('') }

            $kind = [string] $dem[$i]

            $ziel = Read-KindTarget -Kind $kind -AclOptGroup @(Read-AclOptGroup -Kind $kind) -Target $ziele.ToArray()
            $ziele.Add($ziel)
            Write-OperatorLine -Capability $kapazitaet -Line @(Format-KindCaptureSummary -Target $ziel)
        }
    }

    return $ziele.ToArray()
}

function Get-DialogUeberschrift {
    <#
    .SYNOPSIS
        Die Schritt-, Produkt- und Menueueberschriften des Dialogs an genau
        einer Stelle (G-04-2, G-04-4a, NAV-01, NAV-03).

    .DESCRIPTION
        Wie Get-ReportUeberschrift: der Test haelt die Ueberschriften nach und
        braucht dafuer die Textwerte. Zwei Kopien derselben Ueberschrift
        drifteten auseinander. Der fruehere Block Gruppen entfaellt; die
        Gruppen stehen in ihrem Produktblock (G-04-4a).

        Phase 9 (NAV-01, NAV-02): die Schritte von Weg 1 -- Kinds, Groups,
        ConfigFSLogix, ConfigDEM, Check. Kinds bleibt als Schluessel
        erhalten (Tests leiten den Titel der Komponentenfrage daraus her).
        FSLogix und DEM dienen in Weg 1 und Weg 2 als Produktzeile innerhalb
        des Gruppenschritts. Seit 09-02 (NAV-03) die Schritte von Weg 2
        (AuditRoot, AuditGroups, AuditReport) und Weg 3 (AdjustRoot,
        AdjustChange, Check) und der Kopf Menu des Hauptmenues; die frueheren
        Blockschluessel Audit und Adjust entfallen.

    .OUTPUTS
        [hashtable] Schluessel -> Ueberschriftstext.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Kinds         = 'Komponenten auswählen'
        Groups        = 'Gruppen erfassen'
        ConfigFSLogix = 'FSLogix konfigurieren'
        ConfigDEM     = 'DEM konfigurieren'
        Check         = 'Prüfung und Ausführung'

        FSLogix       = 'FSLogix -- Profilcontainer'
        DEM           = 'DEM -- Dynamic Environment Manager'

        # Weg 2 und Weg 3 (NAV-03, Entscheidung Projektinhaber 2026-09-30);
        # Weg 3 endet mit Check wie Weg 1.
        AuditRoot     = 'Wurzelverzeichnis und Zuordnung'
        AuditGroups   = 'Gruppen und Optionen bestätigen'
        AuditReport   = 'Prüfung und Bericht'
        AdjustRoot    = 'Wurzelverzeichnis und Auswahl'
        AdjustChange  = 'Änderungen erfassen'

        # Der Kopf des Hauptmenues, ohne Zaehler (NAV-01).
        Menu          = 'Hauptmenü'
    }
}

function Get-KindBeschreibung {
    <#
    .SYNOPSIS
        Ordnerart -> Kurzbeschreibung, wie sie die Komponentenliste zeigt --
        an genau einer Stelle. Die FSLogix-Produktzeile baut darauf auf.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        'FSLogix-Profiles'     = 'Profilcontainer'
        'FSLogix-Redirections' = 'Ablage für redirections.xml'
        'DEMConfig'            = 'DEM-Konfiguration'
        'DEMProfiles'          = 'DEM-Profilarchive'
        'DEMComputerLogs'      = 'DEM-Computerprotokolle'
    }
}

function Get-ProductHeading {
    <#
    .SYNOPSIS
        Die Produktzeile im Gruppenschritt und in der Gruppenuebersicht,
        passend zu den gewaehlten Ordnerarten.

    .DESCRIPTION
        Serverlauf 2026-10-05: mit nur FSLogix-Redirections stand dort
        "FSLogix -- Profilcontainer". Die Zeile nennt deshalb je Produkt die
        Beschreibungen der gewaehlten Ordnerarten in Listenreihenfolge, die
        letzte mit "und", die uebrigen mit Komma angehaengt (Entscheidung
        Projektinhaber 2026-10-05, auch fuer DEM). Bei DEM entfaellt das
        Praefix "DEM-" der Beschreibung, das Produkt steht schon vorn:
        "DEM -- Konfiguration und Profilarchive". Ohne Ordnerart des
        Produkts der Titel aus Get-DialogUeberschrift.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Kind
    )

    $titel = Get-DialogUeberschrift
    $beschreibung = Get-KindBeschreibung
    $teile = New-Object System.Collections.Generic.List[string]

    foreach ($art in @(Get-ComponentKind)) {
        if (-not (@($Kind) -ccontains [string] $art)) { continue }
        if ((Get-KindProduct -Kind ([string] $art)) -cne $Product) { continue }
        $text = [string] $beschreibung[[string] $art]
        if (($Product -ceq 'DEM') -and $text.StartsWith('DEM-', [System.StringComparison]::Ordinal)) { $text = $text.Substring(4) }
        $teile.Add($text)
    }

    if ($teile.Count -eq 0) { return [string] $titel[$Product] }

    $liste = $teile[$teile.Count - 1]
    if ($teile.Count -gt 1) {
        $liste = '{0} und {1}' -f (($teile.GetRange(0, $teile.Count - 1)) -join ', '), $teile[$teile.Count - 1]
    }

    return ('{0} -- {1}' -f $Product, $liste)
}

function Get-DialogUeberschriftZeile {
    <#
    .SYNOPSIS
        Eine Blockueberschrift als abgesetzter Kopf mit Gleichheitslinien
        (G-04-4e, NAV-01) -- die eine Stelle fuer diese Form.

    .DESCRIPTION
        Ohne -Sequence (seit 09-02) der Kopf ohne Zaehler: Leerzeile,
        '='-Linie, '<Titel>', '='-Linie -- etwa fuer das Hauptmenue. Die
        fruehere Sternform gibt es nicht mehr.

        MIT -Sequence (Phase 9, NAV-01) der Schrittkopf: Leerzeile,
        '='-Linie, '[Schritt x/y] <Titel>', '='-Linie. x ist die Stelle des
        Schluessels in der Schrittfolge, y ihre Laenge -- die eine Wahrheit
        darueber ist Get-WizardStepSequence. Die Linie ist 72 Zeichen lang
        oder eins laenger als die Kopfzeile. Ein Schluessel ausserhalb der
        Schrittfolge wirft.

        Der Titel kommt aus Get-DialogUeberschrift. Die Farbe (Schwere
        Heading) kommt nur hinzu, wo die Kapazitaet sie traegt (D-14).

    .OUTPUTS
        [string[]] -- die Kopfzeilen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Sequence
    )

    $titel = Get-DialogUeberschrift

    if (-not $titel.ContainsKey($Key)) {
        throw [System.ArgumentException]::new(('Unbekannte Blocküberschrift "{0}".' -f $Key))
    }

    if ($PSBoundParameters.ContainsKey('Sequence')) {

        $folge = [string[]] @($Sequence)
        $stelle = [System.Array]::IndexOf($folge, $Key)

        if ($stelle -lt 0) {
            throw [System.ArgumentException]::new(('Der Schritt "{0}" steht nicht in der Schrittfolge.' -f $Key))
        }

        $schritt = '[Schritt {0}/{1}] {2}' -f ($stelle + 1), $folge.Length, [string] $titel[$Key]
        $laenge = [System.Math]::Max(72, $schritt.Length + 1)
        $linie = ''.PadRight($laenge, [char] '=')

        return @('', $linie, $schritt, $linie)
    }

    $kopf = [string] $titel[$Key]
    $breite = [System.Math]::Max(72, $kopf.Length + 1)
    $gleich = ''.PadRight($breite, [char] '=')

    return @('', $gleich, $kopf, $gleich)
}

function Get-StartBanner {
    <#
    .SYNOPSIS
        Das Startbanner des Laufs als Zeilensaetze (G-04-4e) -- die eine
        Stelle fuer diesen Text.

    .DESCRIPTION
        Zwei '='-Linien um die Titelzeile (NAV-01, seit 09-02), alle drei mit
        Schwere Heading; Einleitung ohne Schwere. Die Titelzeile ist die
        einzige Heading-Zeile mit Buchstaben -- darauf verlassen sich
        Tests/BundleSmoke.Tests.ps1 und Tests/Orchestration.Tests.ps1. Keine
        Zeile ueber 78 Zeichen, kein Emoji und keine Fremdmarke: das Banner
        muss auf jeder Konsole und in jeder umgeleiteten Datei gleich lesbar
        sein. Es endet OHNE Leerzeile; die Leerzeile vor dem ersten Kopf
        genuegt.

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param()

    $breite = 72
    $gleich = ''.PadRight($breite, [char] '=')
    $titel = '  DemFsAcl -- Ablagen für FSLogix und Omnissa DEM einrichten'

    $zeilen = New-Object System.Collections.Generic.List[object]

    foreach ($rahmen in @($gleich, $titel, $gleich)) {
        $zeilen.Add((New-OperatorTextLine -Severity 'Heading' -Text $rahmen))
    }

    foreach ($text in @(
            ''
            '  Dieses Skript unterstützt bei der Einrichtung, Überprüfung und Anpassung'
            '  von FSLogix- und Omnissa DEM-Verzeichnissen.'
            ''
            '  Es erstellt Ordner, SMB-Freigaben und NTFS-Berechtigungen gemäß den'
            '  Herstellerempfehlungen oder analysiert eine bestehende Struktur.'
            '  NTFS-Berechtigungen können gezielt hinzugefügt, entfernt oder ersetzt'
            '  werden.'
            ''
            '  Alle geplanten Änderungen werden vorab angezeigt, müssen ausdrücklich'
            '  bestätigt werden, werden anschließend umgesetzt und automatisch'
            '  überprüft.'
        )) {
        $zeilen.Add((New-OperatorTextLine -Text $text))
    }

    return $zeilen.ToArray()
}

function Read-KindTarget {
    <#
    .SYNOPSIS
        Der Bereichsteil einer Ordnerart: Bindung, Bestand, Pfad und
        Freigabename. Intern zu Read-ProvisioningTarget.

    .DESCRIPTION
        Die Bindung fragt hier nichts neu -- die Rollen sind am Anfang des
        Produktblocks erhoben (G-04-4a). Braeuchte eine gewaehlte Optionsgruppe
        kuenftig eine weitere Rolle, fragte Read-TrusteeRole sie an dieser
        Stelle.

        EINGABEPRUEFUNG (G-04-1b, VAL-01). Nach jeder Pfadermittlung wird der
        Kandidat ueber Get-TargetPathInputError geprueft -- Pfad-Sperrliste,
        fehlendes Laufwerk und Konflikt mit einem bereits erhobenen Ziel. Ein
        Fehlersatz fuehrt zu einem [FEHLER]-Hinweis, und der Pfad wird AUF DEM
        TATSAECHLICH GEWAEHLTEN WEG erneut ermittelt -- Neuanlage oder Bestand.
        Die Neuanlage weist schon an der Zielpfadfrage ab (Test-TargetPathInput);
        die Schleife hier traegt den Bestandsweg.

        WEGWECHSEL (G-04-5c, Projektinhaber 2026-09-22; revidiert die fruehere
        Festlegung "wer den Weg wechseln will, bricht ab"). Im Bestandsweg
        bietet Read-ExistingRoot ausdruecklich den Wechsel auf die Neuanlage
        an. Meldet das Ergebnis SwitchedToNew, gilt ab dort der
        Neuanlage-Weg: IsExisting wird false, und eine erneute Pfadermittlung
        nach einem Konflikt fragt den Zielpfad der Neuanlage, nicht wieder den
        Startpfad. Geraten wird dabei nichts (D-08): jeder Wechsel ist eine
        ausdrueckliche Wahl des Operators.

    .PARAMETER Target
        Die in diesem Lauf bereits erhobenen Ziele.

    .PARAMETER PathProposal
        Ein Vorschlag fuer den Zielpfad der Neuanlage (RDX-03). Leer heisst:
        kein Vorschlag, wie bisher.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $AclOptGroup = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string] $PathProposal = ''
    )

    $bisher = @(@($Target) | Where-Object { $null -ne $_ })
    $aclOpt = @($AclOptGroup)
    $shareOpt = @(Get-FixedOptGroup -Kind $Kind -Scope 'Share')
    $bindung = Read-GroupBinding -Kind $Kind -AclOptGroup $aclOpt -ShareOptGroup $shareOpt

    # FLOW-02: Vorgabe Nein. Die Neuanlage ist der Normalfall dieses
    # Werkzeugs; der Bestandsfall ist die Ausnahme und soll ausdruecklich
    # gewaehlt werden.
    $bestand = Read-YesNoAnswer -Prompt ('Ordnerart "{0}": eine bestehende Struktur nutzen?' -f $Kind) -Default $false

    while ($true) {

        if ($bestand) {
            $pfad = Read-ExistingRoot -Kind $Kind -Target $bisher

            # G-04-5c: der Weg folgt der Wahl, nicht der ersten Antwort.
            if ([bool] $pfad.SwitchedToNew) { $bestand = $false }
        }
        else {
            $pfad = Read-NewRoot -Kind $Kind -DefaultPath $PathProposal -Target $bisher
        }

        # VAL-01: dieselben Praedikate wie das Preflight. Entschieden hat
        # Get-TargetPathInputError; hier entsteht nur die Darstellung.
        $fehler = @(Get-TargetPathInputError -LiteralPath ([string] $pfad.Path) -Kind $Kind -Target $bisher)

        if ($fehler.Count -eq 0) { break }

        Write-OperatorHint -Severity 'Error' -Text ([string]::Join([System.Environment]::NewLine, [string[]] @(Format-PathInputError -PathError $fehler -Kind $Kind)))
    }

    return [pscustomobject] @{
        Kind          = $Kind
        Path          = [string] $pfad.Path
        ShareName     = (Read-ShareName -Kind $Kind -DefaultName ([string] $pfad.LeafName) -Path ([string] $pfad.Path) -Target $bisher)
        IsExisting    = [bool] $bestand
        Binding       = $bindung
        AclOptGroup   = $aclOpt
        ShareOptGroup = $shareOpt
    }
}

function Get-ComponentKind {
    <#
    .SYNOPSIS
        Die fuenf Ordnerarten der Komponentenliste in Listenreihenfolge
        (Phase 9, ERF-01).

    .DESCRIPTION
        Eine reine Zeichenkettenliste: sie faellt damit unter den
        Listenwaechter Tests/KindList.Tests.ps1.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')
}

function Format-KindSelectionList {
    <#
    .SYNOPSIS
        Die nummerierte Komponentenliste mit Markierung [X] / [ ] (ERF-01).

    .DESCRIPTION
        Leerzeile, Frage, Leerzeile, dann je Ordnerart eine Zeile
        '    n) [X] <Ordnerart> <Kurzbeschreibung>'.

    .PARAMETER Cursor
        Nur im Tastenmodus (W-09-1): die Zeile dieses Eintrags (ab 0) beginnt
        mit '  > ' statt mit vier Leerzeichen. Ohne Angabe ist die Liste
        zeichengleich zur Nummernform.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Selected,

        [Parameter()]
        [int] $Cursor = -1
    )

    $beschreibung = Get-KindBeschreibung

    $gewaehlt = @($Selected)
    $arten = @(Get-ComponentKind)

    $zeilen = New-Object System.Collections.Generic.List[string]
    $zeilen.Add('')
    $zeilen.Add('  Welche Ablagen sollen eingerichtet werden?')
    $zeilen.Add('')

    for ($i = 0; $i -lt $arten.Count; $i++) {
        $art = [string] $arten[$i]
        $marke = if ($gewaehlt -ccontains $art) { 'X' } else { ' ' }
        $einzug = if ($i -eq $Cursor) { '  > ' } else { '    ' }
        $zeilen.Add(('{0}{1}) [{2}] {3,-21} {4}' -f $einzug, ($i + 1), $marke, $art, [string] $beschreibung[$art]))
    }

    return $zeilen.ToArray()
}

function Test-KindToggleChoice {
    <#
    .SYNOPSIS
        Prueft eine Umschalteingabe: Enter, oder Nummern 1 bis Count,
        getrennt durch Komma, Semikolon oder Leerraum (ERF-01).

    .DESCRIPTION
        Ueber TryParse, nie ueber eine Umwandlung mit Ausnahme: eine
        ungueltige Eingabe fuehrt zu Hinweis und erneuter Frage (FLOW-06).

    .OUTPUTS
        [pscustomobject] mit IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [int] $Count
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [pscustomobject] @{ IsValid = $true; Reason = '' }
    }

    $erwartet = 'Erwartet werden Nummern zwischen 1 und {0}, getrennt durch Komma, oder Enter zum Übernehmen.' -f $Count

    foreach ($teil in @([regex]::Split($Value.Trim(), '[,;\s]+'))) {

        if ([string]::IsNullOrEmpty($teil)) { continue }

        $zahl = 0

        if (-not [int]::TryParse($teil, [ref] $zahl)) {
            return [pscustomobject] @{ IsValid = $false; Reason = ('"{0}" ist keine Nummer. {1}' -f $teil, $erwartet) }
        }

        if (($zahl -lt 1) -or ($zahl -gt $Count)) {
            return [pscustomobject] @{ IsValid = $false; Reason = ('Die Nummer {0} liegt außerhalb der Liste. {1}' -f $zahl, $erwartet) }
        }
    }

    return [pscustomobject] @{ IsValid = $true; Reason = '' }
}

function ConvertFrom-KindToggleChoice {
    <#
    .SYNOPSIS
        Die verschiedenen Nummern einer geprueften Umschalteingabe, in der
        Reihenfolge ihres ersten Auftretens (ERF-01).

    .DESCRIPTION
        Jede Nummer schaltet genau einmal um, auch wenn sie mehrfach
        genannt ist. Enter liefert keine Nummer.

    .OUTPUTS
        [int[]]
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $nummern = New-Object System.Collections.Generic.List[int]

    if ([string]::IsNullOrWhiteSpace($Value)) { return $nummern.ToArray() }

    foreach ($teil in @([regex]::Split($Value.Trim(), '[,;\s]+'))) {

        if ([string]::IsNullOrEmpty($teil)) { continue }

        $zahl = 0
        if (-not [int]::TryParse($teil, [ref] $zahl)) { continue }
        if (-not $nummern.Contains($zahl)) { $nummern.Add($zahl) }
    }

    return $nummern.ToArray()
}

function Read-ProvisioningKind {
    <#
    .SYNOPSIS
        Schritt 1 von Weg 1: die Komponentenliste mit Vorauswahl und
        Umschaltung (FLOW-01, ERF-01, NAV-02).

    .DESCRIPTION
        Vorausgewaehlt ist jede Ordnerart ausser DEMComputerLogs -- der
        einzigen ohne Herstellervorgabe. Kopf und Liste reisen mit jeder
        Frage als Kontext; y im Kopf rechnet aus der gerade angezeigten
        Auswahl (Planer-Entscheidung 7).

        Zuerst "Auswahl aendern? [j/N]": Enter oder n uebernimmt. Bei j die
        Nummernfrage;
        Enter uebernimmt, jede gueltige Eingabe schaltet um und zeigt Kopf
        und Liste neu.

        Meldet die UEBERGEBENE Kapazitaet Tasteneingabe (SupportsKeyInput,
        Test-KeyChannelOffen), fuehrt stattdessen Read-ProvisioningKindByKey
        die Liste mit Pfeiltasten, Leertaste und Enter (W-09-1). Ohne
        Kapazitaet, ohne das Feld oder mit falsch bleibt der Nummerndialog
        zeichengleich. Der modulweite Zwischenspeicher wird bewusst nicht
        gelesen (Begruendung im Kopf von Read-OperatorInput.ps1).

    .PARAMETER Capability
        Die vorab erhobene Konsolenkapazitaet des Laufs, oder nichts.

    .OUTPUTS
        [string[]] -- die gewaehlten Ordnerarten in Listenreihenfolge.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    if (Test-KeyChannelOffen -Capability $Capability) {
        return Read-ProvisioningKindByKey -Capability $Capability
    }

    $arten = @(Get-ComponentKind)

    # Der Validator laeuft im Kindskopus von Read-OptionalText und sieht
    # diese Variable ueber die dynamische Skopusregel -- ausdruecklich OHNE
    # GetNewClosure, wie in Read-ExistingRoot.
    $komponentenZahl = $arten.Count

    $an = New-Object 'bool[]' $komponentenZahl
    for ($i = 0; $i -lt $komponentenZahl; $i++) { $an[$i] = ([string] $arten[$i] -cne 'DEMComputerLogs') }

    $ersteRunde = $true

    while ($true) {

        $auswahl = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $komponentenZahl; $i++) { if ($an[$i]) { $auswahl.Add([string] $arten[$i]) } }

        $folge = @(Get-WizardStepSequence -Mode Provision -Kind $auswahl.ToArray())

        Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'Kinds' -Sequence $folge)
        Add-PromptContext -Line @(Format-KindSelectionList -Selected $auswahl.ToArray())

        if ($ersteRunde) {

            $ersteRunde = $false

            if (-not (Read-YesNoAnswer -Prompt 'Auswahl ändern?' -Default $false -ShortLabel)) {
                return $auswahl.ToArray()
            }
        }

        $eingabe = Read-OptionalText `
            -Prompt 'Nummern zum Umschalten (z. B. 2 oder 2,5; Enter = Auswahl übernehmen)' `
            -Validator { param($Wert) Test-KindToggleChoice -Value $Wert -Count $komponentenZahl }

        $nummern = @(ConvertFrom-KindToggleChoice -Value $eingabe)

        if ($nummern.Count -eq 0) { return $auswahl.ToArray() }

        foreach ($nummer in $nummern) { $an[$nummer - 1] = -not $an[$nummer - 1] }
    }
}

function Get-KindKeyAction {
    <#
    .SYNOPSIS
        Deutet eine Taste der Komponentenliste (W-09-1). Rein, ohne Ein- und
        Ausgabe.

    .DESCRIPTION
        Pfeil hoch/runter bewegt die Markierung; am Rand bleibt sie stehen,
        die Taste wirkt dann nicht (P-4). Leertaste schaltet die markierte
        Zeile um, eine Ziffer 1 bis Count den Eintrag dieser Nummer (die
        Markierung springt dorthin). Enter uebernimmt. Jede andere Taste
        wirkt nicht.

    .OUTPUTS
        [pscustomobject] mit Action (Move, Toggle, Confirm, None) und
        Index (die neue Markierung bzw. der umzuschaltende Eintrag, ab 0).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Key,

        [Parameter(Mandatory)]
        [int] $Cursor,

        [Parameter(Mandatory)]
        [int] $Count
    )

    $name = ''
    if ($null -ne $Key.PSObject.Properties['Key']) { $name = [string] $Key.Key }
    $zeichen = ''
    if ($null -ne $Key.PSObject.Properties['Char']) { $zeichen = [string] $Key.Char }

    $ordinal = [System.StringComparison]::Ordinal

    if ([string]::Equals($name, 'UpArrow', $ordinal)) {
        if ($Cursor -le 0) { return [pscustomobject] @{ Action = 'None'; Index = $Cursor } }
        return [pscustomobject] @{ Action = 'Move'; Index = $Cursor - 1 }
    }

    if ([string]::Equals($name, 'DownArrow', $ordinal)) {
        if ($Cursor -ge ($Count - 1)) { return [pscustomobject] @{ Action = 'None'; Index = $Cursor } }
        return [pscustomobject] @{ Action = 'Move'; Index = $Cursor + 1 }
    }

    if ([string]::Equals($name, 'Spacebar', $ordinal) -or [string]::Equals($zeichen, ' ', $ordinal)) {
        return [pscustomobject] @{ Action = 'Toggle'; Index = $Cursor }
    }

    if ([string]::Equals($name, 'Enter', $ordinal)) {
        return [pscustomobject] @{ Action = 'Confirm'; Index = $Cursor }
    }

    # Ziffern 1 bis Count schalten direkt um; die Markierung springt dorthin.
    $ziffer = 0
    if (($zeichen.Length -eq 1) -and
        [int]::TryParse($zeichen, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $ziffer) -and
        ($ziffer -ge 1) -and ($ziffer -le $Count)) {
        return [pscustomobject] @{ Action = 'Toggle'; Index = $ziffer - 1 }
    }

    return [pscustomobject] @{ Action = 'None'; Index = $Cursor }
}

function Get-KindKeyBlock {
    <#
    .SYNOPSIS
        Kopf und Komponentenliste des Tastenmodus als Zeilensaetze (W-09-1).
        Intern zu Read-ProvisioningKindByKey.

    .DESCRIPTION
        y im Kopf rechnet aus der uebergebenen Auswahl (NAV-02). Mit einer
        Markierung ab 0 traegt deren Zeile '  > ' und die Schwere Heading
        (additiv, D-14), darunter eine Leerzeile und die zwei Hinweiszeilen.
        Mit -1 -- nach Enter -- nur Kopf und Liste.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Selected,

        [Parameter(Mandatory)]
        [int] $Cursor
    )

    $zeilen = New-Object System.Collections.Generic.List[object]

    $folge = @(Get-WizardStepSequence -Mode Provision -Kind $Selected)
    foreach ($satz in @(Get-StepHeaderRecord -Key 'Kinds' -Sequence $folge)) { $zeilen.Add($satz) }

    foreach ($text in @(Format-KindSelectionList -Selected $Selected -Cursor $Cursor)) {
        $schwere = if (([string] $text).StartsWith('  > ', [System.StringComparison]::Ordinal)) { 'Heading' } else { 'None' }
        $zeilen.Add((New-OperatorTextLine -Text ([string] $text) -Severity $schwere))
    }

    if ($Cursor -ge 0) {
        $anzahl = @(Get-ComponentKind).Count
        $zeilen.Add((New-OperatorTextLine -Text ''))
        $zeilen.Add((New-OperatorTextLine -Text ('  Pfeiltasten: Zeile wählen. Leertaste oder 1 bis {0}: an/aus.' -f $anzahl)))
        $zeilen.Add((New-OperatorTextLine -Text '  Enter: Auswahl übernehmen.'))
    }

    return $zeilen.ToArray()
}

function Read-ProvisioningKindByKey {
    <#
    .SYNOPSIS
        Schritt 1 von Weg 1 im Tastenmodus: Pfeiltasten, Leertaste, Enter
        (W-09-1, Entscheidung Projektinhaber 2026-10-01).

    .DESCRIPTION
        Startzustand wie im Nummerndialog: jede Ordnerart ausser
        DEMComputerLogs an, Markierung auf Eintrag 1. Abgelegter Kontext geht
        vor dem ersten Zeichnen hinaus (Send-PromptContext). Je wirksamer
        Taste wird der Block genau einmal an Ort und Stelle neu gezeichnet;
        eine wirkungslose Taste zeichnet nicht. Nach Enter wird einmal
        abschliessend ohne Markierung und Hinweiszeilen gezeichnet (P-4).
        Getippt wird nur ueber Read-OperatorKey, gezeichnet nur ueber
        Write-OperatorBlock.

    .OUTPUTS
        [string[]] -- die gewaehlten Ordnerarten in Listenreihenfolge.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object] $Capability
    )

    $arten = @(Get-ComponentKind)
    $zahl = $arten.Count

    $an = New-Object 'bool[]' $zahl
    for ($i = 0; $i -lt $zahl; $i++) { $an[$i] = ([string] $arten[$i] -cne 'DEMComputerLogs') }

    $cursor = 0
    $zeichnen = $true
    $ersetzen = 0
    $belegt = 0

    Send-PromptContext -Capability $Capability

    while ($true) {

        $auswahl = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $zahl; $i++) { if ($an[$i]) { $auswahl.Add([string] $arten[$i]) } }

        if ($zeichnen) {
            $block = @(Get-KindKeyBlock -Selected $auswahl.ToArray() -Cursor $cursor)
            $belegt = [int] (Write-OperatorBlock -Capability $Capability -Line $block -ReplaceRows $ersetzen)
            $zeichnen = $false
        }

        $aktion = Get-KindKeyAction -Key (Read-OperatorKey) -Cursor $cursor -Count $zahl
        $art = [string] $aktion.Action

        if ([string]::Equals($art, 'Move', [System.StringComparison]::Ordinal)) {
            $cursor = [int] $aktion.Index
            $ersetzen = $belegt
            $zeichnen = $true
        }
        elseif ([string]::Equals($art, 'Toggle', [System.StringComparison]::Ordinal)) {
            $cursor = [int] $aktion.Index
            $an[$cursor] = -not $an[$cursor]
            $ersetzen = $belegt
            $zeichnen = $true
        }
        elseif ([string]::Equals($art, 'Confirm', [System.StringComparison]::Ordinal)) {
            $block = @(Get-KindKeyBlock -Selected $auswahl.ToArray() -Cursor -1)
            $null = Write-OperatorBlock -Capability $Capability -Line $block -ReplaceRows $belegt
            return $auswahl.ToArray()
        }
    }
}

function Read-AclOptGroup {
    <#
    .SYNOPSIS
        Die ACL-Optionsgruppen einer Ordnerart: fest belegte plus die eine
        gefragte.

    .DESCRIPTION
        GENAU EINE OPT-IN-FRAGE FUER OPTIONSGRUPPEN, und sie gilt der
        Optionsgruppe SystemAndBuiltinAdmins auf FSLogix-Profiles. Die Frage
        nach der Redirections-Ablage (Read-RedirectionsTarget) ist keine
        Optionsgruppe, sondern ein eigenes Ziel; fuer FSLogix-Redirections
        stellt diese Funktion keine Frage, deren Eintraege sind fest.
        Begruendung: SPEC-06 verlangt fuer genau diese Gruppe eine
        Operatorwahl mit herstellerwortgetreuer Vorgabe, und PRE-06 nennt sie
        woertlich als Ausweg aus der drohenden Aussperrung -- ohne die Frage
        zeigte die Warnung auf einen Bedienknopf, den es nicht gibt.

        Die Vorgabe ist NEIN: das herstellerkonforme FSLogix-Soll fuehrt diese
        Eintraege nicht, und eine Vorgabe Ja machte aus der Ausnahme den
        Normalfall.

        Die Frage lautet "[J/n]", ohne "?"-Erklaerung (HLP-01 gestrichen,
        Entscheidung Projektinhaber 2026-10-04). Die Vorgabe ist JA
        (Entscheidung Projektinhaber 2026-09-24): der Betrieb braucht SYSTEM
        auf den Profilcontainern, das herstellerwoertliche Soll bleibt per "n"
        waehlbar.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind
    )

    $gruppen = New-Object System.Collections.Generic.List[string]

    foreach ($name in @(Get-FixedOptGroup -Kind $Kind -Scope 'Acl')) { $gruppen.Add([string] $name) }

    if ($Kind -eq 'FSLogix-Profiles') {

        # G-04-4c: die Frage nennt die lokale Gruppe des Servers und NICHT die
        # Rolle "Gruppe der Administratoren" -- zwei verschiedene Dinge.
        $frage = 'Ordnerart "FSLogix-Profiles": zusätzlich die lokale Administratorengruppe des Servers und das Systemkonto eintragen (Optionsgruppe SystemAndBuiltinAdmins)?'

        if (Read-YesNoAnswer -Prompt $frage -Default $true -ShortLabel) {
            $gruppen.Add('SystemAndBuiltinAdmins')
        }
    }

    return $gruppen.ToArray()
}

function Read-NewRoot {
    <#
    .SYNOPSIS
        FLOW-03, FLOW-05: der Zielpfad einer Neuanlage, einschliesslich
        Laufwerk.

    .DESCRIPTION
        Validiert ueber Test-TargetPathInput: erst Resolve-OperatorPath -- die
        eine Normalisierungs- und Pruefstelle --, dann die fruehe
        Eingabepruefung Get-TargetPathInputError (VAL-01). Ein abgewiesener
        Pfad fuehrt zu einem [FEHLER]-Hinweis mit Grund und Beispiel und zur
        erneuten Frage; ohne Grund waere die erneute Frage eine Sackgasse.

    .PARAMETER DefaultPath
        Ein Vorschlagswert, den Enter uebernimmt. Leer heisst: kein
        Vorschlag, wie bisher.

    .PARAMETER Target
        Die in diesem Lauf bereits erhobenen Ziele -- fuer die
        Konfliktpruefung der Eingabe.

    .OUTPUTS
        Der Datensatz aus Resolve-OperatorPath.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter()]
        [AllowEmptyString()]
        [string] $DefaultPath = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    # Eigene Namen und AUSDRUECKLICH OHNE GetNewClosure, wie in
    # Read-ShareName: der Validator laeuft im Kindskopus von Read-RequiredText
    # und sieht diese Variablen ueber die dynamische Skopusregel.
    $neuKind = $Kind
    $neuZiele = @(@($Target) | Where-Object { $null -ne $_ })

    $eingabe = Read-RequiredText `
        -Prompt ('Zielpfad für "{0}" einschließlich Laufwerk' -f $Kind) `
        -DefaultValue $DefaultPath `
        -Validator { param($Wert) Test-TargetPathInput -Value $Wert -Kind $neuKind -Target $neuZiele }

    return Resolve-OperatorPath -InputValue $eingabe
}

function Test-TargetPathInput {
    <#
    .SYNOPSIS
        Der Validator der Zielpfadfrage (VAL-01). Intern zu Read-NewRoot.

    .DESCRIPTION
        Erst Resolve-OperatorPath (FLOW-05), dann Get-TargetPathInputError mit
        dem normalisierten Pfad. Beide Abweisungen bekommen dieselbe Form aus
        Format-PathInputError und die Schwere Error. Eine eigene Pfadrechnung
        gibt es hier nicht.

    .OUTPUTS
        [pscustomobject] mit IsValid, Reason (mehrzeilig) und Severity.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    $aufgeloest = Resolve-OperatorPath -InputValue $Value

    if ([bool] $aufgeloest.IsValid) {
        $fehler = @(Get-TargetPathInputError -LiteralPath ([string] $aufgeloest.Path) -Kind $Kind -Target $Target)
    }
    else {
        $fehler = @([pscustomobject] @{ Check = ''; Reason = [string] $aufgeloest.Reason; Conflict = $null })
    }

    if ($fehler.Count -eq 0) {
        return [pscustomobject] @{ IsValid = $true; Reason = ''; Severity = 'Error' }
    }

    return [pscustomobject] @{
        IsValid  = $false
        Reason   = [string]::Join([System.Environment]::NewLine, [string[]] @(Format-PathInputError -PathError $fehler -Kind $Kind))
        Severity = 'Error'
    }
}

function Format-PathInputError {
    <#
    .SYNOPSIS
        Die Zeilen einer abgewiesenen Pfadeingabe (VAL-01): [FEHLER], Grund,
        Beispiel. Intern zur Interaktionsschicht.

    .DESCRIPTION
        Je Fehlersatz ohne Konflikt eine Zeile '    [FEHLER] <Grund>'; ein
        Konflikt bekommt die gegliederten Zeilen aus Format-ConflictHint, die
        fuer einen Pfad ebenfalls mit [FEHLER] beginnen. Darunter genau eine
        Beispielzeile mit der Ordnerart. Die Marke kommt aus
        Get-StatusMarkierung -- ohne Farbe vollstaendig (D-14).

    .PARAMETER PathError
        Fehlersaetze mit Check, Reason und Conflict (Get-TargetPathInputError).

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object[]] $PathError,

        [Parameter(Mandatory)]
        [string] $Kind
    )

    $marke = Get-StatusMarkierung -Status 'Error'
    $zeilen = New-Object System.Collections.Generic.List[string]

    foreach ($satz in @($PathError)) {

        if ($null -eq $satz) { continue }

        $konflikt = $null
        if ($null -ne $satz.PSObject.Properties['Conflict']) { $konflikt = $satz.Conflict }

        if ($null -ne $konflikt) {
            foreach ($zeile in @(Format-ConflictHint -Conflict $konflikt -Kind $Kind)) { $zeilen.Add([string] $zeile) }
            continue
        }

        $zeilen.Add(('    {0} {1}' -f $marke, [string] $satz.Reason))
    }

    $zeilen.Add(('      Beispiel: D:\Freigaben\{0}' -f $Kind))

    return $zeilen.ToArray()
}

function Read-RedirectionsTarget {
    <#
    .SYNOPSIS
        RDX-03, ERF-02: die Ablage fuer redirections.xml in Schritt 3.
        Intern zu Read-ProvisioningTarget.

    .DESCRIPTION
        Gewaehlt wird sie in der Komponentenliste (Phase 9, vorausgewaehlt);
        die fruehere Ja/Nein-Frage entfaellt. Die Ablage laeuft als eigene
        Ordnerart FSLogix-Redirections durch Read-KindTarget -- Bestand,
        Pfad, Freigabename wie bei jeder Ordnerart. Die Gruppen kommen aus
        dem FSLogix-Rollenspeicher (Get-KindProduct liefert FSLogix); es gibt
        keine weitere Gruppenfrage und keine Opt-in-Frage, die Eintraege der
        lokalen Administratorengruppe und des Systemkontos sind fest
        (Inhaberentscheid 2026-09-25).

        Mit Profilziel schlaegt die Pfadfrage den Nachbarordner
        FSLogix-Redirections vor; ohne Profilziel gibt es keinen Vorschlag --
        geraten wird nichts (D-08).

    .PARAMETER ProfileTarget
        Das in diesem Lauf erhobene Ziel FSLogix-Profiles, oder $null.

    .PARAMETER Target
        Die in diesem Lauf bereits erhobenen Ziele.

    .OUTPUTS
        Der Zieldatensatz.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $ProfileTarget = $null,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    $vorschlag = ''

    if ($null -ne $ProfileTarget) {
        $vorschlag = Get-RedirectionsPfadVorschlag -ProfilePath ([string] $ProfileTarget.Path) -Target $Target
    }

    return Read-KindTarget -Kind 'FSLogix-Redirections' `
        -AclOptGroup @(Read-AclOptGroup -Kind 'FSLogix-Redirections') `
        -Target $Target `
        -PathProposal $vorschlag
}

function Get-RedirectionsPfadVorschlag {
    <#
    .SYNOPSIS
        Der Pfadvorschlag der Redirections-Ablage: der Nachbarordner
        FSLogix-Redirections neben der Profilablage (RDX-03).

    .DESCRIPTION
        Elternordner des Profilpfades plus FSLogix-Redirections. Ohne
        Elternordner -- etwa bei einer Laufwerkswurzel -- gibt es keinen
        Vorschlag. Liefert Get-TargetPathInputError fuer den Vorschlag einen
        Fehlersatz (VAL-01: Sperrliste, fehlendes Laufwerk, Konflikt mit einem
        bereits erhobenen Ziel), entfaellt er: ein Vorschlag, den der Dialog im
        selben Atemzug abwiese, waere eine Falle (wie Read-ShareName).

    .OUTPUTS
        [string] -- der Vorschlag oder ''.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ProfilePath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    if ([string]::IsNullOrWhiteSpace($ProfilePath)) { return '' }

    $gekuerzt = $ProfilePath.TrimEnd([char] 92, [char] 47)
    if ([string]::IsNullOrEmpty($gekuerzt)) { return '' }

    $eltern = $null
    try { $eltern = [System.IO.Path]::GetDirectoryName($gekuerzt) }
    catch { return '' }

    if ([string]::IsNullOrEmpty($eltern)) { return '' }

    $vorschlag = [System.IO.Path]::Combine($eltern, 'FSLogix-Redirections')

    $bisher = @(@($Target) | Where-Object { $null -ne $_ })

    $fehler = @(Get-TargetPathInputError -LiteralPath $vorschlag -Kind 'FSLogix-Redirections' -Target $bisher)

    if ($fehler.Count -gt 0) { return '' }

    return $vorschlag
}

function Read-ExistingRoot {
    <#
    .SYNOPSIS
        FLOW-04, D-08: klaert im Bestandsfall AUSDRUECKLICH, ob der Startpfad
        selbst die Freigabewurzel ist.

    .DESCRIPTION
        Zuerst der Startpfad ueber dieselbe Strecke wie die Neuanlage. Danach
        die ausdrueckliche Frage. Bei Nein werden die unmittelbaren Unterordner
        nummeriert aufgelistet, dazu zwei Zusatzeintraege (G-04-5c):
        "0) zurueck zur Frage nach der Freigabewurzel" und "n) stattdessen
        einen neuen Ordner anlegen". 0 stellt die WURZELFRAGE fuer denselben
        Startpfad erneut, n wechselt auf die Neuanlage (Read-NewRoot). Eine
        Eingabe ausserhalb von 0 bis N, die nicht n ist, fuehrt zur erneuten
        Frage (FLOW-06).

        Gibt es keinen Unterordner, wird genau das gemeldet und gefragt
        "Stattdessen einen neuen Ordner anlegen?" mit Vorgabe NEIN; Nein
        stellt die Wurzelfrage erneut -- nicht die Pfadfrage: der Startpfad
        war ja richtig, nur die Antwort darauf passt nicht. Ein nicht
        auflistbarer Startpfad fuehrt wie bisher mit Hinweis zur Wurzelfrage
        zurueck.

        HIER WIRD NICHTS GERATEN (D-08). Ein leerer Bestandsordner ist genau
        der Greenfield-Normalfall; jede Heuristik ueber die Ordnerstruktur
        ordnete ihn falsch ein, und ein falsch geratener Wurzelpfad ist bei
        einem Werkzeug, das ACLs setzt, teuer.

    .OUTPUTS
        Der Datensatz aus Resolve-OperatorPath, ergaenzt um SwitchedToNew:
        wahr, wenn der Operator auf die Neuanlage gewechselt hat.
        Read-KindTarget uebernimmt daraus den Weg (IsExisting,
        Konflikt-Schleife).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Kind,

        # Die in diesem Lauf bereits erhobenen Ziele; reist an die Neuanlage
        # weiter, wenn der Operator dorthin wechselt (VAL-01).
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    $eingabe = Read-RequiredText `
        -Prompt ('Startpfad der bestehenden Struktur für "{0}"' -f $Kind) `
        -Validator { param($Wert) Resolve-OperatorPath -InputValue $Wert }

    $start = Resolve-OperatorPath -InputValue $eingabe

    while ($true) {

        $frage = 'Ist der Pfad "{0}" selbst die Freigabewurzel für "{1}"?' -f [string] $start.Path, $Kind

        if (Read-YesNoAnswer -Prompt $frage -Default $true) {
            return (Add-SwitchedToNew -Path $start -Switched $false)
        }

        # Laesst sich der Startpfad nicht auflisten -- etwa weil das
        # ausfuehrende Konto dort kein Leserecht hat --, steht der Grund im
        # Prompt der wiederholten Wurzelfrage. Der Dialog bricht nicht ab
        # (FLOW-06); der Startpfad kann ja trotzdem die Freigabewurzel sein.
        try {
            $unterordner = @(Get-ChildDirectoryPath -LiteralPath ([string] $start.Path))
        }
        catch {
            Write-OperatorHint -Text ('    Die Unterordner von "{0}" lassen sich nicht auflisten: {1}' -f [string] $start.Path, $_.Exception.Message)
            continue
        }

        if ($unterordner.Count -eq 0) {
            Write-OperatorHint -Text ('    Unterhalb von "{0}" liegt kein Unterordner. Dann ist dieser Pfad selbst die Freigabewurzel -- oder es ist der falsche Startpfad.' -f [string] $start.Path)

            # G-04-5c: der Wechsel auf die Neuanlage, Vorgabe nein -- Nein
            # fuehrt zur Wurzelfrage zurueck.
            if (Read-YesNoAnswer -Prompt 'Stattdessen einen neuen Ordner anlegen?' -Default $false) {
                return (Add-SwitchedToNew -Path (Read-NewRoot -Kind $Kind -Target $Target) -Switched $true)
            }

            continue
        }

        # Die Liste reist mit der Nummernfrage (G-04-3a): eine Nummer ohne die
        # Liste daneben ist unter '> datei' eine Wahl im Blindflug.
        $zeilen = New-Object System.Collections.Generic.List[string]
        $zeilen.Add('')
        $zeilen.Add(('  Unterordner von "{0}":' -f [string] $start.Path))

        for ($i = 0; $i -lt $unterordner.Count; $i++) {
            $zeilen.Add(('    {0,3}) {1}' -f ($i + 1), [System.IO.Path]::GetFileName([string] $unterordner[$i])))
        }

        # G-04-5c: die beiden Zusatzeintraege reisen mit derselben Liste.
        $zeilen.Add(('    {0,3}) {1}' -f '0', 'zurück zur Frage nach der Freigabewurzel'))
        $zeilen.Add(('    {0,3}) {1}' -f 'n', 'stattdessen einen neuen Ordner anlegen'))

        Add-PromptContext -Line $zeilen.ToArray()

        $anzahl = $unterordner.Count

        # AUSDRUECKLICH OHNE GetNewClosure. Gemessen: eine geschlossene Kopie
        # bekommt einen eigenen, NEUEN Modulskopus und findet die
        # modulprivaten Funktionen nicht mehr -- Test-SubfolderNumber endete
        # dann in einer CommandNotFoundException. Der Skriptblock laeuft
        # stattdessen im Kindskopus dieser Funktion, und $anzahl ist dort ueber
        # die dynamische Skopusregel von PowerShell sichtbar.
        $nummer = ([string] (Read-RequiredText `
                    -Prompt ('Nummer des Unterordners, der die Freigabewurzel ist (1 bis {0}, 0 oder n)' -f $anzahl) `
                    -Validator { param($Wert) Test-SubfolderNumber -Value $Wert -Count $anzahl })).Trim()

        if ([string]::Equals($nummer, 'n', [System.StringComparison]::OrdinalIgnoreCase)) {
            return (Add-SwitchedToNew -Path (Read-NewRoot -Kind $Kind -Target $Target) -Switched $true)
        }

        $zahl = [int] $nummer

        # 0: zurueck zur Wurzelfrage fuer denselben Startpfad.
        if ($zahl -eq 0) { continue }

        # Auch dieser zusammengesetzte Pfad laeuft noch einmal durch die eine
        # Normalisierungsstelle (FLOW-05).
        return (Add-SwitchedToNew -Path (Resolve-OperatorPath -InputValue ([string] $unterordner[$zahl - 1])) -Switched $false)
    }
}

function Test-SubfolderNumber {
    <#
    .SYNOPSIS
        Prueft eine Nummerneingabe gegen den Bereich 0 bis Count oder 'n'
        (G-04-5c). Intern zu Read-ExistingRoot.

    .DESCRIPTION
        Geprueft wird ueber TryParse und nicht ueber eine Umwandlung mit
        Ausnahme: eine nicht numerische Eingabe ist am Dialog der Normalfall
        und fuehrt zur erneuten Frage, nicht zum Abbruch (FLOW-06).

    .OUTPUTS
        [pscustomobject] mit IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [int] $Count
    )

    $erwartet = 'Erwartet wird eine Nummer zwischen 1 und {0}, 0 (zurück) oder n (neuer Ordner).' -f $Count

    if ([string]::Equals($Value.Trim(), 'n', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject] @{ IsValid = $true; Reason = '' }
    }

    $zahl = 0

    if (-not [int]::TryParse($Value.Trim(), [ref] $zahl)) {
        return [pscustomobject] @{
            IsValid = $false
            Reason  = ('"{0}" ist keine Zahl. {1}' -f $Value, $erwartet)
        }
    }

    if (($zahl -lt 0) -or ($zahl -gt $Count)) {
        return [pscustomobject] @{
            IsValid = $false
            Reason  = ('Die Nummer {0} liegt außerhalb des Bereichs. {1}' -f $zahl, $erwartet)
        }
    }

    return [pscustomobject] @{ IsValid = $true; Reason = '' }
}

function Add-SwitchedToNew {
    <#
    .SYNOPSIS
        Ergaenzt einen Pfaddatensatz um SwitchedToNew (G-04-5c). Intern zu
        Read-ExistingRoot.

    .DESCRIPTION
        Ein Feld am Datensatz statt eines Wrappers: Path und LeafName bleiben
        fuer jeden Aufrufer unveraendert erreichbar, und Read-KindTarget liest
        den Weg an genau einer Stelle ab.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Path,

        [Parameter(Mandatory)]
        [bool] $Switched
    )

    return ($Path | Add-Member -NotePropertyName 'SwitchedToNew' -NotePropertyValue $Switched -Force -PassThru)
}

function Get-ChildDirectoryPath {
    <#
    .SYNOPSIS
        Die unmittelbaren Unterordner eines Pfades, sortiert. Intern zu
        Read-ExistingRoot.

    .DESCRIPTION
        OHNE ABSTIEG. Gelistet wird genau eine Ebene: die Freigabewurzel liegt
        entweder auf dem Startpfad selbst oder unmittelbar darunter, und ein
        Abstieg waere zugleich der erste Schritt zu der rekursiven Reparatur,
        die dieses Projekt ausdruecklich ausschliesst.

        Ein nicht existierender Pfad liefert eine leere Liste statt einer
        Ausnahme: ob der Pfad taugt, entscheidet das Preflight, und der Dialog
        soll an dieser Stelle fragen statt abzubrechen.

        Sortiert, damit die ausgegebene Nummerierung reproduzierbar ist -- der
        Operator waehlt ueber die Nummer, und eine wechselnde Reihenfolge
        machte aus derselben Eingabe ein anderes Ziel.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $LiteralPath
    )

    if ([string]::IsNullOrWhiteSpace($LiteralPath)) { return @() }
    if (-not [System.IO.Directory]::Exists($LiteralPath)) { return @() }

    return @([System.IO.Directory]::GetDirectories($LiteralPath) | Sort-Object)
}

function Read-ShareName {
    <#
    .SYNOPSIS
        SHARE-02: der Freigabename, mit dem Blattnamen des Zielpfades plus '$'
        als Vorschlag (G-04-4b).

    .DESCRIPTION
        WARUM DER BLATTNAME UND NICHT DER NAME DER ORDNERART: der Operator hat
        den Pfad gerade getippt; der Blattname ist damit die einzige Vorgabe,
        die aus einer Angabe desselben Operators stammt statt aus einer
        Konvention. Ein Vorschlag aus dem Ordnerart-Namen erzeugte den Fall
        "Freigabe DEMConfig zeigt auf D:\Ablage\Konfig" -- eine Abweichung, die
        spaeter niemand mehr erklaeren kann.

        WARUM MIT '$': versteckte Freigaben sind der Hausstandard des
        Projektinhabers (G-04-4b, lauf5_1.txt: jeder Vorschlag wurde von Hand
        um '$' ergaenzt). Den Vorschlag baut Get-ShareNameVorschlag; ein
        Blattname, der schon auf '$' endet, wird nicht verdoppelt.

        Ob der Name auf dem SERVER bereits belegt ist, entscheidet weiterhin
        PRE-05 im Preflight. Laufinterne Doppel prueft der Dialog ueber
        Get-TargetConflict -- dieselbe Funktion wie das Preflight, eine Regel,
        zwei Aufrufer (G-04-1b). Ein Name, den ein frueheres Ziel dieses Laufs
        traegt, wird mit der Konfliktmeldung als Grund abgewiesen.

        Ist der Vorschlag bereits als Freigabename vergeben, gibt es KEINEN
        Vorschlag: ein Vorschlag, den der Dialog im selben Atemzug abwiese,
        waere eine Falle (lauf3.txt: dreimal "DEM").

    .PARAMETER Path
        Der Pfad des Ziels, fuer den Kandidaten der Konfliktpruefung.

    .PARAMETER Target
        Die in diesem Lauf bereits erhobenen Ziele.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $DefaultName,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    # Eigene Namen und nicht $Kind/$Path: der Validator laeuft im Kindskopus
    # von Read-RequiredText und sieht diese Variablen ueber die dynamische
    # Skopusregel -- ein gleichnamiger Bezeichner dort verdeckte sie.
    $freigabeKind = $Kind
    $freigabePfad = $Path
    $freigabeZiele = @(@($Target) | Where-Object { $null -ne $_ })

    $vorschlag = Get-ShareNameVorschlag -LeafName $DefaultName

    foreach ($ziel in $freigabeZiele) {

        if ([string]::IsNullOrEmpty($vorschlag)) { break }
        if ($null -eq $ziel.PSObject.Properties['ShareName']) { continue }

        if ([string]::Equals(([string] $ziel.ShareName).Trim(), $vorschlag, [System.StringComparison]::OrdinalIgnoreCase)) {
            $vorschlag = ''
            break
        }
    }

    # AUSDRUECKLICH OHNE GetNewClosure -- wie $anzahl in Read-ExistingRoot:
    # die geschlossene Kopie findet modulprivate Funktionen nicht.
    return Read-RequiredText `
        -Prompt ('Freigabename für "{0}"' -f $Kind) `
        -DefaultValue $vorschlag `
        -Validator { param($Wert) Test-ShareNameInRun -Name $Wert -Kind $freigabeKind -Path $freigabePfad -Target $freigabeZiele }
}

function Get-ShareNameVorschlag {
    <#
    .SYNOPSIS
        Der Vorschlag fuer einen Freigabenamen: der Blattname plus '$'
        (G-04-4b). Intern zu Read-ShareName.

    .DESCRIPTION
        Der Blattname wird getrimmt. Endet er bereits auf '$', bleibt er
        unveraendert -- kein "Daten$$". Ist er leer, gibt es keinen Vorschlag.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $LeafName
    )

    $blatt = $LeafName.Trim()

    if ([string]::IsNullOrEmpty($blatt)) { return '' }
    if ($blatt.EndsWith('$', [System.StringComparison]::Ordinal)) { return $blatt }

    return $blatt + '$'
}

function Format-ConflictHint {
    <#
    .SYNOPSIS
        Ein laufinterner Konflikt als gegliederter HINWEIS in kurzen Zeilen
        (G-04-4f). Intern zur Interaktionsschicht.

    .DESCRIPTION
        Gebaut AUSSCHLIESSLICH aus den Feldern eines Datensatzes von
        Get-TargetConflict -- Type, Kind, Path, OtherKind, OtherPath und
        ShareName. Die Entscheidung bleibt dort; hier entsteht nur die
        Darstellung: was kollidiert, womit, warum, was zu tun ist.

        Ein Pfadkonflikt beginnt seit Phase 9 (VAL-01) mit der Marke
        [FEHLER] und reist in Fehlerschwere: er ist eine abgewiesene Eingabe,
        wie eine Laufwerkswurzel. Ein doppelter Freigabename bleibt ein
        HINWEIS -- kein Pfadfehler.

    .PARAMETER Kind
        Die Ordnerart, fuer die erneut gefragt wird.

    .OUTPUTS
        [string[]] -- die Hinweiszeilen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object] $Conflict,

        [Parameter(Mandatory)]
        [string] $Kind
    )

    $art = [string] $Conflict.Type
    $anderKind = [string] $Conflict.OtherKind
    $anderPfad = [string] $Conflict.OtherPath

    $zeilen = New-Object System.Collections.Generic.List[string]

    if ($art -ceq 'SameShareName') {

        $zeilen.Add('    HINWEIS: Dieser Freigabename ist in diesem Lauf schon vergeben.')
        $zeilen.Add(('      Freigabename: "{0}"' -f [string] $Conflict.ShareName))
        $zeilen.Add(('      Kollidiert mit: Ordnerart "{0}", Pfad "{1}"' -f $anderKind, $anderPfad))
        $zeilen.Add('      Grund: Ein Freigabename kann nur auf einen Ordner zeigen.')
        $zeilen.Add(('      Bitte für "{0}" einen anderen Freigabenamen angeben.' -f $Kind))

        return $zeilen.ToArray()
    }

    # VAL-01: ein Pfadkonflikt ist eine abgewiesene Eingabe und traegt die
    # Fehlermarke; der Freigabenamenzweig oben bleibt ein HINWEIS.
    $marke = Get-StatusMarkierung -Status 'Error'

    if ($art -ceq 'NestedPath') {
        $zeilen.Add(('    {0} Dieser Pfad liegt in einem anderen Ziel oder umgekehrt.' -f $marke))
        $zeilen.Add(('      Kollidiert mit: Ordnerart "{0}", Pfad "{1}"' -f $anderKind, $anderPfad))
        $zeilen.Add('      Grund: Ineinander liegende Freigabewurzeln greifen in die äußere Freigabe ein.')
    }
    else {
        $zeilen.Add(('    {0} Dieser Pfad ist in diesem Lauf schon vergeben.' -f $marke))
        $zeilen.Add(('      Kollidiert mit: Ordnerart "{0}", Pfad "{1}"' -f $anderKind, $anderPfad))
        $zeilen.Add('      Grund: Auf einem gemeinsamen Pfad überschreibt ein ACL das andere.')
    }

    $zeilen.Add(('      Bitte für "{0}" einen anderen Pfad angeben.' -f $Kind))

    return $zeilen.ToArray()
}

function Test-ShareNameInRun {
    <#
    .SYNOPSIS
        Prueft einen Freigabenamen auf Form und auf laufinterne Doppel. Intern
        zu Read-ShareName.

    .DESCRIPTION
        Zuerst die Form ueber Test-ShareNameValid, dann Get-TargetConflict mit
        einem Kandidaten, der den eingegebenen Namen traegt. Ein PRE-05-Datensatz
        des Kandidaten weist ab; der Grund ist der gegliederte Hinweis aus
        Format-ConflictHint, mehrzeilig (G-04-4f).

    .OUTPUTS
        [pscustomobject] mit IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    $form = Test-ShareNameValid -Name $Name

    if (-not [bool] $form.IsValid) { return $form }

    $kandidat = [pscustomobject] @{ Kind = $Kind; Path = $Path; ShareName = $Name }

    $konflikte = @(@(Get-TargetConflict -Target (@(@($Target) | Where-Object { $null -ne $_ }) + @($kandidat))) | Where-Object {
            ([string] $_.Kind -ceq $Kind) -and ([string] $_.Check -ceq 'PRE-05')
        })

    if ($konflikte.Count -gt 0) {
        return [pscustomobject] @{
            IsValid = $false
            Reason  = [string]::Join([System.Environment]::NewLine, [string[]] @(Format-ConflictHint -Conflict $konflikte[0] -Kind $Kind))
        }
    }

    return [pscustomobject] @{ IsValid = $true; Reason = '' }
}

function Test-ShareNameValid {
    <#
    .SYNOPSIS
        Prueft einen Freigabenamen auf Laenge und verbotene Zeichen. Intern zu
        Read-ShareName.

    .DESCRIPTION
        Geprueft wird die FORM und sonst nichts. Die Belegung entscheidet PRE-05,
        die Tauglichkeit des Pfades Test-TargetPathSafety -- beide im Preflight,
        beide genau einmal.

    .OUTPUTS
        [pscustomobject] mit IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [pscustomobject] @{ IsValid = $false; Reason = 'Der Freigabename darf nicht leer sein.' }
    }

    if ($Name.Length -gt 80) {
        return [pscustomobject] @{
            IsValid = $false
            Reason  = ('Der Freigabename ist {0} Zeichen lang; höchstens 80 sind zulässig.' -f $Name.Length)
        }
    }

    # Als Zeichencodes und nicht als Literalkette: eine Zeichenkette mit
    # Anfuehrungszeichen, Backslash und senkrechtem Strich ist in der Quelle
    # kaum noch lesbar und laedt zum Tippfehler ein.
    $verboten = @([char] 92, [char] 47, [char] 58, [char] 42, [char] 63, [char] 34, [char] 60, [char] 62, [char] 124)

    foreach ($zeichen in $verboten) {

        if ($Name.IndexOf($zeichen) -ge 0) {
            return [pscustomobject] @{
                IsValid = $false
                Reason  = ('Der Freigabename enthält das unzulässige Zeichen "{0}". Nicht erlaubt sind Schrägstriche, Doppelpunkt, Stern, Fragezeichen, Anführungszeichen, spitze Klammern und der senkrechte Strich.' -f $zeichen)
            }
        }
    }

    return [pscustomobject] @{ IsValid = $true; Reason = '' }
}

function Get-FixedOptGroup {
    <#
    .SYNOPSIS
        Die FEST belegten Optionsgruppen je Ordnerart -- die ohne Frage.

    .DESCRIPTION
        D-07: ComputerEnvironmentSettings ist fuer DEMConfig und DEMProfiles
        FEST ANGEWAEHLT. Der Projektinhaber hat bestaetigt, dass die Computer
        Environment Settings in dieser Umgebung genutzt werden. Das Template
        bleibt davon unberuehrt herstellertreu -- der Eintrag bleibt dort als
        optional gefuehrt und traegt sein Provenienz-Badge auch in der Ausgabe.
        Es ist eine feste Vorbelegung des Dialogs, keine Abweichung von der
        Herstellervorgabe.

        SystemLocalOps bleibt fest AUS: der Verwaltungsgruppen-Eintrag deckt
        serverlokale Arbeiten bereits ab, und ueber SMB authentifiziert der
        Agent als Maschinenkonto, das der Computerkonten-Eintrag traegt
        (FEATURES.md Paragraph 1.4, Zeile 4).

        ShareAdminFullControl bleibt fest AUS: der Eintrag ist abgeleitet und
        ohne Herstellerbeleg; Change auf Share-Ebene ist der
        herstellerwoertliche Zustand.

        IDENT-05: die Optionsgruppe Helpdesk des Share-Templates von DEMProfiles
        ist genau dann gewaehlt, wenn in diesem Lauf tatsaechlich eine
        Helpdesk-Gruppe gebunden wurde. Gewaehlt ohne Bindung liesse
        ConvertTo-ShareDesired ueber dem ungebundenen Token werfen; gebunden
        ohne gewaehlt liesse den herstellerwoertlichen Eintrag still unter den
        Tisch fallen. Beide Seiten lesen deshalb dasselbe eine Merkmal.

        Die beiden Listen sind NICHT dieselbe: Invoke-ShareApply erwartet die
        Namen des Share-Templates, Expand-AclTemplate die des ACL-Templates, und
        ein Name der einen Liste laesst die andere Funktion mit einer
        ArgumentException werfen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [ValidateSet('Acl', 'Share')]
        [string] $Scope
    )

    if ($Scope -eq 'Acl') {

        if (($Kind -eq 'DEMConfig') -or ($Kind -eq 'DEMProfiles')) {
            return @('ComputerEnvironmentSettings')
        }

        return @()
    }

    if (($Kind -eq 'DEMProfiles') -and (Test-HelpdeskBound)) {
        return @('Helpdesk')
    }

    return @()
}
