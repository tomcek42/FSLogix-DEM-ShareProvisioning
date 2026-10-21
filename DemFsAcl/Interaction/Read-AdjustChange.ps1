<#
    Read-AdjustChange -- der Dialog von Weg 3, "NTFS-Berechtigungen anpassen".

    Gesammelt wird, nicht geschrieben: jede Aenderung veraendert nur die
    geplante Regelmenge (Invoke-AdjustChange). Geschrieben wird erst nach Plan,
    Preflight und getipptem JA in der Orchestrierung. Deshalb darf Entfernen
    auch eine Rollengruppe treffen -- etwa um danach eine andere
    hinzuzufuegen; ob am Ende eine Rolle fehlt, zeigt der Plan.

    Eine Aenderung gilt fuer ALLE gewaehlten Ordner, in denen sie anwendbar
    ist. Wo nicht, steht der Grund direkt unter der Frage.
#>

function Read-AdjustChangeSet {
    <#
    .SYNOPSIS
        Zeigt die geplanten Eintraege je Ordner und sammelt Aenderungen, bis
        der Operator 0 waehlt.

    .PARAMETER State
        Die anpassbaren Ziele aus New-AdjustState.

    .PARAMETER Name
        SID-Wert -> Anzeigename. Wird ergaenzt, sobald eine neue Gruppe
        hinzukommt.

    .OUTPUTS
        [int] -- die Zahl der angewendeten Aenderungen.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $State,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $anzahl = 0

    while ($true) {

        Add-PromptContext -Line @(Format-AdjustStateText -State $State -Name $Name)

        $wahl = ([string] (Read-RequiredText -Prompt 'Änderung (1 = Gruppe hinzufügen, 2 = Gruppe ersetzen, 3 = Gruppe entfernen, 0 = fertig)' `
                    -DefaultValue '0' -Validator { param($Wert) Test-AdjustActionChoice -Value $Wert })).Trim()

        if ($wahl -ceq '0') { return $anzahl }

        if ($wahl -ceq '1') {

            $rollen = @(Get-AdjustRoleChoice -State $State)
            $karte = Get-TokenRoleMap

            $liste = @('', '  Die neue Gruppe bekommt genau die Rechte dieser Rolle:')
            for ($i = 0; $i -lt $rollen.Count; $i++) {
                $liste += ('    {0}) {1}' -f ($i + 1), (Get-TrusteeRoleLabel -Role $karte[$rollen[$i]]))
            }
            Add-PromptContext -Line $liste

            $rollenZahl = $rollen.Count
            $nummer = [int] ([string] (Read-RequiredText -Prompt ('Rolle (1 bis {0})' -f $rollenZahl) `
                        -Validator { param($Wert) Test-AuditPickNumber -Value $Wert -Count $rollenZahl })).Trim()

            $token = $rollen[$nummer - 1]
            $gruppe = Read-TrusteeGroup -Prompt (Get-TrusteeRolePrompt -Role $karte[$token])
            $Name[[string] $gruppe.Sid.Value] = [string] $gruppe.DisplayName

            $wirkung = Invoke-AdjustChange -State $State -Action 'Add' -Role $token -Sid $gruppe.Sid
            Add-AdjustEffectContext -Effect $wirkung -Verb 'Hinzugefügt'
            if (@($wirkung.Applied).Count -gt 0) { $anzahl++ }
            continue
        }

        $gruppen = @(Get-AdjustGroup -State $State)

        if ($gruppen.Count -eq 0) {
            Write-OperatorHint -Text '    In den gewählten Ordnern gibt es keine Gruppe, die sich ersetzen oder entfernen lässt.'
            continue
        }

        $liste = @('', '  Gruppen:')
        for ($i = 0; $i -lt $gruppen.Count; $i++) {
            $liste += ('    {0}) {1}' -f ($i + 1), (Get-AdjustName -Sid $gruppen[$i].Sid -Name $Name))
        }
        Add-PromptContext -Line $liste

        $gruppenZahl = $gruppen.Count
        $nummer = [int] ([string] (Read-RequiredText -Prompt ('Gruppe (1 bis {0})' -f $gruppenZahl) `
                    -Validator { param($Wert) Test-AuditPickNumber -Value $Wert -Count $gruppenZahl })).Trim()

        $alt = $gruppen[$nummer - 1].Sid

        if ($wahl -ceq '2') {

            $neu = Read-TrusteeGroup -Prompt ('Neue Gruppe anstelle von {0} (Domäne\Gruppe, UPN oder SID)' -f (Get-AdjustName -Sid $alt -Name $Name))
            $Name[[string] $neu.Sid.Value] = [string] $neu.DisplayName

            $wirkung = Invoke-AdjustChange -State $State -Action 'Replace' -Sid $alt -NewSid $neu.Sid
            Add-AdjustEffectContext -Effect $wirkung -Verb 'Ersetzt'
        }
        else {
            $wirkung = Invoke-AdjustChange -State $State -Action 'Remove' -Sid $alt
            Add-AdjustEffectContext -Effect $wirkung -Verb 'Entfernt'
        }

        if (@($wirkung.Applied).Count -gt 0) { $anzahl++ }
    }
}

function Get-AdjustRoleShortLabel {
    <#
    .SYNOPSIS
        Die kurze Rollenbezeichnung fuer die Tabellenspalte.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Token
    )

    $kurz = @{
        '<AdminGroup>'    = 'Administratoren'
        '<UserGroup>'     = 'Benutzer'
        '<ComputerGroup>' = 'Computer'
        '<HelpdeskGroup>' = 'Helpdesk'
    }

    return [string] $kurz[$Token]
}

function Test-AdjustActionChoice {
    <#
    .SYNOPSIS
        Prueft die Antwort auf die Aenderungsfrage: 0 bis 3 nach Trim.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    if (@('0', '1', '2', '3') -ccontains $Value.Trim()) {
        return [pscustomobject] @{ IsValid = $true; Reason = '' }
    }

    return [pscustomobject] @{ IsValid = $false; Reason = 'Erwartet wird 0, 1, 2 oder 3.' }
}

function Add-AdjustEffectContext {
    <#
    .SYNOPSIS
        Meldet, wo eine Aenderung gegriffen hat und wo nicht. Intern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Effect,

        [Parameter(Mandatory)]
        [string] $Verb
    )

    $zeilen = @()

    if (@($Effect.Applied).Count -gt 0) {
        $zeilen += ('    {0} in {1} Ordner(n).' -f $Verb, @($Effect.Applied).Count)
    }
    else {
        $zeilen += '    Keine Änderung.'
    }

    foreach ($s in @($Effect.Skipped)) {
        $zeilen += ('    Nicht in {0} ({1}): {2}.' -f [string] $s.Kind, [string] $s.Path, [string] $s.Reason)
    }

    Add-PromptContext -Severity 'OK' -Line $zeilen
}

function Get-AdjustName {
    <#
    .SYNOPSIS
        Der Anzeigename einer SID; aufgeloest wird hoechstens einmal je SID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Sid,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $schluessel = [string] $Sid.Value

    if (-not $Name.ContainsKey($schluessel)) {
        $Name[$schluessel] = Get-TrusteeDisplayName -Sid $Sid
    }

    return [string] $Name[$schluessel]
}

function Format-AdjustStateText {
    <#
    .SYNOPSIS
        Die geplanten Eintraege je Ordner: Prinzipal, Rechte, Gilt fuer und
        die Rolle, deren Rechte der Eintrag traegt.

    .DESCRIPTION
        Geaenderte Eintraege sind markiert (Serverlauf 2026-09-25): neu gruen
        mit "(neu)", ersetzt gelb mit dem alten Eintrag rot durchgestrichen in
        derselben Zelle ("(vorher: ...)"), entfernt rot durchgestrichen mit
        "(entfernt)". Die Tabelle kommt als Zeilensaetze mit Abschnitten.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $State,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $karte = Get-TokenRoleMap
    $zeilen = New-Object System.Collections.Generic.List[object]

    $zeilen.Add('')
    $zeilen.Add('  Einträge je Ordner (so würde geschrieben):')

    foreach ($ziel in @($State | Where-Object { $_.Eligible })) {

        $zeilen.Add('')
        $zeilen.Add(('    {0} -- {1}' -f [string] $ziel.Kind, [string] $ziel.Path))

        foreach ($regel in @($ziel.Before) + @($ziel.Rules)) { $null = Get-AdjustName -Sid $regel.IdentityReference -Name $Name }

        $reihen = New-Object System.Collections.Generic.List[object]
        $stile = New-Object System.Collections.Generic.List[object]

        foreach ($aenderung in @(Get-AdjustRowChange -State $ziel)) {

            $rollen = @(Get-AdjustRuleRole -Shape $ziel.Shape -Rule $aenderung.Rule)
            $rolle = @($rollen | ForEach-Object { Get-AdjustRoleShortLabel -Token $_ }) -join ' / '

            $reihe = Get-AdjustChangeRow -Change $aenderung -Name $Name
            $reihen.Add(@(@($reihe.Cells) + @($rolle)))
            $stile.Add($reihe.Style)
        }

        foreach ($zeile in @(Format-AdjustTable -Header @('Prinzipal', 'Rechte', 'Gilt für', 'Rolle') -Row $reihen.ToArray() -RowStyle $stile.ToArray() -Indent '      ')) {
            $zeilen.Add($zeile)
        }
    }

    # Eine Leerzeile zwischen Tabelle und naechster Frage.
    $zeilen.Add('')

    return $zeilen.ToArray()
}

function Read-AdjustTarget {
    <#
    .SYNOPSIS
        Die Auswahl der Ordner fuer Weg 3 -- dieselbe Auswahl per Nummer wie
        in Weg 2 (Read-AuditAssignment), im Wortlaut "anpassen".

    .DESCRIPTION
        Ein gewaehlter, nicht erkannter Ordner bekommt seine Ordnerart per
        Pflichtzuordnung (Serverlauf 2026-09-25); ohne Ordnerart gaebe es
        keine Rollen.

    .OUTPUTS
        Sammlung von [pscustomobject] mit Kind, Path, RelativePath und
        ShareNames; leer, wenn nichts gewaehlt wurde.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Scan
    )

    $auswahl = Read-AuditAssignment -Scan $Scan

    return @(@($auswahl.Target) | Where-Object { $null -ne $_ })
}
