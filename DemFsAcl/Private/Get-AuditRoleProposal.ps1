<#
    Get-AuditRoleProposal -- die Ableitung der Gruppen und Optionen aus einem
    vorhandenen ACL (AUDIT-04, D-11 bis D-13, Planerentscheid 3 aus 05-01).

    DIE ROLLENSIGNATUR KOMMT AUS DEM TEMPLATE, NICHT AUS EINER ZWEITEN
    RECHTETABELLE. Je Platzhalter-Token wird das Template mit einer eigenen
    Platzhalter-SID gebunden (Expand-AclTemplate) und die gebaute Regel ueber
    ConvertTo-AceKey normalisiert -- Rechte, Vererbung, Propagation und Typ
    stehen damit genau so da, wie der Vergleicher sie spaeter sieht.
    Normalisiert wird ausschliesslich in ConvertTo-AceKey.

    KANDIDAT IST EIN EXPLIZITER ACE MIT GENAU DIESER SIGNATUR, dessen SID keine
    der sechs Well-Known-SIDs des Werkzeugs ist. Genau ein Kandidat ergibt einen
    Vorschlag; keiner oder mehrere nicht (D-12) -- geraten wird nichts.

    GETEILTE SIGNATUR (Benutzer- und Computergruppe in DEMConfig und
    DEMProfiles): hier entscheidet allein die feste relative Kennung 515 der
    Domaenengruppe der Computerkonten -- eine SID-Tatsache, kein Namensraten.
    Ohne eindeutige Trennung gibt es fuer beide Rollen keinen Vorschlag.

    REIN: kein Dateisystem ausser der Templatedatei des Moduls, kein Netz,
    keine Namensaufloesung, keine Ausgabe. Die Platzhalter-SIDs
    (S-1-5-21-0-0-0-<n>) werden nie aufgeloest.
#>

function Get-AuditPlaceholderDesired {
    <#
    .SYNOPSIS
        Das Template einer Ordnerart, mit Platzhalter-SIDs und ALLEN
        Optionsgruppen gebunden. Intern.

    .DESCRIPTION
        Alle Optionsgruppen, damit auch die Signatur eines optionalen Eintrags
        (etwa der Computergruppe oder der beiden Well-Known-Eintraege von
        SystemAndBuiltinAdmins) bekannt ist.
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

function Get-AuditRoleSignature {
    <#
    .SYNOPSIS
        Die normalisierte Signatur je Platzhalter-Token eines Templates.
        Intern zu Get-AuditRoleProposal.

    .DESCRIPTION
        Die Signatur ist "Typ|Maske|Inheritance|Propagation" -- der Schluessel
        aus ConvertTo-AceKey ohne die SID.

    .OUTPUTS
        [hashtable] Token -> Signatur.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind
    )

    $signatur = @{}

    foreach ($ace in @((Get-AuditPlaceholderDesired -Kind $Kind).Aces)) {

        $trustee = [string] $ace.Trustee
        if (-not $trustee.StartsWith('<', [System.StringComparison]::Ordinal)) { continue }

        $signatur[$trustee] = ConvertTo-AuditSignature -Norm (ConvertTo-AceKey -Ace $ace.Rule)
    }

    return $signatur
}

function Get-AuditWellKnownOptionKey {
    <#
    .SYNOPSIS
        Die vollen Vergleichsschluessel der Well-Known-Eintraege einer
        Optionsgruppe. Intern zu Get-AuditRoleProposal.

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

function ConvertTo-AuditSignature {
    <#
    .SYNOPSIS
        Der Schluessel aus ConvertTo-AceKey ohne SID. Intern.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Norm
    )

    return ('{0}|{1}|{2}|{3}' -f [int] $Norm.AccessControlType, [int] $Norm.Rights, [int] $Norm.Inheritance, [int] $Norm.Propagation)
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

function Get-AuditRoleProposal {
    <#
    .SYNOPSIS
        Rollen- und Optionskandidaten aus einem Ist-Schnappschuss (D-11 bis
        D-13).

    .DESCRIPTION
        Je Rolle (Admin aus <AdminGroup>, User aus <UserGroup>, Computer aus
        <ComputerGroup>) ein Datensatz mit State (Found, NotFound, Ambiguous),
        Sid (SecurityIdentifier oder leer), Count (Zahl der Kandidaten) und
        Path (der Ordner, an dem abgelesen wurde). Rollen, die das Template
        der Ordnerart nicht fuehrt, fehlen in der Rueckgabe.

        Teilen sich Benutzer- und Computergruppe dieselbe Signatur, gilt fuer
        die gemeinsame Kandidatenmenge C:
          leer          -> beide NotFound, Option nicht erkannt;
          ein Kandidat  -> mit RID 515 Computer (Option erkannt), sonst User
                           (Option nicht erkannt);
          zwei          -> Option erkannt; genau einer mit RID 515 trennt
                           beide, sonst beide Ambiguous;
          drei und mehr -> Option erkannt, beide Ambiguous.

        Optionen (D-13): FSLogix-Profiles SystemAndBuiltinAdmins gilt als
        erkannt, wenn mindestens einer der beiden Well-Known-Eintraege mit
        seiner Template-Signatur explizit vorhanden ist. SystemLocalOps und
        ShareAdminFullControl werden NICHT abgelesen -- der Schreibpfad setzt
        sie nie (Get-FixedOptGroup), und ein Soll, das er nie setzt, waere
        eine zweite Wahrheit.

    .OUTPUTS
        [pscustomobject] mit Kind, Path, Role (hashtable Rolle -> Datensatz)
        und OptGroup (hashtable Optionsgruppe -> bool, erkannt).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [object] $Actual,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = ''
    )

    $signatur = Get-AuditRoleSignature -Kind $Kind
    $bekannt = @($script:WellKnownSid.Values | ForEach-Object { [string] $_ })

    # Die expliziten Ist-ACEs, normalisiert: je Signatur die SIDs ausserhalb
    # der sechs Well-Known-SIDs (je SID einmal, in Leserichtung) und die
    # Menge aller vollen Schluessel.
    $jeSignatur = @{}
    $alleSchluessel = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    foreach ($regel in @($Actual.Aces)) {

        if ($null -eq $regel) { continue }

        $norm = ConvertTo-AceKey -Ace $regel
        $null = $alleSchluessel.Add([string] $norm.Key)

        if ($bekannt -contains [string] $norm.Sid) { continue }

        $schluessel = ConvertTo-AuditSignature -Norm $norm

        if (-not $jeSignatur.ContainsKey($schluessel)) {
            $jeSignatur[$schluessel] = New-Object System.Collections.Generic.List[string]
        }

        if (-not $jeSignatur[$schluessel].Contains([string] $norm.Sid)) {
            $jeSignatur[$schluessel].Add([string] $norm.Sid)
        }
    }

    $rollen = @{}
    $optionen = @{}

    # Geordnet, nicht als Feld aus Feldern: eine Zeilenfolge von @(a, b)
    # innerhalb von @(...) wird entrollt und liefe elementweise durch.
    $tokenRolle = [ordered] @{ '<AdminGroup>' = 'Admin'; '<UserGroup>' = 'User'; '<ComputerGroup>' = 'Computer' }

    $geteilt = $signatur.ContainsKey('<UserGroup>') -and $signatur.ContainsKey('<ComputerGroup>') -and
        ([string] $signatur['<UserGroup>'] -ceq [string] $signatur['<ComputerGroup>'])

    foreach ($token in @($tokenRolle.Keys)) {

        if (-not $signatur.ContainsKey($token)) { continue }
        if ($geteilt -and (@('<UserGroup>', '<ComputerGroup>') -ccontains $token)) { continue }

        $kandidaten = @()
        if ($jeSignatur.ContainsKey([string] $signatur[$token])) { $kandidaten = @($jeSignatur[[string] $signatur[$token]]) }

        $rollen[[string] $tokenRolle[$token]] = New-AuditRoleRecord -Candidate $kandidaten -Path $Path
    }

    if ($geteilt) {

        $menge = @()
        if ($jeSignatur.ContainsKey([string] $signatur['<UserGroup>'])) { $menge = @($jeSignatur[[string] $signatur['<UserGroup>']]) }

        $rechner = @($menge | Where-Object { Test-IsComputerGroupSid -Sid $_ })
        $uebrige = @($menge | Where-Object { -not (Test-IsComputerGroupSid -Sid $_) })

        if ($menge.Count -eq 0) {
            $rollen['User'] = New-AuditRoleRecord -State 'NotFound' -Path $Path
            $rollen['Computer'] = New-AuditRoleRecord -State 'NotFound' -Path $Path
            $optionen['ComputerEnvironmentSettings'] = $false
        }
        elseif (($menge.Count -eq 1) -and ($rechner.Count -eq 1)) {
            $rollen['Computer'] = New-AuditRoleRecord -Candidate $rechner -Path $Path
            $rollen['User'] = New-AuditRoleRecord -State 'NotFound' -Path $Path
            $optionen['ComputerEnvironmentSettings'] = $true
        }
        elseif ($menge.Count -eq 1) {
            $rollen['User'] = New-AuditRoleRecord -Candidate $uebrige -Path $Path
            $rollen['Computer'] = New-AuditRoleRecord -State 'NotFound' -Path $Path
            $optionen['ComputerEnvironmentSettings'] = $false
        }
        elseif (($menge.Count -eq 2) -and ($rechner.Count -eq 1)) {
            $rollen['Computer'] = New-AuditRoleRecord -Candidate $rechner -Path $Path
            $rollen['User'] = New-AuditRoleRecord -Candidate $uebrige -Path $Path
            $optionen['ComputerEnvironmentSettings'] = $true
        }
        else {
            $rollen['User'] = New-AuditRoleRecord -Candidate $menge -State 'Ambiguous' -Path $Path
            $rollen['Computer'] = New-AuditRoleRecord -Candidate $menge -State 'Ambiguous' -Path $Path
            $optionen['ComputerEnvironmentSettings'] = $true
        }
    }

    if ($Kind -ceq 'FSLogix-Profiles') {

        $erkannt = $false
        foreach ($schluessel in @(Get-AuditWellKnownOptionKey -Kind $Kind -OptGroup 'SystemAndBuiltinAdmins')) {
            if ($alleSchluessel.Contains($schluessel)) { $erkannt = $true }
        }

        $optionen['SystemAndBuiltinAdmins'] = $erkannt
    }

    return [pscustomobject] @{
        Kind     = $Kind
        Path     = $Path
        Role     = $rollen
        OptGroup = $optionen
    }
}

function New-AuditRoleRecord {
    <#
    .SYNOPSIS
        Ein Rollendatensatz aus einer Kandidatenliste. Intern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Candidate = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = '',

        [Parameter()]
        [ValidateSet('', 'Found', 'NotFound', 'Ambiguous')]
        [string] $State = ''
    )

    $liste = @(@($Candidate) | Where-Object { -not [string]::IsNullOrEmpty($_) })

    if ([string]::IsNullOrEmpty($State)) {
        $State = if ($liste.Count -eq 1) { 'Found' } elseif ($liste.Count -eq 0) { 'NotFound' } else { 'Ambiguous' }
    }

    $sid = $null
    if ($State -ceq 'Found') { $sid = [System.Security.Principal.SecurityIdentifier]::new([string] $liste[0]) }

    return [pscustomobject] @{
        State = $State
        Sid   = $sid
        Count = $liste.Count
        Path  = $Path
    }
}

function Get-AuditHelpdeskProposal {
    <#
    .SYNOPSIS
        Der Helpdesk-Vorschlag aus den Eintraegen einer DEMProfiles-Freigabe
        (D-13, FEATURES.md Paragraph 1.3).

    .DESCRIPTION
        Die Helpdesk-Gruppe kommt in KEINEM ACL-Template vor, nur im
        Share-Template von DEMProfiles, dort mit Vollzugriff. Kandidat ist
        deshalb jeder Freigabeeintrag mit Access Full, einer nicht leeren SID
        und einer SID ungleich der Welt-SID. Genau einer -> Found, keiner ->
        NotFound (Option Helpdesk nicht erkannt), mehrere -> Ambiguous.

    .PARAMETER ShareActual
        Die Freigabeeintraege in SID-Form aus ConvertTo-ShareActual.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ShareActual,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = ''
    )

    $welt = [string] $script:WellKnownSid['WorldEveryone']
    $kandidaten = New-Object System.Collections.Generic.List[string]

    foreach ($eintrag in @($ShareActual)) {

        if ($null -eq $eintrag) { continue }

        $sid = [string] $eintrag.Sid
        if ([string]::IsNullOrEmpty($sid)) { continue }
        if ($sid -ceq $welt) { continue }
        if (-not [string]::Equals([string] $eintrag.Access, 'Full', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($kandidaten.Contains($sid)) { continue }

        $kandidaten.Add($sid)
    }

    return New-AuditRoleRecord -Candidate $kandidaten.ToArray() -Path $Path
}

function Get-AuditProductProposal {
    <#
    .SYNOPSIS
        Die Rollen- und Optionsvorschlaege eines Produkts (FSLogix oder DEM)
        aus den Schnappschuessen seiner Ziele (D-11, D-13, G-04-4a).

    .DESCRIPTION
        Abgelesen wird je Rolle am ersten LESBAREN Ziel des Produkts, dessen
        Template die Rolle fuehrt -- bei FSLogix in der Reihenfolge
        FSLogix-Profiles, FSLogix-Redirections, bei DEM in der Reihenfolge
        DEMConfig, DEMProfiles, DEMComputerLogs, je Ordnerart in
        Pfadreihenfolge. Ist die Profilablage unlesbar, liest der Vorschlag
        also an der Redirections-Ablage ab (Phase 7, RDX-04). Die
        abgelesenen Gruppen gelten dann fuer alle Ziele des Produkts. Ohne
        lesbares Ziel ist jede Rolle NotFound.

        Optionen: SystemAndBuiltinAdmins vom ersten lesbaren FSLogix-Ziel,
        ComputerEnvironmentSettings vom ersten lesbaren DEMConfig- oder
        DEMProfiles-Ziel. Helpdesk aus -HelpdeskShareActual; ohne diese
        Angabe NotFound.

    .OUTPUTS
        [pscustomobject] mit Product, Role, OptGroup, OptGroupPath und
        Helpdesk.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [hashtable] $Snapshot,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $HelpdeskShareActual = $null,

        [Parameter()]
        [AllowEmptyString()]
        [string] $HelpdeskPath = ''
    )

    $reihenfolge = if ($Product -eq 'FSLogix') { @('FSLogix-Profiles', 'FSLogix-Redirections') } else { @('DEMConfig', 'DEMProfiles', 'DEMComputerLogs') }

    $ziele = New-Object System.Collections.Generic.List[object]

    foreach ($art in $reihenfolge) {
        foreach ($ziel in @(@($Target) | Where-Object { ($null -ne $_) -and ([string] $_.Kind -ceq $art) } |
                    Sort-Object -Property { [string] $_.Path })) {
            $ziele.Add($ziel)
        }
    }

    # Je lesbarem Ziel ein Vorschlag, in der Reihenfolge oben.
    $vorschlaege = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in $ziele) {

        $schnapp = Get-AuditSnapshotEntry -Snapshot $Snapshot -LiteralPath ([string] $ziel.Path)
        if ($null -eq $schnapp) { continue }
        if ($null -eq $schnapp.Actual) { continue }

        $vorschlaege.Add((Get-AuditRoleProposal -Kind ([string] $ziel.Kind) -Actual $schnapp.Actual -Path ([string] $ziel.Path)))
    }

    $rollen = @{}

    foreach ($rolle in @('Admin', 'User', 'Computer')) {

        foreach ($vorschlag in $vorschlaege) {
            if ($vorschlag.Role.ContainsKey($rolle)) {
                $rollen[$rolle] = $vorschlag.Role[$rolle]
                break
            }
        }

        if (-not $rollen.ContainsKey($rolle)) {
            $rollen[$rolle] = New-AuditRoleRecord -State 'NotFound'
        }
    }

    $optionen = @{}
    $optionPfad = @{}

    foreach ($name in @('SystemAndBuiltinAdmins', 'ComputerEnvironmentSettings')) {
        foreach ($vorschlag in $vorschlaege) {
            if ($vorschlag.OptGroup.ContainsKey($name)) {
                $optionen[$name] = [bool] $vorschlag.OptGroup[$name]
                $optionPfad[$name] = [string] $vorschlag.Path
                break
            }
        }
    }

    $helpdesk = New-AuditRoleRecord -State 'NotFound' -Path $HelpdeskPath

    if ($null -ne $HelpdeskShareActual) {
        $helpdesk = Get-AuditHelpdeskProposal -ShareActual $HelpdeskShareActual -Path $HelpdeskPath
    }

    return [pscustomobject] @{
        Product      = $Product
        Role         = $rollen
        OptGroup     = $optionen
        OptGroupPath = $optionPfad
        Helpdesk     = $helpdesk
    }
}
