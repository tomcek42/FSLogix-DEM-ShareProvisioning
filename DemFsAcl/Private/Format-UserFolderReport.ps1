<#
    Format-UserFolderReport -- die Zeilensaetze des Benutzerordner-Berichts
    (Phase 8, USR-05, USR-08).

    DIESE DATEI DRUCKT NICHT. Sie liefert Zeilensaetze (New-OperatorTextLine);
    ausgegeben wird ausschliesslich ueber Write-OperatorLine (OUT-07).

    JE ABLAGE EINE STATUSZEILE MIT FUENF ZAHLEN, darunter die geduldeten
    Verwaltungseintraege je Konto und eine gerahmte Tabelle nur mit den
    auffaelligen und nicht lesbaren Ordnern. Die Tabelle geht OUT-04 Regel 4
    vor wie beim Pruefbericht (D-16); ausserhalb der Tabelle gelten alle fuenf
    Luftigkeitsregeln. Eine Zeilenobergrenze gibt es nicht -- die Mitschrift
    ist der Beleg.

    NAMEN NUR ZUR ANZEIGE (IDENT-06). Sie kommen als Tabelle SID -> Name
    herein; fehlt eine SID darin, steht die SID selbst da. Der Formatierer
    fragt die Maschine nie (OUT-06).
#>

function Format-UserFolderReport {
    <#
    .SYNOPSIS
        Der Benutzerordner-Bericht als Zeilensaetze: Ueberschrift, je Ablage
        Zahlen, geduldete Konten und Tabelle.

    .PARAMETER Report
        Die Ablageberichte aus Test-UserFolderSet, in Zielreihenfolge.

    .PARAMETER Name
        SID -> Anzeigename fuer Besitzer, fremde und geduldete Konten.

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Report,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Name = $null
    )

    $zeilen = New-Object System.Collections.Generic.List[object]

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Text ([string] (Get-ReportUeberschrift)['UserFolder'])))

    $erste = $true

    foreach ($bericht in @($Report)) {

        if ($null -eq $bericht) { continue }

        if (-not $erste) { $zeilen.Add((New-OperatorTextLine -Text '')) }
        $erste = $false

        $art = [string] $bericht.Kind
        $pfad = [string] $bericht.Path

        if (-not [string]::IsNullOrEmpty([string] $bericht.ListError)) {
            $text = '  {0} {1} "{2}": die Ablage lässt sich nicht auflisten: {3}' -f (Get-StatusMarkierung -Status 'Error'), $art, $pfad, [string] $bericht.ListError
            $zeilen.Add((New-OperatorTextLine -Text $text -Severity 'Error'))
            continue
        }

        $zahl = Get-UserFolderCount -Report $bericht
        $auffaellig = [int] $zahl.Finding + [int] $zahl.Unreadable

        $status = 'OK'
        if ($auffaellig -gt 0) { $status = 'Error' }

        $text = '  {0} {1} "{2}": {3} geprüft, {4} unauffällig, {5} auffällig, {6} nicht zuordenbar, {7} nicht lesbar' -f
            (Get-StatusMarkierung -Status $status), $art, $pfad,
            [int] $zahl.Checked, [int] $zahl.Clean, [int] $zahl.Finding, [int] $zahl.Unassigned, [int] $zahl.Unreadable
        $zeilen.Add((New-OperatorTextLine -Text $text -Severity (Get-LineSeverity -Status $status)))

        # Je Konto die Zahl der Ordner -- nie eine Gesamtzahl (Entscheidung
        # Projektinhaber 2026-09-29).
        $konten = @($zahl.ToleratedAccount)
        if ($konten.Count -gt 0) {
            $teile = New-Object System.Collections.Generic.List[string]
            foreach ($konto in $konten) {
                $sid = [string] $konto.Sid
                $anzeige = $sid
                if (($null -ne $Name) -and $Name.ContainsKey($sid)) { $anzeige = [string] $Name[$sid] }
                $teile.Add(('{0}: {1}' -f $anzeige, [int] $konto.Count))
            }
            $zeilen.Add((New-OperatorTextLine -Text ('    Geduldete Verwaltungseinträge (kein Befund): {0}' -f ($teile.ToArray() -join ', '))))
        }

        if ([int] $zahl.Checked -eq 0) {
            $zeilen.Add((New-OperatorTextLine -Text '    Keine Benutzerordner gefunden.'))
            continue
        }

        if ($auffaellig -eq 0) {
            $zeilen.Add((New-OperatorTextLine -Text '    Kein Ordner auffällig.' -Severity 'OK'))
            continue
        }

        $reihen = New-Object System.Collections.Generic.List[object]
        $fussnote = $false

        foreach ($ordner in @($bericht.Folder)) {

            if ($null -eq $ordner) { continue }

            $zustand = [string] $ordner.State
            if (-not ([string]::Equals($zustand, 'Finding', [System.StringComparison]::Ordinal) -or
                    [string]::Equals($zustand, 'Unreadable', [System.StringComparison]::Ordinal))) { continue }

            if (@($ordner.Finding) -ccontains 'InheritanceDisabled') { $fussnote = $true }

            $zellen = New-Object System.Collections.Generic.List[object]
            $zellen.Add((Get-AuditOrdnerZelle -Target ([pscustomobject] @{ RelativePath = [string] $ordner.Name; Path = [string] $ordner.Path })))
            $zellen.Add([string] $ordner.UserLabel)
            $zellen.Add((New-AdjustCell -Segment @((New-TextSegment -Text (Get-UserFolderFindingCell -Folder $ordner -Name $Name) -Severity 'Error'))))
            $reihen.Add($zellen.ToArray())
        }

        foreach ($zeile in @(Format-AdjustTable -Header @('Ordner', 'Nutzer', 'Befundarten') -Row $reihen.ToArray() -Indent '    ')) {
            $zeilen.Add($zeile)
        }

        if ($fussnote) {
            $zeilen.Add((New-OperatorTextLine -Text '    * Vererbung abgeschaltet: die Rechte der Wurzel kommen im Ordner nicht an.'))
            $zeilen.Add((New-OperatorTextLine -Text '      Gewollt ist das nur, wenn FSLogix die Ordner über die Einstellung SIDDirSDDL anlegt.'))
        }
    }

    return $zeilen.ToArray()
}

function Get-UserFolderFindingCell {
    <#
    .SYNOPSIS
        Der Text der Befundzelle eines Ordners: Besitzer, Vererbung, erster
        fremder Eintrag mit der Zahl weiterer. Intern.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Folder,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Name = $null
    )

    if ([string]::Equals([string] $Folder.State, 'Unreadable', [System.StringComparison]::Ordinal)) { return 'nicht lesbar' }

    $befunde = @($Folder.Finding)
    $teile = New-Object System.Collections.Generic.List[string]

    if ($befunde -ccontains 'Owner') {
        $sid = [string] $Folder.OwnerSid
        $anzeige = $sid
        if ([string]::IsNullOrEmpty($sid)) { $anzeige = '(nicht gelesen)' }
        elseif (($null -ne $Name) -and $Name.ContainsKey($sid)) { $anzeige = [string] $Name[$sid] }
        $teile.Add(('Besitzer {0}' -f $anzeige))
    }

    if ($befunde -ccontains 'InheritanceDisabled') { $teile.Add('Vererbung abgeschaltet *') }

    if ($befunde -ccontains 'ForeignAce') {
        $fremd = @($Folder.ForeignSid)
        if ($fremd.Count -gt 0) {
            $sid = [string] $fremd[0]
            $anzeige = $sid
            if (($null -ne $Name) -and $Name.ContainsKey($sid)) { $anzeige = [string] $Name[$sid] }
            $teil = 'fremder Eintrag {0}' -f $anzeige
            if ($fremd.Count -gt 1) { $teil += (' +{0}' -f ($fremd.Count - 1)) }
            $teile.Add($teil)
        }
    }

    return ($teile.ToArray() -join ', ')
}
