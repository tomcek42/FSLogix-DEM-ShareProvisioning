<#
    Read-WizardStep -- die Schrittfuehrung von Weg 1 (Phase 9, NAV-01,
    NAV-02, ERF-03 bis ERF-05); seit 09-02 auch die Schrittfolgen von Weg 2
    und Weg 3 (NAV-03).

    EINE WAHRHEIT UEBER NUMMER UND GESAMTZAHL. Get-WizardStepSequence
    liefert die Schrittschluessel der gewaehlten Auswahl; jeder Kopf
    "[Schritt x/y]" entsteht aus dieser Folge ueber
    Get-DialogUeberschriftZeile -Sequence. Entfallende Schritte zaehlen
    nicht mit: ohne FSLogix-Ordnerart gibt es ConfigFSLogix nicht, ohne
    DEM-Ordnerart ConfigDEM nicht.

    KANALREGEL (Planer-Entscheidung 6, Entscheidung Projektinhaber
    2026-09-30). Beginnt ein Schritt mit einer Frage, reist sein Kopf als
    Rueckfragekontext (Add-PromptContext, Schwere Heading) -- unter
    '> datei' im Prompt, sonst farbig ueber die Ausgabenaht. Beginnt er mit
    einer Ausgabe, geht der Kopf ueber Write-OperatorLine
    (Get-StepHeaderRecord). Die Gruppenuebersicht gehoert zur Frage
    "Weiter?" und reist als Kontext. Der Kurzueberblick nach jeder
    erfassten Ordnerart geht DIREKT ueber Write-OperatorLine: als Kontext
    hinge der letzte Ueberblick bis zur JA-Frage in der Warteschlange und
    erschiene NACH dem Plan. Unter '-File > datei' steht er damit in der
    Datei und nicht auf der Konsole -- gewollt.

    DIESE DATEI LIEST NICHT SELBST UND GIBT NICHT SELBST AUS. Gelesen wird
    ueber die Fragefunktionen aus Read-OperatorInput.ps1, ausgegeben ueber
    Add-PromptContext bzw. die Zeilensaetze, die der Aufrufer an
    Write-OperatorLine gibt.
#>

function Get-WizardStepSequence {
    <#
    .SYNOPSIS
        Die Schrittschluessel eines Weges fuer eine gegebene Auswahl
        (NAV-02).

    .DESCRIPTION
        Provision: Kinds, Groups, ConfigFSLogix (nur mit FSLogix-Profiles
        oder FSLogix-Redirections), ConfigDEM (nur mit einer DEM-Ordnerart),
        Check -- in dieser Reihenfolge.

        Audit (Weg 2) und Adjust (Weg 3), Entscheidung Projektinhaber
        2026-09-30 (NAV-03): eine feste Schrittzahl, unabhaengig von der
        Auswahl. Weg 3: AdjustRoot, AdjustChange, Check. Weg 2 seit
        2026-10-22 nur noch AuditRoot, AuditReport -- die Gruppen werden nicht
        mehr bestaetigt, und ein Angleichen gibt es in Weg 2 nicht mehr.
        Ansichtswahl und Benutzerordner-Bericht gehoeren zu "Pruefung und
        Bericht".

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Provision', 'Audit', 'Adjust')]
        [string] $Mode,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Kind = @()
    )

    if ($Mode -ceq 'Audit') { return [string[]] @('AuditRoot', 'AuditReport') }
    if ($Mode -ceq 'Adjust') { return [string[]] @('AdjustRoot', 'AdjustChange', 'Check') }

    $arten = @(@($Kind) | Where-Object { $null -ne $_ })

    $folge = New-Object System.Collections.Generic.List[string]
    $folge.Add('Kinds')
    $folge.Add('Groups')

    if (($arten -ccontains 'FSLogix-Profiles') -or ($arten -ccontains 'FSLogix-Redirections')) {
        $folge.Add('ConfigFSLogix')
    }

    if (($arten -ccontains 'DEMConfig') -or ($arten -ccontains 'DEMProfiles') -or ($arten -ccontains 'DEMComputerLogs')) {
        $folge.Add('ConfigDEM')
    }

    $folge.Add('Check')

    return $folge.ToArray()
}

function Get-StepHeaderRecord {
    <#
    .SYNOPSIS
        Ein Schrittkopf als Zeilensaetze fuer die Ausgabenaht (NAV-01).

    .DESCRIPTION
        Fuer Schritte, die mit einer Ausgabe beginnen (Kanalregel im
        Dateikopf). Die Leerzeile ohne Schwere, die Kopfzeilen mit Schwere
        Heading.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Sequence
    )

    $zeilen = New-Object System.Collections.Generic.List[object]

    foreach ($text in @(Get-DialogUeberschriftZeile -Key $Key -Sequence $Sequence)) {
        $schwere = if ([string]::IsNullOrEmpty([string] $text)) { 'None' } else { 'Heading' }
        $zeilen.Add((New-OperatorTextLine -Text ([string] $text) -Severity $schwere))
    }

    return $zeilen.ToArray()
}

function Get-WizardProductKind {
    <#
    .SYNOPSIS
        Die gewaehlten Ordnerarten eines Produkts in fester Reihenfolge.
        Intern zu dieser Datei.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Kind,

        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product
    )

    $gewaehlt = @($Kind)
    $liste = New-Object System.Collections.Generic.List[string]

    foreach ($art in @(Get-ComponentKind)) {
        if ($gewaehlt -cnotcontains [string] $art) { continue }
        if ((Get-KindProduct -Kind ([string] $art)) -cne $Product) { continue }
        $liste.Add([string] $art)
    }

    return $liste.ToArray()
}

function Read-GroupStep {
    <#
    .SYNOPSIS
        Schritt 2 von Weg 1: jede noetige Gruppenrolle je Produkt genau
        einmal, danach die Gruppenuebersicht und "Weiter? [J/n]" (ERF-03,
        ERF-04).

    .DESCRIPTION
        Die Reihenfolge ist die von v1.2: fuer jede gewaehlte
        FSLogix-Ordnerart Read-GroupBinding mit den fest belegten
        Optionsgruppen, dann -- mit DEMProfiles -- Read-HelpdeskGroup und
        fuer jede gewaehlte DEM-Ordnerart Read-GroupBinding. Die Ergebnisse
        werden verworfen; der Zweck ist allein, jede Rolle einmal in den
        Rollenspeicher zu bringen. Aufloesung, Rueckspiegelung und das
        Angebot der FSLogix-Wahl im DEM-Teil bleiben unveraendert.

        Vor den Fragen eines Produkts steht seine Produktzeile. Nach "n" auf
        "Weiter?" wird der Rollenspeicher geleert, der Kopf erscheint erneut
        und alle Gruppen werden neu gefragt -- ohne Vorbelegung aus der
        verworfenen Runde. Die Auswahl aus Schritt 1 bleibt unberuehrt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Kind,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Sequence
    )

    $fslogix = @(Get-WizardProductKind -Kind $Kind -Product 'FSLogix')
    $dem = @(Get-WizardProductKind -Kind $Kind -Product 'DEM')

    while ($true) {

        Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'Groups' -Sequence $Sequence)

        if ($fslogix.Count -gt 0) {

            Add-PromptContext -Line @('')
            Add-PromptContext -Severity 'Heading' -Line @(('  {0}' -f (Get-ProductHeading -Product 'FSLogix' -Kind $fslogix)))
            Add-PromptContext -Line @('')

            foreach ($art in $fslogix) {
                $null = Read-GroupBinding -Kind $art -OfferAdditional `
                    -AclOptGroup @(Get-FixedOptGroup -Kind $art -Scope 'Acl') `
                    -ShareOptGroup @(Get-FixedOptGroup -Kind $art -Scope 'Share')
            }
        }

        if ($dem.Count -gt 0) {

            Add-PromptContext -Line @('')
            Add-PromptContext -Severity 'Heading' -Line @(('  {0}' -f (Get-ProductHeading -Product 'DEM' -Kind $dem)))
            Add-PromptContext -Line @('')

            # Die Helpdesk-Klaerung laeuft VOR der Bindung und nur mit
            # DEMProfiles -- sie entscheidet ueber die Optionsgruppe Helpdesk
            # des Share-Templates, die Get-FixedOptGroup danach abliest.
            if ($dem -ccontains 'DEMProfiles') { $null = Read-HelpdeskGroup -OfferAdditional }

            foreach ($art in $dem) {
                $null = Read-GroupBinding -Kind $art -OfferAdditional `
                    -AclOptGroup @(Get-FixedOptGroup -Kind $art -Scope 'Acl') `
                    -ShareOptGroup @(Get-FixedOptGroup -Kind $art -Scope 'Share')
            }
        }

        Add-PromptContext -Line @(Format-GroupOverview -Kind $Kind)

        if (Read-YesNoAnswer -Prompt 'Weiter?' -Default $true -ShortLabel) { return }

        Reset-TrusteeRoleStore
    }
}

function Format-GroupOverview {
    <#
    .SYNOPSIS
        Die Gruppenuebersicht nach Schritt 2: je gewaehltem Produkt eine
        gerahmte Tabelle Rolle / Gruppe (ERF-04).

    .DESCRIPTION
        Rollen in der Reihenfolge Admin, User, Computer, abgelesen ueber
        Get-RequiredTrusteeToken aus den Templates der gewaehlten
        Ordnerarten des Produkts. Mit DEMProfiles zusaetzlich die Zeile
        Helpdesk-Gruppe -- der Anzeigename oder "nicht gesetzt". Keine SID:
        sie stand schon in der Rueckspiegelung. Ein Produkt ohne gewaehlte
        Ordnerart fehlt. Die Tabellenzeilen kommen unveraendert aus
        Format-AdjustTable.

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Kind
    )

    $karte = Get-TokenRoleMap
    $nichtGesetzt = 'nicht gesetzt'

    $zeilen = New-Object System.Collections.Generic.List[object]
    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Severity 'Heading' -Text '  Gruppenübersicht'))

    foreach ($produkt in @('FSLogix', 'DEM')) {

        $arten = @(Get-WizardProductKind -Kind $Kind -Product $produkt)
        if ($arten.Count -eq 0) { continue }

        $rollen = New-Object System.Collections.Generic.List[string]

        foreach ($art in $arten) {
            $token = @(Get-RequiredTrusteeToken -Kind $art `
                    -AclOptGroup @(Get-FixedOptGroup -Kind $art -Scope 'Acl') `
                    -ShareOptGroup @(Get-FixedOptGroup -Kind $art -Scope 'Share'))
            foreach ($name in $token) {
                if (-not $karte.ContainsKey($name)) { continue }
                $rolle = [string] $karte[$name]
                if ($rolle -ceq 'Helpdesk') { continue }
                if (-not $rollen.Contains($rolle)) { $rollen.Add($rolle) }
            }
        }

        $speicher = Get-TrusteeRoleStore -Product $produkt
        $reihen = New-Object System.Collections.Generic.List[object]

        foreach ($rolle in @('Admin', 'User', 'Computer')) {
            if (-not $rollen.Contains($rolle)) { continue }
            $name = $nichtGesetzt
            if ($speicher.ContainsKey($rolle)) { $name = [string] $speicher[$rolle].DisplayName }
            $reihen.Add([object[]] @((Get-TrusteeRoleLabel -Role $rolle), $name))
            foreach ($satz in @(Get-TrusteeRoleAdditional -Product $produkt -Role $rolle)) {
                $reihen.Add([object[]] @((Get-TrusteeRoleLabel -Role $rolle), [string] $satz.DisplayName))
            }
        }

        if (($produkt -ceq 'DEM') -and ($arten -ccontains 'DEMProfiles')) {
            $name = $nichtGesetzt
            if (Test-HelpdeskBound) { $name = [string] $speicher['Helpdesk'].DisplayName }
            $reihen.Add([object[]] @((Get-TrusteeRoleLabel -Role 'Helpdesk'), $name))
        }

        $zeilen.Add((New-OperatorTextLine -Text ''))
        $zeilen.Add((New-OperatorTextLine -Severity 'Heading' -Text ('  {0}' -f (Get-ProductHeading -Product $produkt -Kind $arten))))

        foreach ($zeile in @(Format-AdjustTable -Header @('Rolle', 'Gruppe') -Row $reihen.ToArray() -Indent '    ')) {
            $zeilen.Add($zeile)
        }
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    return $zeilen.ToArray()
}

function Format-KindCaptureSummary {
    <#
    .SYNOPSIS
        Der Kurzueberblick nach einer erfassten Ordnerart (ERF-05).

    .DESCRIPTION
        Eine Schluessel-Wert-Folge statt einer Tabelle: ein langer Pfad
        braeche eine 72-Zeichen-Tabelle. Leerzeile, Ordnerart, Pfad (mit
        " (Bestand)" bei bestehender Struktur), Freigabe, Optionen (ACL- und
        Freigabe-Optionsgruppen ohne Doppel, sonst "keine"), dann
        "[OK] Erfassung abgeschlossen" mit Schwere OK.

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Target
    )

    $optionen = New-Object System.Collections.Generic.List[string]
    foreach ($gruppe in @(@($Target.AclOptGroup) + @($Target.ShareOptGroup))) {
        if ($null -eq $gruppe) { continue }
        $name = [string] $gruppe
        if ([string]::IsNullOrEmpty($name)) { continue }
        if (-not $optionen.Contains($name)) { $optionen.Add($name) }
    }

    $optionText = if ($optionen.Count -gt 0) { [string]::Join(', ', $optionen.ToArray()) } else { 'keine' }

    $pfad = [string] $Target.Path
    if ([bool] $Target.IsExisting) { $pfad = $pfad + ' (Bestand)' }

    return @(
        (New-OperatorTextLine -Text '')
        (New-OperatorTextLine -Text ('    Ordnerart : {0}' -f [string] $Target.Kind))
        (New-OperatorTextLine -Text ('    Pfad      : {0}' -f $pfad))
        (New-OperatorTextLine -Text ('    Freigabe  : {0}' -f [string] $Target.ShareName))
        (New-OperatorTextLine -Text ('    Optionen  : {0}' -f $optionText))
        (New-OperatorTextLine -Severity 'OK' -Text ('    {0} Erfassung abgeschlossen' -f (Get-StatusMarkierung -Status 'OK')))
    )
}
