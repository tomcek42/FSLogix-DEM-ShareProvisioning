<#
    Write-OperatorLine -- die EINE Ausgabenaht des Werkzeugs (OUT-02, OUT-03,
    OUT-07, D-04, D-14).

    Unterhalb dieser Datei gibt nichts aus. Die Engines liefern
    ProvisioningResult-Objekte, die Formatierer liefern Zeilensaetze; gedruckt
    wird ausschliesslich hier. Das ist der Grund, warum die zurueckgestellte
    Logdatei spaeter ein Export-Csv-Einzeiler ueber dieselbe Objektsammlung
    bleibt (OPS-01, OUT-06).

    TEXTMARKIERUNG IST DIE GRUNDFORM, FARBE KOMMT ADDITIV DAZU (D-14). Der
    Text ist ohne jede Farbe vollstaendig; die Farbe ergaenzt ihn nur. Damit
    bleibt das Ergebnis auch in einer umgeleiteten Ausgabe lesbar.

    DIE KAPAZITAET WIRD VORAB ERHOBEN UND NICHT IN EINEM catch-ZWEIG ERRATEN
    (D-14). Ein selten gefahrener Ausnahmezweig veraltet still; eine Abfrage,
    die bei jedem Lauf laeuft, tut das nicht.
#>

# Die einmal je Lauf erhobene Kapazitaet. Sie liegt hier und nicht beim
# Aufrufer, damit die Dialogfunktionen einen Hinweistext ausgeben koennen, ohne
# die Kapazitaet durch jede einzelne Signatur zu faedeln. Get-ConsoleCapability
# setzt sie; Invoke-DemFsProvisioning ruft sie genau einmal vorab.
$script:ConsoleCapability = $null

function Get-ConsoleCapability {
    <#
    .SYNOPSIS
        Erhebt EINMAL VORAB, was die Konsole dieses Laufs traegt.

    .DESCRIPTION
        SupportsColor ist falsch, wenn die Ausgabe umgeleitet ist, wenn
        NO_COLOR gesetzt ist oder wenn der Host keine Rohkonsole fuehrt.
        SupportsUnicode ist wahr, wenn die Ausgabekodierung die Codepage 65001
        fuehrt.

        Ausdruecklich KEIN Rueckfall in einem catch-Zweig: die drei Abfragen
        laufen bei jedem Lauf und koennen deshalb nicht veralten.

        SupportsStrike ist wahr, wenn Farbe getragen wird und der Host
        VT-Steuerfolgen verarbeitet -- dann erscheint ein ersetzter Eintrag in
        Weg 3 durchgestrichen (Serverlauf 2026-09-25).

        SupportsVirtualTerminal ist wahr, wenn Farbe getragen wird und der
        Host VT-Steuerfolgen verarbeitet -- dann erscheint die Schwere Error in
        hellem Rot RGB 255/110/110 statt ConsoleColor Red (G-09-3). Beide
        Felder kommen aus derselben einen Abfrage; Verbraucher sind die
        Durchstreichung (SupportsStrike) und das helle Fehlerrot
        (SupportsVirtualTerminal).

        OutputRedirected ist wahr, wenn die Ausgabe umgeleitet ist. Verbraucher
        ist die Bestaetigung in Invoke-DemFsProvisioning: unter Umleitung
        erreicht der Plan die Konsole nur noch als Teil des
        Bestaetigungsprompts (G-04-3a).

        SupportsKeyInput ist wahr, wenn dieser Lauf einzelne Tasten lesen
        kann (Test-OperatorKeyInput: weder Aus- noch Eingabe umgeleitet, echte
        Konsole). Verbraucher ist Schritt 1 von Weg 1: nur damit erscheint die
        Komponentenliste mit Pfeiltasten und Leertaste (W-09-1).

    .OUTPUTS
        [pscustomobject] mit SupportsColor, SupportsUnicode, SupportsStrike,
        SupportsVirtualTerminal, OutputRedirected und SupportsKeyInput.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $farbe = $true

    $umgeleitet = [bool] [System.Console]::IsOutputRedirected

    if ($umgeleitet) { $farbe = $false }

    if (-not [string]::IsNullOrEmpty([string] $env:NO_COLOR)) { $farbe = $false }

    if ($null -eq $Host.UI) { $farbe = $false }
    elseif ($null -eq $Host.UI.RawUI) { $farbe = $false }

    $unicode = ([int] [System.Console]::OutputEncoding.CodePage) -eq 65001

    # Die EINE Abfrage der VT-Verarbeitung; beide Felder lesen diesen Wert.
    $vt = $false
    if ($farbe -and ($null -ne $Host.UI.PSObject.Properties['SupportsVirtualTerminal'])) {
        $vt = [bool] $Host.UI.SupportsVirtualTerminal
    }

    $script:ConsoleCapability = [pscustomobject] @{
        SupportsColor           = [bool] $farbe
        SupportsUnicode         = [bool] $unicode
        SupportsStrike          = [bool] $vt
        SupportsVirtualTerminal = [bool] $vt
        OutputRedirected        = $umgeleitet
        SupportsKeyInput        = [bool] (Test-OperatorKeyInput -OutputRedirected $umgeleitet)
    }

    return $script:ConsoleCapability
}

function Get-ConsoleBufferWidth {
    <#
    .SYNOPSIS
        Die Pufferbreite der Konsole in Zeichen, oder 0. Intern zu
        Write-OperatorBlock; eigene Funktion, damit Tests sie ersetzen.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    try {
        return [int] [System.Console]::BufferWidth
    }
    catch {
        return 0
    }
}

function Clear-OperatorRows {
    <#
    .SYNOPSIS
        Leert die letzten Rows Bildschirmzeilen ohne VT und setzt den Cursor
        an deren Anfang (W-09-1). Intern zu Write-OperatorBlock.

    .DESCRIPTION
        Ueber SetCursorPosition und Zeilen aus Leerzeichen per Write-Host --
        bewusst nicht ueber einen Konsolen-Schreibaufruf, die Ausgabe bleibt
        bei Write-Host. Falsch, wenn die Breite unbekannt ist oder die
        Positionierung scheitert; dann druckt der Aufrufer schlicht neu.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [int] $Rows
    )

    $breite = Get-ConsoleBufferWidth
    if ($breite -le 0) { return $false }

    try {
        $ziel = [System.Math]::Max(0, [System.Console]::CursorTop - $Rows)
        [System.Console]::SetCursorPosition(0, $ziel)

        $leer = ''.PadRight($breite - 1)
        for ($i = 0; $i -lt $Rows; $i++) { Write-Host -Object $leer }

        [System.Console]::SetCursorPosition(0, $ziel)
        return $true
    }
    catch {
        return $false
    }
}

function Write-OperatorBlock {
    <#
    .SYNOPSIS
        Zeichnet einen Block aus Zeilensaetzen, wahlweise an Stelle des zuvor
        gezeichneten (W-09-1). Liefert die Zahl der belegten Bildschirmzeilen.

    .DESCRIPTION
        Die Zeilen selbst gehen ueber Write-OperatorLine -- Farbe, helles
        Fehlerrot und Umlautweiche laufen damit unveraendert mit.

        Ist ReplaceRows groesser 0, wird zuerst der alte Block ersetzt:
        meldet die Kapazitaet SupportsVirtualTerminal, ueber EINE VT-Folge
        (Cursor ReplaceRows Zeilen hoch an den Zeilenanfang, Rest des
        Bildschirms loeschen); sonst ueber Clear-OperatorRows
        (SetCursorPosition). Scheitert die Positionierung, wird schlicht unter
        dem alten Block neu gedruckt (V-05). Das Steuerzeichen entsteht aus
        seinem Zeichencode.

        Gezaehlt wird je Zeile max(1, aufgerundet(Textlaenge / Pufferbreite));
        bei unbekannter Breite eine Bildschirmzeile je Zeile.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Line,

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null,

        [Parameter()]
        [int] $ReplaceRows = 0
    )

    $breite = Get-ConsoleBufferWidth
    $belegt = 0

    foreach ($satz in @($Line)) {

        if ($null -eq $satz) { continue }

        $text = ''
        if ($satz -is [string]) { $text = [string] $satz }
        elseif ($null -ne $satz.PSObject.Properties['Text']) { $text = [string] $satz.Text }

        $laenge = (ConvertTo-KonsolenText -Text $text).Length

        if ($breite -le 0) { $belegt++ }
        else { $belegt += [System.Math]::Max(1, [int] [System.Math]::Ceiling($laenge / $breite)) }
    }

    $vtWeg = ($null -ne $Capability) -and
        ($null -ne $Capability.PSObject.Properties['SupportsVirtualTerminal']) -and
        [bool] $Capability.SupportsVirtualTerminal

    if ($ReplaceRows -gt 0) {
        if ($vtWeg) {
            $esc = [string] [char] 27
            Write-Host -Object ($esc + '[' + $ReplaceRows + 'F' + $esc + '[0J') -NoNewline
        }
        else {
            # Das Ergebnis entscheidet nichts weiter: bei falsch folgt der
            # Block schlicht unter dem alten (V-05).
            $null = Clear-OperatorRows -Rows $ReplaceRows
        }
    }

    Write-OperatorLine -Capability $Capability -Line @($Line)

    return [int] $belegt
}

function Write-OperatorLine {
    <#
    .SYNOPSIS
        Gibt Zeilensaetze der Formatierer aus. Die einzige Ausgabestelle des
        Moduls.

    .DESCRIPTION
        Ein Zeilensatz traegt Text und Severity. Severity steuert
        ausschliesslich die Farbe (OK gruen, Warning gelb, Error rot, Heading
        cyan, None ohne Farbangabe) und nie den Text -- die Textmarkierung
        selbst steht bereits im Feld Text.

        Meldet die Kapazitaet SupportsVirtualTerminal, erscheint Error in
        hellem Rot RGB 255/110/110 ueber eine VT-Vordergrundfolge im Text und
        ohne -ForegroundColor, unabhaengig von der Konsolenpalette (G-09-3).
        Ohne das Feld oder mit falsch bleibt es bei ConsoleColor Red; ohne
        Farbe gibt es weder Farbe noch Steuerzeichen (D-14).

        Eine blosse Zeichenkette wird als Zeile ohne Schwere behandelt. Das
        haelt die Hinweistexte des Dialogs kurz, ohne eine zweite Ausgabestelle
        zu brauchen.

        Traegt ein Zeilensatz Segments (je Abschnitt Text, Severity, Strike),
        erscheint er bei Farbe abschnittsweise gefaerbt, Strike durchgestrichen,
        sofern die Kapazitaet SupportsStrike meldet. Ohne Farbe gilt Text --
        die Verkettung der Abschnitte, vollstaendig auch ohne Farbe (D-14).

    .PARAMETER Capability
        Die vorab erhobene Kapazitaet. Fehlt sie, wird die des Laufs benutzt
        beziehungsweise einmalig erhoben.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Line,

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    if ($null -eq $Capability) {
        if ($null -eq $script:ConsoleCapability) { $null = Get-ConsoleCapability }
        $Capability = $script:ConsoleCapability
    }

    $farbig = [bool] $Capability.SupportsColor
    $vtWeg = $farbig -and ($null -ne $Capability.PSObject.Properties['SupportsVirtualTerminal']) -and [bool] $Capability.SupportsVirtualTerminal

    foreach ($satz in @($Line)) {

        if ($null -eq $satz) { continue }

        $text = ''
        $schwere = 'None'

        if ($satz -is [string]) {
            $text = [string] $satz
        }
        else {
            if ($null -ne $satz.PSObject.Properties['Text']) { $text = [string] $satz.Text }
            if ($null -ne $satz.PSObject.Properties['Severity']) { $schwere = [string] $satz.Severity }
        }

        if ([string]::IsNullOrWhiteSpace($schwere)) { $schwere = 'None' }

        $abschnitte = @()
        if (($satz -isnot [string]) -and ($null -ne $satz.PSObject.Properties['Segments']) -and ($null -ne $satz.Segments)) {
            $abschnitte = @($satz.Segments | Where-Object { $null -ne $_ })
        }

        if ($farbig -and ($abschnitte.Count -gt 0)) {
            Write-OperatorSegment -Segment $abschnitte -Capability $Capability
            continue
        }

        $farbe = Get-SeverityColor -Severity $schwere
        $text = ConvertTo-KonsolenText -Text $text

        $vtFarbe = ''
        if ($vtWeg) { $vtFarbe = Get-SeverityVtColor -Severity $schwere }

        if (-not [string]::IsNullOrEmpty($vtFarbe) -and -not [string]::IsNullOrEmpty($text)) {
            # ESC[39m setzt nur die Vordergrundfarbe zurueck.
            Write-Host -Object ($vtFarbe + $text + [string] [char] 27 + '[39m')
        }
        elseif ($farbig -and -not [string]::IsNullOrEmpty($farbe)) {
            Write-Host -Object $text -ForegroundColor $farbe
        }
        else {
            Write-Host -Object $text
        }
    }
}

function Write-OperatorSegment {
    <#
    .SYNOPSIS
        Gibt eine Zeile abschnittsweise farbig aus. Intern zu
        Write-OperatorLine -- die Ausgabenaht bleibt diese Datei.

    .DESCRIPTION
        Durchgestrichen wird ueber die VT-Folgen ESC[9m und ESC[29m, nur wenn
        die Kapazitaet SupportsStrike meldet; sonst bleibt der Abschnitt nur
        gefaerbt. Das Steuerzeichen entsteht aus seinem Zeichencode.

        Meldet die Kapazitaet SupportsVirtualTerminal, erscheint ein
        Error-Abschnitt in hellem Rot RGB 255/110/110 (G-09-3): die
        Farbfolge umhuellt den gegebenenfalls schon durchgestrichenen Text
        aussen, ohne -ForegroundColor. Sonst bleibt es bei ConsoleColor Red.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Segment,

        [Parameter(Mandatory)]
        [object] $Capability
    )

    $strich = ($null -ne $Capability.PSObject.Properties['SupportsStrike']) -and [bool] $Capability.SupportsStrike
    $vtWeg = ($null -ne $Capability.PSObject.Properties['SupportsVirtualTerminal']) -and [bool] $Capability.SupportsVirtualTerminal
    $esc = [string] [char] 27

    foreach ($abschnitt in $Segment) {

        $text = ConvertTo-KonsolenText -Text ([string] $abschnitt.Text)
        if ($text.Length -eq 0) { continue }

        $durch = ($null -ne $abschnitt.PSObject.Properties['Strike']) -and [bool] $abschnitt.Strike
        if ($strich -and $durch) { $text = $esc + '[9m' + $text + $esc + '[29m' }

        $schwere = 'None'
        if ($null -ne $abschnitt.PSObject.Properties['Severity']) { $schwere = [string] $abschnitt.Severity }
        $farbe = Get-SeverityColor -Severity $schwere

        $vtFarbe = ''
        if ($vtWeg) { $vtFarbe = Get-SeverityVtColor -Severity $schwere }

        if (-not [string]::IsNullOrEmpty($vtFarbe)) {
            Write-Host -Object ($vtFarbe + $text + $esc + '[39m') -NoNewline
        }
        elseif (-not [string]::IsNullOrEmpty($farbe)) {
            Write-Host -Object $text -NoNewline -ForegroundColor $farbe
        }
        else {
            Write-Host -Object $text -NoNewline
        }
    }

    Write-Host -Object ''
}

function Write-OperatorHint {
    <#
    .SYNOPSIS
        Ein einzelner Hinweistext des Dialogs. Intern zur Interaktionsschicht.

    .DESCRIPTION
        DER HINWEIS WIRD DER NAECHSTEN FRAGE MITGEGEBEN (G-04-3a). Jede
        Aufrufstelle steht unmittelbar vor einer erneuten Frage; der Hinweis
        erscheint damit genau dort, wo er gebraucht wird. Ueber welchen Kanal
        er reist, entscheidet Join-PromptContext anhand der vorab erhobenen
        Kapazitaet (G-04-4d); die Begruendung steht im Kopf von
        Read-OperatorInput.ps1.

        Severity faerbt im nicht umgeleiteten Kanal, sofern die Kapazitaet
        Farbe traegt. Im Prompt bleibt sie ohne Wirkung -- ein Prompt ist
        ungefaerbt, und D-14 traegt die Aussage ohnehin ueber den Text.
        Ein mehrzeiliger Text wird in seine Zeilen geteilt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [ValidateSet('OK', 'Warning', 'Error', 'None', 'Heading')]
        [string] $Severity = 'Warning'
    )

    Add-PromptContext -Line @($Text) -Severity $Severity
}

function Get-SeverityColor {
    <#
    .SYNOPSIS
        Die Vordergrundfarbe zu einer Schwere, oder leer. Intern zu
        Write-OperatorLine.

    .DESCRIPTION
        Leer heisst: keine Farbangabe. Das ist nicht dasselbe wie eine
        neutrale Farbe -- eine gesetzte Farbe uebersteuerte das Farbschema des
        Operators auch dort, wo nichts zu melden ist.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Severity
    )

    if ([string]::Equals($Severity, 'OK', [System.StringComparison]::Ordinal)) { return 'Green' }
    if ([string]::Equals($Severity, 'Warning', [System.StringComparison]::Ordinal)) { return 'Yellow' }
    if ([string]::Equals($Severity, 'Error', [System.StringComparison]::Ordinal)) { return 'Red' }

    # Banner, Rahmen und Schrittkoepfe (G-04-4e, NAV-01). Cyan wie die
    # Info-Farbe des Vorbilds; ohne Farbe tragen die Gleichheitslinien die
    # Abgrenzung allein.
    if ([string]::Equals($Severity, 'Heading', [System.StringComparison]::Ordinal)) { return 'Cyan' }

    return ''
}

function Get-SeverityVtColor {
    <#
    .SYNOPSIS
        Die VT-Vordergrundfolge zu einer Schwere, oder leer. Intern zu
        Write-OperatorLine.

    .DESCRIPTION
        Nur Error hat eine: helles Rot RGB 255/110/110 als 24-Bit-Folge,
        unabhaengig von der Konsolenpalette. Entscheidung Projektinhaber
        2026-10-01 zu G-09-3 -- ConsoleColor Red war auf der Serverkonsole
        tief dunkelrot und schwer zu lesen. Eine weitere Schwere nur auf
        Entscheidung des Projektinhabers.

        Gerufen nur, wenn die Kapazitaet SupportsVirtualTerminal meldet.
        Get-SeverityColor bleibt der Rueckfall ohne VT und wird NICHT
        geaendert. Das Steuerzeichen entsteht aus seinem Zeichencode.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Severity
    )

    if ([string]::Equals($Severity, 'Error', [System.StringComparison]::Ordinal)) {
        return ([string] [char] 27 + '[38;2;255;110;110m')
    }

    return ''
}

function Test-UmlautDarstellbar {
    <#
    .SYNOPSIS
        Ob die Konsolenkodierung die deutschen Umlaute und das Eszett
        darstellen kann. Einmal je Lauf erhoben.

    .DESCRIPTION
        Geprueft wird ein Hin- und Rueckweg durch die Ausgabekodierung der
        Konsole: nur was unveraendert zurueckkommt, laesst sich darstellen.
        Die ueblichen Codepages (850, 437, 1252, UTF-8) koennen es; die Weiche
        greift fuer alles andere. Ohne Konsole gilt die Darstellung als moeglich.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $bekannt = Get-Variable -Name 'UmlautDarstellbar' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $bekannt) { return [bool] $bekannt }

    # Umlaute, Eszett und die Rahmenzeichen der Tabellen.
    $probe = [string]::new([char[]] @(0xE4, 0xF6, 0xFC, 0xC4, 0xD6, 0xDC, 0xDF,
            0x2500, 0x2502, 0x250C, 0x252C, 0x2510, 0x251C, 0x253C, 0x2524, 0x2514, 0x2534, 0x2518))
    $ergebnis = $true

    try {
        $kodierung = [System.Console]::OutputEncoding
        $zurueck = $kodierung.GetString($kodierung.GetBytes($probe))
        $ergebnis = [string]::Equals($zurueck, $probe, [System.StringComparison]::Ordinal)
    }
    catch {
        $ergebnis = $true
    }

    $script:UmlautDarstellbar = $ergebnis
    return $ergebnis
}

function ConvertTo-KonsolenText {
    <#
    .SYNOPSIS
        Ein Ausgabetext fuer die Konsole: unveraendert, wenn sie Umlaute
        darstellen kann, sonst mit ae, oe, ue und ss.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    if (Test-UmlautDarstellbar) { return $Text }

    # Paare statt Hashtable: deren Schluessel unterscheiden Gross- und
    # Kleinschreibung nicht, ae und Ae waeren ein und derselbe.
    $ersatz = @(
        @(0xE4, 'ae'), @(0xF6, 'oe'), @(0xFC, 'ue'),
        @(0xC4, 'Ae'), @(0xD6, 'Oe'), @(0xDC, 'Ue'),
        @(0xDF, 'ss'),
        @(0x2500, '-'), @(0x2502, '|'),
        @(0x250C, '+'), @(0x252C, '+'), @(0x2510, '+'), @(0x251C, '+'), @(0x253C, '+'),
        @(0x2524, '+'), @(0x2514, '+'), @(0x2534, '+'), @(0x2518, '+')
    )

    $sb = [System.Text.StringBuilder]::new($Text)
    foreach ($paar in $ersatz) { $null = $sb.Replace([string] [char] [int] $paar[0], [string] $paar[1]) }

    return $sb.ToString()
}
