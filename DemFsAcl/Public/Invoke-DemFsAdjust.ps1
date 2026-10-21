<#
    Invoke-DemFsAdjust -- die Orchestrierung von Weg 3, "NTFS-Berechtigungen
    anpassen" (Entscheidung Projektinhaber 2026-09-24). NICHT exportiert: der
    einzige oeffentliche Einstieg bleibt Invoke-DemFsProvisioning.

    DIE REIHENFOLGE IST DER INHALT DIESER DATEI:
      1. Erhoehte Sitzung, sonst Ende mit 2 -- wie Weg 2.
      2. Wurzel und Erkennung wie Weg 2, dann dieselbe Auswahl per Nummer
        (Read-AdjustTarget); nicht erkannte Ordner mit Pflichtzuordnung.
      3. Je Ziel GENAU EINE Lesung; abgelehnt wird eine Wurzel, die nicht
        lesbar ist, erbt oder einen verweigernden Eintrag traegt.
      4. Aenderungen sammeln (Read-AdjustChangeSet). Bis hier wird nichts
        geschrieben.
      5. Je geaendertem Ziel das geplante ACL in der Form eines DesiredAcl.
      6. Preflight, Plan mit Vorher/Nachher, Hostsperre, getipptes JA.
      7. Schreiben ueber Invoke-AclApplySet -- dieselbe eine Schreibstelle,
        dasselbe Ruecklesen und derselbe Vergleich wie Weg 1, hier gegen den
        Plan. Keine Freigabestufe: Weg 3 aendert nur NTFS-Rechte.
      8. Zusammenfassung und Rueckgabewert.

    NUR DIE WURZEL. Unterordner bekommen die Aenderung ueber die Vererbung;
    ein Abstieg waere das rekursive Setzen, das die Sicherheitsverbote
    ausschliessen.

    KEIN EINGABE-CMDLET UND KEIN AUSGABE-CMDLET IN DIESER DATEI.
#>

function Invoke-DemFsAdjust {
    <#
    .SYNOPSIS
        Weg 3: NTFS-Berechtigungen gewaehlter Ablagen anpassen -- Gruppen
        hinzufuegen, ersetzen oder entfernen.

    .OUTPUTS
        [pscustomobject] mit ExitCode, Confirmed, Target und Result -- dieselbe
        Form wie Invoke-DemFsProvisioning.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    $kapazitaet = $Capability

    # --- 1. Erhoehte Sitzung -------------------------------------------------
    if (-not (Test-IsElevated)) {

        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Severity 'Error' -Text 'Das Anpassen braucht eine erhöhte Sitzung: die ACLs fremder Ordner lassen sich sonst weder lesen noch schreiben. Bitte die Konsole als Administrator starten. Es wurde nichts geändert.')
            (New-OperatorTextLine -Text '')
        )

        return (New-AdjustRunResult -ExitCode (Get-ProvisioningExitCode -Result @() -Blocked))
    }

    # --- 2. Wurzel, Erkennung, Zuordnung ------------------------------------
    $namen = Get-AuditKindNameMap

    $freigabeListe = @()
    try { $freigabeListe = @(Get-ShareList) }
    catch {
        Write-OperatorHint -Text ('    Die Freigaben des Servers lassen sich nicht lesen: {0} -- die Erkennung läuft ohne Freigabenamen weiter.' -f $_.Exception.Message)
    }

    # Der Zweck steuert Blockueberschrift und Wortlaut der Zuordnung; er wird
    # nach der Zuordnung in jedem Fall zurueckgesetzt.
    Set-AuditPurpose -Purpose 'Adjust'

    try {
        while ($true) {

            $wurzel = Read-AuditRoot

            try {
                $scan = Find-AuditTarget -RootPath ([string] $wurzel.Path) -NameMap $namen -ShareList $freigabeListe
                break
            }
            catch {
                Write-OperatorHint -Text ('    Das Wurzelverzeichnis "{0}" lässt sich nicht auflisten: {1}' -f [string] $wurzel.Path, $_.Exception.Message)
            }
        }

        # Dieselbe Auswahl per Nummer wie Weg 2 (Serverlauf 2026-09-25): ein
        # nicht erkannter Ordner wird dort gewaehlt und zugeordnet.
        $ziele = @(Read-AdjustTarget -Scan $scan | Where-Object { $null -ne $_ })
    }
    finally {
        Set-AuditPurpose -Purpose 'Audit'
    }

    if ($ziele.Count -eq 0) {
        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Severity 'Warning' -Text 'Es wurde kein Ordner zum Anpassen gewählt. Es wurde nichts geändert.')
            (New-OperatorTextLine -Text '')
        )
        return (New-AdjustRunResult -ExitCode (Get-ProvisioningExitCode -Result @() -Confirmed $false -NothingSelected))
    }

    # --- 3. Je Ziel genau eine Lesung ---------------------------------------
    $schnapp = Get-AuditSnapshot -Target $ziele
    $zustaende = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in $ziele) {
        $eintrag = $schnapp[[string] $ziel.Path]
        $zustaende.Add((New-AdjustState -Kind ([string] $ziel.Kind) -Path ([string] $ziel.Path) `
                    -Actual $eintrag.Actual -ReadError ([string] $eintrag.Error) -ShareNames @($ziel.ShareNames)))
    }

    $abgelehnt = @($zustaende | Where-Object { -not $_.Eligible })
    $anpassbar = @($zustaende | Where-Object { $_.Eligible })

    if ($abgelehnt.Count -gt 0) {
        $zeilen = @((New-OperatorTextLine -Text ''))
        foreach ($z in $abgelehnt) {
            $zeilen += (New-OperatorTextLine -Severity 'Warning' -Text (
                    '[WARNUNG] {0} -- {1} wird nicht angepasst. {2}' -f [string] $z.Kind, [string] $z.Path, [string] $z.Reason))
        }
        Write-OperatorLine -Capability $kapazitaet -Line $zeilen
    }

    if ($anpassbar.Count -eq 0) {
        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Severity 'Warning' -Text 'Keiner der gewählten Ordner lässt sich anpassen. Es wurde nichts geändert.')
            (New-OperatorTextLine -Text '')
        )
        return (New-AdjustRunResult -ExitCode 1)
    }

    # --- 4. Aenderungen sammeln ---------------------------------------------
    # NAV-03: Schritt 2 von Weg 3; der Kopf reist als Kontext mit der ersten
    # Aenderungsfrage.
    $folge = @(Get-WizardStepSequence -Mode Adjust)
    Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'AdjustChange' -Sequence $folge)

    $anzeige = @{}
    $null = Read-AdjustChangeSet -State $anpassbar -Name $anzeige

    $geaendert = @($anpassbar | Where-Object { Test-AdjustChanged -State $_ })

    if ($geaendert.Count -eq 0) {
        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Text 'Keine Änderung geplant. Es wurde nichts geschrieben.')
            (New-OperatorTextLine -Text '')
        )
        return (New-AdjustRunResult -ExitCode (Get-ProvisioningExitCode -Result @() -Confirmed $false -NothingSelected))
    }

    # --- 5. Geplantes ACL je Ziel -------------------------------------------
    $schreibZiele = foreach ($z in $geaendert) {

        foreach ($r in @($z.Before) + @($z.Rules)) { $null = Get-AdjustName -Sid $r.IdentityReference -Name $anzeige }

        [pscustomobject] @{
            Kind             = [string] $z.Kind
            Path             = [string] $z.Path
            ShareName        = ''
            IsExisting       = $true
            Binding          = (Get-AdjustBinding -State $z)
            AclOptGroup      = @()
            ShareOptGroup    = @()
            Desired          = (ConvertTo-AdjustDesired -State $z -Name $anzeige)
            SkipContentCheck = $true
        }
    }
    $schreibZiele = @($schreibZiele)

    # --- 6. Preflight, Plan, Sperre, JA -------------------------------------
    $preflight = @(Test-ProvisioningPreflight -Target $schreibZiele)
    $planzeilen = @(Format-AdjustPlan -State $geaendert -PreflightResult $preflight -Name $anzeige)

    # NAV-03: Schritt 3 beginnt mit einer Ausgabe -- Kopf ueber die
    # Ausgabenaht, unmittelbar vor den Planzeilen (wie Weg 1).
    Write-OperatorLine -Capability $kapazitaet -Line @(Get-StepHeaderRecord -Key 'Check' -Sequence $folge)
    Write-OperatorLine -Capability $kapazitaet -Line $planzeilen

    if (Test-HostSperre -PreflightResult $preflight) {

        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Severity 'Error' -Text 'Das Preflight sperrt den gesamten Lauf. Es wurde nichts geändert.')
            (New-OperatorTextLine -Text '')
        )

        return (New-AdjustRunResult -ExitCode (Get-ProvisioningExitCode -Result $preflight -Confirmed $false -Blocked) `
                -Target $schreibZiele -Result $preflight)
    }

    $umgeleitet = ($null -ne $kapazitaet) -and ($null -ne $kapazitaet.PSObject.Properties['OutputRedirected']) -and [bool] $kapazitaet.OutputRedirected

    if ($umgeleitet) {
        Add-PromptContext -Line @($planzeilen | ForEach-Object { [string] $_.Text })
    }

    if (-not (Confirm-TypedWord -Prompt 'Sollen diese Änderungen jetzt geschrieben werden?' -Word 'JA')) {

        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Severity 'Warning' -Text 'Abgebrochen. Es wurde nichts geändert.')
            (New-OperatorTextLine -Text '')
        )

        return (New-AdjustRunResult -ExitCode (Get-ProvisioningExitCode -Result $preflight -Confirmed $false) `
                -Target $schreibZiele -Result $preflight)
    }

    # --- 7. Schreiben, zuruecklesen, gegen den Plan pruefen -----------------
    $alle = @(@($preflight) + @(Invoke-AclApplySet -Target $schreibZiele -PreflightResult $preflight))

    # --- 8. Zusammenfassung ---------------------------------------------------
    # Erst jetzt: vor dem Preflight hiesse ein Freigabename, dass eine Freigabe
    # geplant ist (PRE-05, PRE-06).
    foreach ($z in $schreibZiele) { $z.ShareName = '(unverändert)' }

    $gruppen = @{}
    foreach ($sid in @($anzeige.Keys)) {
        $gruppen[$sid] = [pscustomobject] @{ Sid = [System.Security.Principal.SecurityIdentifier]::new($sid); DisplayName = [string] $anzeige[$sid] }
    }

    Write-OperatorLine -Capability $kapazitaet -Line @(
        Format-ProvisioningSummary -Result $alle -Target $schreibZiele -Capability $kapazitaet -Group $gruppen)

    return (New-AdjustRunResult -ExitCode (Get-ProvisioningExitCode -Result $alle -Confirmed $true) `
            -Confirmed $true -Target $schreibZiele -Result $alle)
}

function Get-AdjustBinding {
    <#
    .SYNOPSIS
        Rolle -> Gruppen nach den Aenderungen, fuer Zusammenfassung und
        Detailbericht. Nur Anzeige; geschrieben wird der Plan.

    .DESCRIPTION
        KEINE GERATENE ROLLE (Serverlauf ACC-02, 2026-10-04). Passt die
        Rechteform einer Regel auf mehrere Rollen -- bei DEMConfig Benutzer-
        und Computergruppe --, steht die Gruppe unter dem Sammelschluessel
        aller passenden Token, etwa "<UserGroup>/<ComputerGroup>". Der fruehere
        Weg vergab die erste freie Rolle und vertauschte so Benutzer- und
        Computergruppe in der Anzeige.

        Jeder Schluessel traegt ALLE seine Gruppen in der Reihenfolge der
        Regeln: eine SID allein als SecurityIdentifier, mehrere als Feld.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $State
    )

    $reihen = [ordered] @{}

    foreach ($regel in @($State.Rules)) {

        $rollen = @(Get-AdjustRuleRole -Shape $State.Shape -Rule $regel)
        if ($rollen.Count -eq 0) { continue }

        $schluessel = $rollen -join '/'
        $sid = [System.Security.Principal.SecurityIdentifier] $regel.IdentityReference

        if (-not $reihen.Contains($schluessel)) { $reihen[$schluessel] = New-Object System.Collections.Generic.List[object] }
        if (@($reihen[$schluessel] | Where-Object { $_.Value -ceq $sid.Value }).Count -eq 0) { $reihen[$schluessel].Add($sid) }
    }

    $bindung = @{}

    foreach ($schluessel in @($reihen.Keys)) {
        $sids = $reihen[$schluessel].ToArray()
        if ($sids.Count -eq 1) { $bindung[$schluessel] = $sids[0] } else { $bindung[$schluessel] = $sids }
    }

    return $bindung
}

function New-AdjustRunResult {
    <#
    .SYNOPSIS
        Das Rueckgabeobjekt von Weg 3. Intern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [int] $ExitCode,

        [Parameter()]
        [bool] $Confirmed = $false,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Result = @()
    )

    return [pscustomobject] @{
        ExitCode  = $ExitCode
        Confirmed = $Confirmed
        Target    = @($Target)
        Result    = @($Result)
    }
}
