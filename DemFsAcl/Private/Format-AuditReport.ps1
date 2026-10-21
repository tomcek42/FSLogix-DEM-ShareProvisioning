<#
    Format-AuditReport -- der Bericht der Bestandspruefung (AUDIT-06, D-16,
    D-17, D-18).

    DIESE DATEI DRUCKT NICHT. Sie liefert Zeilensaetze (New-OperatorTextLine);
    ausgegeben wird ausschliesslich ueber Write-OperatorLine (OUT-07). Eine
    Berichtsdatei entsteht nicht (D-18).

    OBEN DIE TABELLE, DARUNTER DIE BEFUNDE (D-16). Die Tabelle ist gerahmt
    wie in Weg 3 (Format-AdjustTable, Serverlauf 2026-09-25); D-16 verlangt
    ausdruecklich eine Tabelle und geht damit OUT-04 Regel 4 vor
    (Planerentscheid 5 aus 05-01). Die Befunde darunter entstehen ueber
    Format-ProvisioningSummary und halten alle fuenf Luftigkeitsregeln; die
    Zuordnung Satz -> Ziel laeuft dort ueber Ordnerart UND Pfad
    (Get-TargetResult, G-04-1a).
#>

function Format-AuditReport {
    <#
    .SYNOPSIS
        Der Pruefbericht als Zeilensaetze: Tabelle, Befunde nur fuer
        abweichende Ziele, Gesamtzustand.

    .PARAMETER Target
        Die geprueften Ziele, jeweils mit Kind, Path, RelativePath, ShareName
        und Binding.

    .PARAMETER Result
        Die gesamte Ergebnissammlung des Pruefwegs.

    .PARAMETER Owner
        Pfad -> Besitzer (Name, Expected) aus Get-AuditOwnerTable; ohne ihn
        zeigt die Tabelle die Marke der Stufe Owner.

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
        [hashtable] $Owner = $null
    )

    $ueberschrift = Get-ReportUeberschrift
    $zeilen = New-Object System.Collections.Generic.List[object]
    $ziele = @(@($Target) | Where-Object { $null -ne $_ })
    $saetze = @(@($Result) | Where-Object { $null -ne $_ })

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['AuditTable'])))

    if ($ziele.Count -eq 0) {
        $zeilen.Add((New-OperatorTextLine -Text '  Es wurde kein Ordner geprüft.'))
    }
    else {
        foreach ($zeile in @(Format-AuditTable -Target $ziele -Result $saetze -Owner $Owner)) { $zeilen.Add($zeile) }
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    # Die Tabelle traegt das Ergebnis; darunter steht nur, was vom Soll
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
