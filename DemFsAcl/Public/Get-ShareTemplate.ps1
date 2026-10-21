function Get-ShareTemplate {
    <#
    .SYNOPSIS
        Laedt das Share-Template zur genannten Ordnerart, validiert es und
        wirft bei Schemabefunden.

    .DESCRIPTION
        Der einzige unterstuetzte Weg zu einem Share-Template. Die Datendatei
        direkt zu laden umgeht die Schemapruefung und damit SHARE-01.

        "Abgewiesen" heisst geworfen und nicht gemeldet -- dieselbe Bauform wie
        bei Get-AclTemplate: ein Aufrufer, der eine zurueckgegebene Befundliste
        ignoriert, macht aus einer Sicherheitspruefung eine Protokollzeile.

        Die Funktion gibt zurueck oder wirft. Kein Write-Host, kein Read-Host;
        die Ausgabe an den Bediener entsteht ausschliesslich in der
        Orchestrierung (C-10, C-12).

        -Kind traegt denselben Doppelvertrag wie bei Get-AclTemplate: es ist
        Nachschlagschluessel UND Sollwert der Gegenprobe gegen das Kind-Feld des
        geladenen Templates. Erst die zweite, unabhaengige Angabe macht einen
        Zahlendreher in der handabgeschriebenen Datei ueberhaupt sichtbar.

    .PARAMETER Kind
        Die angefragte Ordnerart. Dieselben Literalnamen wie bei
        Get-AclTemplate -- das Werkzeug kennt genau eine Ordnerartenliste.

    .OUTPUTS
        [hashtable] -- das validierte Share-Template.

    .EXAMPLE
        Get-ShareTemplate -Kind 'DEMConfig'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind
    )

    $alle = Get-DataTable -Name 'ShareTemplates'

    if (-not $alle.ContainsKey($Kind)) {
        throw [System.InvalidOperationException]::new(
            ('Die Ordnerart "{0}" fehlt in den Share-Templates.' -f $Kind))
    }

    $template = $alle[$Kind]

    # Die Klammerform ist Pflicht und kein Stil: der Validator liefert bei null
    # Befunden nichts, und Set-StrictMode -Version Latest macht .Count auf einer
    # leeren Rueckgabe zu einem Fehler.
    $befunde = @(Test-ShareTemplateSchema -Template $template -Kind $Kind)

    if ($befunde.Count -gt 0) {

        $meldung = ('Das Share-Template "{0}" wurde abgewiesen -- {1} Schemabefund(e):{2}{3}' -f
            $Kind,
            $befunde.Count,
            [System.Environment]::NewLine,
            ($befunde -join [System.Environment]::NewLine))

        throw [System.InvalidOperationException]::new($meldung)
    }

    return $template
}

function Test-ShareTemplateSchema {
    <#
    .SYNOPSIS
        Prueft ein geladenes Share-Template gegen den Regelsatz und liefert eine
        Befundliste. Intern zu Get-ShareTemplate.

    .DESCRIPTION
        Sammelt ALLE Befunde und wirft nicht -- dieselbe Begruendung wie bei
        Test-TemplateSchema: die Datei wird von einem Menschen aus
        Herstellertabellen abgeschrieben, und fail-fast erzwaenge fuer sieben
        Tippfehler sieben Editier-Lauf-Zyklen. Nach aussen bleibt das Verhalten
        abweisend, weil Get-ShareTemplate bei nicht leerer Befundliste wirft.

        WARUM EIN EIGENER VALIDATOR UND NICHT Test-TemplateSchema: die beiden
        Schemata haben kein Feld gemeinsam ausser Trustee, Status, Source und
        Section. Ein Validator mit zwei Bedeutungen muesste verzweigen, welche
        Haelfte er gerade prueft -- und prueft dann beide schlechter.

        In derselben Datei wie der Lader und nicht daneben: das Schema ist
        deutlich kleiner als das der ACL-Templates, und eine eigene Datei dafuer
        waere Zeremonie. Vorbild fuer zwei Funktionen in einer Datei ist
        Compare-AceSet.ps1.

    .OUTPUTS
        [string[]] -- je Befund eine deutschsprachige Zeile mit Ordnerart und
        Eintragsindex.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Template,

        [Parameter(Mandatory)]
        [string] $Kind
    )

    $befunde = New-Object System.Collections.Generic.List[string]

    $gueltigeOrdnerarten = @('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')
    $gueltigerStatus = @('Verified', 'Derived')

    # Genau drei Rechtestufen. Das ist die vollstaendige Vokabel der
    # SMB-Freigabeebene -- mehr gibt es dort nicht, und ein vierter Wert waere
    # ein Tippfehler und keine Erweiterung.
    $gueltigerAccess = @('Read', 'Change', 'Full')

    $wellKnownTokens = @(
        'WellKnown:CreatorOwner'
        'WellKnown:System'
        'WellKnown:BuiltinAdmins'
        'WellKnown:BuiltinUsers'
        'WellKnown:AuthenticatedUsers'
        'WellKnown:WorldEveryone'
    )

    $platzhalterTokens = @('<AdminGroup>', '<UserGroup>', '<ComputerGroup>', '<HelpdeskGroup>')

    # Die Belegfelder sind nur Pflicht, wo das Soll Belege fuehrt (Modul);
    # das Einzeldatei-Buendel laesst sie weg.
    $belegfelder = @('Status', 'Source', 'Section')
    $mitBeleg = Test-MitBeleg
    $pflichtfelder = @('Trustee', 'Access')
    if ($mitBeleg) { $pflichtfelder += $belegfelder }

    # Lokal statt als eigene Funktion -- dieselbe Begruendung wie in
    # Test-TemplateSchema: die Exportflaeche und der Funktionsbestand sind ein
    # Vertrag, in den kein stiller Zusatzname gehoert.
    $istGefuellt = {
        param($Behaelter, [string] $Feld)

        if (-not $Behaelter.ContainsKey($Feld)) { return $false }

        $wert = $Behaelter[$Feld]
        if ($null -eq $wert) { return $false }
        if ($wert -is [string]) { return (-not [string]::IsNullOrWhiteSpace($wert)) }

        return $true
    }

    $marke = '[{0}]' -f $Kind

    # ---------------------------------------------------------------- Template

    if (-not (& $istGefuellt $Template 'Kind')) {
        $befunde.Add(('{0} Pflichtfeld "Kind" fehlt oder ist leer.' -f $marke))
    }
    elseif ($gueltigeOrdnerarten -cnotcontains [string] $Template['Kind']) {
        # Der Schluesselzugriff in einer geladenen .psd1 ist case-insensitiv.
        # Die Schreibweise muss trotzdem exakt stimmen, damit die Datei gegen
        # die Herstellerdoku diffbar bleibt.
        $befunde.Add(('{0} Kind "{1}" ist zeichengenau keiner der bekannten Literalnamen.' -f
            $marke, $Template['Kind']))
    }
    elseif ([string] $Template['Kind'] -cne $Kind) {
        $befunde.Add(('{0} Kind "{1}" widerspricht der angefragten Ordnerart "{2}" -- Hashtable-Schlüssel und Kind-Feld müssen dieselbe Ordnerart nennen.' -f
            $marke, $Template['Kind'], $Kind))
    }

    $eintraege = @()

    if (-not $Template.ContainsKey('Entries')) {
        $befunde.Add(('{0} Pflichtfeld "Entries" fehlt.' -f $marke))
    }
    elseif ($Template['Entries'] -isnot [array]) {
        # Nur die Array-Reihenfolge ueberlebt Import-PowerShellDataFile; die
        # Schluesselreihenfolge einer Hashtable tut es nachweislich nicht.
        $befunde.Add(('{0} Entries ist kein Array -- nur ein Array hält die Eintragsreihenfolge.' -f $marke))
    }
    elseif (@($Template['Entries']).Count -eq 0) {
        $befunde.Add(('{0} Entries ist leer -- ein Share-Template ohne Eintrag beschreibt kein Soll (SHARE-01).' -f $marke))
    }
    else {
        $eintraege = @($Template['Entries'])
    }

    # -------------------------------------------------------------- Je Eintrag

    for ($i = 0; $i -lt $eintraege.Count; $i++) {

        $eintrag = $eintraege[$i]
        $ort = '{0} Eintrag #{1} :' -f $marke, ($i + 1)

        if ($eintrag -isnot [hashtable]) {
            $befunde.Add(('{0} Eintrag ist keine Hashtable.' -f $ort))
            continue
        }

        $fehlend = @()

        foreach ($feld in $pflichtfelder) {
            if (-not (& $istGefuellt $eintrag $feld)) {
                $befunde.Add(('{0} Pflichtfeld "{1}" fehlt oder ist leer.' -f $ort, $feld))
                $fehlend += $feld
            }
        }

        # Ohne Belege gelten die Belegfelder als abwesend: keine Folgepruefung.
        if (-not $mitBeleg) { $fehlend += $belegfelder }

        if ($fehlend -notcontains 'Access') {
            if ($gueltigerAccess -cnotcontains [string] $eintrag['Access']) {
                $befunde.Add(('{0} Access "{1}" ist keiner der drei Werte "Read", "Change" oder "Full".' -f
                    $ort, $eintrag['Access']))
            }
        }

        if ($fehlend -notcontains 'Status') {
            if ($gueltigerStatus -cnotcontains [string] $eintrag['Status']) {
                $befunde.Add(('{0} Status "{1}" ist weder "Verified" noch "Derived".' -f
                    $ort, $eintrag['Status']))
            }
        }

        if ($fehlend -notcontains 'Trustee') {

            $trustee = [string] $eintrag['Trustee']

            if (($wellKnownTokens -cnotcontains $trustee) -and ($platzhalterTokens -cnotcontains $trustee)) {
                $befunde.Add(('{0} Trustee "{1}" entspricht nicht der Tokengrammatik.' -f $ort, $trustee))
            }

            # Die Welt-SID darf auf Freigabeebene erscheinen, aber niemals mit
            # Vollzugriff: keines der drei Herstellerdokumente gibt das vor, und
            # die Kombination hebelte die Zugriffssteuerung auf NTFS-Ebene aus.
            # Strukturell abgewiesen statt nur in einem Test bemerkt -- ein
            # Datenfehler soll am Lader scheitern, nicht auf dem Fileserver.
            if (($trustee -ceq 'WellKnown:WorldEveryone') -and
                ($fehlend -notcontains 'Access') -and
                ([string] $eintrag['Access'] -ceq 'Full')) {
                $befunde.Add(('{0} Die Welt-SID mit Access "Full" ist ausgeschlossen -- auf Freigabeebene erscheint sie ausschließlich mit "Change".' -f $ort))
            }
        }

        if ($fehlend -notcontains 'Source') {

            $quelle = [string] $eintrag['Source']

            if (-not ($quelle.StartsWith('http://', [System.StringComparison]::Ordinal) -or
                      $quelle.StartsWith('https://', [System.StringComparison]::Ordinal))) {
                $befunde.Add(('{0} Source "{1}" ist keine URL -- ein Quellenfeld mit Fließtext ist kein Beleg.' -f
                    $ort, $quelle))
            }
        }

        # Anders als bei den ACL-Templates gibt es kein getrenntes
        # Optional-Feld: ein Eintrag mit OptGroup IST der abwaehlbare Fall. Ein
        # leeres OptGroup waere dann eine Gruppe ohne Namen und nie anwaehlbar.
        if ($eintrag.ContainsKey('OptGroup')) {
            if (-not (& $istGefuellt $eintrag 'OptGroup')) {
                $befunde.Add(('{0} OptGroup ist gesetzt, aber leer -- der Eintrag wäre nie anwählbar.' -f $ort))
            }
        }
    }

    return $befunde.ToArray()
}
