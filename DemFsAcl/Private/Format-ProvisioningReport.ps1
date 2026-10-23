<#
    Format-ProvisioningReport -- die Formatierer (OUT-01 bis OUT-07, D-09,
    D-14, D-16).

    DIESE DATEI DRUCKT NICHT. Sie liefert Zeilensaetze mit den Feldern Text und
    Severity; ausgegeben wird ausschliesslich ueber Write-OperatorLine. Der
    Zeilensatz ist der Vertrag zwischen Formatierer und Ausgabe -- hier
    entsteht kein Text, der nicht aus einem Ergebnisobjekt oder einem
    erhobenen Ziel stammt (OUT-06).

    TEXTMARKIERUNG IST DIE GRUNDFORM (D-14). [OK], [WARNUNG] und [FEHLER]
    stehen immer im Text; Severity traegt ausschliesslich die Farbinformation.
    Ein Ergebnis, das nur an der Farbe erkennbar waere, verschwindet in jeder
    umgeleiteten Ausgabe.

    DER PLAN ZEIGT KOMPAKT, WAS BESTAETIGT WIRD (OUT-02 v1.3, loest D-09 v1.0
    ab): eine gerahmte Tabelle mit je Ziel Ordnerart, vollem Pfad, Freigabe
    und Anlage (neu oder Bestand), darunter "Gruppen" mit Anzeigenamen und
    "Optionen" je Ziel. Kompakt heisst ohne SIDs, ACE-Anzahl und Belege, nicht
    ohne Gegenstand der Bestaetigung. SIDs, ACE-Anzahl und Belege stehen im
    Detailbericht (Format-RunDetailReport, hinter [R] der Abschlussfrage) und
    in der Rueckspiegelung von Schritt 2 (ERF-03).

    LUFTIGKEIT IST HIER EINE REGEL UND KEIN GESCHMACK (OUT-04). Fuenf Zusagen,
    alle ueber das Feld Text entscheidbar und alle in Tests/Report.Tests.ps1
    nachgehalten:
      1. Genau eine Leerzeile zwischen zwei Zielbloecken, nie zwei.
      2. Eine Leerzeile VOR jeder Abschnittsueberschrift, keine danach.
      3. Einzug ueber Leerzeichen in den Stufen 0, 2, 4 und 6; kein Tabulator.
      4. Keine Spaltenausrichtung -- hinter dem Einzug steht nie ein Lauf aus
         zwei oder mehr Leerzeichen. Spaltenbreiten ueber Pfade und
         Gruppennamen zu rechnen, deren Laenge die Umgebung bestimmt, bricht in
         einer schmalen Konsole mitten im Wort.
      5. Die Statuszeile je Ziel ist EINE Zeile; alles Weitere steht
         eingerueckt darunter.

    DER EINZUG ENTSTEHT IM TEXT UND NIE IN DER AUSGABESTELLE. Write-OperatorLine
    rueckt nichts ein -- sonst stuende die Luftigkeit in einer Schicht, die der
    Test gar nicht sieht.
#>

function New-OperatorTextLine {
    <#
    .SYNOPSIS
        Baut einen Zeilensatz. Die Form, die Write-OperatorLine entgegennimmt.

    .DESCRIPTION
        Severity steuert ausschliesslich die Farbe. Die Textmarkierung steht
        bereits im Text -- deshalb ist eine Zeile ohne Farbe vollstaendig.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [ValidateSet('OK', 'Warning', 'Error', 'None', 'Heading')]
        [string] $Severity = 'None'
    )

    return [pscustomobject] @{ Text = $Text; Severity = $Severity }
}

function Get-ReportUeberschrift {
    <#
    .SYNOPSIS
        Die vier Abschnittsueberschriften der Ausgabe an genau einer Stelle.

    .DESCRIPTION
        OUT-04 verlangt vor jeder Abschnittsueberschrift eine Leerzeile und
        dahinter eine nicht leere. Der Test haelt das nach und braucht dafuer
        die Textwerte -- also stehen sie hier einmal und nicht viermal im Code
        verstreut. Zwei Kopien derselben Ueberschrift drifteten auseinander,
        und dann pruefte der Test eine Ueberschrift, die es nicht mehr gibt.

    .OUTPUTS
        [hashtable] Schluessel -> Ueberschriftstext.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Plan          = 'Plan -- das wird geschrieben:'
        Preflight     = 'Preflight -- Befunde vor dem Schreiben:'
        Summary       = 'Zusammenfassung:'
        Footnote      = 'Hinweis, falls Profile später mit einem Zugriffsfehler scheitern:'

        # Phase 5 -- der Bericht der Bestandspruefung (D-16, D-17).
        AuditTable    = 'Prüfbericht -- ein Ziel je Zeile:'
        AuditGroupTable = 'Berechtigte Prinzipale je Ablage:'
        AuditBlock    = 'Prüfbericht -- ein Block je Ablage:'
        AuditDetail   = 'Befunde je Ziel:'

        AdjustPlan    = 'Plan -- diese Änderungen werden geschrieben:'

        # Phase 7 -- der UNC-Hinweis zu RedirXMLSourceFolder (RDX-06).
        Redirections  = 'Hinweis für die FSLogix-Konfiguration:'

        # Phase 8 -- der Benutzerordner-Bericht (USR-08).
        UserFolder    = 'Benutzerordner -- erste Ebene unter den Profilablagen:'

        # v1.3 -- der Detailbericht hinter [R] (OUT-03 v1.3, D-01).
        Detail        = 'Detailbericht -- je Ziel:'
    }
}

function Format-ProvisioningPlan {
    <#
    .SYNOPSIS
        OUT-02 (v1.3), D-10: der kompakte Plan und die Preflight-Befunde in
        EINEM Bild, vor der Bestaetigung.

    .DESCRIPTION
        Eine gerahmte Tabelle mit je Ziel genau einer Zeile -- Ordnerart,
        voller Pfad, Freigabe, Anlage --, darunter "Gruppen" als Tabelle
        Produkt, Rolle, Gruppe (Format-PlanGroupTable) und "Optionen" mit einer
        Zeile je Ziel. Danach die Preflight-Befunde samt Tabelle nach
        Ordnerart (OUT-01 v1.3).

        OUT-02 (v1.3) LOEST D-09 (v1.0) AB: SIDs, ACE-Anzahl und Belege stehen
        nicht mehr vor dem JA, sondern im Detailbericht hinter [R]
        (Format-RunDetailReport) und in der Rueckspiegelung von Schritt 2.
        Der Pfad wird nie gekuerzt -- er ist Gegenstand der Bestaetigung.

    .PARAMETER Target
        Die erhobenen Ziele, jeweils mit Desired.

    .PARAMETER PreflightResult
        Die Befundsammlung aus Test-ProvisioningPreflight, einmal ueber alle
        Ziele erhoben (D-06).

    .PARAMETER Group
        Die erhobenen Gruppenrollen als Tabelle Rolle -> Datensatz mit Sid und
        DisplayName. Damit erscheint der Anzeigename, ohne dass die Formatierung
        ihn ein zweites Mal aufloest -- IDENT-06 loest jede Gruppe genau einmal
        auf, und eine zweite Aufloesung waere eine zweite Wahrheit ueber
        denselben Prinzipal.

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult = @(),

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null
    )

    $ueberschrift = Get-ReportUeberschrift
    $zeilen = New-Object System.Collections.Generic.List[object]
    $ziele = @(@($Target) | Where-Object { $null -ne $_ })

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['Plan'])))

    if ($ziele.Count -eq 0) {
        # Eine Ueberschrift ohne Inhalt verletzte OUT-04 Regel 2 und saehe
        # ausserdem wie ein Darstellungsfehler aus.
        $zeilen.Add((New-OperatorTextLine -Text '  Es wurde keine Ordnerart gewählt.'))
    }

    if ($ziele.Count -gt 0) {

        # Je Ziel genau eine Tabellenzeile. Der Pfad steht UNGEKUERZT -- er ist
        # Gegenstand der Bestaetigung (OUT-02 v1.3); gekuerzt wird nur in der
        # Ergebnistabelle nach dem Lauf.
        $reihen = New-Object System.Collections.Generic.List[object]

        foreach ($ziel in $ziele) {

            $freigabe = [string] $ziel.ShareName
            if ([string]::IsNullOrWhiteSpace($freigabe)) { $freigabe = '--' }

            $anlage = if ([bool] $ziel.IsExisting) { 'Bestand' } else { 'neu' }

            $reihen.Add([string[]] @([string] $ziel.Kind, [string] $ziel.Path, $freigabe, $anlage))
        }

        foreach ($zeile in @(Format-AdjustTable -Header @('Ordnerart', 'Pfad', 'Freigabe', 'Anlage') -Row $reihen.ToArray() -Indent '  ')) {
            $zeilen.Add($zeile)
        }

        $zeilen.Add((New-OperatorTextLine -Text ''))
        $zeilen.Add((New-OperatorTextLine -Text '  Gruppen:'))

        foreach ($zeile in @(Format-PlanGroupTable -Target $ziele -Group $Group)) {
            $zeilen.Add($zeile)
        }

        $zeilen.Add((New-OperatorTextLine -Text ''))
        $zeilen.Add((New-OperatorTextLine -Text '  Optionen:'))

        foreach ($ziel in $ziele) {

            $optAcl = @(@($ziel.AclOptGroup) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) })
            $optShare = @(@($ziel.ShareOptGroup) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) })

            $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                            '    {0}: ACL {1}; Freigabe {2}' -f
                            (Get-ZielBezeichnung -Target $ziel -Alle $ziele),
                            (Format-Aufzaehlung -Wert $optAcl), (Format-Aufzaehlung -Wert $optShare)))))
        }
    }

    foreach ($zeile in @(Format-PreflightBefund -Target $ziele -PreflightResult $PreflightResult)) {
        $zeilen.Add($zeile)
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    return $zeilen.ToArray()
}

function Get-ZielBezeichnung {
    <#
    .SYNOPSIS
        Die Ordnerart eines Ziels als Beschriftung -- mit Pfad, wenn die
        Ordnerart im Lauf mehrfach vorkommt (Weg 2 und 3). Intern zu den
        Formatierern.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Alle
    )

    $art = [string] $Target.Kind
    $zahl = @(@($Alle) | Where-Object { ($null -ne $_) -and ([string] $_.Kind -ceq $art) }).Count

    if ($zahl -gt 1) { return ('{0} ({1})' -f $art, [string] $Target.Path) }

    return $art
}

function Format-PlanGroupTable {
    <#
    .SYNOPSIS
        OUT-02 (v1.3): die gebundenen Gruppen des Plans als gerahmte Tabelle
        Produkt, Rolle, Gruppe. Intern zu Format-ProvisioningPlan.

    .DESCRIPTION
        Je Produkt in der Folge FSLogix, DEM und je Rolle in der Folge
        Gruppe der Administratoren, Benutzergruppe, Computergruppe,
        Helpdesk-Gruppe eine Zeile je verschiedener gebundener SID. Die Gruppe
        steht mit ihrem Anzeigenamen aus dem Rollenspeicher, ohne erhobenen
        Namen als SID -- derselbe Rueckfall wie Format-GruppenText. Ein Token
        ausserhalb der Rollenkarte erscheint mit dem Token als Rolle:
        verworfen wird nichts, was bestaetigt wird.

        Mit DEMProfiles im Lauf und ohne gebundene Helpdesk-Gruppe steht die
        Zeile "nicht gesetzt" -- dieselbe Aussage wie in der Gruppenuebersicht
        des Dialogs.

        Keine SID einer Gruppe mit erhobenem Namen und keine Aufloesung: die
        SID steht im Detailbericht hinter [R] und in der Rueckspiegelung von
        Schritt 2 (IDENT-06).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null
    )

    $ziele = @(@($Target) | Where-Object { $null -ne $_ })
    $karte = Get-SidAnzeigeKarte -Group $Group
    $rollen = Get-TokenRoleMap
    $reihen = New-Object System.Collections.Generic.List[object]

    foreach ($produkt in @('FSLogix', 'DEM')) {

        $eigene = @($ziele | Where-Object { (Get-KindProduct -Kind ([string] $_.Kind)) -ceq $produkt })
        if ($eigene.Count -eq 0) { continue }

        # Token -> verschiedene SIDs in der Reihenfolge ihres ersten Auftretens.
        $tokenSids = @{}

        foreach ($ziel in $eigene) {

            $bindung = $null
            if ($null -ne $ziel.PSObject.Properties['Binding']) { $bindung = $ziel.Binding }
            if ($bindung -isnot [hashtable]) { continue }

            foreach ($token in (@($bindung.Keys) | Sort-Object)) {

                # Weg 3 bindet je Schluessel auch mehrere Gruppen (Get-AdjustBinding).
                foreach ($wert in @($bindung[$token])) {

                    if ($null -eq $wert) { continue }

                    $sid = if ($wert -is [System.Security.Principal.SecurityIdentifier]) { [string] $wert.Value } else { [string] $wert }
                    if ([string]::IsNullOrEmpty($sid)) { continue }

                    if (-not $tokenSids.ContainsKey($token)) { $tokenSids[$token] = New-Object System.Collections.Generic.List[string] }
                    if (-not $tokenSids[$token].Contains($sid)) { $tokenSids[$token].Add($sid) }
                }
            }
        }

        $folge = New-Object System.Collections.Generic.List[string]

        foreach ($rolle in @('Admin', 'User', 'Computer', 'Helpdesk')) {
            foreach ($token in (@($tokenSids.Keys) | Sort-Object)) {
                if ($rollen.ContainsKey($token) -and ([string] $rollen[$token] -ceq $rolle)) { $folge.Add([string] $token) }
            }
        }

        foreach ($token in (@($tokenSids.Keys) | Sort-Object)) {
            if (-not $rollen.ContainsKey($token)) { $folge.Add([string] $token) }
        }

        foreach ($token in $folge) {

            $beschriftung = if ($rollen.ContainsKey($token)) { Get-TrusteeRoleLabel -Role ([string] $rollen[$token]) } else { $token }

            foreach ($sid in $tokenSids[$token]) {

                $name = ''
                if ($karte.ContainsKey($sid)) { $name = [string] $karte[$sid] }
                if ([string]::IsNullOrEmpty($name)) { $name = $sid }

                $reihen.Add([string[]] @($produkt, $beschriftung, $name))
            }
        }

        if ($produkt -ceq 'DEM') {

            $mitProfil = @($eigene | Where-Object { [string] $_.Kind -ceq 'DEMProfiles' }).Count -gt 0
            $helpdesk = @($tokenSids.Keys | Where-Object { $rollen.ContainsKey($_) -and ([string] $rollen[$_] -ceq 'Helpdesk') }).Count -gt 0

            if ($mitProfil -and -not $helpdesk) {
                $reihen.Add([string[]] @('DEM', (Get-TrusteeRoleLabel -Role 'Helpdesk'), 'nicht gesetzt'))
            }
        }
    }

    if ($reihen.Count -eq 0) { return @(New-OperatorTextLine -Text '    (keine)') }

    return @(Format-AdjustTable -Header @('Produkt', 'Rolle', 'Gruppe') -Row $reihen.ToArray() -Indent '  ')
}

function Format-BindingLine {
    <#
    .SYNOPSIS
        Je gebundenem Token eine Zeile mit Anzeigename und SID. Intern zu
        Format-ProvisioningPlan.

    .DESCRIPTION
        DIE SID STEHT IMMER DA, der Anzeigename nur, wenn er erhoben wurde.
        Das ist die Richtung, die IDENT-06 vorgibt: zurueckgespiegelt wird
        beides, massgeblich ist die SID.

        KEINE SPALTENAUSRICHTUNG (OUT-04 Regel 4): der Token wird nicht auf eine
        feste Breite aufgefuellt. Tokenlaenge und Gruppennamenlaenge bestimmt die
        Umgebung, und eine Auffuellung erzeugte in einer schmalen Konsole
        Umbrueche mitten im Wort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [hashtable] $Binding,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null
    )

    $zeilen = New-Object System.Collections.Generic.List[object]

    if ($null -eq $Binding) { return $zeilen.ToArray() }

    $anzeige = @{}

    if ($null -ne $Group) {
        foreach ($rolle in @($Group.Keys)) {
            $satz = $Group[$rolle]
            if ($null -eq $satz) { continue }
            if ($null -eq $satz.PSObject.Properties['Sid']) { continue }
            $schluessel = [string] $satz.Sid.Value
            if ([string]::IsNullOrEmpty($schluessel)) { continue }
            if ($anzeige.ContainsKey($schluessel)) { continue }
            $anzeige[$schluessel] = [string] $satz.DisplayName
        }
    }

    foreach ($token in (@($Binding.Keys) | Sort-Object)) {

        # Weg 3 bindet je Schluessel auch mehrere Gruppen (Get-AdjustBinding).
        foreach ($wert in @($Binding[$token])) {

            if ($null -eq $wert) { continue }

            $sid = [string] $wert.Value
            $name = ''
            if ($anzeige.ContainsKey($sid)) { $name = [string] $anzeige[$sid] }

            if ([string]::IsNullOrEmpty($name)) {
                $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                                '  Gruppe {0}: SID {1}' -f $token, $sid))))
            }
            else {
                $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                                '  Gruppe {0}: {1} (SID {2})' -f $token, $name, $sid))))
            }
        }
    }

    return $zeilen.ToArray()
}

function Get-SidAnzeigeKarte {
    <#
    .SYNOPSIS
        SID-Wert -> Anzeigename aus dem Rollenspeicher. Intern zu den
        Formatierern.

    .DESCRIPTION
        Dieselbe Regel wie die lokale Karte in Format-BindingLine: der erste
        Datensatz je SID gilt, Datensaetze ohne SID werden uebersprungen. Der
        Name stammt aus der einen Aufloesung bei der Erhebung (IDENT-06) --
        hier wird nichts aufgeloest.

    .OUTPUTS
        [hashtable] SID-Wert -> Anzeigename (moeglicherweise leer).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null
    )

    $anzeige = @{}

    if ($null -eq $Group) { return $anzeige }

    foreach ($rolle in @($Group.Keys)) {
        $satz = $Group[$rolle]
        if ($null -eq $satz) { continue }
        if ($null -eq $satz.PSObject.Properties['Sid']) { continue }
        if ($null -eq $satz.Sid) { continue }
        $schluessel = [string] $satz.Sid.Value
        if ([string]::IsNullOrEmpty($schluessel)) { continue }
        if ($anzeige.ContainsKey($schluessel)) { continue }
        $name = ''
        if ($null -ne $satz.PSObject.Properties['DisplayName']) { $name = [string] $satz.DisplayName }
        $anzeige[$schluessel] = $name
    }

    return $anzeige
}

function Format-RunDetailReport {
    <#
    .SYNOPSIS
        OUT-03 (v1.3), D-01: der Detailbericht hinter [R] -- je Ziel des
        letzten Durchlaufs Ordnerart, Pfad, Freigabe, die gebundenen Gruppen
        mit SID, die Zahl der Soll-Eintraege und je Eintrag Anzeige, SID,
        Rechte und "Gilt fuer".

    .DESCRIPTION
        [R] IST DER DETAILMODUS (D-01). Was der kompakte Plan vor dem JA
        weglaesst -- SIDs, ACE-Anzahl, Herstellerbelege (OUT-02 v1.3) --,
        steht hier an genau einer Stelle.

        KEINE AUFLOESUNG, KEIN LESEN, KEIN SCHREIBEN (IDENT-06). Der Bericht
        entsteht nur aus dem Feld Target des Durchlaufs (samt gebundenem Soll
        Desired) und dem Rollenspeicher. Eine zweite Aufloesung waere eine
        zweite Wahrheit ueber denselben Prinzipal; ein nachgelesenes ACL
        gehoert in die Bestandspruefung, nicht in eine Anzeige.

        BELEGE NUR UEBER Test-MitBeleg. Das Einzeldatei-Buendel entfernt die
        Belegschluessel nach Namen und setzt $script:MitBelegen = $false; dann
        entfallen die Belegzeilen, alle uebrigen Zeilen bleiben zeichengleich.
        Aus demselben Grund fuehrt der Bericht kein eigenes Feld mit einem der
        Namen Status, Source oder Section -- das Buendel entfernte es still.

        Ein Soll ohne Provenienz (Weg 3, ConvertTo-AdjustDesired) ist ein
        eigener Plan und kein Herstellertemplate; im Modullauf steht dafuer
        eine Hinweiszeile statt leerer Belege.

        Einzug in den Stufen 0, 2, 4 und 6; jede Zeile mit Datenanteil laeuft
        durch ConvertTo-Einzeiler.

    .PARAMETER Target
        Die Ziele des Durchlaufs, jeweils mit Kind, Path, ShareName, Binding
        und -- wo gebunden -- Desired.

    .PARAMETER Group
        Die flache Anzeigetabelle aus Get-TrusteeRoleStore (ohne -Product).

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null
    )

    $ueberschrift = Get-ReportUeberschrift
    $zeilen = New-Object System.Collections.Generic.List[object]
    $ziele = @(@($Target) | Where-Object { $null -ne $_ })
    $karte = Get-SidAnzeigeKarte -Group $Group
    $mitBeleg = Test-MitBeleg

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Severity 'Heading' -Text ([string] $ueberschrift['Detail'])))

    if ($ziele.Count -eq 0) {
        $zeilen.Add((New-OperatorTextLine -Text '  Für diesen Durchlauf gibt es kein Ziel.'))
    }

    for ($i = 0; $i -lt $ziele.Count; $i++) {

        $ziel = $ziele[$i]

        if ($i -gt 0) { $zeilen.Add((New-OperatorTextLine -Text '')) }

        $freigabe = Get-BefundFeld -Befund $ziel -Name 'ShareName' -Ersatz '(keine)'
        if ([string]::IsNullOrWhiteSpace($freigabe)) { $freigabe = '(keine)' }

        $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                        '{0} -- {1} -- Freigabe {2}' -f
                        (Get-BefundFeld -Befund $ziel -Name 'Kind'),
                        (Get-BefundFeld -Befund $ziel -Name 'Path'),
                        $freigabe))))

        $bindung = $null
        if ($null -ne $ziel.PSObject.Properties['Binding']) { $bindung = $ziel.Binding }

        $gruppen = @()
        if ($bindung -is [hashtable]) { $gruppen = @(Format-BindingLine -Binding $bindung -Group $Group) }

        if ($gruppen.Count -eq 0) {
            $zeilen.Add((New-OperatorTextLine -Text '  Gruppen: (keine)'))
        }
        else {
            foreach ($zeile in $gruppen) { $zeilen.Add($zeile) }
        }

        $soll = $null
        if ($null -ne $ziel.PSObject.Properties['Desired']) { $soll = $ziel.Desired }

        if ($null -eq $soll) {
            $zeilen.Add((New-OperatorTextLine -Text '  ACEs: (kein Soll gebunden)'))
            continue
        }

        $aces = @()
        if ($null -ne $soll.PSObject.Properties['Aces']) { $aces = @(@($soll.Aces) | Where-Object { $null -ne $_ }) }

        $zeilen.Add((New-OperatorTextLine -Text ('  ACEs: {0}' -f $aces.Count)))

        $mitProvenienz = $false

        foreach ($ace in $aces) {

            $sid = ''
            if (($null -ne $ace.PSObject.Properties['Sid']) -and ($null -ne $ace.Sid)) { $sid = [string] $ace.Sid }

            $anzeige = ''
            if ((-not [string]::IsNullOrEmpty($sid)) -and $karte.ContainsKey($sid)) { $anzeige = [string] $karte[$sid] }
            if ([string]::IsNullOrEmpty($anzeige)) { $anzeige = Get-BefundFeld -Befund $ace -Name 'Trustee' -Ersatz $sid }

            $rechte = ''
            if (($null -ne $ace.PSObject.Properties['Rule']) -and
                ($ace.Rule -is [System.Security.AccessControl.FileSystemAccessRule])) {
                $rechte = Get-AdjustRightsLabel -Rule $ace.Rule
            }
            else {
                $rechte = Get-BefundFeld -Befund $ace -Name 'Rights' -Ersatz '(unbekannt)'
            }

            $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                            '    {0} -- SID {1} -- Rechte {2} -- Gilt für {3}' -f
                            $anzeige, $sid, $rechte,
                            (Get-BefundFeld -Befund $ace -Name 'AppliesTo' -Ersatz '(unbekannt)')))))

            $herkunft = Get-BefundFeld -Befund $ace -Name 'Status'
            if ([string]::IsNullOrEmpty($herkunft)) { continue }

            $mitProvenienz = $true

            if ($mitBeleg) {
                $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                                '      {0} Quelle: {1} Abschnitt: {2}' -f
                                (Get-ProvenienzBadge -Provenance $herkunft),
                                (Get-BefundFeld -Befund $ace -Name 'Source' -Ersatz '(keine)'),
                                (Get-BefundFeld -Befund $ace -Name 'Section' -Ersatz '(keiner)')))))
            }
        }

        $schutz = $false
        if ($null -ne $soll.PSObject.Properties['ProtectInheritance']) { $schutz = [bool] $soll.ProtectInheritance }

        $zeilen.Add((New-OperatorTextLine -Text ('  Vererbungsschutz: {0}' -f $(if ($schutz) { 'an' } else { 'aus' }))))

        $schutzHerkunft = Get-BefundFeld -Befund $soll -Name 'ProtectInheritanceStatus'

        if (-not [string]::IsNullOrEmpty($schutzHerkunft)) {

            $mitProvenienz = $true

            if ($mitBeleg) {
                $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                                '    {0} Quelle: {1} Abschnitt: {2}' -f
                                (Get-ProvenienzBadge -Provenance $schutzHerkunft),
                                (Get-BefundFeld -Befund $soll -Name 'ProtectInheritanceSource' -Ersatz '(keine)'),
                                (Get-BefundFeld -Befund $soll -Name 'ProtectInheritanceSection' -Ersatz '(keiner)')))))
            }
        }

        if ($mitBeleg -and -not $mitProvenienz) {
            $zeilen.Add((New-OperatorTextLine -Text '  Belege: keine -- das Soll dieses Ziels ist ein eigener Plan, kein Herstellertemplate.'))
        }
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    return $zeilen.ToArray()
}

function Format-PreflightBefund {
    <#
    .SYNOPSIS
        Die Preflight-Befunde als Zeilensaetze -- im selben Bild wie der Plan
        (D-10). Intern zu Format-ProvisioningPlan.

    .DESCRIPTION
        GETRENNT NACH SCOPE, weil die Folge fuer den Operator eine voellig
        andere ist: ein Befund mit Scope gleich Host sperrt jedes Ziel, ein
        Zielbefund nur seines. Zielbefunde mit Status OK stehen unter einer
        eigenen Unterueberschrift "Hinweise, die nichts sperren" (G-04-4g). Beides unter einer gemeinsamen Ueberschrift
        aufzufuehren zwaenge ihn, je Zeile nachzusehen, was sie fuer seine
        Entscheidung bedeutet -- und die Entscheidung faellt unmittelbar
        darunter.

        Check und Scope haengen NUR an Preflight-Saetzen und nicht an der
        eingefrorenen Ergebnisform. Unter Set-StrictMode -Version Latest wirft
        der Zugriff auf ein fehlendes Feld, deshalb laeuft jeder Zugriff darauf
        ueber PSObject.Properties.

        OUT-01 (v1.3): zwischen den Host-Befunden und den Zeilen der
        Zielbefunde steht die Tabelle aus Format-PreflightTable -- je Ziel
        seine Pruefkennungen mit Statusmarke, ein Ziel ohne Befund mit "alle"
        und [OK]. Die Befundzeilen mit Meldungstext bleiben darunter
        unveraendert; die Tabelle ersetzt keinen Befund, sie ordnet sie nach
        Ordnerart. Host-Befunde stehen nie in der Tabelle.

    .PARAMETER Target
        Die Ziele des Laufs (Weg 1 und 2) bzw. die Anpasszustaende (Weg 3),
        jeweils mit Kind und Path. Ohne Ziele und ohne Zielbefund entfaellt die
        Tabelle.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult
    )

    $ueberschrift = Get-ReportUeberschrift
    $zeilen = New-Object System.Collections.Generic.List[object]
    $befunde = @(@($PreflightResult) | Where-Object { $null -ne $_ })
    $ziele = @(@($Target) | Where-Object { $null -ne $_ })

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['Preflight'])))

    # Nicht $host: das ist eine automatische Variable von PowerShell, und eine
    # Zuweisung darauf ist unter Set-StrictMode ein schwer zu findender Fehler.
    $rechnerweit = @($befunde | Where-Object { (Get-BefundScope -Befund $_) -ceq 'Host' })

    # G-04-4g: ein Zielbefund mit Status OK sperrt nichts -- etwa PRE-05 bei
    # einer bestehenden Freigabe auf demselben Pfad. Unter der Ueberschrift der
    # sperrenden Befunde laese er sich als Sperre.
    $zielbezogen = @($befunde | Where-Object { ((Get-BefundScope -Befund $_) -cne 'Host') -and ([string] $_.Status -cne 'OK') })
    $hinweise = @($befunde | Where-Object { ((Get-BefundScope -Befund $_) -cne 'Host') -and ([string] $_.Status -ceq 'OK') })

    if ($rechnerweit.Count -gt 0) {
        $zeilen.Add((New-OperatorTextLine -Text '  Diese Befunde sperren den gesamten Lauf:'))
        foreach ($befund in $rechnerweit) {
            $zeilen.Add((Format-BefundZeile -Befund $befund -MitPfad $false))
        }
    }

    foreach ($zeile in @(Format-PreflightTable -Target $ziele -PreflightResult $befunde)) {
        $zeilen.Add($zeile)
    }

    if ($befunde.Count -eq 0) {
        $zeilen.Add((New-OperatorTextLine -Severity 'OK' -Text '  [OK] Das Preflight hat keinen Befund gemeldet.'))
        return $zeilen.ToArray()
    }

    if ($zielbezogen.Count -gt 0) {
        $zeilen.Add((New-OperatorTextLine -Text '  Diese Befunde sperren nur ihr eigenes Ziel:'))
        foreach ($befund in $zielbezogen) {
            $zeilen.Add((Format-BefundZeile -Befund $befund -MitPfad $true))
        }
    }

    if ($hinweise.Count -gt 0) {
        $zeilen.Add((New-OperatorTextLine -Text '  Hinweise, die nichts sperren:'))
        foreach ($befund in $hinweise) {
            $zeilen.Add((Format-BefundZeile -Befund $befund -MitPfad $true))
        }
    }

    return $zeilen.ToArray()
}

function Format-PreflightTable {
    <#
    .SYNOPSIS
        OUT-01 (v1.3): die Zielbefunde des Preflights als gerahmte Tabelle
        Ordnerart, Pruefung, Ergebnis. Intern zu Format-PreflightBefund.

    .DESCRIPTION
        Je Ziel in der Reihenfolge der Ziele seine Zielbefunde, ordinal nach
        Pruefkennung sortiert, je Befund eine Zeile; ein Ziel ohne Befund eine
        Zeile mit "alle" und [OK]. Die Zuordnung laeuft ueber Ordnerart UND
        normalisierten Pfad wie in Get-TargetResult.

        VERWORFEN WIRD NICHTS. Ein Zielbefund ohne passendes Ziel bekommt eine
        eigene Zeile hinter den Zielen -- mit Ordnerart und Pfad des Befundes,
        damit er sich nicht als Befund eines gleichartigen Ziels liest; ohne
        Ordnerart steht "--". Host-Befunde stehen nie hier, sie sperren den
        ganzen Lauf und haben ihre eigene Unterueberschrift.

        Ohne Ziel und ohne Zielbefund entfaellt die Tabelle.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult = @()
    )

    $ziele = @(@($Target) | Where-Object { $null -ne $_ })
    $zielbefunde = @(@($PreflightResult) | Where-Object { ($null -ne $_) -and ((Get-BefundScope -Befund $_) -cne 'Host') })

    if (($ziele.Count -eq 0) -and ($zielbefunde.Count -eq 0)) { return @() }

    $vergeben = New-Object 'System.Collections.Generic.HashSet[int]'
    $reihen = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in $ziele) {

        $zelle = Get-ZielBezeichnung -Target $ziel -Alle $ziele
        $art = [string] $ziel.Kind
        $praefix = ConvertTo-PfadPraefix -LiteralPath ([string] $ziel.Path)

        $eigene = New-Object System.Collections.Generic.List[object]

        for ($k = 0; $k -lt $zielbefunde.Count; $k++) {

            if ($vergeben.Contains($k)) { continue }

            $befund = $zielbefunde[$k]
            $pfad = Get-BefundFeld -Befund $befund -Name 'Path'

            if ((Get-BefundFeld -Befund $befund -Name 'Kind') -cne $art) { continue }
            if ([string]::IsNullOrEmpty($pfad)) { continue }
            if ((ConvertTo-PfadPraefix -LiteralPath $pfad) -ne $praefix) { continue }

            $null = $vergeben.Add($k)
            $eigene.Add($befund)
        }

        if ($eigene.Count -eq 0) {
            $reihen.Add([object[]] @($zelle, 'alle', (Get-StatusZelle -Status 'OK')))
            continue
        }

        # Ordinal nach Pruefkennung -- Sort-Object vergliche kulturabhaengig.
        $eigene.Sort([System.Comparison[object]] {
                param($Links, $Rechts)
                [string]::CompareOrdinal(
                    (Get-BefundFeld -Befund $Links -Name 'Check'),
                    (Get-BefundFeld -Befund $Rechts -Name 'Check'))
            })

        foreach ($befund in $eigene) {
            $reihen.Add([object[]] @($zelle, (Get-BefundFeld -Befund $befund -Name 'Check' -Ersatz '--'),
                    (Get-StatusZelle -Status ([string] $befund.Status))))
        }
    }

    for ($k = 0; $k -lt $zielbefunde.Count; $k++) {

        if ($vergeben.Contains($k)) { continue }

        $befund = $zielbefunde[$k]
        $art = Get-BefundFeld -Befund $befund -Name 'Kind'
        $pfad = Get-BefundFeld -Befund $befund -Name 'Path'

        $zelle = if ([string]::IsNullOrEmpty($art)) { '--' }
        elseif ([string]::IsNullOrEmpty($pfad)) { $art }
        else { '{0} ({1})' -f $art, $pfad }

        $reihen.Add([object[]] @($zelle, (Get-BefundFeld -Befund $befund -Name 'Check' -Ersatz '--'),
                (Get-StatusZelle -Status ([string] $befund.Status))))
    }

    return @(Format-AdjustTable -Header @('Ordnerart', 'Prüfung', 'Ergebnis') -Row $reihen.ToArray() -Indent '  ')
}

function Get-BefundScope {
    <#
    .SYNOPSIS
        Der Scope eines Preflight-Befundes, oder leer. Intern zu
        Format-PreflightBefund.

    .DESCRIPTION
        Ueber PSObject.Properties, weil Scope nur an Preflight-Saetzen haengt
        und der Direktzugriff unter Set-StrictMode -Version Latest wirft.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Befund
    )

    if ($null -eq $Befund) { return '' }
    if ($null -eq $Befund.PSObject.Properties['Scope']) { return '' }

    return [string] $Befund.Scope
}

function Format-BefundZeile {
    <#
    .SYNOPSIS
        Ein Preflight-Befund als eine Zeile der Einzugstufe 4. Intern zu
        Format-PreflightBefund.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Befund,

        [Parameter()]
        [bool] $MitPfad = $true
    )

    $status = [string] $Befund.Status

    $pruefung = ''
    if ($null -ne $Befund.PSObject.Properties['Check']) { $pruefung = [string] $Befund.Check }

    $pfad = [string] $Befund.Path

    $text = if ($MitPfad -and -not [string]::IsNullOrEmpty($pfad)) {
        '    {0} {1} ({2}): {3}' -f (Get-StatusMarkierung -Status $status), $pruefung, $pfad, [string] $Befund.Message
    }
    else {
        '    {0} {1}: {2}' -f (Get-StatusMarkierung -Status $status), $pruefung, [string] $Befund.Message
    }

    return (New-OperatorTextLine -Severity (Get-LineSeverity -Status $status) -Text (
            ConvertTo-Einzeiler -Wert $text))
}

function Test-HostSperre {
    <#
    .SYNOPSIS
        Wahr, wenn die Preflight-Sammlung einen Befund mit Scope gleich Host
        und Zustand Error traegt.

    .DESCRIPTION
        DIE BESTAETIGUNGSFRAGE WIRD DANN GAR NICHT ERST GESTELLT. Ein Befund
        dieser Art sperrt jedes Ziel; nach der Bestaetigung bliebe nichts zu
        tun, und die Frage waere eine Aufforderung ohne Gegenstand. Das ist die
        Zusage aus Erfolgskriterium 1 der Phase 3: Abbruch, bevor irgendetwas
        geschrieben wurde.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult
    )

    foreach ($befund in @($PreflightResult)) {

        if ($null -eq $befund) { continue }
        if ((Get-BefundScope -Befund $befund) -cne 'Host') { continue }
        if ([string] $befund.Status -cne 'Error') { continue }

        return $true
    }

    return $false
}

function Format-ProvisioningSummary {
    <#
    .SYNOPSIS
        OUT-01, D-13: je Ziel eine Statuszeile nach dem schwersten Zustand
        seiner Ergebnissaetze -- und die vollen Befunde nur dort, wo der
        Vergleicher etwas gemeldet hat.

    .DESCRIPTION
        Die Statuszeile entsteht AUSSCHLIESSLICH aus den Ergebnisobjekten. Was
        dort nicht steht, kann die Zusammenfassung nicht zeigen -- fehlt ein
        Feld, gehoert es in das ProvisioningResult und nicht in einen
        Ausgabetext (OUT-06).

        GENAU DREI ZUSTAENDE, mehr nicht: Status ist im Ergebnisobjekt per
        ValidateSet auf OK, Warning und Error begrenzt, und die Zusammenfassung
        fuehrt keinen vierten ein.

        EIN ERGEBNISSATZ MIT LEEREM Detail ERZEUGT KEINE DETAILZEILE. Traegt er
        Befunde, erscheinen sie vollstaendig -- so bleibt der gruene Lauf
        lesbar, und wo es klemmt, steht alles da (D-13, OUT-05).

        JEDER MELDUNGSTEXT JE ZIEL GENAU EINMAL (G-04-3b). Je Ziel wird die
        Menge der bereits ausgegebenen Meldungstexte gefuehrt (ordinal). Ein
        Detaildatensatz, der KEIN ACE-Befund ist und dessen Message dort schon
        steht, erzeugt keine Zeile. Das nimmt den Doppel aus Satzmeldung und
        gleichlautendem Detaildatensatz eines Preflight-Befundes und den
        zwischen Preflight-Befund und Sperrsatz-Detail. DIE GRENZE: ACE-Befunde
        (Test-AceBefund) laufen ausnahmslos durch, auch bei gleichem Text --
        ihre Vollstaendigkeit sagt OUT-05 zu.

    .PARAMETER Group
        Die erhobenen Gruppenrollen als Tabelle Rolle -> Datensatz mit Sid und
        DisplayName -- dieselbe Quelle wie in der Planvorschau. Ohne sie nennt
        die Statuszeile die SID; eine zweite Aufloesung im Formatierer waere
        eine zweite Wahrheit ueber denselben Prinzipal.

    .PARAMETER HeadingKey
        Der Schluessel der Ueberschrift aus Get-ReportUeberschrift. Vorgabe
        Summary; der Bericht der Bestandspruefung nutzt AuditDetail (D-16).

    .PARAMETER ResultProvenance
        Nur im Pruefbericht (D-16, OUT-05): jedem Ergebnissatz mit Zustand
        ungleich OK und nicht leerer Provenance folgt eine Belegzeile der
        Einzugstufe 4 mit Badge, Quelle und Abschnitt. Ohne den Schalter
        aendert sich keine Zeile -- Weg 1 bleibt unberuehrt.

    .PARAMETER ServerName
        Der Servername fuer den UNC-Hinweis zu RedirXMLSourceFolder (RDX-06).
        Die Orchestrierung liefert ihn ueber Get-ServerDnsName; der Formatierer
        fragt die Maschine nie selbst (OUT-06). Leer erscheint als <Server>.

    .PARAMETER Table
        Weg 1: die Ergebnistabelle je Ziel, die
        Befunde nur fuer Ziele, die nicht OK sind, und unter dem
        Gesamtzustand der Abschlussblock -- Abschlussmeldung und Kurzuebersicht
        aus Format-ProvisioningClosing (OUT-04 v1.3).

    .OUTPUTS
        Sammlung von Zeilensaetzen mit Text und Severity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null,

        [Parameter()]
        [ValidateSet('Summary', 'AuditDetail')]
        [string] $HeadingKey = 'Summary',

        [Parameter()]
        [switch] $ResultProvenance,

        # Nur Ziele, die nicht OK sind; ohne solche entfallen Ueberschrift und
        # Zielbloecke, es bleibt der Gesamtzustand (Pruefbericht, Serverlauf
        # 2026-09-25: die Tabelle traegt das Ergebnis).
        [Parameter()]
        [switch] $OnlyDeviating,

        [Parameter()]
        [AllowEmptyString()]
        [string] $ServerName = '',

        # Weg 1 (Serverlauf 2026-09-28): oben eine Zeile je Ziel als gerahmte
        # Tabelle, darunter die Befunde nur fuer Ziele, die nicht OK sind --
        # dieselbe Aufteilung wie im Pruefbericht. Unter dem Gesamtzustand
        # folgt der Abschlussblock aus Format-ProvisioningClosing (OUT-04 v1.3).
        [Parameter()]
        [switch] $Table
    )

    $ueberschrift = Get-ReportUeberschrift
    $zeilen = New-Object System.Collections.Generic.List[object]
    $saetze = @(@($Result) | Where-Object { $null -ne $_ })
    $ziele = @(@($Target) | Where-Object { $null -ne $_ })
    $alleZiele = $ziele

    if ($Table) {

        $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['Summary'])))

        if ($ziele.Count -eq 0) {
            $zeilen.Add((New-OperatorTextLine -Text '  Es wurde kein Ziel bearbeitet.'))
        }
        else {
            foreach ($zeile in @(Format-ProvisioningTable -Result $saetze -Target $ziele -Group $Group)) { $zeilen.Add($zeile) }
        }

        $zeilen.Add((New-OperatorTextLine -Text ''))

        $OnlyDeviating = [switch] $true
        $HeadingKey = 'AuditDetail'
    }

    if ($OnlyDeviating) {
        $ziele = @($ziele | Where-Object { (Get-SchwersterStatus -Result @(Get-TargetResult -Result $saetze -Target $_)) -cne 'OK' })
    }

    $ohneBlock = $OnlyDeviating -and ($ziele.Count -eq 0)

    # Die Ueberschrift ist der ERSTE Satz dieser Sammlung; die Leerzeile davor
    # liefert die Planvorschau, die unmittelbar davor ausgegeben wird. Eine
    # zweite hier ergaebe zwei aufeinanderfolgende Leerzeilen und damit den
    # Eindruck eines Abbruchs (OUT-04 Regel 1).
    if (-not $ohneBlock) {
        $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift[$HeadingKey])))
    }

    if (($ziele.Count -eq 0) -and -not $ohneBlock) {
        $zeilen.Add((New-OperatorTextLine -Text '  Es wurde kein Ziel bearbeitet.'))
    }

    for ($i = 0; $i -lt $ziele.Count; $i++) {

        $ziel = $ziele[$i]

        if ($i -gt 0) { $zeilen.Add((New-OperatorTextLine -Text '')) }

        $eigene = @(Get-TargetResult -Result $saetze -Target $ziel)
        $status = Get-SchwersterStatus -Result $eigene

        # OUT-04 Regel 5: EINE Zeile, Einzugstufe 0. Alles Weitere steht
        # eingerueckt darunter.
        $zeilen.Add((New-OperatorTextLine -Severity (Get-LineSeverity -Status $status) -Text (
                    ConvertTo-Einzeiler -Wert (
                        '{0} {1} {2} -- {3} -- Freigabe {4} -- Gruppen {5}' -f
                        (Get-StatusMarkierung -Status $status),
                        (Get-StatusZeichen -Status $status -Capability $Capability),
                        [string] $ziel.Kind, [string] $ziel.Path, [string] $ziel.ShareName,
                        (Format-GruppenText -Binding $ziel.Binding -Group $Group)))))

        # Die bereits ausgegebenen Meldungstexte DIESES Ziels (G-04-3b).
        $gezeigt = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

        foreach ($satz in $eigene) {

            $detail = @($satz.Detail)

            # Ein gruener Satz ohne Befund schweigt. Ein gruener Satz MIT
            # Befund tut es ausdruecklich nicht: ein stillschweigend
            # verschluckter Befund waere in einem Compliance-Werkzeug der
            # schlimmste Ausgang.
            if (([string] $satz.Status -ceq 'OK') -and ($detail.Count -eq 0)) { continue }

            $zeilen.Add((New-OperatorTextLine -Severity (Get-LineSeverity -Status ([string] $satz.Status)) -Text (
                        ConvertTo-Einzeiler -Wert (
                            '  {0} {1}: {2}' -f
                            (Get-StatusMarkierung -Status ([string] $satz.Status)),
                            [string] $satz.Stage, [string] $satz.Message))))

            $null = $gezeigt.Add([string] $satz.Message)

            # Der Beleg des Satzes (D-16, OUT-05) -- nur mit -ResultProvenance,
            # also im Pruefbericht. Ohne den Schalter aendert sich keine Zeile.
            if ($ResultProvenance -and (Test-MitBeleg) -and ([string] $satz.Status -cne 'OK')) {

                $herkunft = Get-BefundFeld -Befund $satz -Name 'Provenance'

                if (-not [string]::IsNullOrEmpty($herkunft)) {
                    $zeilen.Add((New-OperatorTextLine -Severity (Get-LineSeverity -Status ([string] $satz.Status)) -Text (
                                ConvertTo-Einzeiler -Wert (
                                    '    {0} Quelle: {1} Abschnitt: {2}' -f
                                    (Get-ProvenienzBadge -Provenance $herkunft),
                                    (Get-BefundFeld -Befund $satz -Name 'Source' -Ersatz '(keine)'),
                                    (Get-BefundFeld -Befund $satz -Name 'Section' -Ersatz '(keiner)')))))
                }
            }

            foreach ($befund in $detail) {

                if (($null -ne $befund) -and (-not (Test-AceBefund -Befund $befund))) {

                    $meldung = Get-BefundFeld -Befund $befund -Name 'Message'

                    if (-not [string]::IsNullOrEmpty($meldung)) {
                        if ($gezeigt.Contains($meldung)) { continue }
                        $null = $gezeigt.Add($meldung)
                    }
                }

                foreach ($zeile in @(Format-AceFindingLine -Befund $befund -Severity ([string] $satz.Status))) {
                    $zeilen.Add($zeile)
                }
            }
        }
    }

    $gesamt = Get-SchwersterStatus -Result $saetze

    if (-not $ohneBlock) { $zeilen.Add((New-OperatorTextLine -Text '')) }
    $zeilen.Add((New-OperatorTextLine -Severity (Get-LineSeverity -Status $gesamt) -Text (
                '  Gesamtzustand: {0} {1}' -f
                (Get-StatusMarkierung -Status $gesamt),
                (Get-StatusZeichen -Status $gesamt -Capability $Capability))))

    # OUT-04 (v1.3): nur im Zweig -Table (Weg 1)
    # die Abschlussmeldung mit Kurzuebersicht, direkt hinter dem
    # Gesamtzustand und vor dem UNC-Hinweis.
    if ($Table) {
        foreach ($zeile in @(Format-ProvisioningClosing -Result $saetze -Target $alleZiele)) {
            $zeilen.Add($zeile)
        }
    }

    # RDX-06: nach dem Gesamtzustand und vor der Fussnote. Ohne ein Ziel, das
    # die Bedingung erfuellt, kommt keine Zeile hinzu. Ueber ALLE Ziele: der
    # Hinweis gilt gerade den gruenen, die -OnlyDeviating ausblendet.
    foreach ($zeile in @(Format-RedirectionsHinweis -Result $saetze -Target $alleZiele -ServerName $ServerName)) {
        $zeilen.Add($zeile)
    }

    foreach ($zeile in @(Format-Fussnote -Result $saetze)) {
        $zeilen.Add($zeile)
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))

    return $zeilen.ToArray()
}

function Format-ProvisioningClosing {
    <#
    .SYNOPSIS
        OUT-04 (v1.3): die Abschlussmeldung nach der Ausfuehrung und die
        Kurzuebersicht -- Ordner, verifizierte Freigaben, verifizierte ACLs.
        Intern zu Format-ProvisioningSummary (Zweig -Table).

    .DESCRIPTION
        DIE ERFOLGSMELDUNG NUR BEI DURCHWEG OK. Der Zustand ist derselbe wie
        der Gesamtzustand und der Rueckgabewert (Get-SchwersterStatus ueber
        alle Saetze): eine Warnung oder ein Fehler wird nie als Erfolg
        zusammengefasst, sondern ersetzt die Erfolgsmeldung durch die eigene.

        DIE KURZUEBERSICHT STEHT IN ALLEN DREI FAELLEN. "x von n" macht einen
        Teilausfall sichtbar -- gerade nach einer Warnung oder einem Fehler
        ist die Zahl der verifizierten Ziele die Aussage, die der Operator
        braucht. Gezaehlt wird je Ziel: verifiziert ist eine Freigabe bzw. ein
        ACL, wenn das Ziel mindestens einen Satz der Stufe ShareVerify bzw.
        AclVerify traegt und der schwerste davon OK ist.

        Ohne Ziel keine Zeile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    $zeilen = New-Object System.Collections.Generic.List[object]
    $saetze = @(@($Result) | Where-Object { $null -ne $_ })
    $ziele = @(@($Target) | Where-Object { $null -ne $_ })

    if ($ziele.Count -eq 0) { return $zeilen.ToArray() }

    $zustand = Get-SchwersterStatus -Result $saetze

    $meldung = if ([string]::Equals($zustand, 'Error', [System.StringComparison]::Ordinal)) {
        '  {0} Provisionierung mit Fehlern abgeschlossen -- nicht jedes Ziel ist wie geplant eingerichtet; die Befunde stehen oben.' -f (Get-StatusMarkierung -Status $zustand)
    }
    elseif ([string]::Equals($zustand, 'Warning', [System.StringComparison]::Ordinal)) {
        '  {0} Provisionierung mit Warnungen abgeschlossen -- die Befunde stehen oben.' -f (Get-StatusMarkierung -Status $zustand)
    }
    else {
        '  {0} Provisionierung erfolgreich abgeschlossen.' -f (Get-StatusMarkierung -Status $zustand)
    }

    $freigaben = 0
    $acls = 0

    foreach ($ziel in $ziele) {

        $eigene = @(Get-TargetResult -Result $saetze -Target $ziel)

        $pruefung = @($eigene | Where-Object { [string] $_.Stage -ceq 'ShareVerify' })
        if (($pruefung.Count -gt 0) -and ((Get-SchwersterStatus -Result $pruefung) -ceq 'OK')) { $freigaben++ }

        $pruefung = @($eigene | Where-Object { [string] $_.Stage -ceq 'AclVerify' })
        if (($pruefung.Count -gt 0) -and ((Get-SchwersterStatus -Result $pruefung) -ceq 'OK')) { $acls++ }
    }

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Severity (Get-LineSeverity -Status $zustand) -Text $meldung))
    $zeilen.Add((New-OperatorTextLine -Text ('    Ordner: {0}' -f $ziele.Count)))
    $zeilen.Add((New-OperatorTextLine -Text ('    Freigaben verifiziert: {0} von {1}' -f $freigaben, $ziele.Count)))
    $zeilen.Add((New-OperatorTextLine -Text ('    ACLs verifiziert: {0} von {1}' -f $acls, $ziele.Count)))

    return $zeilen.ToArray()
}

function Format-ProvisioningTable {
    <#
    .SYNOPSIS
        Die Zusammenfassung von Weg 1 als gerahmte Tabelle: eine Zeile je Ziel,
        darunter die gebundenen Gruppen je Produkt (Serverlauf 2026-09-28).

    .DESCRIPTION
        Spalten Ordnerart, Pfad, Freigabename, NTFS, Freigabe, Gesamt. NTFS ist
        die Marke des schwersten Satzes der Stufen Acl und AclVerify, Freigabe
        die der Stufen Share und ShareVerify -- "--", wenn die Stufe kein
        Ergebnis hat (etwa weil das ACL nicht verifiziert ist, SHARE-03).
        Gesamt ist der schwerste Zustand aller Saetze des Ziels, Preflight
        eingeschlossen. Der Pfad wird ab 46 Zeichen vorn gekuerzt; wo ein Ziel
        nicht OK ist, steht der volle Pfad in den Befunden darunter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null
    )

    $kopf = @('Ordnerart', 'Pfad', 'Freigabename', 'NTFS', 'Freigabe', 'Gesamt')
    $spalten = @(@('Acl', 'AclVerify'), @('Share', 'ShareVerify'))

    $reihen = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in @($Target)) {

        $eigene = @(Get-TargetResult -Result $Result -Target $ziel)

        $pfad = [string] $ziel.Path
        if ($pfad.Length -ge 46) { $pfad = '...' + $pfad.Substring($pfad.Length - 42) }

        $freigabe = [string] $ziel.ShareName
        if ([string]::IsNullOrWhiteSpace($freigabe)) { $freigabe = '--' }

        $zellen = New-Object System.Collections.Generic.List[object]
        $zellen.Add([string] $ziel.Kind)
        $zellen.Add($pfad)
        $zellen.Add($freigabe)

        foreach ($stufen in $spalten) {
            $stufenSaetze = @($eigene | Where-Object { $stufen -ccontains [string] $_.Stage })
            if ($stufenSaetze.Count -eq 0) { $zellen.Add('--'); continue }
            $zellen.Add((Get-StatusZelle -Status (Get-SchwersterStatus -Result $stufenSaetze)))
        }

        $zellen.Add((Get-StatusZelle -Status (Get-SchwersterStatus -Result $eigene)))

        $reihen.Add($zellen.ToArray())
    }

    $zeilen = New-Object System.Collections.Generic.List[object]

    foreach ($zeile in @(Format-AdjustTable -Header $kopf -Row $reihen.ToArray() -Indent '  ')) { $zeilen.Add($zeile) }

    # Die Gruppen je Produkt einmal -- beide FSLogix-Ordnerarten binden
    # dieselben, ebenso die DEM-Ordnerarten (RDX-03).
    $gesehen = @{}

    foreach ($ziel in @($Target)) {

        $produkt = Get-KindProduct -Kind ([string] $ziel.Kind)
        if ($gesehen.ContainsKey($produkt)) { continue }
        $gesehen[$produkt] = $true

        $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                        '  Gruppen {0}: {1}' -f $produkt, (Format-GruppenText -Binding $ziel.Binding -Group $Group)))))
    }

    return $zeilen.ToArray()
}

function Get-StatusZelle {
    <#
    .SYNOPSIS
        Eine Tabellenzelle mit der Statusmarke in der Farbe ihres Zustands.
        Intern zu Format-ProvisioningTable.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Status
    )

    return (New-AdjustCell -Segment @((New-TextSegment -Text (Get-StatusMarkierung -Status $Status) -Severity (Get-LineSeverity -Status $Status))))
}

function Get-TargetResult {
    <#
    .SYNOPSIS
        Die Ergebnissaetze EINES Ziels. Intern zu Format-ProvisioningSummary.

    .DESCRIPTION
        BEIDE SEITEN DURCH DIESELBE NORMALISIERUNG. Ein Satz zu einem anderen
        Pfad gehoert nicht in die Statuszeile dieses Ziels -- dieselbe
        Verwechslung, gegen die Select-AclVerifyResult in der Orchestrierung
        gebaut ist.

        DIE ORDNERART GEHOERT ZUM SCHLUESSEL (G-04-1a). Zwei Ziele auf einem
        Pfad zeigten sonst jeder die Saetze des anderen -- in Lauf 3 stand der
        Freigabefehler jedes Ziels unter jedem Ziel desselben Pfades. Saetze mit
        leerer Ordnerart -- die Hostbefunde -- passen damit zu keinem Ziel, wie
        bisher schon ueber ihren leeren Pfad.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [object] $Target
    )

    $zielPraefix = ConvertTo-PfadPraefix -LiteralPath ([string] $Target.Path)
    $zielKind = [string] $Target.Kind

    return @(@($Result) | Where-Object {
            $null -ne $_ -and
            ([string] $_.Kind) -ceq $zielKind -and
            (ConvertTo-PfadPraefix -LiteralPath ([string] $_.Path)) -eq $zielPraefix
        })
}

function Format-GruppenText {
    <#
    .SYNOPSIS
        Die gebundenen Gruppen eines Ziels als EIN Textstueck. Intern zu
        Format-ProvisioningSummary.

    .DESCRIPTION
        Der Anzeigename, wenn er erhoben wurde, sonst die SID. Massgeblich
        bleibt die SID -- der Name ist Anzeige (IDENT-06).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [hashtable] $Binding,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Group = $null
    )

    if ($null -eq $Binding) { return '(keine)' }

    $anzeige = @{}

    if ($null -ne $Group) {
        foreach ($rolle in @($Group.Keys)) {
            $satz = $Group[$rolle]
            if ($null -eq $satz) { continue }
            if ($null -eq $satz.PSObject.Properties['Sid']) { continue }
            $schluessel = [string] $satz.Sid.Value
            if ([string]::IsNullOrEmpty($schluessel)) { continue }
            if ($anzeige.ContainsKey($schluessel)) { continue }
            $anzeige[$schluessel] = [string] $satz.DisplayName
        }
    }

    $stuecke = New-Object System.Collections.Generic.List[string]

    foreach ($token in (@($Binding.Keys) | Sort-Object)) {

        # Weg 3 bindet je Schluessel auch mehrere Gruppen (Get-AdjustBinding).
        foreach ($wert in @($Binding[$token])) {

            if ($null -eq $wert) { continue }

            $sid = [string] $wert.Value

            if ($anzeige.ContainsKey($sid) -and -not [string]::IsNullOrEmpty([string] $anzeige[$sid])) {
                $stuecke.Add(('{0}={1}' -f $token, [string] $anzeige[$sid]))
            }
            else {
                $stuecke.Add(('{0}={1}' -f $token, $sid))
            }
        }
    }

    if ($stuecke.Count -eq 0) { return '(keine)' }

    return ($stuecke -join ', ')
}

function Format-AceFindingLine {
    <#
    .SYNOPSIS
        Ein Befund als Zeile der Einzugstufe 4, bei einem ACE-Befund mit der
        Belegzeile der Stufe 6 darunter. Intern zu Format-ProvisioningSummary.

    .DESCRIPTION
        DREI BEFUNDFORMEN LIEGEN IN Detail, und keine traegt alle Felder der
        anderen: die dreizehnfeldrigen ACE-Befunde aus Compare-AceSet, die
        Freigabebefunde aus Compare-ShareAccess samt dem ShareState-Satz, und
        die Duplikatsaetze aus Test-AceDuplicate. Unter
        Set-StrictMode -Version Latest WIRFT jeder Zugriff auf ein nicht
        vorhandenes Feld; deshalb laeuft hier jeder Feldzugriff ueber
        PSObject.Properties.

        EINE NICHT ERKANNTE BEFUNDFORM WIRD AUSGEGEBEN, NICHT VERWORFEN. Ein
        stillschweigend verschluckter Befund waere in einem Compliance-Werkzeug
        der schlimmste Ausgang -- lieber eine unfoermige Zeile als eine
        fehlende.

        DAS BADGE KOMMT AUS DEM BEFUNDFELD Status (Verified beziehungsweise
        Derived) UND NICHT AUS DEM ERGEBNISSATZ, dessen gleichnamiges Feld OK,
        Warning oder Error traegt. Wer die beiden verwechselt, druckt OK als
        Provenienz und merkt es nie.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Befund,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Severity = 'Error'
    )

    $zeilen = New-Object System.Collections.Generic.List[object]

    if ($null -eq $Befund) { return $zeilen.ToArray() }

    $schwere = Get-LineSeverity -Status $Severity

    if (Test-AceBefund -Befund $Befund) {

        $zeilen.Add((New-OperatorTextLine -Severity $schwere -Text (
                    ConvertTo-Einzeiler -Wert (
                        '    {0}: Prinzipal {1} SID {2} Rechte {3} Gilt für {4} Erwartet {5} Ist {6}' -f
                        (Get-BefundFeld -Befund $Befund -Name 'Finding'),
                        (Get-BefundFeld -Befund $Befund -Name 'Trustee'),
                        (Get-BefundFeld -Befund $Befund -Name 'Sid'),
                        (Get-BefundFeld -Befund $Befund -Name 'RightsHex'),
                        (Get-BefundFeld -Befund $Befund -Name 'AppliesTo'),
                        (Get-BefundFeld -Befund $Befund -Name 'Expected'),
                        (Get-BefundFeld -Befund $Befund -Name 'Actual')))))

        # Die Belegzeile steht IMMER da -- auch ohne Herstellerbeleg. Ein
        # fehlendes Badge waere sonst von einem vergessenen nicht zu
        # unterscheiden (OUT-05).
        # Ohne Belege im Soll (Einzeldatei-Buendel) gibt es keine Belegzeile.
        if (-not (Test-MitBeleg)) { return $zeilen.ToArray() }

        $quelle = Get-BefundFeld -Befund $Befund -Name 'Source' -Ersatz '(keine)'
        $abschnitt = Get-BefundFeld -Befund $Befund -Name 'Section' -Ersatz '(keiner)'

        $zeilen.Add((New-OperatorTextLine -Severity $schwere -Text (
                    ConvertTo-Einzeiler -Wert (
                        '      {0} Quelle: {1} Abschnitt: {2}' -f
                        (Get-ProvenienzBadge -Provenance (Get-BefundFeld -Befund $Befund -Name 'Status')),
                        $quelle, $abschnitt))))

        return $zeilen.ToArray()
    }

    $meldung = Get-BefundFeld -Befund $Befund -Name 'Message'

    if ([string]::IsNullOrWhiteSpace($meldung)) {
        # Weder ACE-Form noch Meldung: dann eben die Felder. Verworfen wird
        # nichts.
        $meldung = (@($Befund.PSObject.Properties |
                    ForEach-Object { '{0}={1}' -f $_.Name, [string] $_.Value }) -join '; ')
    }

    $zeilen.Add((New-OperatorTextLine -Severity $schwere -Text (
                ConvertTo-Einzeiler -Wert ('    {0}' -f $meldung))))

    return $zeilen.ToArray()
}

function Test-AceBefund {
    <#
    .SYNOPSIS
        Wahr, wenn der Befund die vollstaendige ACE-Form aus Compare-AceSet
        traegt. Intern zu Format-AceFindingLine.

    .DESCRIPTION
        Vier Felder zugleich, nicht eines: der Duplikatsatz aus
        Test-AceDuplicate fuehrt Finding, Sid und RightsHex ebenfalls, aber
        kein AppliesTo und keinen Trustee -- er gehoert in den Meldungszweig.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object] $Befund
    )

    foreach ($name in @('Finding', 'Trustee', 'Sid', 'RightsHex', 'AppliesTo')) {
        if ($null -eq $Befund.PSObject.Properties[$name]) { return $false }
    }

    return (-not [string]::IsNullOrEmpty([string] $Befund.AppliesTo))
}

function Get-BefundFeld {
    <#
    .SYNOPSIS
        Ein Feld eines Befundes, oder ein Ersatzwert. Intern zu
        Format-AceFindingLine.

    .DESCRIPTION
        Ueber PSObject.Properties, weil die drei Befundformen unterschiedliche
        Felder fuehren und der Direktzugriff unter Set-StrictMode -Version
        Latest wirft.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Befund,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Ersatz = ''
    )

    if ($null -eq $Befund.PSObject.Properties[$Name]) { return $Ersatz }

    $wert = [string] $Befund.PSObject.Properties[$Name].Value

    if ([string]::IsNullOrEmpty($wert)) { return $Ersatz }

    return $wert
}

function Get-ProvenienzBadge {
    <#
    .SYNOPSIS
        Das Provenienz-Kennzeichen eines Befundes (OUT-05). Intern zu
        Format-AceFindingLine.

    .DESCRIPTION
        Verified heisst herstellerwoertlich belegt, Derived heisst aus einer
        benachbarten Herstelleraussage abgeleitet. Fehlt beides -- ein
        unerwarteter Eintrag hat keinen Soll-Datensatz --, steht das
        ausdruecklich da: ein fehlendes Kennzeichen waere sonst von einem
        vergessenen nicht zu unterscheiden.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Provenance
    )

    if ([string]::Equals($Provenance, 'Verified', [System.StringComparison]::Ordinal)) { return '[Hersteller]' }
    if ([string]::Equals($Provenance, 'Derived', [System.StringComparison]::Ordinal)) { return '[abgeleitet]' }

    return '[ohne Beleg]'
}

function Format-Fussnote {
    <#
    .SYNOPSIS
        OUT-08, D-15: die Fussnote zu weiterhin fehlschlagenden Profilen --
        genau dann, wenn mindestens ein Profilshare verifiziert wurde.

    .DESCRIPTION
        NACH EINEM REINEN KONFIGURATIONSLAUF WAERE SIE RAUSCHEN, und eine
        Fussnote, die immer kommt, wird nicht mehr gelesen. Sie ist
        ausdruecklich auch fuer den GRUENEN Lauf gedacht: gerade dort erklaert
        sie, warum ein Profil trotz verifizierter ACL weiterhin fehlschlagen
        kann.

        DER BETROFFENE VORDEFINIERTE PRINZIPAL WIRD NICHT BEIM ENGLISCHEN NAMEN
        GENANNT. "Allen Konten" ist die richtige Formulierung und zugleich die
        genauere -- IDENT-08 und Tests/NoEnglishPrincipals.Tests.ps1 fassen
        diese Datei mit.

        Quelle der Substanz: FEATURES.md Abschnitt 1.3, Absatz "Traverse
        nuance". Der Verweis steht bewusst nicht in der Ausgabe -- auf dem
        Server kann niemand ihm folgen (Entscheidung 2026-09-24). Die
        Ueberschrift ist bedingt formuliert: nach einem gruenen Lauf schlaegt
        nichts fehl, und sie darf das nicht nahelegen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result
    )

    $zeilen = New-Object System.Collections.Generic.List[object]

    if (-not (Test-ProfilshareVerifiziert -Result $Result)) { return $zeilen.ToArray() }

    $ueberschrift = Get-ReportUeberschrift

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['Footnote'])))

    foreach ($text in @(
            'Der Benutzereintrag auf der Freigabewurzel gewährt nur das Anhängen von Daten.'
            'Dass ein Benutzer sein eigenes Profilverzeichnis darunter öffnen kann, hängt praktisch am'
            'Privileg zum Überspringen der Durchquerungsprüfung (SeChangeNotifyPrivilege), das Windows'
            'standardmäßig allen Konten zuweist.'
            'Entzieht eine gehärtete Gruppenrichtlinie dieses Privileg auf den Sitzungshosts, brechen'
            'Profile mit einem Zugriffsfehler, der wie ein Freigabeproblem aussieht -- obwohl die ACL'
            'verifiziert ist. Die NTFS-Rechte sind dann nicht die Ursache.')) {

        $zeilen.Add((New-OperatorTextLine -Text ('  {0}' -f $text)))
    }

    return $zeilen.ToArray()
}

function Format-RedirectionsHinweis {
    <#
    .SYNOPSIS
        RDX-06: der UNC-Pfad, der als RedirXMLSourceFolder einzutragen ist --
        nur fuer eine in diesem Lauf angelegte und verifizierte Freigabe.

    .DESCRIPTION
        Ein Ziel qualifiziert nur, wenn es die Ordnerart FSLogix-Redirections
        hat, einen Satz der Stufe Share mit Zustand ungleich Error UND einen
        Satz der Stufe ShareVerify mit Zustand OK. Ein Hinweis auf einen
        kaputten Pfad fuehrte in eine Fehlkonfiguration aller Sitzungshosts.
        Weg 3 hat keine Freigabestufe, der reine Pruefbericht keinen
        Share-Satz -- beide zeigen den Hinweis nie.

        Die Belegzeile steht nur, wenn Test-MitBeleg wahr ist UND jeder Wert
        aus Desired.Aces[].Status, Desired.ProtectInheritanceStatus und der
        Provenance des ShareVerify-Satzes Derived lautet -- die Kennzeichnung
        kommt aus den Daten, nicht aus einer Behauptung. Im Buendel entfaellt
        sie.

        Keine Zeile traegt eine Statusmarke; Schwere None.

    .PARAMETER ServerName
        Der Servername; leer erscheint als <Server>.

    .OUTPUTS
        Sammlung von Zeilensaetzen; leer, wenn kein Ziel qualifiziert.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string] $ServerName = ''
    )

    $saetze = @(@($Result) | Where-Object { $null -ne $_ })
    $server = if ([string]::IsNullOrWhiteSpace($ServerName)) { '<Server>' } else { $ServerName.Trim() }

    $uncZeilen = New-Object System.Collections.Generic.List[object]
    $anzahlBelegt = -1

    foreach ($ziel in @(@($Target) | Where-Object { $null -ne $_ })) {

        if (-not [string]::Equals([string] $ziel.Kind, 'FSLogix-Redirections', [System.StringComparison]::Ordinal)) { continue }

        $eigene = @(Get-TargetResult -Result $saetze -Target $ziel)

        $freigabe = @($eigene | Where-Object {
                ([string] $_.Stage -ceq 'Share') -and ([string] $_.Status -cne 'Error')
            })
        $pruefung = @($eigene | Where-Object {
                ([string] $_.Stage -ceq 'ShareVerify') -and ([string] $_.Status -ceq 'OK')
            })

        if (($freigabe.Count -eq 0) -or ($pruefung.Count -eq 0)) { continue }

        $uncZeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                        '  RedirXMLSourceFolder = \\{0}\{1}' -f $server, ([string] $ziel.ShareName).Trim()))))

        if ((Test-MitBeleg) -and ($anzahlBelegt -lt 0)) {

            $werte = New-Object System.Collections.Generic.List[string]
            $aces = @()

            $soll = $null
            if ($null -ne $ziel.PSObject.Properties['Desired']) { $soll = $ziel.Desired }

            if ($null -ne $soll) {
                if ($null -ne $soll.PSObject.Properties['Aces']) { $aces = @(@($soll.Aces) | Where-Object { $null -ne $_ }) }
                foreach ($ace in $aces) { $werte.Add((Get-BefundFeld -Befund $ace -Name 'Status')) }
                $werte.Add((Get-BefundFeld -Befund $soll -Name 'ProtectInheritanceStatus'))
            }

            $werte.Add((Get-BefundFeld -Befund $pruefung[0] -Name 'Provenance'))

            $alleAbgeleitet = ($aces.Count -gt 0)
            foreach ($wert in $werte) {
                if (-not [string]::Equals($wert, 'Derived', [System.StringComparison]::Ordinal)) { $alleAbgeleitet = $false }
            }

            if ($alleAbgeleitet) { $anzahlBelegt = $aces.Count }
        }
    }

    $zeilen = New-Object System.Collections.Generic.List[object]

    if ($uncZeilen.Count -eq 0) { return $zeilen.ToArray() }

    $ueberschrift = Get-ReportUeberschrift

    $zeilen.Add((New-OperatorTextLine -Text ''))
    $zeilen.Add((New-OperatorTextLine -Text ([string] $ueberschrift['Redirections'])))
    foreach ($zeile in $uncZeilen) { $zeilen.Add($zeile) }
    $zeilen.Add((New-OperatorTextLine -Text '  Die Datei redirections.xml legen Sie selbst in dieser Ablage ab.'))

    if ($anzahlBelegt -ge 0) {
        $zeilen.Add((New-OperatorTextLine -Text (ConvertTo-Einzeiler -Wert (
                        '  {0} Alle {1} NTFS-Einträge und das Freigabe-Soll -- Microsoft veröffentlicht für diese Ablage keine Rechtetabelle.' -f
                        (Get-ProvenienzBadge -Provenance 'Derived'), $anzahlBelegt))))
    }

    return $zeilen.ToArray()
}

function Test-ProfilshareVerifiziert {
    <#
    .SYNOPSIS
        Wahr, wenn mindestens ein Profilshare eine gruene ACL-Verifikation
        traegt. Intern zu Format-Fussnote.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result
    )

    foreach ($satz in @($Result)) {

        if ($null -eq $satz) { continue }
        if ([string] $satz.Stage -cne 'AclVerify') { continue }
        if ([string] $satz.Status -cne 'OK') { continue }

        $art = [string] $satz.Kind

        if ($art -ceq 'FSLogix-Profiles' -or $art -ceq 'DEMProfiles') { return $true }
    }

    return $false
}

function ConvertTo-Einzeiler {
    <#
    .SYNOPSIS
        Faltet jeden Leerraumlauf HINTER dem Einzug auf ein einzelnes
        Leerzeichen. Intern zu den Formatierern.

    .DESCRIPTION
        OUT-04 Regel 3 und 4 sind Zusagen ueber das Feld Text, aber ein Teil
        dieses Textes stammt aus DATEN: Meldungen, Quellenangaben und
        Abschnittszitate der Templatedatei. Ein Zeilenumbruch oder ein
        Doppelleerzeichen von dort brauchte die Zusage, ohne dass irgendjemand
        eine Formatierung geaendert haette.

        Der fuehrende Einzug bleibt unangetastet -- er IST die Aussage.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Wert
    )

    $einzug = [regex]::Match($Wert, '^ *').Value
    $rest = $Wert.Substring($einzug.Length)

    return ($einzug + ([regex]::Replace($rest, '\s+', ' ')).TrimEnd())
}

function Get-ProvisioningExitCode {
    <#
    .SYNOPSIS
        D-16: der Rueckgabewert des Gesamtlaufs.

    .DESCRIPTION
        0 nur bei durchweg OK. 1 bei mindestens einer Warnung ohne Fehler, 2 bei
        mindestens einem Fehler, 3 wenn nicht bestaetigt wurde.

        Eine Warnung ist hier oft ein Sicherheitsbefund -- drohende Aussperrung,
        belegter Freigabename -- und darf nicht als Erfolg durchgehen. Genau
        deshalb hat sie einen eigenen Wert.

    .PARAMETER NothingSelected
        Es wurde keine Ordnerart gewaehlt. Das ist eine bewusste Entscheidung
        des Operators, nichts zu tun, und kein verweigerte Bestaetigung --
        deshalb 0 und nicht 3. Ohne diesen Schalter waere der leere Lauf vom
        abgelehnten Lauf nicht zu unterscheiden.

    .PARAMETER Blocked
        Das Preflight hat den gesamten Lauf gesperrt; die Bestaetigungsfrage
        wurde gar nicht erst gestellt. Das ist ein Fehler und keine Ablehnung --
        deshalb 2 und nicht 3.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter()]
        [bool] $Confirmed = $false,

        [Parameter()]
        [switch] $NothingSelected,

        [Parameter()]
        [switch] $Blocked
    )

    if ($NothingSelected) { return 0 }

    if ($Blocked) { return 2 }

    if (-not $Confirmed) { return 3 }

    $status = Get-SchwersterStatus -Result $Result

    if ([string]::Equals($status, 'Error', [System.StringComparison]::Ordinal)) { return 2 }
    if ([string]::Equals($status, 'Warning', [System.StringComparison]::Ordinal)) { return 1 }

    return 0
}

function Get-SchwersterStatus {
    <#
    .SYNOPSIS
        Der schwerste Zustand einer Ergebnissammlung. Intern zu den
        Formatierern.

    .DESCRIPTION
        Fehler schlaegt Warnung schlaegt OK. Eine leere Sammlung ist OK -- es
        gibt nichts zu melden.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result
    )

    $status = 'OK'

    foreach ($satz in @($Result)) {

        if ($null -eq $satz) { continue }

        $wert = [string] $satz.Status

        if ([string]::Equals($wert, 'Error', [System.StringComparison]::Ordinal)) { return 'Error' }
        if ([string]::Equals($wert, 'Warning', [System.StringComparison]::Ordinal)) { $status = 'Warning' }
    }

    return $status
}

function Get-StatusMarkierung {
    <#
    .SYNOPSIS
        Die Textmarkierung eines Zustands (OUT-02, D-14). Intern zu den
        Formatierern.

    .DESCRIPTION
        Immer da, ohne Farbe vollstaendig. Ein Ergebnis, das nur an der Farbe
        erkennbar waere, verschwindet in jeder umgeleiteten Ausgabe und in jedem
        Protokoll.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Status
    )

    if ([string]::Equals($Status, 'Error', [System.StringComparison]::Ordinal)) { return '[FEHLER]' }
    if ([string]::Equals($Status, 'Warning', [System.StringComparison]::Ordinal)) { return '[WARNUNG]' }

    return '[OK]'
}

function Get-StatusZeichen {
    <#
    .SYNOPSIS
        Haken, Ausrufezeichen oder Kreuz zu einem Zustand (OUT-02, D-14).
        Intern zu den Formatierern.

    .DESCRIPTION
        DIE VORAB ERHOBENE KAPAZITAET ENTSCHEIDET, KEIN AUSNAHMEZWEIG. Die
        Konsole eines deutschen Servers laeuft haeufig mit einer Codepage, die
        das Unicode-Hakenzeichen als Fragezeichen ausgibt; dann steht hier die
        reine Textform. Ein Rueckfall im catch-Block wuerde selten gefahren und
        veraltete still -- und OUT-03 haengt daran.

        Fehlt die Kapazitaet, gilt die Textform. Die vorsichtige Annahme ist
        hier die richtige: eine Textform auf einer Unicode-Konsole ist lesbar,
        ein Fragezeichen auf einer Codepage-Konsole nicht.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    $unicode = $false

    if ($null -ne $Capability -and $null -ne $Capability.PSObject.Properties['SupportsUnicode']) {
        $unicode = [bool] $Capability.SupportsUnicode
    }

    # Die Zeichen ueber ihren Codepunkt und nicht als Quelltextliteral: so
    # haengt die Ausgabe nicht daran, mit welcher Kodierung diese Datei zufaellig
    # gelesen wurde.
    if ([string]::Equals($Status, 'Error', [System.StringComparison]::Ordinal)) {
        if ($unicode) { return [string] [char] 0x2717 }
        return '[x]'
    }

    if ([string]::Equals($Status, 'Warning', [System.StringComparison]::Ordinal)) {
        if ($unicode) { return [string] [char] 0x26A0 }
        return '[!]'
    }

    if ($unicode) { return [string] [char] 0x2713 }

    return '[v]'
}

function Get-LineSeverity {
    <#
    .SYNOPSIS
        Uebersetzt einen Ergebniszustand in die Schwere eines Zeilensatzes.
        Intern zu den Formatierern.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Status
    )

    if ([string]::Equals($Status, 'Error', [System.StringComparison]::Ordinal)) { return 'Error' }
    if ([string]::Equals($Status, 'Warning', [System.StringComparison]::Ordinal)) { return 'Warning' }

    return 'OK'
}

function Format-Aufzaehlung {
    <#
    .SYNOPSIS
        Eine Liste als Text, oder das Wort fuer "keine". Intern zu den
        Formatierern.

    .DESCRIPTION
        Eine leere Zeile an dieser Stelle waere mehrdeutig: sie saehe aus wie
        ein Darstellungsfehler statt wie die Aussage "keine".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Wert
    )

    $werte = @(@($Wert) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) })

    if ($werte.Count -eq 0) { return '(keine)' }

    return (($werte | ForEach-Object { [string] $_ }) -join ', ')
}
