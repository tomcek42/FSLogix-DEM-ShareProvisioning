<#
    Format-AdjustReport -- die Ausgabe von Weg 3: der Plan vor dem getippten
    JA. Die Zusammenfassung nach dem Schreiben ist die von Weg 1
    (Format-ProvisioningSummary); verglichen wird dort gegen den Plan, nicht
    gegen das Herstellersoll.

    Kein Ausgabe-Cmdlet: die Funktionen liefern Zeilensaetze, ausgegeben wird
    an einer Stelle (Write-OperatorLine).
#>

function Format-AdjustPlan {
    <#
    .SYNOPSIS
        Je Ordner die Differenz zwischen gelesenem und geplantem ACL, die
        Warnung fuer jede Pflichtrolle ohne Gruppe, dazu die Preflight-Befunde.

    .PARAMETER State
        Die Ziele mit Aenderungen (New-AdjustState nach Invoke-AdjustChange).

    .PARAMETER Name
        SID-Wert -> Anzeigename.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $State,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult = @(),

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $ueberschrift = Get-ReportUeberschrift
    $karte = Get-TokenRoleMap
    $zeilen = New-Object System.Collections.Generic.List[object]

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['AdjustPlan'])))

    for ($i = 0; $i -lt @($State).Count; $i++) {

        $ziel = @($State)[$i]

        if ($i -gt 0) { $zeilen.Add((New-OperatorTextLine -Text '')) }

        $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                        '  {0} -- {1}' -f [string] $ziel.Kind, [string] $ziel.Path))))

        # Eine Tabelle ueber vorher und nachher (Serverlauf 2026-09-25): "+"
        # neu (gruen), "~" ersetzt (gelb, der alte Eintrag rot durchgestrichen
        # in derselben Zelle), "-" entfernt (rot durchgestrichen), leer
        # unveraendert. Der Text traegt die Aussage auch ohne Farbe.
        $reihen = New-Object System.Collections.Generic.List[object]
        $stile = New-Object System.Collections.Generic.List[object]

        foreach ($aenderung in @(Get-AdjustRowChange -State $ziel)) {
            $reihe = Get-AdjustChangeRow -Change $aenderung -Name $Name
            $reihen.Add(@(@($reihe.Marker) + @($reihe.Cells)))
            $stile.Add($reihe.Style)
        }

        foreach ($zeile in @(Format-AdjustTable -Header @('', 'Prinzipal', 'Rechte', 'Gilt für') -Row $reihen.ToArray() -RowStyle $stile.ToArray() -Indent '    ')) {
            $zeilen.Add($zeile)
        }

        foreach ($eintrag in @(Get-AdjustMissingRole -State $ziel)) {
            $namen = @($eintrag.Split('|') | ForEach-Object { Get-TrusteeRoleLabel -Role $karte[$_] }) -join '" oder "'
            $zeilen.Add((New-OperatorTextLine -Severity 'Warning' -Text (ConvertTo-Einzeiler -Wert (
                            '    [WARNUNG] Für die Rolle "{0}" gibt es danach keine eigene Gruppe mehr -- die Ordnerart funktioniert so nicht wie vom Hersteller vorgesehen.' -f
                            $namen))))
        }
    }

    foreach ($zeile in @(Format-PreflightBefund -Target $State -PreflightResult $PreflightResult)) {
        $zeilen.Add($zeile)
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    return $zeilen.ToArray()
}

function Get-AdjustRuleCell {
    <#
    .SYNOPSIS
        Eine Regel als Tabellenzellen: Prinzipal, Rechte, Gilt fuer. Intern.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemAccessRule] $Rule,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $sid = [string] $Rule.IdentityReference.Value
    $anzeige = if ($Name.ContainsKey($sid)) { [string] $Name[$sid] } else { $sid }
    $gilt = (ConvertTo-AppliesTo -Inheritance $Rule.InheritanceFlags -Propagation $Rule.PropagationFlags).AppliesTo

    return [string[]] @($anzeige, (Get-AdjustRightsLabel -Rule $Rule), [string] $gilt)
}

function Get-AdjustChangeRow {
    <#
    .SYNOPSIS
        Eine Zeile der Vorher/Nachher-Tabelle aus Get-AdjustRowChange:
        Markierung, Zellen (Prinzipal mit farbigen Abschnitten, Rechte, Gilt
        fuer) und Zeilenstil. Intern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Change,

        [Parameter(Mandatory)]
        [hashtable] $Name
    )

    $zellen = @(Get-AdjustRuleCell -Rule $Change.Rule -Name $Name)
    $prinzipal = [string] $zellen[0]

    switch ([string] $Change.Change) {

        'Added' {
            $stil = New-AdjustRowStyle -Severity 'OK'
            $erste = New-AdjustCell -Segment @(
                (New-TextSegment -Text $prinzipal -Severity 'OK')
                (New-TextSegment -Text ' (neu)' -Severity 'OK'))
            $marke = '+'
        }

        'Replaced' {
            $alt = [string] @(Get-AdjustRuleCell -Rule $Change.Old -Name $Name)[0]
            $stil = New-AdjustRowStyle -Severity 'Warning'
            $erste = New-AdjustCell -Segment @(
                (New-TextSegment -Text $prinzipal -Severity 'Warning')
                (New-TextSegment -Text ' (vorher: ' -Severity 'Warning')
                (New-TextSegment -Text $alt -Severity 'Error' -Strike $true)
                (New-TextSegment -Text ')' -Severity 'Warning'))
            $marke = '~'
        }

        'Removed' {
            $stil = New-AdjustRowStyle -Severity 'Error' -Strike $true
            $erste = New-AdjustCell -Segment @(
                (New-TextSegment -Text $prinzipal -Severity 'Error' -Strike $true)
                (New-TextSegment -Text ' (entfernt)' -Severity 'Error'))
            $marke = '-'
        }

        default {
            $stil = New-AdjustRowStyle -Severity 'None'
            $erste = $prinzipal
            $marke = ''
        }
    }

    return [pscustomobject] @{
        Marker = $marke
        Cells  = @($erste, [string] $zellen[1], [string] $zellen[2])
        Style  = $stil
    }
}

function New-TextSegment {
    <#
    .SYNOPSIS
        Ein farbiger Abschnitt einer Zeile: Text, Severity, Strike. Intern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [ValidateSet('OK', 'Warning', 'Error', 'None', 'Heading')]
        [string] $Severity = 'None',

        [Parameter()]
        [bool] $Strike = $false
    )

    return [pscustomobject] @{ Text = $Text; Severity = $Severity; Strike = $Strike }
}

function New-AdjustCell {
    <#
    .SYNOPSIS
        Eine Tabellenzelle aus mehreren Abschnitten. Intern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object[]] $Segment
    )

    return [pscustomobject] @{ Segments = @($Segment) }
}

function New-AdjustRowStyle {
    <#
    .SYNOPSIS
        Der Stil einer Tabellenzeile fuer ihre schlichten Zellen. Intern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateSet('OK', 'Warning', 'Error', 'None')]
        [string] $Severity = 'None',

        [Parameter()]
        [bool] $Strike = $false
    )

    return [pscustomobject] @{ Severity = $Severity; Strike = $Strike }
}

function Get-AdjustCellSegment {
    <#
    .SYNOPSIS
        Die Abschnitte einer Zelle: ihre eigenen, oder ihr Text im Zeilenstil.
        Intern zu Format-AdjustTable.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Cell,

        [Parameter()]
        [AllowNull()]
        [object] $Style = $null
    )

    if (($null -ne $Cell) -and ($Cell -isnot [string]) -and ($null -ne $Cell.PSObject.Properties['Segments'])) {
        return @($Cell.Segments)
    }

    $schwere = 'None'
    $durch = $false
    if ($null -ne $Style) {
        $schwere = [string] $Style.Severity
        $durch = [bool] $Style.Strike
    }

    return @(New-TextSegment -Text ([string] $Cell) -Severity $schwere -Strike $durch)
}

function Format-AdjustTable {
    <#
    .SYNOPSIS
        Setzt Zeilen als gerahmte Tabelle: Kopf mittig, Trennlinie zwischen
        allen Zeilen, jede Spalte so breit wie ihr laengster Eintrag.

    .DESCRIPTION
        Die Rahmenzeichen stehen als Zeichencodes: die Quelle bleibt damit
        lesbar, und ConvertTo-KonsolenText ersetzt sie durch + - |, wo die
        Konsole sie nicht darstellen kann. Datenzeile k steht in der
        Rueckgabe an Stelle 3 + 2k.

        Eine Zelle ist Text oder ein Datensatz mit Segments (New-AdjustCell).
        RowStyle gibt je Zeile Farbe und Durchstreichung der schlichten Zellen
        vor. Jede Zeile kommt als Zeilensatz (Text, Severity, Segments): Text
        ist die Zeile ohne Farbe, Segments dieselbe Zeile in Abschnitten --
        die Spaltenbreite richtet sich nach dem Text, so bleibt der Rahmen mit
        und ohne Farbe gerade (Serverlauf 2026-09-25).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]] $Header,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Row,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $RowStyle = @(),

        [Parameter()]
        [string] $Indent = ''
    )

    $z = @{
        H = [string] [char] 0x2500; V = [string] [char] 0x2502
        OL = [string] [char] 0x250C; OM = [string] [char] 0x252C; OR = [string] [char] 0x2510
        ML = [string] [char] 0x251C; MM = [string] [char] 0x253C; MR = [string] [char] 0x2524
        UL = [string] [char] 0x2514; UM = [string] [char] 0x2534; UR = [string] [char] 0x2518
    }

    # Je Zeile und Zelle die Abschnitte; die Breite ist die Laenge ihres Textes.
    $abschnitte = New-Object System.Collections.Generic.List[object]
    $breite = @($Header | ForEach-Object { $_.Length })

    for ($k = 0; $k -lt @($Row).Count; $k++) {

        $reihe = @($Row)[$k]
        $stil = $null
        if ($k -lt @($RowStyle).Count) { $stil = @($RowStyle)[$k] }

        $zellen = New-Object System.Collections.Generic.List[object]

        for ($i = 0; $i -lt $Header.Count; $i++) {
            $teile = @(Get-AdjustCellSegment -Cell (@($reihe)[$i]) -Style $stil)
            $laenge = 0
            foreach ($t in $teile) { $laenge += ([string] $t.Text).Length }
            if ($laenge -gt $breite[$i]) { $breite[$i] = $laenge }
            $zellen.Add([object[]] $teile)
        }

        $abschnitte.Add($zellen)
    }

    $linie = {
        param($Links, $Mitte, $Rechts)
        $text = $Indent + $Links + (@($breite | ForEach-Object { $z.H * ($_ + 2) }) -join $Mitte) + $Rechts
        [pscustomobject] @{ Text = $text; Severity = 'None'; Segments = $null }
    }

    $kopf = for ($i = 0; $i -lt $Header.Count; $i++) {
        $text = [string] $Header[$i]
        $links = [int] [System.Math]::Floor(($breite[$i] - $text.Length) / 2)
        ' ' + (''.PadLeft($links) + $text).PadRight($breite[$i]) + ' '
    }

    $zeilen = New-Object System.Collections.Generic.List[object]
    $zeilen.Add((& $linie $z.OL $z.OM $z.OR))
    $zeilen.Add([pscustomobject] @{ Text = ($Indent + $z.V + (@($kopf) -join $z.V) + $z.V); Severity = 'None'; Segments = $null })

    foreach ($zellen in $abschnitte) {

        $zeilen.Add((& $linie $z.ML $z.MM $z.MR))

        $teile = New-Object System.Collections.Generic.List[object]
        $teile.Add((New-TextSegment -Text ($Indent + $z.V)))

        for ($i = 0; $i -lt $Header.Count; $i++) {
            $teile.Add((New-TextSegment -Text ' '))
            $laenge = 0
            foreach ($t in @($zellen[$i])) { $teile.Add($t); $laenge += ([string] $t.Text).Length }
            $teile.Add((New-TextSegment -Text ((''.PadRight($breite[$i] - $laenge)) + ' ')))
            $teile.Add((New-TextSegment -Text $z.V))
        }

        $text = -join @($teile | ForEach-Object { [string] $_.Text })
        $zeilen.Add([pscustomobject] @{ Text = $text; Severity = 'None'; Segments = $teile.ToArray() })
    }

    $zeilen.Add((& $linie $z.UL $z.UM $z.UR))

    return $zeilen.ToArray()
}
