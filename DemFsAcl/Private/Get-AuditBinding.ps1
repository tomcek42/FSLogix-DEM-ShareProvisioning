<#
    Get-AuditBinding -- die Ableitung des Solls je Ziel aus seinem eigenen
    ACL (Weg 2, Entscheidung Projektinhaber 2026-10-22).

    KEINE RUECKFRAGE, KEINE EINE GRUPPE JE ROLLE. Bis 2026-10-22 las Weg 2 je
    Produkt genau eine Gruppe je Rolle ab und liess sie bestaetigen; bei zwei
    Benutzergruppen musste der Operator eine eintippen, und die zweite galt
    danach als Abweichung -- das Angebot "angleichen" haette sie entfernt.
    Jetzt gilt JEDER explizite Allow-Eintrag, dessen Rechteform eine Rolle des
    Templates traegt, als gueltige Gruppe dieser Rolle. Beliebig viele je
    Rolle.

    DIE RECHTEFORM KOMMT AUS DERSELBEN QUELLE WIE IN WEG 3:
    Get-AdjustRoleShape und Get-AdjustRuleRole. Eine zweite Formtabelle waere
    eine zweite Wahrheit darueber, was eine Benutzergruppe ist.

    GETEILTE FORM (Benutzer- und Computergruppe in DEMConfig und DEMProfiles):
    nur die feste relative Kennung 515 der Domaenengruppe der Computerkonten
    macht eine Gruppe zur Computergruppe -- eine SID-Tatsache, kein
    Namensraten. Alle anderen stehen unter der Benutzergruppe. Fuer den
    Vergleich ist das gleichgueltig, beide Rollen tragen dieselben Rechte; die
    Anzeige nennt solche Gruppen "Benutzer / Computer".

    REIN: kein Dateisystem ausser der Templatedatei, kein Netz, keine
    Namensaufloesung, keine Ausgabe.
#>

function Get-AuditPlaceholderDesired {
    <#
    .SYNOPSIS
        Das Template einer Ordnerart, mit Platzhalter-SIDs und ALLEN
        Optionsgruppen gebunden. Intern.

    .DESCRIPTION
        Alle Optionsgruppen, damit auch die Signatur eines optionalen Eintrags
        (etwa der beiden Well-Known-Eintraege von SystemAndBuiltinAdmins)
        bekannt ist. Die Platzhalter-SIDs (S-1-5-21-0-0-0-<n>) werden nie
        aufgeloest.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind
    )

    $template = Get-AclTemplate -Kind $Kind

    $bindung = @{}
    $optionen = New-Object System.Collections.Generic.List[string]
    $zaehler = 0

    foreach ($ace in @($template.Aces)) {

        $trustee = [string] $ace.Trustee

        if ($trustee.StartsWith('<', [System.StringComparison]::Ordinal) -and -not $bindung.ContainsKey($trustee)) {
            $zaehler++
            $bindung[$trustee] = [System.Security.Principal.SecurityIdentifier]::new(('S-1-5-21-0-0-0-{0}' -f $zaehler))
        }

        if ($ace.ContainsKey('OptGroup') -and -not [string]::IsNullOrEmpty([string] $ace.OptGroup)) {
            if (-not $optionen.Contains([string] $ace.OptGroup)) { $optionen.Add([string] $ace.OptGroup) }
        }
    }

    return Expand-AclTemplate -Template $template -Binding $bindung -IncludeOptGroup $optionen.ToArray()
}

function Get-AuditWellKnownOptionKey {
    <#
    .SYNOPSIS
        Die vollen Vergleichsschluessel der Well-Known-Eintraege einer
        Optionsgruppe. Intern.

    .DESCRIPTION
        Fuer SystemAndBuiltinAdmins sind das die beiden Eintraege des
        Systemkontos und der lokalen Administratorengruppe -- per SID aus dem
        Template, nie per Name.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $OptGroup
    )

    $schluessel = New-Object System.Collections.Generic.List[string]

    foreach ($ace in @((Get-AuditPlaceholderDesired -Kind $Kind).Aces)) {

        if ([string] $ace.OptGroup -cne $OptGroup) { continue }
        if (-not ([string] $ace.Trustee).StartsWith('WellKnown:', [System.StringComparison]::Ordinal)) { continue }

        $schluessel.Add([string] (ConvertTo-AceKey -Ace $ace.Rule).Key)
    }

    return $schluessel.ToArray()
}

function Test-IsComputerGroupSid {
    <#
    .SYNOPSIS
        Wahr, wenn die SID die feste relative Kennung 515 einer Domaene traegt
        -- die Domaenengruppe der Computerkonten.

    .DESCRIPTION
        EINE SID-TATSACHE, KEIN NAME. Der Name dieser Gruppe ist lokalisiert;
        die relative Kennung ist auf jedem Server dieselbe.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Sid
    )

    return [bool] ($Sid -match '^S-1-5-21-\d+-\d+-\d+-515$')
}

function Get-AuditRuleToken {
    <#
    .SYNOPSIS
        Die Rollen-Token, unter denen eine Ist-Regel in Weg 2 gefuehrt wird.
        Intern.

    .DESCRIPTION
        Leer fuer verweigernde Regeln, fuer vordefinierte Prinzipale und fuer
        Regeln ohne passende Rechteform. Traegt die Regel die geteilte Form von
        Benutzer- und Computergruppe, entscheidet die relative Kennung 515:
        dann nur Computer, sonst beide Token -- die Anzeige nennt beide, die
        Bindung nimmt den ersten.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object] $Shape,

        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemAccessRule] $Rule
    )

    if ($Rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { return [string[]] @() }

    # Alle sechs Well-Known-SIDs des Werkzeugs, nicht nur die des Templates:
    # die lokale Administratorengruppe mit Vollzugriff auf DEMProfiles ist
    # eine Abweichung, keine Gruppe der Administratoren.
    if (@($script:WellKnownSid.Values | ForEach-Object { [string] $_ }) -contains [string] $Rule.IdentityReference.Value) { return [string[]] @() }

    $token = @(Get-AdjustRuleRole -Shape $Shape -Rule $Rule)

    if (($token -ccontains '<UserGroup>') -and ($token -ccontains '<ComputerGroup>') -and
        (Test-IsComputerGroupSid -Sid ([string] $Rule.IdentityReference.Value))) {
        return [string[]] @('<ComputerGroup>')
    }

    return [string[]] $token
}

function Get-AuditTargetBinding {
    <#
    .SYNOPSIS
        Bindung, Optionsgruppen und fehlende Rollen eines Ziels, abgelesen an
        seinem Ist-ACL.

    .DESCRIPTION
        Jeder Rollen-Token des Templates ist in Binding enthalten, als Feld von
        SecurityIdentifier -- auch leer: Expand-AclTemplate wirft bei einem
        fehlenden Token und baut fuer ein leeres Feld keinen Eintrag. Eine
        fehlende Pflichtrolle meldet deshalb nicht der Vergleicher, sondern
        MissingRole.

        Optionsgruppen: SystemAndBuiltinAdmins (FSLogix-Profiles), sobald
        einer der beiden Well-Known-Eintraege mit seiner Template-Form
        vorhanden ist; ComputerEnvironmentSettings (DEMConfig, DEMProfiles),
        sobald eine Computergruppe gefunden ist. SystemLocalOps und
        ShareAdminFullControl werden nicht abgelesen -- der Schreibpfad setzt
        sie nie (Get-FixedOptGroup).

        Ohne lesbares ACL ($null) sind alle Rollen leer und keine fehlt: ein
        nicht lesbares Ziel ist bereits ein Befund.

    .OUTPUTS
        [pscustomobject] mit Binding (Token -> SecurityIdentifier[]),
        AclOptGroup (string[]), MissingRole (Token[]) und Role (SID ->
        Token[], fuer die Anzeige).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter()]
        [AllowNull()]
        [object] $Actual = $null
    )

    $form = Get-AdjustRoleShape -Kind $Kind

    $gefunden = @{}
    foreach ($token in @($form.Role.Keys)) { $gefunden[[string] $token] = New-Object System.Collections.Generic.List[string] }

    $rolle = @{}
    $alleSchluessel = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    $regeln = @()
    if ($null -ne $Actual) { $regeln = @(@($Actual.Aces) | Where-Object { $null -ne $_ }) }

    foreach ($regel in $regeln) {

        $null = $alleSchluessel.Add([string] (ConvertTo-AceKey -Ace $regel).Key)

        $token = @(Get-AuditRuleToken -Shape $form -Rule $regel)
        if ($token.Count -eq 0) { continue }

        $sid = [string] $regel.IdentityReference.Value
        $rolle[$sid] = [string[]] $token

        if (-not $gefunden[$token[0]].Contains($sid)) { $gefunden[$token[0]].Add($sid) }
    }

    $bindung = @{}
    foreach ($token in @($gefunden.Keys)) {
        $bindung[$token] = [System.Security.Principal.SecurityIdentifier[]] @(
            $gefunden[$token] | ForEach-Object { [System.Security.Principal.SecurityIdentifier]::new($_) })
    }

    $optionen = New-Object System.Collections.Generic.List[string]

    if ($Kind -ceq 'FSLogix-Profiles') {
        foreach ($schluessel in @(Get-AuditWellKnownOptionKey -Kind $Kind -OptGroup 'SystemAndBuiltinAdmins')) {
            if ($alleSchluessel.Contains($schluessel) -and -not $optionen.Contains('SystemAndBuiltinAdmins')) { $optionen.Add('SystemAndBuiltinAdmins') }
        }
    }

    if ((($Kind -ceq 'DEMConfig') -or ($Kind -ceq 'DEMProfiles')) -and ($gefunden['<ComputerGroup>'].Count -gt 0)) {
        $optionen.Add('ComputerEnvironmentSettings')
    }

    # Pflicht ist eine Rolle mit mindestens einer nicht optionalen Form.
    $fehlend = New-Object System.Collections.Generic.List[string]

    if ($null -ne $Actual) {
        foreach ($token in @('<AdminGroup>', '<UserGroup>', '<ComputerGroup>')) {
            if (-not $form.Role.ContainsKey($token)) { continue }
            if (@(@($form.Role[$token]) | Where-Object { [bool] $_.Required }).Count -eq 0) { continue }
            if ($gefunden[$token].Count -eq 0) { $fehlend.Add($token) }
        }
    }

    return [pscustomobject] @{
        Binding     = $bindung
        AclOptGroup = [string[]] $optionen.ToArray()
        MissingRole = [string[]] $fehlend.ToArray()
        Role        = $rolle
    }
}

function New-AuditDesired {
    <#
    .SYNOPSIS
        Das Soll eines Ziels aus seiner abgelesenen Bindung.

    .DESCRIPTION
        Expand-AclTemplate wirft bei einem Token ohne SID -- im Schreibpfad
        ist das richtig und bleibt so. Weg 2 laesst deshalb die Eintraege
        eines Tokens ohne abgelesene Gruppe aus einer Kopie des Templates weg;
        die fehlende Pflichtrolle meldet Test-AuditTarget ueber MissingRole.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [object] $Derivation
    )

    $template = (Get-AclTemplate -Kind $Kind).Clone()
    $bindung = @{}

    foreach ($token in @($Derivation.Binding.Keys)) {
        if (@($Derivation.Binding[$token]).Count -gt 0) { $bindung[$token] = $Derivation.Binding[$token] }
    }

    $template['Aces'] = @(@($template['Aces']) | Where-Object {
            $trustee = [string] $_['Trustee']
            (-not $trustee.StartsWith('<', [System.StringComparison]::Ordinal)) -or $bindung.ContainsKey($trustee)
        })

    return Expand-AclTemplate -Template $template -Binding $bindung -IncludeOptGroup @($Derivation.AclOptGroup)
}

function Get-AuditHelpdeskSid {
    <#
    .SYNOPSIS
        Die Helpdesk-Gruppen einer DEMProfiles-Freigabe, abgelesen an ihren
        Eintraegen (FEATURES.md Paragraph 1.3).

    .DESCRIPTION
        Die Helpdesk-Gruppe kommt in KEINEM ACL-Template vor, nur im
        Share-Template von DEMProfiles, dort mit Vollzugriff. Gueltig ist
        deshalb jeder zulassende Freigabeeintrag mit Access Full, einer nicht
        leeren SID und einer SID ausserhalb der Well-Known-SIDs des Werkzeugs.
        Beliebig viele; keiner heisst: kein Helpdesk-Eintrag im Soll.

    .PARAMETER ShareActual
        Die Freigabeeintraege in SID-Form aus ConvertTo-ShareActual.

    .OUTPUTS
        [string[]] SIDs in Leserichtung, je SID einmal.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ShareActual
    )

    $bekannt = @($script:WellKnownSid.Values | ForEach-Object { [string] $_ })
    $sids = New-Object System.Collections.Generic.List[string]

    foreach ($eintrag in @($ShareActual)) {

        if ($null -eq $eintrag) { continue }

        $sid = [string] $eintrag.Sid
        if ([string]::IsNullOrEmpty($sid)) { continue }
        if ($bekannt -contains $sid) { continue }
        if (-not [string]::Equals([string] $eintrag.Access, 'Full', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $typ = ''
        if ($null -ne $eintrag.PSObject.Properties['AccessControlType']) { $typ = [string] $eintrag.AccessControlType }
        if ((-not [string]::IsNullOrEmpty($typ)) -and -not [string]::Equals($typ, 'Allow', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        if (-not $sids.Contains($sid)) { $sids.Add($sid) }
    }

    return [string[]] $sids.ToArray()
}
