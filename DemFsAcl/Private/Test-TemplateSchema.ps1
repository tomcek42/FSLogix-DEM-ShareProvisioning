function Test-TemplateSchema {
    <#
    .SYNOPSIS
        Prüft ein geladenes ACL-Template gegen den vollständigen Regelsatz und
        liefert eine Befundliste.

    .DESCRIPTION
        Sammelt ALLE Befunde und wirft nicht. Die Templatedatei wird von einem
        Menschen aus vier Herstellertabellen abgeschrieben; fail-fast erzwänge
        für sieben Tippfehler sieben Editier-Lauf-Zyklen.

        Nach außen bleibt das Verhalten trotzdem abweisend: Get-AclTemplate
        wirft bei nicht leerer Befundliste. Ein Befund, der nur gemeldet wird,
        macht aus SPEC-07 eine Protokollzeile.

        Die Rückgabe ist eine möglicherweise leere Liste. Der AUFRUFER wickelt
        sie in @(...) ein, bevor er .Count liest -- PowerShell entrollt eine
        leere Liste zu nichts, und $null.Count ist unter Set-StrictMode
        -Version Latest ein Fehler.

    .OUTPUTS
        [string[]] -- je Befund eine deutschsprachige Zeile, die die
        Ordnerart und den ACE-Index nennt.
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

    $wellKnownTokens = @(
        'WellKnown:CreatorOwner'
        'WellKnown:System'
        'WellKnown:BuiltinAdmins'
        'WellKnown:BuiltinUsers'
        'WellKnown:AuthenticatedUsers'
        'WellKnown:WorldEveryone'
    )

    $platzhalterTokens = @('<AdminGroup>', '<UserGroup>', '<ComputerGroup>', '<HelpdeskGroup>')

    # Die Verwaltungsklasse der Isolationsregel. Ein vererbbarer ACE ist nur
    # für diese vier Trustees unbedenklich.
    $verwaltungsTokens = @(
        '<AdminGroup>'
        'WellKnown:BuiltinAdmins'
        'WellKnown:System'
        'WellKnown:CreatorOwner'
    )

    # Die Belegfelder sind nur Pflicht, wo das Soll Belege fuehrt (Modul);
    # das Einzeldatei-Buendel laesst sie weg.
    $belegfelder = @('Status', 'Source', 'Section')
    $mitBeleg = Test-MitBeleg
    $pflichtfelder = @('Trustee', 'Rights', 'Inheritance', 'Propagation', 'Type')
    if ($mitBeleg) { $pflichtfelder += $belegfelder }

    # Lokal statt als eigene Funktion: die Modul-Exportfläche und der
    # Funktionsbestand dieser Phase sind ein Vertrag, an den die Phasen 2 bis 8
    # binden. Ein stiller Zusatzname gehört da nicht hinein.
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
        # Der Schlüsselzugriff in einer geladenen .psd1 ist case-insensitiv.
        # Die Schreibweise muss trotzdem exakt stimmen, damit die Datei gegen
        # die Herstellerdoku diffbar bleibt.
        $befunde.Add(('{0} Kind "{1}" ist zeichengenau keiner der bekannten Literalnamen.' -f
            $marke, $Template['Kind']))
    }
    elseif ([string] $Template['Kind'] -cne $Kind) {
        # Dieser Zweig steht NACH dem Abgleich gegen die bekannten
        # Literalnamen: ein völlig fremder Wert soll die präzisere Auskunft
        # bekommen, dass er keiner davon ist, statt bloß einen Widerspruch zu
        # melden.
        #
        # Warum die Ordnerart in der Datendatei doppelt steht -- einmal als
        # Hashtable-Schlüssel, einmal als Feld: nur eine zweite, unabhängige
        # Angabe kann die erste widerlegen. Genau diese Redundanz IST die
        # Prüfung. Ohne den Abgleich passierte ein Zahlendreher in der
        # handabgeschriebenen Datei das Gate lautlos, und die Phasen 2 bis 8
        # bänden Pfad an Template über ein Feld, das nie jemand geprüft hat --
        # das Soll des einen Herstellers läge dann auf der Freigabe des
        # anderen.
        #
        # Case-sensitiv aus demselben Grund wie der Literalnamen-Abgleich
        # darüber: der Schlüsselzugriff einer geladenen .psd1 ist
        # case-insensitiv, die Datei muss trotzdem gegen die Herstellerdoku
        # diffbar bleiben.
        $befunde.Add(('{0} Kind "{1}" widerspricht der angefragten Ordnerart "{2}" -- Hashtable-Schlüssel und Kind-Feld müssen dieselbe Ordnerart nennen.' -f
            $marke, $Template['Kind'], $Kind))
    }

    if (-not $Template.ContainsKey('ProtectInheritance')) {
        $befunde.Add(('{0} Pflichtfeld "ProtectInheritance" fehlt.' -f $marke))
    }
    elseif ($Template['ProtectInheritance'] -ne $true) {
        $befunde.Add(('{0} ProtectInheritance ist nicht True -- SPEC-03 verlangt den abgeschalteten und entfernten Vererbungsschutz auf der Wurzel.' -f $marke))
    }

    if (-not $mitBeleg) {
        # Ohne Belege gibt es auf Wurzelebene nichts zu pruefen.
    }
    elseif (-not (& $istGefuellt $Template 'ProtectInheritanceStatus')) {
        $befunde.Add(('{0} Pflichtfeld "ProtectInheritanceStatus" fehlt oder ist leer.' -f $marke))
    }
    elseif ($gueltigerStatus -cnotcontains [string] $Template['ProtectInheritanceStatus']) {
        $befunde.Add(('{0} ProtectInheritanceStatus "{1}" ist weder "Verified" noch "Derived".' -f
            $marke, $Template['ProtectInheritanceStatus']))
    }

    foreach ($provenienzfeld in @(if ($mitBeleg) { 'ProtectInheritanceSource', 'ProtectInheritanceSection' })) {
        if (-not (& $istGefuellt $Template $provenienzfeld)) {
            $befunde.Add(('{0} Pflichtfeld "{1}" fehlt oder ist leer.' -f $marke, $provenienzfeld))
        }
    }

    $aces = @()

    if (-not $Template.ContainsKey('Aces')) {
        $befunde.Add(('{0} Pflichtfeld "Aces" fehlt.' -f $marke))
    }
    elseif ($Template['Aces'] -isnot [array]) {
        # Nur die Array-Reihenfolge überlebt Import-PowerShellDataFile; die
        # Schlüsselreihenfolge einer Hashtable tut es nachweislich nicht.
        $befunde.Add(('{0} Aces ist kein Array -- nur ein Array hält die ACE-Reihenfolge.' -f $marke))
    }
    elseif (@($Template['Aces']).Count -eq 0) {
        $befunde.Add(('{0} Aces ist leer -- ein Template ohne ACE beschreibt kein Soll (SPEC-01).' -f $marke))
    }
    else {
        $aces = @($Template['Aces'])
    }

    # --------------------------------------------------------------- Je ACE

    for ($i = 0; $i -lt $aces.Count; $i++) {

        $ace = $aces[$i]
        $ort = '{0} ACE #{1} :' -f $marke, ($i + 1)

        if ($ace -isnot [hashtable]) {
            $befunde.Add(('{0} Eintrag ist keine Hashtable.' -f $ort))
            continue
        }

        $fehlend = @()

        foreach ($feld in $pflichtfelder) {
            if (-not (& $istGefuellt $ace $feld)) {
                $befunde.Add(('{0} Pflichtfeld "{1}" fehlt oder ist leer.' -f $ort, $feld))
                $fehlend += $feld
            }
        }

        # Ohne Belege gelten die Belegfelder als abwesend: keine Folgepruefung.
        if (-not $mitBeleg) { $fehlend += $belegfelder }

        if ($fehlend -notcontains 'Status') {
            if ($gueltigerStatus -cnotcontains [string] $ace['Status']) {
                $befunde.Add(('{0} Status "{1}" ist weder "Verified" noch "Derived".' -f
                    $ort, $ace['Status']))
            }
        }

        if ($fehlend -notcontains 'Type') {
            if ([string] $ace['Type'] -cne 'Allow') {
                # Deny wertet vor Allow aus und ist die klassische Ursache
                # unwiederbringlicher Aussperrungen. Keines der drei
                # Herstellerdokumente nennt einen.
                $befunde.Add(('{0} Type "{1}" -- nur "Allow" ist zulässig, Deny ist projektweit verboten.' -f
                    $ort, $ace['Type']))
            }
        }

        if ($fehlend -notcontains 'Trustee') {

            $trustee = [string] $ace['Trustee']

            if ($trustee -ceq 'WellKnown:WorldEveryone') {
                $befunde.Add(('{0} Trustee "WellKnown:WorldEveryone" gehört nicht in ein NTFS-Template -- dieses Token ist ausschließlich auf Freigabeebene vorgesehen.' -f $ort))
            }
            elseif (($wellKnownTokens -cnotcontains $trustee) -and ($platzhalterTokens -cnotcontains $trustee)) {
                $befunde.Add(('{0} Trustee "{1}" entspricht nicht der Tokengrammatik.' -f $ort, $trustee))
            }
        }

        # Numerische Werte werden aktiv abgelehnt, BEVOR gecastet wird. Ein
        # Wert wie 197055 castet klaglos zu "Modify, Synchronize" -- ein
        # Zahlendreher in einer Maske fiele am Cast also nicht auf. Das
        # Template soll ohnehin die Herstellervokabel führen.
        $enumPruefungen = @(
            @{ Feld = 'Rights';      Typ = [System.Security.AccessControl.FileSystemRights] }
            @{ Feld = 'Inheritance'; Typ = [System.Security.AccessControl.InheritanceFlags] }
            @{ Feld = 'Propagation'; Typ = [System.Security.AccessControl.PropagationFlags] }
        )

        foreach ($pruefung in $enumPruefungen) {

            $feld = $pruefung['Feld']
            if ($fehlend -contains $feld) { continue }

            $wert = [string] $ace[$feld]

            if ($wert -match '^\s*(0[xX][0-9a-fA-F]+|\d+)\s*$') {
                $befunde.Add(('{0} {1} "{2}" ist numerisch; nur benannte Werte sind erlaubt.' -f
                    $ort, $feld, $wert))
                continue
            }

            try {
                # Case-sensitiv: die Schreibweise soll gegen die Doku diffbar bleiben.
                $null = [System.Enum]::Parse($pruefung['Typ'], $wert, $false)
            }
            catch {
                $befunde.Add(('{0} {1} "{2}" ist kein gültiger {3}-Wert.' -f
                    $ort, $feld, $wert, $pruefung['Typ'].Name))
            }
        }

        if (($fehlend -notcontains 'Inheritance') -and ($fehlend -notcontains 'Propagation')) {
            if (([string] $ace['Inheritance'] -ceq 'None') -and ([string] $ace['Propagation'] -cne 'None')) {
                # Der FileSystemAccessRule-Konstruktor normalisiert diese
                # Kombination still auf prop=0. Der Eintrag wäre wirkungslos
                # und liefe trotzdem grün durch -- nur das Schema fängt das.
                $befunde.Add(('{0} Propagation "{1}" bei Inheritance "None" -- .NET verwirft diese Kombination still.' -f
                    $ort, $ace['Propagation']))
            }
        }

        if ($fehlend -notcontains 'Source') {

            $quelle = [string] $ace['Source']

            if (-not ($quelle.StartsWith('http://', [System.StringComparison]::Ordinal) -or
                      $quelle.StartsWith('https://', [System.StringComparison]::Ordinal))) {
                $befunde.Add(('{0} Source "{1}" ist keine URL -- ein Quellenfeld mit Fließtext ist kein Beleg.' -f
                    $ort, $quelle))
            }
        }

        $istOptional = $false

        if ($ace.ContainsKey('Optional')) {
            if ($ace['Optional'] -isnot [bool]) {
                $befunde.Add(('{0} Optional ist kein boolescher Wert.' -f $ort))
            }
            else {
                $istOptional = [bool] $ace['Optional']
            }
        }

        if ($istOptional) {
            if (-not (& $istGefuellt $ace 'OptGroup')) {
                $befunde.Add(('{0} Optional ist True, aber OptGroup fehlt oder ist leer.' -f $ort))
            }
        }
        elseif ($ace.ContainsKey('OptGroup')) {
            $befunde.Add(('{0} OptGroup ist gesetzt, obwohl Optional fehlt oder False ist -- die Gruppe würde nie ausgewertet.' -f $ort))
        }
    }

    # ------------------------------------------------------------- Semantik

    # Wörtlich aus FEATURES.md, Abschnitt 1.5, Punkt 2: enthält das Template
    # einen ACE auf S-1-3-0, darf kein ACE außerhalb der Verwaltungsklasse
    # vererbbar sein. Das ist der maschinell prüfbare Ausdruck der
    # Isolationszusage -- ein vererbbarer Benutzer-ACE auf einem Profilshare
    # ließe jeden jedes Profil lesen.

    $hatCreatorOwner = $false

    foreach ($ace in $aces) {
        if (($ace -is [hashtable]) -and ([string] $ace['Trustee'] -ceq 'WellKnown:CreatorOwner')) {
            $hatCreatorOwner = $true
        }
    }

    if ($hatCreatorOwner) {

        for ($i = 0; $i -lt $aces.Count; $i++) {

            $ace = $aces[$i]
            if ($ace -isnot [hashtable]) { continue }

            $trustee = [string] $ace['Trustee']
            if ($verwaltungsTokens -ccontains $trustee) { continue }

            $vererbung = [string] $ace['Inheritance']
            if ([string]::IsNullOrWhiteSpace($vererbung)) { continue }

            if ($vererbung -cne 'None') {
                $befunde.Add(('{0} ACE #{1} : Trustee "{2}" ist vererbbar (Inheritance "{3}"), obwohl das Template WellKnown:CreatorOwner führt -- das verletzt die Isolationsregel.' -f
                    $marke, ($i + 1), $trustee, $vererbung))
            }
        }
    }

    return $befunde.ToArray()
}
