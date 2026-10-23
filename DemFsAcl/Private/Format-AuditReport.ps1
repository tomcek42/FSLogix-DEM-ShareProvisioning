<#
    Format-AuditReport -- der Bericht der Bestandspruefung (AUDIT-06, D-16,
    D-17, D-18).

    DIESE DATEI DRUCKT NICHT. Sie liefert Zeilensaetze (New-OperatorTextLine);
    ausgegeben wird ausschliesslich ueber Write-OperatorLine (OUT-07). Eine
    Berichtsdatei entsteht nicht (D-18).

    OBEN DIE UEBERSICHT, DARUNTER DIE BEFUNDE (D-16). Seit 2026-10-22 in zwei
    Ansichten (Entscheidung Projektinhaber): Table -- die Pruefungstabelle
    mit einer Zeile je Ablage und darunter EINE Gruppentabelle ueber alle
    Ablagen, eine Zeile je Prinzipal -- und Block, je Ablage ein Kopf, eine
    Zustandszeile und ihre Gruppentabelle mit "Gilt fuer". Vorgabe ist
    Table. Die Tabellen sind gerahmt wie in Weg 3 (Format-AdjustTable,
    Serverlauf 2026-09-25); D-16 verlangt ausdruecklich eine Tabelle und
    geht damit OUT-04 Regel 4 vor (Planerentscheid 5 aus 05-01). Die Befunde
    darunter entstehen ueber Format-ProvisioningSummary und halten alle fuenf
    Luftigkeitsregeln; die Zuordnung Satz -> Ziel laeuft dort ueber
    Ordnerart UND Pfad (Get-TargetResult, G-04-1a).

    GELESEN WIRD HIER NICHTS. Die Gruppenzeilen entstehen aus dem einen
    Schnappschuss, den Freigabeeintraegen an den Ergebnissaetzen
    (ShareActual) und der Namenskarte, die die Orchestrierung einmal
    aufgeloest hat (IDENT-06).
#>

function Format-AuditReport {
    <#
    .SYNOPSIS
        Der Pruefbericht als Zeilensaetze: Uebersicht in der gewaehlten
        Ansicht, Befunde nur fuer abweichende Ziele.

    .PARAMETER Target
        Die geprueften Ziele, jeweils mit Kind, Path, RelativePath, ShareName,
        Binding, Role und Desired.

    .PARAMETER Result
        Die gesamte Ergebnissammlung des Pruefwegs.

    .PARAMETER Owner
        Pfad -> Besitzer (Name, Expected) aus Get-AuditOwnerTable; ohne ihn
        zeigt die Tabelle die Marke der Stufe Owner.

    .PARAMETER Snapshot
        Der Schnappschuss je Pfad aus Get-AuditSnapshot; ohne ihn entfallen
        die NTFS-Eintraege der Gruppenuebersicht.

    .PARAMETER Name
        SID -> Anzeigename, einmal aufgeloest.

    .PARAMETER View
        Table (Vorgabe) oder Block.

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Owner = $null,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Snapshot = $null,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Name = $null,

        [Parameter()]
        [ValidateSet('Table', 'Block')]
        [string] $View = 'Table'
    )

    $ueberschrift = Get-ReportUeberschrift
    $zeilen = New-Object System.Collections.Generic.List[object]
    $ziele = @(@($Target) | Where-Object { $null -ne $_ })
    $saetze = @(@($Result) | Where-Object { $null -ne $_ })

    if ($null -eq $Snapshot) { $Snapshot = @{} }
    if ($null -eq $Name) { $Name = @{} }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    if ($ziele.Count -eq 0) {
        $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['AuditTable'])))
        $zeilen.Add((New-OperatorTextLine -Text '  Es wurde kein Ordner geprüft.'))
    }
    elseif ($View -ceq 'Block') {
        $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['AuditBlock'])))

        foreach ($ziel in $ziele) {
            foreach ($zeile in @(Format-AuditBlock -Target $ziel -Result $saetze -Owner $Owner -Snapshot $Snapshot -Name $Name)) { $zeilen.Add($zeile) }
        }
    }
    else {
        $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['AuditTable'])))
        foreach ($zeile in @(Format-AuditTable -Target $ziele -Result $saetze -Owner $Owner)) { $zeilen.Add($zeile) }

        $zeilen.Add((New-OperatorTextLine -Text ''))
        $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['AuditGroupTable'])))
        foreach ($zeile in @(Format-AuditGroupTable -Target $ziele -Result $saetze -Snapshot $Snapshot -Name $Name)) { $zeilen.Add($zeile) }
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    # Die Uebersicht traegt das Ergebnis; darunter steht nur, was vom Soll
    # abweicht (Serverlauf 2026-09-25).
    foreach ($zeile in @(Format-ProvisioningSummary -Result $saetze -Target $ziele -Capability $Capability `
                -Group $Group -HeadingKey 'AuditDetail' -ResultProvenance -OnlyDeviating)) {
        $zeilen.Add($zeile)
    }

    return $zeilen.ToArray()
}

function Format-AuditTable {
    <#
    .SYNOPSIS
        Die Pruefungstabelle: eine Zeile je Ziel (D-16, Planerentscheid 5),
        gerahmt wie in Weg 3 (Serverlauf 2026-09-25).

    .DESCRIPTION
        Spalten Ordner, Ordnerart, NTFS, Freigabe, Caching, Besitzer. Der
        Ordner steht relativ zur Wurzel und wird ab 33 Zeichen vorn mit "..."
        gekuerzt -- der volle Pfad steht in den Befunden darunter.

        Eine Pruefzelle ist die Statusmarke des schwersten Satzes ihrer Stufe
        -- NTFS aus AclVerify, Freigabe aus ShareVerify, Caching aus
        ShareCaching -- in der Farbe ihres Zustands, oder "--", wenn diese
        Stufe kein Ergebnis hat.

        Der Besitzer steht mit Namen da, nicht als Marke. Gehoert er nicht zu
        den ueblichen Besitzern, ist er cyan und traegt ein Sternchen; die
        Fussnote unter der Tabelle sagt, dass das unkritisch ist. Ohne
        Besitzerangabe gilt die Marke der Stufe Owner.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Owner = $null
    )

    $kopf = @('Ordner', 'Ordnerart', 'NTFS', 'Freigabe', 'Caching', 'Besitzer')
    $stufen = @('AclVerify', 'ShareVerify', 'ShareCaching')

    $reihen = New-Object System.Collections.Generic.List[object]
    $fussnote = $false

    foreach ($ziel in $Target) {

        $eigene = @(Get-TargetResult -Result $Result -Target $ziel)

        $zellen = New-Object System.Collections.Generic.List[object]
        $zellen.Add((Get-AuditOrdnerZelle -Target $ziel))
        $zellen.Add([string] $ziel.Kind)

        foreach ($stufe in @($stufen) + @('Owner')) {

            if (($stufe -ceq 'Owner') -and ($null -ne $Owner) -and $Owner.ContainsKey([string] $ziel.Path)) {

                $besitzer = $Owner[[string] $ziel.Path]

                if ([bool] $besitzer.Expected) {
                    $zellen.Add([string] $besitzer.Name)
                }
                else {
                    $fussnote = $true
                    $zellen.Add((New-AdjustCell -Segment @((New-TextSegment -Text ('{0} *' -f [string] $besitzer.Name) -Severity 'Heading'))))
                }
                continue
            }

            $stufenSaetze = @($eigene | Where-Object { [string] $_.Stage -ceq $stufe })
            if ($stufenSaetze.Count -eq 0) { $zellen.Add('--'); continue }

            $status = Get-SchwersterStatus -Result $stufenSaetze
            $zellen.Add((New-AdjustCell -Segment @((New-TextSegment -Text (Get-StatusMarkierung -Status $status) -Severity (Get-LineSeverity -Status $status)))))
        }

        $reihen.Add($zellen.ToArray())
    }

    $zeilen = New-Object System.Collections.Generic.List[object]

    foreach ($zeile in @(Format-AdjustTable -Header $kopf -Row $reihen.ToArray() -Indent '  ')) { $zeilen.Add($zeile) }

    if ($fussnote) {
        $zeilen.Add((New-OperatorTextLine -Text '  * Besitzer ist nicht die Administratorengruppe, das Systemkonto oder die Gruppe'))
        $zeilen.Add((New-OperatorTextLine -Text '    der Administratoren. Das ist unkritisch; das Werkzeug setzt den Besitzer nie.'))
    }

    return $zeilen.ToArray()
}

function Get-AuditOrdnerZelle {
    <#
    .SYNOPSIS
        Die Ordnerzelle eines Ziels: relativ zur Wurzel, ab 33 Zeichen vorn
        gekuerzt. Intern.

    .DESCRIPTION
        Ist die Wurzel selbst das Ziel (D-07, RelativePath "."), steht ihr
        Blattname da -- ein Punkt allein sagte dem Operator nichts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Target
    )

    $relativ = ''
    if ($null -ne $Target.PSObject.Properties['RelativePath']) { $relativ = [string] $Target.RelativePath }

    if ([string]::IsNullOrEmpty($relativ) -or ($relativ -ceq '.')) {
        $relativ = [System.IO.Path]::GetFileName(([string] $Target.Path).TrimEnd([char] 92, [char] 47))
        if ([string]::IsNullOrEmpty($relativ)) { $relativ = [string] $Target.Path }
    }

    if ($relativ.Length -ge 33) { $relativ = '...' + $relativ.Substring($relativ.Length - 29) }

    return $relativ
}

function Get-AuditPrincipalRow {
    <#
    .SYNOPSIS
        Die Prinzipale einer Ablage fuer die Gruppenuebersicht: je SID eine
        Zeile mit Rolle, NTFS-Eintraegen, Freigabeeintraegen und Zustand.
        Intern.

    .DESCRIPTION
        NTFS: jeder explizite Ist-Eintrag; gueltig ist er genau dann, wenn
        sein Vergleichsschluessel im Soll des Ziels steht -- dasselbe Urteil
        wie Compare-AceSet, ohne zweiten Vergleich. Ein Soll-Eintrag ohne
        Ist-Eintrag erscheint als "fehlt".

        Freigabe: die Eintraege, die Test-AuditShare gelesen hat (ShareActual
        an den Saetzen der Stufe ShareVerify); ungueltig ist, was der
        Vergleich als Unexpected meldet, Missing erscheint als "fehlt".

        Rolle: aus der Ableitung (Role am Ziel), Helpdesk aus den
        Freigabesaetzen, sonst "vordefiniert" fuer die Well-Known-SIDs des
        Werkzeugs und "unbekannt" fuer jede andere SID. Sortiert nach Rolle,
        innerhalb der Rolle in Leserichtung.

    .OUTPUTS
        Sammlung von [pscustomobject] mit Sid, Name, Role, Ntfs, Share und
        Status; Ntfs und Share sind Felder von Eintraegen mit Text, AppliesTo
        und Status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [hashtable] $Snapshot,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $pfad = [string] $Target.Path
    $reihe = [ordered] @{}

    $neueZeile = {
        param($Sid)
        if (-not $reihe.Contains($Sid)) {
            $reihe[$Sid] = [pscustomobject] @{
                Sid   = $Sid
                Ntfs  = New-Object System.Collections.Generic.List[object]
                Share = New-Object System.Collections.Generic.List[object]
            }
        }
        return $reihe[$Sid]
    }

    # --- NTFS ----------------------------------------------------------------
    $soll = @{}
    if (($null -ne $Target.PSObject.Properties['Desired']) -and ($null -ne $Target.Desired)) {
        foreach ($ace in @($Target.Desired.Aces)) {
            if ($null -eq $ace) { continue }
            $soll[[string] (ConvertTo-AceKey -Ace $ace.Rule).Key] = $ace.Rule
        }
    }

    $eintrag = $null
    if ($Snapshot.ContainsKey($pfad)) { $eintrag = $Snapshot[$pfad] }

    if (($null -ne $eintrag) -and ($null -ne $eintrag.Actual)) {

        $gesehen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

        foreach ($regel in @($eintrag.Actual.Aces)) {

            if ($null -eq $regel) { continue }

            $schluessel = [string] (ConvertTo-AceKey -Ace $regel).Key
            $null = $gesehen.Add($schluessel)

            $text = Get-AdjustRightsLabel -Rule $regel
            if ($regel.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { $text = 'Verweigert: ' + $text }

            $zeile = & $neueZeile ([string] $regel.IdentityReference.Value)
            $zeile.Ntfs.Add([pscustomobject] @{
                    Text      = $text
                    AppliesTo = [string] (ConvertTo-AppliesTo -Inheritance $regel.InheritanceFlags -Propagation $regel.PropagationFlags).AppliesTo
                    Status    = $(if ($soll.ContainsKey($schluessel)) { 'OK' } else { 'Error' })
                })
        }

        foreach ($schluessel in @($soll.Keys | Sort-Object)) {

            if ($gesehen.Contains([string] $schluessel)) { continue }

            $regel = $soll[$schluessel]
            $zeile = & $neueZeile ([string] $regel.IdentityReference.Value)
            $zeile.Ntfs.Add([pscustomobject] @{
                    Text      = ('{0} (fehlt)' -f (Get-AdjustRightsLabel -Rule $regel))
                    AppliesTo = [string] (ConvertTo-AppliesTo -Inheritance $regel.InheritanceFlags -Propagation $regel.PropagationFlags).AppliesTo
                    Status    = 'Error'
                })
        }
    }

    # --- Freigabe ------------------------------------------------------------
    $stufe = @{ Full = 'Vollzugriff'; Change = 'Ändern'; Read = 'Lesen' }
    $helpdesk = New-Object System.Collections.Generic.List[string]
    $kontoName = @{}

    $freigabeSaetze = @(Get-TargetResult -Result @($Result) -Target $Target | Where-Object {
            ([string] $_.Stage -ceq 'ShareVerify') -and ($null -ne $_.PSObject.Properties['ShareActual'])
        })
    $mehrere = $freigabeSaetze.Count -gt 1

    foreach ($satz in $freigabeSaetze) {

        $vorsatz = if ($mehrere) { '{0}: ' -f [string] $satz.ShareName } else { '' }

        $unerwartet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

        foreach ($befund in @($satz.Detail)) {
            if (($null -eq $befund) -or ($null -eq $befund.PSObject.Properties['Finding'])) { continue }

            if ([string] $befund.Finding -ceq 'Unexpected') { $null = $unerwartet.Add(('{0}|{1}' -f [string] $befund.Sid, [string] $befund.Access)) }

            if ([string] $befund.Finding -ceq 'Missing') {
                $zugriff = [string] $befund.Access
                if ($stufe.ContainsKey($zugriff)) { $zugriff = [string] $stufe[$zugriff] }
                $zeile = & $neueZeile ([string] $befund.Sid)
                $zeile.Share.Add([pscustomobject] @{ Text = ('{0}{1} (fehlt)' -f $vorsatz, $zugriff); AppliesTo = ''; Status = 'Error' })
            }
        }

        foreach ($ist in @($satz.ShareActual)) {

            if ($null -eq $ist) { continue }

            $sid = [string] $ist.Sid
            if ([string]::IsNullOrEmpty($sid)) { $sid = '?' + [string] $ist.AccountName }
            if (-not $kontoName.ContainsKey($sid)) { $kontoName[$sid] = [string] $ist.AccountName }

            $zugriff = [string] $ist.Access
            if ($stufe.ContainsKey($zugriff)) { $zugriff = [string] $stufe[$zugriff] }

            $zeile = & $neueZeile $sid
            $zeile.Share.Add([pscustomobject] @{
                    Text      = ('{0}{1}' -f $vorsatz, $zugriff)
                    AppliesTo = ''
                    Status    = $(if ($unerwartet.Contains(('{0}|{1}' -f [string] $ist.Sid, [string] $ist.Access))) { 'Error' } else { 'OK' })
                })
        }

        if ($null -ne $satz.PSObject.Properties['HelpdeskSid']) {
            foreach ($sid in @($satz.HelpdeskSid)) { if (-not $helpdesk.Contains([string] $sid)) { $helpdesk.Add([string] $sid) } }
        }
    }

    # --- Rolle, Name, Zustand ---------------------------------------------------
    $rollen = @{}
    if (($null -ne $Target.PSObject.Properties['Role']) -and ($Target.Role -is [hashtable])) { $rollen = $Target.Role }

    $bekannt = @($script:WellKnownSid.Values | ForEach-Object { [string] $_ })
    $rang = @{ 'Administratoren' = 0; 'Benutzer' = 1; 'Benutzer / Computer' = 2; 'Computer' = 3; 'Helpdesk' = 4; 'vordefiniert' = 5; 'unbekannt' = 6 }

    $zeilen = New-Object System.Collections.Generic.List[object]
    $nummer = 0

    foreach ($sid in @($reihe.Keys)) {

        $zeile = $reihe[$sid]

        $rolle = 'unbekannt'
        if ($rollen.ContainsKey($sid)) { $rolle = (@($rollen[$sid]) | ForEach-Object { Get-AdjustRoleShortLabel -Token $_ }) -join ' / ' }
        elseif ($helpdesk.Contains($sid)) { $rolle = 'Helpdesk' }
        elseif ($bekannt -contains $sid) { $rolle = 'vordefiniert' }

        $anzeige = $sid
        if ($Name.ContainsKey($sid) -and -not [string]::IsNullOrEmpty([string] $Name[$sid])) { $anzeige = [string] $Name[$sid] }
        elseif ($kontoName.ContainsKey($sid) -and -not [string]::IsNullOrEmpty([string] $kontoName[$sid])) { $anzeige = [string] $kontoName[$sid] }

        # .ToArray(): @() um eine List[object] wirft unter 5.1 (CLAUDE.md).
        $ntfs = $zeile.Ntfs.ToArray()
        $freigabe = $zeile.Share.ToArray()
        $alle = [object[]] (@($ntfs) + @($freigabe))
        $status = if (@($alle | Where-Object { [string] $_.Status -ceq 'Error' }).Count -gt 0) { 'Error' } else { 'OK' }
        if ($rolle -ceq 'unbekannt') { $status = 'Error' }

        $zeilen.Add([pscustomobject] @{
                Sid    = $sid
                Name   = $anzeige
                Role   = $rolle
                Ntfs   = $ntfs
                Share  = $freigabe
                Status = $status
                Order  = ([int] $rang[$rolle] * 10000) + $nummer
            })
        $nummer++
    }

    return @($zeilen.ToArray() | Sort-Object -Property Order)
}

function Get-AuditEntryCell {
    <#
    .SYNOPSIS
        Die Eintraege einer Zeile als eine Zelle: ungueltige rot, mehrere mit
        "; " verbunden, keiner als "--". Intern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Entry,

        [Parameter()]
        [switch] $AppliesTo
    )

    $eintraege = @(@($Entry) | Where-Object { $null -ne $_ })
    if ($eintraege.Count -eq 0) { return '--' }

    $abschnitte = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $eintraege.Count; $i++) {
        if ($i -gt 0) { $abschnitte.Add((New-TextSegment -Text '; ')) }
        $text = if ($AppliesTo) { [string] $eintraege[$i].AppliesTo } else { [string] $eintraege[$i].Text }
        $schwere = if ([string] $eintraege[$i].Status -ceq 'Error') { 'Error' } else { 'None' }
        $abschnitte.Add((New-TextSegment -Text $text -Severity $schwere))
    }

    return (New-AdjustCell -Segment $abschnitte.ToArray())
}

function Get-AuditStatusCell {
    <#
    .SYNOPSIS
        Die Statusmarke als farbige Zelle. Intern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Status
    )

    return (New-AdjustCell -Segment @((New-TextSegment -Text (Get-StatusMarkierung -Status $Status) -Severity (Get-LineSeverity -Status $Status))))
}

function Format-AuditGroupTable {
    <#
    .SYNOPSIS
        Die Gruppenuebersicht der Tabellenansicht: eine Tabelle ueber alle
        Ablagen, eine Zeile je Prinzipal (Entscheidung Projektinhaber
        2026-10-22).

    .DESCRIPTION
        Spalten Ablage, Prinzipal, Rolle, NTFS, Freigabe, Status. Die Ablage
        steht nur in der ersten Zeile ihres Abschnitts. "Gilt fuer" steht nur
        in der Blockansicht -- die Tabelle bliebe sonst auf keiner
        Serverkonsole lesbar breit; ein Eintrag mit falscher Vererbung ist
        trotzdem rot und steht in den Befunden.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [hashtable] $Snapshot,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $reihen = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in @($Target)) {

        if ($null -eq $ziel) { continue }

        $ablage = Get-AuditOrdnerZelle -Target $ziel
        $prinzipale = @(Get-AuditPrincipalRow -Target $ziel -Result $Result -Snapshot $Snapshot -Name $Name)

        if ($prinzipale.Count -eq 0) {
            $reihen.Add(@($ablage, '(keine Einträge lesbar)', '--', '--', '--', (Get-AuditStatusCell -Status 'Error')))
            continue
        }

        for ($i = 0; $i -lt $prinzipale.Count; $i++) {
            $p = $prinzipale[$i]
            $reihen.Add(@(
                    $(if ($i -eq 0) { $ablage } else { '' })
                    [string] $p.Name
                    [string] $p.Role
                    (Get-AuditEntryCell -Entry @($p.Ntfs))
                    (Get-AuditEntryCell -Entry @($p.Share))
                    (Get-AuditStatusCell -Status ([string] $p.Status))
                ))
        }
    }

    return @(Format-AdjustTable -Header @('Ablage', 'Prinzipal', 'Rolle', 'NTFS', 'Freigabe', 'Status') -Row $reihen.ToArray() -Indent '  ')
}

function Format-AuditBlock {
    <#
    .SYNOPSIS
        Eine Ablage in der Blockansicht: Kopf, Zustandszeile und ihre
        Gruppentabelle mit "Gilt fuer" (Entscheidung Projektinhaber
        2026-10-22).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Owner = $null,

        [Parameter(Mandatory)]
        [hashtable] $Snapshot,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $zeilen = New-Object System.Collections.Generic.List[object]
    $eigene = @(Get-TargetResult -Result @($Result) -Target $Target)

    $freigabe = [string] $Target.ShareName
    if ([string]::IsNullOrWhiteSpace($freigabe)) { $freigabe = '(keine)' }

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Severity 'Heading' -Text (ConvertTo-Einzeiler -Wert (
                    '  {0} -- {1} -- Freigabe {2}' -f [string] $Target.Kind, [string] $Target.Path, $freigabe))))

    $teile = New-Object System.Collections.Generic.List[string]
    $gesamt = @()

    foreach ($paar in @(@('NTFS', 'AclVerify'), @('Freigabe', 'ShareVerify'), @('Caching', 'ShareCaching'))) {
        $stufenSaetze = @($eigene | Where-Object { [string] $_.Stage -ceq $paar[1] })
        if ($stufenSaetze.Count -eq 0) { $teile.Add(('{0} --' -f $paar[0])); continue }
        $gesamt += $stufenSaetze
        $teile.Add(('{0} {1}' -f $paar[0], (Get-StatusMarkierung -Status (Get-SchwersterStatus -Result $stufenSaetze))))
    }

    if (($null -ne $Owner) -and $Owner.ContainsKey([string] $Target.Path)) {
        $besitzer = $Owner[[string] $Target.Path]
        $teile.Add(('Besitzer {0}{1}' -f [string] $besitzer.Name, $(if ([bool] $besitzer.Expected) { '' } else { ' (unkritisch)' })))
    }

    $zeilen.Add((New-OperatorTextLine -Severity (Get-LineSeverity -Status (Get-SchwersterStatus -Result $gesamt)) -Text (
                ConvertTo-Einzeiler -Wert ('  ' + ($teile.ToArray() -join ' | ')))))

    $prinzipale = @(Get-AuditPrincipalRow -Target $Target -Result $Result -Snapshot $Snapshot -Name $Name)

    if ($prinzipale.Count -eq 0) {
        $zeilen.Add((New-OperatorTextLine -Text '  Keine Einträge lesbar.'))
        return $zeilen.ToArray()
    }

    $reihen = New-Object System.Collections.Generic.List[object]

    foreach ($p in $prinzipale) {
        $reihen.Add(@(
                [string] $p.Name
                [string] $p.Role
                (Get-AuditEntryCell -Entry @($p.Ntfs))
                (Get-AuditEntryCell -Entry @($p.Ntfs) -AppliesTo)
                (Get-AuditEntryCell -Entry @($p.Share))
                (Get-AuditStatusCell -Status ([string] $p.Status))
            ))
    }

    foreach ($zeile in @(Format-AdjustTable -Header @('Prinzipal', 'Rolle', 'NTFS', 'Gilt für', 'Freigabe', 'Status') -Row $reihen.ToArray() -Indent '  ')) {
        $zeilen.Add($zeile)
    }

    return $zeilen.ToArray()
}

function Get-AuditDisplaySid {
    <#
    .SYNOPSIS
        Die SIDs, die die Gruppenuebersicht anzeigt -- fuer die eine
        Namensaufloesung in der Orchestrierung (IDENT-06). Intern.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [hashtable] $Snapshot
    )

    $sids = New-Object System.Collections.Generic.List[string]

    foreach ($ziel in @($Target)) {
        if ($null -eq $ziel) { continue }
        foreach ($p in @(Get-AuditPrincipalRow -Target $ziel -Result $Result -Snapshot $Snapshot -Name @{})) {
            $sid = [string] $p.Sid
            if ($sid -notmatch '^S-\d') { continue }
            if (-not $sids.Contains($sid)) { $sids.Add($sid) }
        }
    }

    return [string[]] $sids.ToArray()
}
