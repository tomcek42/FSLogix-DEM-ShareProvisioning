<#
    Read-AuditTarget -- der Dialog der Bestandspruefung (AUDIT-01, AUDIT-03,
    AUDIT-04, D-01, D-03, D-09 bis D-13).

    DIESE SCHICHT ERHEBT UND BESTAETIGT, SIE RECHNET NICHTS ACL-FACHLICHES.
    Erkennung (Find-AuditTarget), Rollenableitung (Get-AuditProductProposal)
    und Pruefung (Test-AuditTarget) stehen unter Private; hier wird gefragt,
    gezeigt und bestaetigt. Eingelesen wird ausschliesslich ueber die
    Fragefunktionen aus Read-OperatorInput.ps1 (FLOW-08).

    GERATEN WIRD NICHTS (D-09). Jede Zuordnung ist vor dem ersten Lesezugriff
    bestaetigt, jeder abgelesene Vorschlag vor seiner Uebernahme.

    VALIDATOREN OHNE GetNewClosure -- gemessen in Phase 4: die geschlossene
    Kopie bekommt einen neuen Modulskopus und findet die modulprivaten
    Funktionen nicht mehr.
#>

function Read-RunMode {
    <#
    .SYNOPSIS
        D-01: die erste Frage nach dem Banner -- neu einrichten, bestehende
        Struktur pruefen oder NTFS-Berechtigungen anpassen (Weg 3, 2026-09-24).

    .DESCRIPTION
        Vorgabe 1: das Anlegen bleibt der Normalfall, Enter fuehrt dorthin.
        Nach einem Durchlauf kehrt der Dialog ins Hauptmenue zurueck
        (Serverlauf 2026-09-25); dann ist Beenden die Vorgabe. Eine andere
        Eingabe als 0 bis 3 fuehrt zu Hinweis und erneuter Frage (FLOW-06).

    .PARAMETER DefaultChoice
        Die Vorgabe: 1 beim ersten Aufruf, 0 nach einem Durchlauf.

    .OUTPUTS
        [string] -- Provision, Audit, Adjust oder Exit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateSet('0', '1')]
        [string] $DefaultChoice = '1'
    )

    # NAV-01: der Kopf des Hauptmenues, ohne Zaehler, vor der unveraenderten
    # Optionsliste.
    Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'Menu')

    Add-PromptContext -Line @(
        ''
        '  Bitte wählen Sie eine Option:'
        ''
        '  [1] Neue FSLogix-/DEM-Struktur erstellen:'
        '      Ordner, Freigaben und Berechtigungen einrichten'
        ''
        '  [2] Bestehende FSLogix-/DEM-Struktur analysieren:'
        '      Ordner, Freigaben und Berechtigungen analysieren'
        ''
        '  [3] NTFS-Berechtigungen anpassen:'
        '      Gruppen hinzufügen, ersetzen oder entfernen'
        ''
        '  [0] Beenden'
        ''
    )

    $wahl = ([string] (Read-RequiredText -Prompt 'Option (0, 1, 2 oder 3)' -DefaultValue $DefaultChoice `
                -Validator { param($Wert) Test-RunModeChoice -Value $Wert })).Trim()

    if ($wahl -ceq '0') { return 'Exit' }
    if ($wahl -ceq '2') { return 'Audit' }
    if ($wahl -ceq '3') { return 'Adjust' }

    return 'Provision'
}

function Test-RunModeChoice {
    <#
    .SYNOPSIS
        Prueft die Antwort auf die Modusfrage: 0, 1, 2 oder 3 nach Trim.
        Intern zu Read-RunMode.

    .OUTPUTS
        [pscustomobject] mit IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $wert = $Value.Trim()

    if (@('0', '1', '2', '3') -ccontains $wert) {
        return [pscustomobject] @{ IsValid = $true; Reason = '' }
    }

    return [pscustomobject] @{ IsValid = $false; Reason = 'Erwartet wird 0, 1, 2 oder 3.' }
}

function Read-RunCloseChoice {
    <#
    .SYNOPSIS
        OUT-05 (v1.3), D-02: die Abschlussfrage nach einem Durchlauf --
        Hauptmenue, Bericht anzeigen oder Beenden.

    .DESCRIPTION
        NUR AUS DER MENUESCHLEIFE GERUFEN (Invoke-DemFsMenuLoop). Ohne
        -Menu gibt es genau einen Durchlauf und keine Abschlussfrage; die
        Antwortfolgen der Suite und die Regressionsaufnahmen bleiben damit
        unberuehrt (D-02).

        [R] IST DER DETAILMODUS (D-01): es gibt keinen eigenen Schalter und
        keine zweite Ausgabestufe. Den Bericht gibt die Menueschleife aus;
        diese Funktion fragt nur.

        Vorgabe E: nach einem Durchlauf ist Beenden schon die Vorgabe des
        Hauptmenues (Serverlauf 2026-09-25) -- ein Enter beendet damit wie
        bisher mit genau einem Tastendruck. m, r und e gelten wie M, R und E.

    .OUTPUTS
        [string] -- Menu, Report oder Exit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Add-PromptContext -Line @('')

    $wahl = ([string] (Read-RequiredText -Prompt '[M] Hauptmenü / [R] Bericht anzeigen / [E] Beenden' -DefaultValue 'E' `
                -Validator { param($Wert) Test-RunCloseChoice -Value $Wert })).Trim()

    if ([string]::Equals($wahl, 'M', [System.StringComparison]::OrdinalIgnoreCase)) { return 'Menu' }
    if ([string]::Equals($wahl, 'R', [System.StringComparison]::OrdinalIgnoreCase)) { return 'Report' }

    return 'Exit'
}

function Test-RunCloseChoice {
    <#
    .SYNOPSIS
        Prueft die Antwort auf die Abschlussfrage: M, R oder E nach Trim,
        ohne Ruecksicht auf Gross- und Kleinschreibung (ordinal). Intern zu
        Read-RunCloseChoice.

    .OUTPUTS
        [pscustomobject] mit IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $wert = $Value.Trim()

    foreach ($gueltig in @('M', 'R', 'E')) {
        if ([string]::Equals($wert, $gueltig, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject] @{ IsValid = $true; Reason = '' }
        }
    }

    return [pscustomobject] @{ IsValid = $false; Reason = 'Erwartet wird M, R oder E.' }
}

function Read-AuditRoot {
    <#
    .SYNOPSIS
        D-03: genau EIN Wurzelverzeichnis der bestehenden Struktur.

    .DESCRIPTION
        Gueltig ist, was Resolve-OperatorPath annimmt UND als Ordner besteht.
        Die Rueckgabe ist der Datensatz aus Resolve-OperatorPath -- die eine
        Normalisierungsstelle fuer Pfade (FLOW-05).

    .OUTPUTS
        [pscustomobject] mit Path, LeafName, IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # NAV-03: Schritt 1 von Weg 2 oder Weg 3, je nach Zweck. Der Kopf reist
    # als Kontext mit der ersten Frage des Schritts (Kanalregel in
    # Read-WizardStep.ps1).
    if ((Get-AuditWort -Key 'Tun') -ceq 'anpassen') {
        Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'AdjustRoot' -Sequence @(Get-WizardStepSequence -Mode Adjust))
    }
    else {
        Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'AuditRoot' -Sequence @(Get-WizardStepSequence -Mode Audit))
    }

    $eingabe = Read-RequiredText -Prompt 'Wurzelverzeichnis der bestehenden Struktur (genau eines)' `
        -Validator { param($Wert) Test-AuditRootValid -Value $Wert }

    return Resolve-OperatorPath -InputValue $eingabe
}

function Test-AuditRootValid {
    <#
    .SYNOPSIS
        Gueltig nach Resolve-OperatorPath und als Ordner vorhanden. Intern zu
        Read-AuditRoot.

    .OUTPUTS
        [pscustomobject] mit IsValid und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $pfad = Resolve-OperatorPath -InputValue $Value

    if (-not [bool] $pfad.IsValid) {
        return [pscustomobject] @{ IsValid = $false; Reason = [string] $pfad.Reason }
    }

    if (-not [System.IO.Directory]::Exists([string] $pfad.Path)) {
        return [pscustomobject] @{ IsValid = $false; Reason = ('Der Ordner "{0}" existiert nicht.' -f [string] $pfad.Path) }
    }

    return [pscustomobject] @{ IsValid = $true; Reason = '' }
}

function Read-AuditAssignment {
    <#
    .SYNOPSIS
        D-09: zeigt die gefundenen Ordner nummeriert und fragt, welche geprueft
        (Weg 2) oder angepasst (Weg 3) werden; bestaetigt vor dem ersten
        Lesezugriff.

    .DESCRIPTION
        DIE NUMMER WAEHLT AUS (Serverlauf 2026-09-25). Im frueheren Dialog hiess
        eine Nummer "Ordnerart dieses Ordners aendern"; wer einen nicht
        erkannten Ordner pruefen wollte, gab seine Nummer immer wieder ein und
        kam immer wieder zur Liste zurueck. Jetzt nennt der Operator die
        Nummern der gewuenschten Ordner; fuer jeden gewaehlten, nicht erkannten
        Ordner fragt der Dialog sofort die Ordnerart -- die Zuordnung ist dort
        Pflicht, geraten wird nichts (D-09). Weg 2 und Weg 3 teilen diese
        Auswahl; nur der Wortlaut folgt Set-AuditPurpose.

        Die Liste reist mit der Frage (G-04-3a): "Erkannt" und "Nicht erkannt"
        mit Nummer, Sammel- und Zwischenordner ohne Nummer. Vorgabe ist "alle
        erkannten", wenn es erkannte gibt; 0 waehlt keinen Ordner.

        Liegt ein gewaehlter Ordner der Ebene 2 unter einem gewaehlten Ordner
        der Ebene 1, entfaellt er mit Hinweis: unter einer Freigabewurzel wird
        nicht gesondert geprueft (D-06).

    .PARAMETER Scan
        Das Ergebnis von Find-AuditTarget.

    .OUTPUTS
        [pscustomobject] mit Target (je Ziel Kind, Path, RelativePath,
        ShareNames; in der Reihenfolge FSLogix-Profiles,
        FSLogix-Redirections, DEMConfig, DEMProfiles, DEMComputerLogs, je
        Ordnerart nach Pfad) und Unassigned
        (jeder nummerierte, nicht gewaehlte Ordner mit Grund, in
        Fundreihenfolge).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Scan
    )

    $eintraege = @(@($Scan.Entries) | Where-Object { $null -ne $_ })

    # Nummeriert: erst die erkannten, dann die nicht erkannten und offenen
    # DEM-Ordner, je in Fundreihenfolge. Die Nummer ist die Position hier.
    $nummeriert = @(
        @($eintraege | Where-Object { [string] $_.State -ceq 'Recognised' })
        @($eintraege | Where-Object { @('Unrecognised', 'DemOpen') -ccontains [string] $_.State })
    )

    $ohneNummer = @($eintraege | Where-Object { @('Collection', 'Container') -ccontains [string] $_.State })
    $erkanntZahl = @($nummeriert | Where-Object { [string] $_.State -ceq 'Recognised' }).Count

    Add-PromptContext -Line @(Format-AuditSelectionList -RootPath ([string] $Scan.RootPath) -Numbered $nummeriert -Unnumbered $ohneNummer)

    if ($nummeriert.Count -eq 0) {
        return [pscustomobject] @{ Target = @(); Unassigned = @() }
    }

    while ($true) {

        # Validator OHNE GetNewClosure -- $anzahl und $erkanntZahl sind ueber
        # die dynamische Skopusregel sichtbar (gemessen in Phase 4).
        $anzahl = $nummeriert.Count
        $vorgabe = if ($erkanntZahl -gt 0) { 'alle erkannten' } else { '' }

        $antwort = ([string] (Read-RequiredText -Prompt ('Welche Ordner {0}? (Nummern, z. B. 1 oder 1,3; 0 = keinen)' -f (Get-AuditWort -Key 'Tun')) `
                    -DefaultValue $vorgabe `
                    -Validator { param($Wert) Test-AuditSelectionChoice -Value $Wert -Count $anzahl -RecognisedCount $erkanntZahl })).Trim()

        $gewaehlt = New-Object System.Collections.Generic.List[object]

        foreach ($nummer in @(ConvertFrom-AuditSelectionChoice -Value $antwort -Count $anzahl -RecognisedCount $erkanntZahl)) {

            $eintrag = $nummeriert[$nummer - 1]

            if ([string] $eintrag.State -ceq 'Recognised') {
                $gewaehlt.Add([pscustomobject] @{ Entry = $eintrag; Kind = [string] $eintrag.Kind; Checked = $true })
                continue
            }

            $frage = 'Ordnerart für "{0}" (1 = FSLogix-Profiles, 2 = DEMConfig, 3 = DEMProfiles, 4 = DEMComputerLogs, 5 = FSLogix-Redirections, 0 = doch nicht {1})' -f [string] $eintrag.RelativePath, (Get-AuditWort -Key 'Tun')

            $art = ConvertFrom-AuditKindChoice -Value ([string] (Read-RequiredText -Prompt $frage `
                        -Validator { param($Wert) Test-AuditKindChoice -Value $Wert }))

            if ($art -ceq '0') { continue }

            $gewaehlt.Add([pscustomobject] @{ Entry = $eintrag; Kind = $art; Checked = $true })
        }

        # Unter einer gewaehlten Freigabewurzel der Ebene 1 entfaellt jeder
        # gewaehlte Ordner darunter (D-06).
        $hinweis = New-Object System.Collections.Generic.List[string]
        $unterWurzel = @{}

        foreach ($oben in @($gewaehlt | Where-Object { [int] $_.Entry.Level -eq 1 })) {

            $praefix = ConvertTo-PfadPraefix -LiteralPath ([string] $oben.Entry.Path)

            foreach ($unten in @($gewaehlt | Where-Object { [int] $_.Entry.Level -eq 2 })) {
                $eigen = ConvertTo-PfadPraefix -LiteralPath ([string] $unten.Entry.Path)
                if (-not $eigen.StartsWith($praefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $unterWurzel[[string] $unten.Entry.Path] = $true
                $hinweis.Add(('    "{0}" liegt unter "{1}" und wird nicht gesondert {2}.' -f
                        [string] $unten.Entry.RelativePath, [string] $oben.Entry.RelativePath, (Get-AuditWort -Key 'Getan')))
            }
        }

        $ziele = @(Get-AuditOrderedTarget -State @($gewaehlt | Where-Object { -not $unterWurzel.ContainsKey([string] $_.Entry.Path) }))

        # --- Bestaetigung vor dem ersten Lesezugriff (D-09) ------------------
        $liste = New-Object System.Collections.Generic.List[string]
        if ($hinweis.Count -gt 0) { $liste.Add(''); foreach ($h in $hinweis) { $liste.Add($h) } }
        $liste.Add('')
        $liste.Add(('  {0} werden:' -f (Get-AuditWort -Key 'GetanGross')))
        if ($ziele.Count -eq 0) { $liste.Add('    (kein Ordner)') }
        foreach ($ziel in $ziele) {
            $liste.Add(('    {0} -> {1}' -f [string] $ziel.Entry.RelativePath, [string] $ziel.Kind))
        }
        Add-PromptContext -Line $liste.ToArray()

        if (-not (Read-YesNoAnswer -Prompt (Get-AuditWort -Key 'Frage') -Default $true)) {
            Add-PromptContext -Line @(Format-AuditSelectionList -RootPath ([string] $Scan.RootPath) -Numbered $nummeriert -Unnumbered $ohneNummer)
            continue
        }

        Add-PromptContext -Line @('')

        $zielDaten = @($ziele | ForEach-Object {
                [pscustomobject] @{
                    Kind         = [string] $_.Kind
                    Path         = [string] $_.Entry.Path
                    RelativePath = [string] $_.Entry.RelativePath
                    ShareNames   = @($_.Entry.ShareNames)
                }
            })

        $gewaehltPfad = @{}
        foreach ($ziel in $ziele) { $gewaehltPfad[[string] $ziel.Entry.Path] = $true }

        # Nicht gewaehlt, in Fundreihenfolge (Planerentscheid 6). Sammel- und
        # Zwischenordner zaehlen nicht dazu.
        $offen = New-Object System.Collections.Generic.List[object]

        foreach ($eintrag in $nummeriert) {

            $pfad = [string] $eintrag.Path
            if ($gewaehltPfad.ContainsKey($pfad)) { continue }

            $grund = Get-AuditUnselectedReason -Entry $eintrag -Selected $ziele -BelowRoot $unterWurzel.ContainsKey($pfad)

            $offen.Add([pscustomobject] @{
                    Path         = $pfad
                    RelativePath = [string] $eintrag.RelativePath
                    Reason       = $grund
                })
        }

        return [pscustomobject] @{ Target = $zielDaten; Unassigned = $offen.ToArray() }
    }
}

function Get-AuditUnselectedReason {
    <#
    .SYNOPSIS
        Warum ein nummerierter Ordner nicht geprueft wird. Intern zu
        Read-AuditAssignment.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Entry,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Selected,

        [Parameter()]
        [bool] $BelowRoot = $false
    )

    if ($BelowRoot) { return 'liegt unter einer Freigabewurzel' }

    if ([int] $Entry.Level -eq 2) {
        $eigen = ConvertTo-PfadPraefix -LiteralPath ([string] $Entry.Path)
        foreach ($oben in @($Selected | Where-Object { [int] $_.Entry.Level -eq 1 })) {
            $praefix = ConvertTo-PfadPraefix -LiteralPath ([string] $oben.Entry.Path)
            if ($eigen.StartsWith($praefix, [System.StringComparison]::OrdinalIgnoreCase)) { return 'liegt unter einer Freigabewurzel' }
        }
    }

    if ([string] $Entry.State -ceq 'Recognised') { return 'nicht ausgewählt' }

    $grund = [string] $Entry.Reason
    if ([string]::IsNullOrEmpty($grund)) { return 'nicht ausgewählt' }

    return $grund
}

function Get-AuditOrderedTarget {
    <#
    .SYNOPSIS
        Die gewaehlten Ordner in der Reihenfolge der Ordnerarten (FSLogix vor
        DEM: FSLogix-Profiles, FSLogix-Redirections, DEMConfig, DEMProfiles,
        DEMComputerLogs), je Ordnerart nach Pfad. Intern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $State
    )

    $ziele = New-Object System.Collections.Generic.List[object]

    foreach ($art in @('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')) {
        foreach ($satz in @($State | Where-Object { [bool] $_.Checked -and ([string] $_.Kind -ceq $art) } |
                    Sort-Object -Property { [string] $_.Entry.Path })) {
            $ziele.Add($satz)
        }
    }

    return $ziele.ToArray()
}

function Format-AuditSelectionList {
    <#
    .SYNOPSIS
        Die Ordnerliste als Promptkontext. Intern zu Read-AuditAssignment.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $RootPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Numbered,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Unnumbered
    )

    $zeilen = New-Object System.Collections.Generic.List[string]
    $zeilen.Add('')
    $zeilen.Add(('  Gefunden unter "{0}":' -f $RootPath))

    $zeilen.Add('    Erkannt:')
    $erkanntDa = $false

    for ($i = 0; $i -lt $Numbered.Count; $i++) {

        $eintrag = $Numbered[$i]
        if ([string] $eintrag.State -cne 'Recognised') { continue }
        $erkanntDa = $true

        $freigabe = ''
        $namen = @(@($eintrag.ShareNames) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) })
        if ($namen.Count -gt 0) { $freigabe = ' (Freigabe {0})' -f ($namen -join ', ') }

        $zeilen.Add(('    {0,3}) {1} -> {2}{3}' -f ($i + 1), [string] $eintrag.RelativePath, [string] $eintrag.Kind, $freigabe))
    }

    if (-not $erkanntDa) { $zeilen.Add('      (keiner)') }

    if (@($Unnumbered).Count -gt 0) {
        $zeilen.Add(('    Sammel- und Zwischenordner (werden nicht {0}):' -f (Get-AuditWort -Key 'Getan')))
        foreach ($eintrag in $Unnumbered) {
            $art = if ([string] $eintrag.State -ceq 'Collection') { 'Sammelordner' } else { 'Zwischenordner' }
            $zeilen.Add(('          {0} ({1})' -f [string] $eintrag.RelativePath, $art))
        }
    }

    $nichtDa = $false
    for ($i = 0; $i -lt $Numbered.Count; $i++) {

        $eintrag = $Numbered[$i]
        if ([string] $eintrag.State -ceq 'Recognised') { continue }

        if (-not $nichtDa) {
            $zeilen.Add(('    Nicht erkannt (werden nur mit Zuordnung {0}):' -f (Get-AuditWort -Key 'Getan')))
            $nichtDa = $true
        }

        $zeilen.Add(('    {0,3}) {1} ({2})' -f ($i + 1), [string] $eintrag.RelativePath, [string] $eintrag.Reason))
    }

    if ($Numbered.Count -eq 0) { $zeilen.Add('    Es wurde kein Ordner gefunden.') }

    return $zeilen.ToArray()
}

function Test-AuditSelectionChoice {
    <#
    .SYNOPSIS
        "alle erkannten" (nur wenn es erkannte gibt), 0 oder Nummern von 1
        bis Count. Intern zu Read-AuditAssignment.

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
        [int] $Count,

        [Parameter()]
        [int] $RecognisedCount = 0
    )

    $wert = $Value.Trim()

    if ($wert -ceq '0') { return [pscustomobject] @{ IsValid = $true; Reason = '' } }

    if (@(ConvertFrom-AuditSelectionChoice -Value $wert -Count $Count -RecognisedCount $RecognisedCount).Count -gt 0) {
        return [pscustomobject] @{ IsValid = $true; Reason = '' }
    }

    $alle = if ($RecognisedCount -gt 0) { '"alle erkannten", ' } else { '' }

    return [pscustomobject] @{
        IsValid = $false
        Reason  = ('Erwartet wird {0}0 oder eine oder mehrere Nummern zwischen 1 und {1}, z. B. 1 oder 1,3.' -f $alle, $Count)
    }
}

function ConvertFrom-AuditSelectionChoice {
    <#
    .SYNOPSIS
        Die gewaehlten Nummern, aufsteigend und ohne Doppelte; leer bei 0 oder
        ungueltiger Eingabe. "alle erkannten" (auch "alle") steht fuer die
        erkannten Ordner, die in der Nummerierung vorn stehen.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter()]
        [int] $RecognisedCount = 0
    )

    $text = $Value.Trim()

    foreach ($wort in @('alle erkannten', 'alle')) {
        if ([string]::Equals($text, $wort, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($RecognisedCount -lt 1) { return [int[]] @() }
            return [int[]] @(1..$RecognisedCount)
        }
    }

    $teile = @($text -split '[,;\s]+' | Where-Object { $_.Length -gt 0 })
    if ($teile.Count -eq 0) { return [int[]] @() }

    $nummern = New-Object System.Collections.Generic.List[int]

    foreach ($teil in $teile) {
        $zahl = 0
        if (-not [int]::TryParse($teil, [ref] $zahl)) { return [int[]] @() }
        if (($zahl -lt 1) -or ($zahl -gt $Count)) { return [int[]] @() }
        if (-not $nummern.Contains($zahl)) { $nummern.Add($zahl) }
    }

    return [int[]] @($nummern | Sort-Object)
}

function Test-AuditPickNumber {
    <#
    .SYNOPSIS
        Eine Nummer von 1 bis Count. Intern zur Interaktionsschicht.
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

    $zahl = 0

    if ([int]::TryParse($Value.Trim(), [ref] $zahl) -and ($zahl -ge 1) -and ($zahl -le $Count)) {
        return [pscustomobject] @{ IsValid = $true; Reason = '' }
    }

    return [pscustomobject] @{ IsValid = $false; Reason = ('Erwartet wird eine Nummer zwischen 1 und {0}.' -f $Count) }
}

function Test-AuditKindChoice {
    <#
    .SYNOPSIS
        Die Wahl einer Ordnerart: 0 bis 5. Intern zu Read-AuditAssignment.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    if (@('0', '1', '2', '3', '4', '5') -ccontains $Value.Trim()) { return [pscustomobject] @{ IsValid = $true; Reason = '' } }

    return [pscustomobject] @{ IsValid = $false; Reason = 'Erwartet wird 0 bis 5.' }
}

function ConvertFrom-AuditKindChoice {
    <#
    .SYNOPSIS
        Die Wahl als Ordnerart, oder "0". Intern.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    switch ($Value.Trim()) {
        '1' { return 'FSLogix-Profiles' }
        '2' { return 'DEMConfig' }
        '3' { return 'DEMProfiles' }
        '4' { return 'DEMComputerLogs' }
        '5' { return 'FSLogix-Redirections' }
        default { return '0' }
    }
}

function Read-AuditGroupBinding {
    <#
    .SYNOPSIS
        D-11, D-12: die am vorhandenen ACL abgelesenen Gruppen eines Produkts
        als Vorschlag bestaetigen -- sonst die normale Gruppenabfrage.

    .DESCRIPTION
        Fuer jede Rolle, die Get-RequiredTrusteeToken ueber die Ordnerarten des
        Produkts verlangt, in der Reihenfolge Admin, User, Computer: bei einem
        eindeutigen Vorschlag die abgelesene Gruppe mit Pfad, Anzeigename und
        SID (IDENT-06) und die Frage nach der Uebernahme, Vorgabe ja. Bei Nein,
        ohne Vorschlag oder bei mehreren Kandidaten die normale Abfrage ueber
        Read-TrusteeRole (samt FSLogix-Angebot im DEM-Block).

        Bestaetigte Vorschlaege landen ueber Set-TrusteeRoleRecord im
        Rollenspeicher -- die eine Wahrheit ueber gebundene Gruppen.

    .OUTPUTS
        [pscustomobject] mit OptGroup: die bestaetigten Optionsgruppen.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [object] $Proposal,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Kind
    )

    $gewaehlt = New-Object System.Collections.Generic.List[string]

    # --- 1. Optionen (D-13) -------------------------------------------------
    # Nur die am Ordner erkannten werden gefragt; eine nicht erkannte gilt als
    # nicht gewaehlt -- das Soll ist dann herstellerwoertlich ohne sie.
    foreach ($name in @('SystemAndBuiltinAdmins', 'ComputerEnvironmentSettings')) {

        if (-not $Proposal.OptGroup.ContainsKey($name)) { continue }
        if (-not [bool] $Proposal.OptGroup[$name]) { continue }

        $pfad = ''
        if ($Proposal.OptGroupPath.ContainsKey($name)) { $pfad = [string] $Proposal.OptGroupPath[$name] }

        $optionsFrage = 'Option "{0}" ist am Ordner "{1}" gesetzt -- als Soll übernehmen?' -f $name, $pfad

        if (Read-YesNoAnswer -Prompt $optionsFrage -Default $true) { $gewaehlt.Add($name) }

        Add-PromptContext -Line @('')
    }

    # --- 2. Rollen unter den bestaetigten Optionen ---------------------------
    foreach ($rolle in @(Get-AuditRequiredRole -Kind $Kind -AclOptGroup $gewaehlt.ToArray())) {
        Read-AuditRoleChoice -Product $Product -Role $rolle -Proposal $Proposal
    }

    # --- 3. Helpdesk (nur DEM mit DEMProfiles-Ziel) --------------------------
    if (($Product -ceq 'DEM') -and (@($Kind) -ccontains 'DEMProfiles')) {
        Read-AuditHelpdeskChoice -Proposal $Proposal
    }

    return [pscustomobject] @{ OptGroup = $gewaehlt.ToArray() }
}

function Read-AuditHelpdeskChoice {
    <#
    .SYNOPSIS
        Die Helpdesk-Gruppe im Pruefweg: an der DEMProfiles-Freigabe
        abgelesen, bestaetigt oder normal gefragt (D-13). Intern zu
        Read-AuditGroupBinding.

    .DESCRIPTION
        Found: Vorschlag mit Anzeigename und SID, Vorgabe ja; Ja bindet ueber
        Set-HelpdeskResolution. Nein oder Ambiguous: die normale, optionale
        Abfrage Read-HelpdeskGroup. NotFound: geklaert, nicht gebunden -- das
        Soll ist herstellerwoertlich ohne Helpdesk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Proposal
    )

    $satz = $Proposal.Helpdesk

    if (($null -eq $satz) -or ([string] $satz.State -ceq 'NotFound')) {
        Set-HelpdeskResolution
        return
    }

    if ([string] $satz.State -ceq 'Found') {

        $anzeige = Get-TrusteeDisplayName -Sid $satz.Sid

        Add-PromptContext -Severity 'OK' -Line @(
            ('    Abgelesen an  : {0}' -f [string] $satz.Path)
            ('    Aufgelöst auf: {0}' -f $anzeige)
            ('    SID           : {0}' -f [string] $satz.Sid.Value)
        )

        if (Read-YesNoAnswer -Prompt 'Helpdesk-Gruppe (DEM): die an der Freigabe abgelesene Gruppe übernehmen?' -Default $true) {

            Set-HelpdeskResolution -Record ([pscustomobject] @{
                    InputValue  = [string] $satz.Sid.Value
                    Sid         = $satz.Sid
                    DisplayName = $anzeige
                })

            Add-PromptContext -Line @('')
            return
        }
    }
    else {
        Add-PromptContext -Severity 'Warning' -Line @(
            ('    Keine eindeutige Helpdesk-Gruppe abgelesen ({0} Kandidaten).' -f [int] $satz.Count)
        )
    }

    $null = Read-HelpdeskGroup
}

function Get-AuditRequiredRole {
    <#
    .SYNOPSIS
        Die Rollen, die die Ordnerarten eines Produkts unter den gewaehlten
        Optionsgruppen verlangen, in der Reihenfolge Admin, User, Computer.
        Intern.

    .DESCRIPTION
        Abgelesen ueber Get-RequiredTrusteeToken -- aus den Templates, nicht aus
        einer Liste im Dialog. Die Helpdesk-Rolle fragt diese Funktion nie;
        sie hat eine eigene Fragefolge.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $AclOptGroup = @()
    )

    $karte = Get-TokenRoleMap
    $gesucht = New-Object System.Collections.Generic.List[string]

    foreach ($art in @($Kind)) {

        $optionen = @(Get-AuditKindOptGroup -Kind $art -OptGroup $AclOptGroup)

        foreach ($token in @(Get-RequiredTrusteeToken -Kind $art -AclOptGroup $optionen `
                    -ShareOptGroup @(Get-FixedOptGroup -Kind $art -Scope 'Share'))) {

            if (-not $karte.ContainsKey($token)) { continue }
            $rolle = [string] $karte[$token]
            if ($rolle -ceq 'Helpdesk') { continue }
            if (-not $gesucht.Contains($rolle)) { $gesucht.Add($rolle) }
        }
    }

    return @(@('Admin', 'User', 'Computer') | Where-Object { $gesucht.Contains($_) })
}

function Get-AuditKindOptGroup {
    <#
    .SYNOPSIS
        Die bestaetigten ACL-Optionsgruppen, die zur Ordnerart gehoeren.
        Intern.

    .DESCRIPTION
        SystemAndBuiltinAdmins gehoert zu FSLogix-Profiles,
        ComputerEnvironmentSettings zu DEMConfig und DEMProfiles;
        FSLogix-Redirections und DEMComputerLogs haben keine. Eine
        Optionsgruppe, die das Template der Ordnerart nicht kennt, liesse
        Expand-AclTemplate werfen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $OptGroup = @()
    )

    $gewaehlt = @(@($OptGroup) | Where-Object { -not [string]::IsNullOrEmpty($_) })

    if ($Kind -ceq 'FSLogix-Profiles') {
        return @($gewaehlt | Where-Object { $_ -ceq 'SystemAndBuiltinAdmins' })
    }

    if (($Kind -ceq 'DEMConfig') -or ($Kind -ceq 'DEMProfiles')) {
        return @($gewaehlt | Where-Object { $_ -ceq 'ComputerEnvironmentSettings' })
    }

    return @()
}

function Read-AuditRoleChoice {
    <#
    .SYNOPSIS
        Eine Rolle eines Produkts: Vorschlag bestaetigen oder normal fragen.
        Intern zu Read-AuditGroupBinding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer')]
        [string] $Role,

        [Parameter(Mandatory)]
        [object] $Proposal
    )

    # Schon erhoben -- etwa ueber die Helpdesk-Klaerung: nicht erneut.
    if ((Get-TrusteeRoleStore -Product $Product).ContainsKey($Role)) { return }

    $satz = $null
    if ($Proposal.Role.ContainsKey($Role)) { $satz = $Proposal.Role[$Role] }

    if (($null -ne $satz) -and ([string] $satz.State -ceq 'Found')) {

        $anzeige = Get-TrusteeDisplayName -Sid $satz.Sid

        Add-PromptContext -Severity 'OK' -Line @(
            ('    Abgelesen an  : {0}' -f [string] $satz.Path)
            ('    Aufgelöst auf: {0}' -f $anzeige)
            ('    SID           : {0}' -f [string] $satz.Sid.Value)
        )

        $frage = '{0} ({1}): die am Ordner abgelesene Gruppe übernehmen?' -f (Get-TrusteeRoleLabel -Role $Role), $Product

        if (Read-YesNoAnswer -Prompt $frage -Default $true) {

            Set-TrusteeRoleRecord -Product $Product -Role $Role -Record ([pscustomobject] @{
                    InputValue  = [string] $satz.Sid.Value
                    Sid         = $satz.Sid
                    DisplayName = $anzeige
                })

            Add-PromptContext -Line @('')
            return
        }
    }
    elseif (($null -ne $satz) -and ([string] $satz.State -ceq 'Ambiguous')) {
        Add-PromptContext -Severity 'Warning' -Line @(
            ('    Keine eindeutige Gruppe abgelesen ({0} Kandidaten) -- bitte angeben.' -f [int] $satz.Count)
        )
    }

    $null = Read-TrusteeRole -Role $Role -Product $Product
}

function Read-AuditAdjustOffer {
    <#
    .SYNOPSIS
        Das Angebot nach dem Pruefbericht: die abweichenden Ziele ueber den
        Schreibpfad angleichen? Vorgabe nein (D-02, AUDIT-07).

    .DESCRIPTION
        Gestellt wird die Frage nur, wenn es abweichende Ziele gibt -- das
        entscheidet der Aufrufer. Wer ablehnt oder Enter drueckt, hat einen
        reinen Prueflauf: bis hierhin wurde nichts geschrieben und nichts
        geprobt.

    .PARAMETER Deviation
        Die Datensaetze aus Select-AuditDeviation.

    .OUTPUTS
        [bool] -- wahr heisst angleichen.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object[]] $Deviation
    )

    $abweichend = @(@($Deviation) | Where-Object { $null -ne $_ })

    $zeilen = New-Object System.Collections.Generic.List[string]
    $zeilen.Add('  Abweichende Ziele:')

    foreach ($satz in $abweichend) {

        # Die Gruende in Kurzform (NTFS, Freigabe fehlt, Freigabe, Caching).
        $gruende = @()
        if ($null -ne $satz.PSObject.Properties['Reason']) { $gruende = @(@($satz.Reason) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) }) }
        $zusatz = if ($gruende.Count -gt 0) { ' -- ' + ($gruende -join ', ') } else { '' }

        $zeilen.Add(('    {0} ({1}){2}' -f (Get-AuditAdjustLabel -Deviation $satz), [string] $satz.Kind, $zusatz))

        # Weitere Freigaben auf demselben Pfad bleiben unveraendert
        # (Planerentscheid 11) -- ausdruecklich genannt, nicht still.
        $bleiben = @()
        if ($null -ne $satz.PSObject.Properties['KeptShareNames']) { $bleiben = @(@($satz.KeptShareNames) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) }) }
        if ($bleiben.Count -gt 0) { $zeilen.Add(('      bleibt unverändert: {0}' -f ($bleiben -join ', '))) }
    }

    Add-PromptContext -Line @('')
    Add-PromptContext -Line $zeilen.ToArray()

    return (Read-YesNoAnswer -Prompt ('Diese {0} Ziele jetzt über den Schreibpfad angleichen?' -f $abweichend.Count) -Default $false)
}

function Get-AuditAdjustLabel {
    <#
    .SYNOPSIS
        Die Bezeichnung eines abweichenden Ziels im Angebot: relativ zur
        Wurzel, bei der Wurzel selbst ihr Blattname. Intern.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Deviation
    )

    $relativ = [string] $Deviation.RelativePath

    if ([string]::IsNullOrEmpty($relativ) -or ($relativ -ceq '.')) {
        $relativ = [System.IO.Path]::GetFileName(([string] $Deviation.Path).TrimEnd([char] 92, [char] 47))
        if ([string]::IsNullOrEmpty($relativ)) { $relativ = [string] $Deviation.Path }
    }

    return $relativ
}

function Read-UserFolderOffer {
    <#
    .SYNOPSIS
        Die Frage am Ende von Weg 2: auch die Benutzerordner der
        Profilablagen pruefen? Vorgabe nein (USR-01).

    .DESCRIPTION
        Gestellt wird die Frage nur, wenn unter den geprueften Zielen
        mindestens eine FSLogix-Profiles- oder DEMProfiles-Ablage ist -- das
        entscheidet der Aufrufer. Wer ablehnt oder Enter drueckt, liest keinen
        einzigen Benutzerordner. Auch nach einem Ja wird nur gelesen; ein
        Angleichen der Benutzerordner gibt es nicht (USR-09).

    .PARAMETER Root
        Die Profilablagen aus Select-UserFolderRoot.

    .OUTPUTS
        [bool] -- wahr heisst pruefen.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object[]] $Root
    )

    $zeilen = New-Object System.Collections.Generic.List[string]
    $zeilen.Add('  Die Benutzerordner der ersten Ebene unter diesen Ablagen lassen sich')
    $zeilen.Add('  zusätzlich rein lesend prüfen: Besitzer, abgeschaltete Vererbung und')
    $zeilen.Add('  fremde explizite Einträge. Geändert wird nichts.')

    foreach ($ablage in @(@($Root) | Where-Object { $null -ne $_ })) {
        $zeilen.Add(('    {0}: {1}' -f [string] $ablage.Kind, [string] $ablage.Path))
    }

    Add-PromptContext -Line @('')
    Add-PromptContext -Line $zeilen.ToArray()

    return (Read-YesNoAnswer -Prompt 'Auch die Benutzerordner prüfen?' -Default $false)
}

function Read-AuditAdjustTarget {
    <#
    .SYNOPSIS
        Baut aus den abweichenden Zielen die Ziele des Schreibpfads; fehlt
        eine Freigabe, wird ihr Name erfragt (D-04, SHARE-02, G-04-4b).

    .DESCRIPTION
        Der Datensatz hat die Form, die Invoke-ProvisioningWrite auch von
        Weg 1 bekommt: Kind, Path, ShareName, IsExisting (immer wahr),
        Binding, AclOptGroup, ShareOptGroup.

        Den Freigabenamen bestimmt der Abweichungsdatensatz. Ist er leer --
        auf den Pfad zeigt keine Freigabe --, fragt Read-ShareName mit dem
        Vorschlag Blattname plus '$'; die Laufdoppel-Pruefung ueber
        Get-TargetConflict kommt damit unveraendert mit. Angelegt wird die
        Freigabe spaeter wie beim Anlegen: erst nach verifiziertem ACL
        (SHARE-03).

    .PARAMETER Target
        Die Datensaetze aus Select-AuditDeviation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Target
    )

    $erhoben = New-Object System.Collections.Generic.List[object]

    foreach ($satz in @($Target)) {

        if ($null -eq $satz) { continue }

        $art = [string] $satz.Kind
        $pfad = [string] $satz.Path
        $name = [string] $satz.ShareName

        if ([string]::IsNullOrWhiteSpace($name)) {
            $blatt = [System.IO.Path]::GetFileName($pfad.TrimEnd([char] 92, [char] 47))
            $name = Read-ShareName -Kind $art -DefaultName $blatt -Path $pfad -Target $erhoben.ToArray()
        }

        $erhoben.Add([pscustomobject] @{
                Kind          = $art
                Path          = $pfad
                ShareName     = $name
                IsExisting    = $true
                Binding       = $satz.Binding
                AclOptGroup   = @($satz.AclOptGroup)
                ShareOptGroup = @($satz.ShareOptGroup)
            })
    }

    return $erhoben.ToArray()
}

function Set-AuditPurpose {
    <#
    .SYNOPSIS
        Legt fest, wofuer die Zuordnung gebraucht wird: Pruefen (Weg 2) oder
        Anpassen (Weg 3). Steuert nur den Wortlaut der Fragen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Audit', 'Adjust')]
        [string] $Purpose
    )

    $script:AuditZweck = $Purpose
}

function Get-AuditWort {
    <#
    .SYNOPSIS
        Der Wortlaut der Zuordnungsfragen zum aktuellen Zweck. Ohne gesetzten
        Zweck gilt Pruefen -- der Wortlaut von Weg 2 bleibt damit unveraendert.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Tun', 'Getan', 'GetanGross', 'Frage')]
        [string] $Key
    )

    $zweck = Get-Variable -Name 'AuditZweck' -Scope Script -ValueOnly -ErrorAction SilentlyContinue

    $woerter = if ($zweck -ceq 'Adjust') {
        @{ Tun = 'anpassen'; Getan = 'angepasst'; GetanGross = 'Angepasst'; Frage = 'Diese Ordner anpassen?' }
    }
    else {
        @{ Tun = 'prüfen'; Getan = 'geprüft'; GetanGross = 'Geprüft'; Frage = 'Diese Zuordnung prüfen?' }
    }

    return [string] $woerter[$Key]
}
