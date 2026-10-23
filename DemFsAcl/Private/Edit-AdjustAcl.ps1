<#
    Edit-AdjustAcl -- die Rechenschicht von Weg 3, "NTFS-Berechtigungen
    anpassen" (Entscheidung Projektinhaber 2026-09-24).

    REIN AUF OBJEKTEN. Keine Lesestelle, keine Schreibstelle, kein Eingabe- und
    kein Ausgabe-Cmdlet: gelesen wird ueber Get-ActualAceSet in der
    Orchestrierung, geschrieben ueber dieselbe Schreibstrecke wie Weg 1
    (Invoke-AclApplySet). Diese Datei rechnet nur aus, wie das ACL einer
    Zielwurzel NACH den gesammelten Aenderungen aussehen soll, und liefert es
    in der Form, die Expand-AclTemplate liefert -- damit laufen Preflight,
    Deskriptorbau, Schreiben, Ruecklesen und Vergleich unveraendert.

    DIE REGELN, AUS DEN SICHERHEITSVERBOTEN ABGELEITET:
      - Nur explizite Eintraege der Zielwurzel. Eine Wurzel mit geerbten
        Eintraegen oder ohne Vererbungsschutz wird abgelehnt: das Werkzeug
        schreibt immer einen geschuetzten Deskriptor, und stillschweigend
        geerbte Eintraege zu entfernen waere eine Aenderung, die niemand
        gewaehlt hat.
      - Eine Wurzel mit einem verweigernden Eintrag wird abgelehnt. Das
        Werkzeug schreibt nie einen; ihn fortzuschreiben hiesse, einen Zustand
        zu bestaetigen, den es selbst nie anlegen wuerde.
      - Der Ersteller-Besitzer-Eintrag und das Systemkonto sind nicht
        waehlbar: beide sind keine Gruppen, und ohne den ersten entsteht kein
        Benutzerprofil mehr.
      - Eine hinzugefuegte Gruppe bekommt genau die Rechte einer Rolle der
        Ordnerart aus dem Template -- nie frei gewaehlte.
#>

function Get-AdjustProtectedSid {
    <#
    .SYNOPSIS
        Die SIDs, die Weg 3 nie aendert: Ersteller-Besitzer und Systemkonto.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return [string[]] @(
        [string] (Resolve-TrusteeSid -InputValue 'WellKnown:CreatorOwner').Value
        [string] (Resolve-TrusteeSid -InputValue 'WellKnown:System').Value
    )
}

function Get-AdjustRoleShape {
    <#
    .SYNOPSIS
        Die Rollen einer Ordnerart laut Template: je Platzhalter-Token die
        Rechteformen, dazu die SIDs der vordefinierten Prinzipale.

    .OUTPUTS
        [pscustomobject] mit Role (Token -> Liste von Formen mit Rights,
        Inheritance, Propagation, Required) und WellKnownSid (string[]).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind
    )

    $template = Get-AclTemplate -Kind $Kind
    $rollen = @{}
    $bekannt = New-Object System.Collections.Generic.List[string]

    foreach ($ace in @($template['Aces'])) {

        $trustee = [string] $ace['Trustee']
        $optional = $ace.ContainsKey('Optional') -and [bool] $ace['Optional']

        $regel = [System.Security.AccessControl.FileSystemAccessRule]::new(
            [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),
            [System.Enum]::Parse([System.Security.AccessControl.FileSystemRights], [string] $ace['Rights']),
            [System.Enum]::Parse([System.Security.AccessControl.InheritanceFlags], [string] $ace['Inheritance']),
            [System.Enum]::Parse([System.Security.AccessControl.PropagationFlags], [string] $ace['Propagation']),
            [System.Security.AccessControl.AccessControlType]::Allow)

        $norm = ConvertTo-AceKey -Ace $regel

        if ($trustee.StartsWith('<', [System.StringComparison]::Ordinal)) {

            if (-not $rollen.ContainsKey($trustee)) { $rollen[$trustee] = New-Object System.Collections.Generic.List[object] }

            $rollen[$trustee].Add([pscustomobject] @{
                    Rights      = [int] $norm.Rights
                    Inheritance = [int] $norm.Inheritance
                    Propagation = [int] $norm.Propagation
                    Required    = -not $optional
                })
        }
        else {
            $bekannt.Add([string] (Resolve-TrusteeSid -InputValue $trustee).Value)
        }
    }

    # Als Array ablegen: @() um eine generische Liste dieser Eintraege wirft
    # unter Windows PowerShell 5.1 "Die Argumenttypen stimmen nicht ueberein".
    foreach ($token in @($rollen.Keys)) { $rollen[$token] = $rollen[$token].ToArray() }

    return [pscustomobject] @{
        Kind         = $Kind
        Role         = $rollen
        WellKnownSid = [string[]] @($bekannt | Select-Object -Unique)
    }
}

function New-AdjustState {
    <#
    .SYNOPSIS
        Der Ausgangszustand eines Ziels aus seinem Ist-Schnappschuss: die
        expliziten Eintraege als Regelliste, dazu ob das Ziel anpassbar ist.

    .PARAMETER Actual
        Der Schnappschuss aus Get-ActualAceSet, oder $null, wenn das ACL nicht
        lesbar war.

    .PARAMETER ReadError
        Der Lesefehler, wenn Actual $null ist.

    .OUTPUTS
        [pscustomobject] mit Kind, Path, ShareNames, Shape, Before, Rules
        (List der geplanten Regeln), Replaced (Schluessel der neuen Regel ->
        ersetzte Regel aus Before), Eligible und Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [object] $Actual = $null,

        [Parameter()]
        [string] $ReadError = '',

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $ShareNames = @()
    )

    $regeln = New-Object System.Collections.Generic.List[System.Security.AccessControl.FileSystemAccessRule]
    $vorher = @()
    $grund = ''

    if ($null -eq $Actual) {
        $grund = 'Das ACL lässt sich nicht lesen: {0}' -f $ReadError
    }
    else {
        $vorher = @($Actual.Aces)
        foreach ($r in $vorher) { $regeln.Add($r) }

        $verweigernd = @($vorher | Where-Object { $_.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow })

        if ($verweigernd.Count -gt 0) {
            $grund = 'Die Wurzel trägt {0} verweigernde(n) Eintrag/Einträge. Solche Einträge schreibt dieses Werkzeug nie; bitte die Wurzel zuerst mit Option 1 (vorhandenen Ordner übernehmen) neu berechtigen.' -f $verweigernd.Count
        }
        elseif (-not [bool] $Actual.IsProtected -or @($Actual.Inherited).Count -gt 0) {
            $grund = 'Die Wurzel erbt Rechte vom übergeordneten Ordner. Angepasst werden nur Wurzeln mit abgeschalteter Vererbung; bitte die Wurzel zuerst mit Option 1 (vorhandenen Ordner übernehmen) neu berechtigen.'
        }
    }

    return [pscustomobject] @{
        Kind       = $Kind
        Path       = $Path
        ShareNames = @($ShareNames)
        Shape      = (Get-AdjustRoleShape -Kind $Kind)
        Before     = $vorher
        Rules      = $regeln
        Replaced   = @{}
        Eligible   = [string]::IsNullOrEmpty($grund)
        Reason     = $grund
    }
}

function Get-AdjustRuleRole {
    <#
    .SYNOPSIS
        Die Rollen-Token, deren Rechteform eine Regel traegt, in fester
        Reihenfolge; leer fuer vordefinierte Prinzipale der Ordnerart.

    .DESCRIPTION
        Mehr als ein Token ist der Normalfall bei DEMConfig: Benutzer- und
        Computergruppe tragen dort dieselben Rechte, und am ACL allein ist
        nicht zu unterscheiden, welche Gruppe welche Rolle spielt.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object] $Shape,

        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemAccessRule] $Rule
    )

    $norm = ConvertTo-AceKey -Ace $Rule

    if (@($Shape.WellKnownSid) -contains $norm.Sid) { return [string[]] @() }
    if (@(Get-AdjustProtectedSid) -contains $norm.Sid) { return [string[]] @() }

    $treffer = New-Object System.Collections.Generic.List[string]

    foreach ($token in @('<AdminGroup>', '<UserGroup>', '<ComputerGroup>', '<HelpdeskGroup>')) {
        if (-not $Shape.Role.ContainsKey($token)) { continue }
        foreach ($form in @($Shape.Role[$token])) {
            if (($form.Rights -eq $norm.Rights) -and ($form.Inheritance -eq $norm.Inheritance) -and ($form.Propagation -eq $norm.Propagation)) {
                $treffer.Add($token)
                break
            }
        }
    }

    return [string[]] $treffer.ToArray()
}

function Get-AdjustGroup {
    <#
    .SYNOPSIS
        Die waehlbaren Gruppen ueber alle anpassbaren Ziele: jede SID mit
        mindestens einer expliziten Regel, ohne Ersteller-Besitzer und
        Systemkonto. In Reihenfolge des ersten Auftretens.

    .OUTPUTS
        Sammlung von [pscustomobject] mit Sid (SecurityIdentifier) und Count
        (Zahl der Ziele, in denen sie vorkommt).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $State
    )

    $geschuetzt = @(Get-AdjustProtectedSid)
    $reihenfolge = New-Object System.Collections.Generic.List[string]
    $zahl = @{}
    $objekt = @{}

    foreach ($ziel in @($State | Where-Object { $_.Eligible })) {

        $gesehen = @{}

        foreach ($regel in @($ziel.Rules)) {

            $sid = [string] $regel.IdentityReference.Value
            if ($geschuetzt -contains $sid) { continue }
            if ($gesehen.ContainsKey($sid)) { continue }
            $gesehen[$sid] = $true

            if (-not $zahl.ContainsKey($sid)) {
                $reihenfolge.Add($sid)
                $zahl[$sid] = 0
                $objekt[$sid] = $regel.IdentityReference
            }
            $zahl[$sid]++
        }
    }

    foreach ($sid in $reihenfolge) {
        [pscustomobject] @{ Sid = $objekt[$sid]; Count = [int] $zahl[$sid] }
    }
}

function Get-AdjustRoleChoice {
    <#
    .SYNOPSIS
        Die Rollen-Token, die in mindestens einem anpassbaren Ziel vorkommen,
        in fester Reihenfolge.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $State
    )

    $vorhanden = @{}
    foreach ($ziel in @($State | Where-Object { $_.Eligible })) {
        foreach ($token in @($ziel.Shape.Role.Keys)) { $vorhanden[[string] $token] = $true }
    }

    return [string[]] @(
        @('<AdminGroup>', '<UserGroup>', '<ComputerGroup>', '<HelpdeskGroup>') |
            Where-Object { $vorhanden.ContainsKey($_) }
    )
}

function Invoke-AdjustChange {
    <#
    .SYNOPSIS
        Wendet EINE Aenderung auf alle anpassbaren Ziele an und veraendert
        deren geplante Regelliste.

    .PARAMETER Action
        Add: der neuen Gruppe die Rechte der Rolle Role geben. Replace: jede
        Regel der Gruppe Sid auf NewSid umschreiben, Rechte unveraendert.
        Remove: jede Regel der Gruppe Sid entfernen.

    .OUTPUTS
        [pscustomobject] mit Applied (Pfade, in denen sich etwas geaendert
        hat) und Skipped (Pfade samt Grund, in denen es nicht anwendbar war).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $State,

        [Parameter(Mandatory)]
        [ValidateSet('Add', 'Replace', 'Remove')]
        [string] $Action,

        [Parameter()]
        [string] $Role = '',

        [Parameter()]
        [AllowNull()]
        [System.Security.Principal.SecurityIdentifier] $Sid = $null,

        [Parameter()]
        [AllowNull()]
        [System.Security.Principal.SecurityIdentifier] $NewSid = $null
    )

    $geschuetzt = @(Get-AdjustProtectedSid)

    foreach ($pruef in @($Sid, $NewSid)) {
        if (($null -ne $pruef) -and ($geschuetzt -contains [string] $pruef.Value)) {
            throw [System.ArgumentException]::new('Ersteller-Besitzer und Systemkonto sind in Weg 3 nicht wählbar.')
        }
    }

    if ($null -eq $Sid) {
        throw [System.ArgumentException]::new('Jede Änderung braucht eine Gruppe.')
    }
    if (($Action -eq 'Replace') -and ($null -eq $NewSid)) {
        throw [System.ArgumentException]::new('Ersetzen braucht die neue Gruppe.')
    }
    if (($Action -eq 'Add') -and [string]::IsNullOrEmpty($Role)) {
        throw [System.ArgumentException]::new('Hinzufügen braucht eine Rolle.')
    }

    $angewendet = New-Object System.Collections.Generic.List[string]
    $uebersprungen = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in @($State | Where-Object { $_.Eligible })) {

        $regeln = $ziel.Rules
        $vorher = $regeln.Count
        $geaendert = $false

        if ($Action -eq 'Add') {

            if (-not $ziel.Shape.Role.ContainsKey($Role)) {
                $uebersprungen.Add([pscustomobject] @{ Path = $ziel.Path; Kind = $ziel.Kind; Reason = 'Rolle gibt es in dieser Ordnerart nicht' })
                continue
            }

            foreach ($form in @($ziel.Shape.Role[$Role])) {
                $neu = [System.Security.AccessControl.FileSystemAccessRule]::new(
                    $Sid,
                    [System.Security.AccessControl.FileSystemRights] ($form.Rights -band (-bnot 0x100000)),
                    [System.Security.AccessControl.InheritanceFlags] $form.Inheritance,
                    [System.Security.AccessControl.PropagationFlags] $form.Propagation,
                    [System.Security.AccessControl.AccessControlType]::Allow)

                if (Add-AdjustRule -Rules $regeln -Rule $neu) { $geaendert = $true }
            }

            if (-not $geaendert) {
                $uebersprungen.Add([pscustomobject] @{ Path = $ziel.Path; Kind = $ziel.Kind; Reason = 'Eintrag besteht bereits' })
                continue
            }
        }
        else {

            $treffer = @($regeln | Where-Object { [string] $_.IdentityReference.Value -ceq [string] $Sid.Value })

            if ($treffer.Count -eq 0) {
                $uebersprungen.Add([pscustomobject] @{ Path = $ziel.Path; Kind = $ziel.Kind; Reason = 'Gruppe kommt hier nicht vor' })
                continue
            }

            foreach ($alt in $treffer) { $null = $regeln.Remove($alt) }

            # Ersetzt-Buchfuehrung fuer die Anzeige (Serverlauf 2026-09-25):
            # die neue Regel merkt sich die URSPRUENGLICHE Regel aus Before,
            # auch ueber mehrere Ersetzungen hinweg. Wer entfernt wird, verliert
            # seine Herkunft -- die urspruengliche Regel gilt dann als entfernt.
            $herkunft = @{}
            foreach ($alt in $treffer) {
                $altSchluessel = (ConvertTo-AceKey -Ace $alt).Key
                if ($ziel.Replaced.ContainsKey($altSchluessel)) {
                    $herkunft[$altSchluessel] = $ziel.Replaced[$altSchluessel]
                    $ziel.Replaced.Remove($altSchluessel)
                }
                else {
                    $herkunft[$altSchluessel] = $alt
                }
            }

            if ($Action -eq 'Replace') {
                foreach ($alt in $treffer) {
                    $neu = [System.Security.AccessControl.FileSystemAccessRule]::new(
                        $NewSid, $alt.FileSystemRights, $alt.InheritanceFlags, $alt.PropagationFlags,
                        [System.Security.AccessControl.AccessControlType]::Allow)
                    $null = Add-AdjustRule -Rules $regeln -Rule $neu

                    $ursprung = $herkunft[(ConvertTo-AceKey -Ace $alt).Key]
                    $neuSchluessel = (ConvertTo-AceKey -Ace $neu).Key
                    if ((ConvertTo-AceKey -Ace $ursprung).Key -cne $neuSchluessel) {
                        $ziel.Replaced[$neuSchluessel] = $ursprung
                    }
                }
            }

            $geaendert = $true
        }

        if ($geaendert -or $regeln.Count -ne $vorher) { $angewendet.Add([string] $ziel.Path) }
    }

    return [pscustomobject] @{
        Applied = $angewendet.ToArray()
        Skipped = $uebersprungen.ToArray()
    }
}

function Get-AdjustRowChange {
    <#
    .SYNOPSIS
        Die Zeilen einer Vorher/Nachher-Anzeige: je Regel, ob sie unveraendert,
        neu, ersetzt oder entfernt ist (Serverlauf 2026-09-25).

    .DESCRIPTION
        Reihenfolge: die Regeln aus Before in ihrer Reihenfolge -- unveraendert,
        an ihrer Stelle ersetzt oder entfernt --, danach die neuen. Eine
        Ersetzung steht als EINE Zeile mit der neuen Regel und der alten in Old.

    .OUTPUTS
        Sammlung von [pscustomobject] mit Rule, Change (None, Added, Replaced,
        Removed) und Old (die ersetzte Regel oder $null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $State
    )

    $nachher = @{}
    foreach ($r in @($State.Rules)) { $nachher[(ConvertTo-AceKey -Ace $r).Key] = $r }

    $vorher = @{}
    foreach ($r in @($State.Before)) { $vorher[(ConvertTo-AceKey -Ace $r).Key] = $r }

    $ersetztDurch = @{}
    $ersetzt = @{}
    if ($null -ne $State.PSObject.Properties['Replaced']) { $ersetzt = $State.Replaced }

    foreach ($neuSchluessel in @($ersetzt.Keys)) {
        if (-not $nachher.ContainsKey($neuSchluessel)) { continue }
        # Fiel die Ersetzung mit einem schon vorhandenen Eintrag zusammen, ist
        # der alte schlicht entfernt.
        if ($vorher.ContainsKey($neuSchluessel)) { continue }
        $altSchluessel = (ConvertTo-AceKey -Ace $ersetzt[$neuSchluessel]).Key
        if (-not $ersetztDurch.ContainsKey($altSchluessel)) { $ersetztDurch[$altSchluessel] = New-Object System.Collections.Generic.List[string] }
        $ersetztDurch[$altSchluessel].Add([string] $neuSchluessel)
    }

    $gezeigt = @{}

    foreach ($r in @($State.Before)) {

        $schluessel = (ConvertTo-AceKey -Ace $r).Key

        if ($nachher.ContainsKey($schluessel)) {
            $gezeigt[$schluessel] = $true
            [pscustomobject] @{ Rule = $r; Change = 'None'; Old = $null }
            continue
        }

        if ($ersetztDurch.ContainsKey($schluessel)) {
            foreach ($neuSchluessel in $ersetztDurch[$schluessel]) {
                if ($gezeigt.ContainsKey($neuSchluessel)) { continue }
                $gezeigt[$neuSchluessel] = $true
                [pscustomobject] @{ Rule = $nachher[$neuSchluessel]; Change = 'Replaced'; Old = $r }
            }
            continue
        }

        [pscustomobject] @{ Rule = $r; Change = 'Removed'; Old = $null }
    }

    foreach ($r in @($State.Rules)) {
        $schluessel = (ConvertTo-AceKey -Ace $r).Key
        if ($gezeigt.ContainsKey($schluessel)) { continue }
        if ($vorher.ContainsKey($schluessel)) { continue }
        $gezeigt[$schluessel] = $true
        [pscustomobject] @{ Rule = $r; Change = 'Added'; Old = $null }
    }
}

function Add-AdjustRule {
    <#
    .SYNOPSIS
        Haengt eine Regel an, wenn ihr Schluessel noch nicht vorkommt. Intern
        zu Invoke-AdjustChange.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Security.AccessControl.FileSystemAccessRule]] $Rules,

        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemAccessRule] $Rule
    )

    $schluessel = (ConvertTo-AceKey -Ace $Rule).Key

    foreach ($r in $Rules) {
        if ((ConvertTo-AceKey -Ace $r).Key -ceq $schluessel) { return $false }
    }

    $Rules.Add($Rule)
    return $true
}

function Test-AdjustChanged {
    <#
    .SYNOPSIS
        Wahr, wenn sich die geplante Regelmenge eines Ziels von der gelesenen
        unterscheidet.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object] $State
    )

    $vorher = @(@($State.Before) | ForEach-Object { (ConvertTo-AceKey -Ace $_).Key } | Sort-Object -Unique)
    $nachher = @(@($State.Rules) | ForEach-Object { (ConvertTo-AceKey -Ace $_).Key } | Sort-Object -Unique)

    return (($vorher -join "`n") -cne ($nachher -join "`n"))
}

function Get-AdjustMissingRole {
    <#
    .SYNOPSIS
        Die Rollen der Ordnerart, fuer die nach den Aenderungen eine eigene
        Gruppe fehlt.

    .DESCRIPTION
        Rollen mit gleicher Rechteform (DEMConfig: Benutzer- und
        Computergruppe) sind am ACL nicht zu unterscheiden. Gezaehlt wird
        deshalb je Rechteform, wie viele verschiedene Gruppen sie tragen --
        vorher und nachher. Gewarnt wird, wenn nachher weniger Gruppen da sind,
        als die Form Pflichtrollen hat, oder wenn eine Gruppe weggefallen ist
        und nachher weniger Gruppen als Rollen bleiben. Die Warnung nennt dann
        alle Rollen dieser Form.

    .OUTPUTS
        [string[]] -- je Eintrag ein Token oder mehrere, getrennt durch "|".
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object] $State
    )

    $formVon = @{}
    $rollenJeForm = @{}

    foreach ($token in @('<AdminGroup>', '<UserGroup>', '<ComputerGroup>', '<HelpdeskGroup>')) {
        if (-not $State.Shape.Role.ContainsKey($token)) { continue }
        $form = @(@($State.Shape.Role[$token]) | ForEach-Object { '{0}/{1}/{2}' -f $_.Rights, $_.Inheritance, $_.Propagation } | Sort-Object) -join ';'
        $formVon[$token] = $form
        if (-not $rollenJeForm.ContainsKey($form)) { $rollenJeForm[$form] = New-Object System.Collections.Generic.List[string] }
        $rollenJeForm[$form].Add($token)
    }

    $zaehle = {
        param($Regeln, $Form)
        $sids = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($regel in @($Regeln)) {
            foreach ($token in @(Get-AdjustRuleRole -Shape $State.Shape -Rule $regel)) {
                if ($formVon[$token] -ceq $Form) { $null = $sids.Add([string] $regel.IdentityReference.Value) }
            }
        }
        $sids.Count
    }

    $fehlend = New-Object System.Collections.Generic.List[string]

    foreach ($form in @($rollenJeForm.Keys)) {

        $rollen = @($rollenJeForm[$form])
        $pflicht = @($rollen | Where-Object { @(@($State.Shape.Role[$_]) | Where-Object { $_.Required }).Count -gt 0 })

        $vorher = [int] (& $zaehle $State.Before $form)
        $nachher = [int] (& $zaehle $State.Rules $form)

        $zuWenig = $nachher -lt $pflicht.Count
        $weggefallen = ($nachher -lt $vorher) -and ($nachher -lt $rollen.Count)

        if ($zuWenig -or $weggefallen) { $fehlend.Add(($rollen -join '|')) }
    }

    return [string[]] @($fehlend | Sort-Object)
}

function ConvertTo-AdjustDesired {
    <#
    .SYNOPSIS
        Die geplante Regelmenge eines Ziels in der Form eines DesiredAcl, wie
        Expand-AclTemplate es liefert.

    .PARAMETER Name
        SID-Wert -> Anzeigename, fuer das Feld Trustee der Befunde.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $State,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Name = $null
    )

    $datensaetze = New-Object System.Collections.Generic.List[object]

    foreach ($regel in @($State.Rules)) {

        $sid = [System.Security.Principal.SecurityIdentifier] $regel.IdentityReference
        $beschriftung = ConvertTo-AppliesTo -Inheritance $regel.InheritanceFlags -Propagation $regel.PropagationFlags

        $trustee = [string] $sid.Value
        if (($null -ne $Name) -and $Name.ContainsKey($trustee)) { $trustee = [string] $Name[$trustee] }

        $datensaetze.Add([pscustomobject] @{
                Rule              = $regel
                Trustee           = $trustee
                Sid               = $sid
                Rights            = [int] $regel.FileSystemRights
                Inheritance       = [int] $regel.InheritanceFlags
                Propagation       = [int] $regel.PropagationFlags
                AccessControlType = $regel.AccessControlType
                IsInherited       = $false
                AppliesTo         = $beschriftung.AppliesTo
                Icacls            = $beschriftung.Icacls
                Status            = ''
                Source            = ''
                Section           = ''
                Optional          = $false
                OptGroup          = ''
            })
    }

    return [pscustomobject] @{
        Kind                      = [string] $State.Kind
        ProtectInheritance        = $true
        ProtectInheritanceStatus  = ''
        ProtectInheritanceSource  = ''
        ProtectInheritanceSection = ''
        Aces                      = @(Sort-AceCanonical -Ace $datensaetze.ToArray())
        OptDecisions              = @()
    }
}

function Get-AdjustRightsLabel {
    <#
    .SYNOPSIS
        Die Rechte einer Regel als kurzer deutscher Name, sonst als Maske.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemAccessRule] $Rule
    )

    $maske = [int] (ConvertTo-AceKey -Ace $Rule).Rights

    $namen = @{
        0x1F01FF = 'Vollzugriff'
        0x1301BF = 'Ändern'
        0x1200A9 = 'Lesen, Ausführen'
        0x120089 = 'Lesen'
        0x100004 = 'Ordner erstellen'
        0x100006 = 'Dateien und Ordner erstellen'
    }

    if ($namen.ContainsKey($maske)) { return [string] $namen[$maske] }

    return ('Rechte 0x{0:X}' -f $maske)
}
