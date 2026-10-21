<#
    Read-OperatorInput -- die EINE Eingabenaht des Werkzeugs (D-04, FLOW-06,
    FLOW-08).

    Read-OperatorLine ist die einzige Stelle des gesamten Moduls, an der das
    PowerShell-Eingabe-Cmdlet aufgerufen wird. Jede weitere Dialogfunktion ruft
    SIE und nicht das Cmdlet. Nur so bleibt FLOW-08 eine Ordnerregel statt einer
    gepflegten Ausnahmeliste von Funktionsnamen, und nur so laesst sich der
    gesamte Dialog im Test gegen eine abgespielte Antwortfolge fahren.

    WIEDERHOLEN STATT ABBRECHEN (FLOW-06): eine ungueltige Freitexteingabe
    fuehrt ausnahmslos zu einer erneuten Frage. Ein Abbruch mitten im Dialog
    kostet den Operator die gesamte bereits erhobene Auskunft und ist bei einem
    rein interaktiven Werkzeug die teuerste aller Reaktionen.

    DIESE DATEI GIBT NICHT SELBST AUS. Damit traegt genau eine Datei den
    Eingabeaufruf und genau eine den Ausgabeaufruf (OUT-07). Wo der
    Rueckfragekontext ausgegeben statt in den Prompt gesetzt wird, reicht diese
    Datei ihn an die Ausgabenaht Write-OperatorLine weiter; das Ausgabe-Cmdlet
    selbst steht weiterhin nur dort.

    DER RUECKFRAGEKONTEXT WAEHLT SEINEN KANAL UEBER DIE KAPAZITAET (G-04-4d,
    D-14). Drei Messungen tragen das:
      1. Tests/Fixtures/lauf4.txt gegen lauf4_prompt.txt, Kindprozess per
         -File mit '> datei': die Zeilen der Ausgabenaht landen in der Datei,
         der Prompt des Eingabe-Cmdlets auf der Konsole. Die Rueckspiegelung
         einer Gruppe stand damit in der Datei, die Frage "Ist das die
         gemeinte Gruppe?" auf der Konsole -- der Operator bestaetigte blind
         (G-04-3a).
      2. Tests/Fixtures/lauf5_2.txt, '> datei' in der laufenden Sitzung:
         Blockueberschriften, Aufloesung, Plan und Zusammenfassung standen auf
         der Konsole.
      3. Probe vom 2026-09-22: die Umleitung einer laufenden Sitzung faengt
         Hostzeilen NICHT ein, nur die Erfolgsausgabe.
    Die Ausgabenaht erreicht die Konsole also genau dann, wenn
    [System.Console]::IsOutputRedirected falsch ist -- und diesen Wert erhebt
    Get-ConsoleCapability ohnehin EINMAL VORAB als OutputRedirected.
    Invoke-DemFsProvisioning uebergibt die Kapazitaet des Laufs mit
    Set-PromptChannel. Ist sie nicht umgeleitet, gibt Join-PromptContext den
    Kontext mit seiner Schwere ueber die Ausgabenaht aus -- farbig, sofern die
    Kapazitaet Farbe traegt -- und stellt die Frage unveraendert. Ist sie
    umgeleitet oder gar nicht gesetzt, reist der Kontext wie bisher im Prompt:
    der einzige gemessene Weg, der den Operator auch unter Umleitung
    erreicht, dort ohne Farbe (D-14). Entschieden wird ueber die vorab
    erhobene Kapazitaet, nie in einem Ausnahmezweig. Die dokumentierte
    Aufrufform bleibt -File (D-01); '*> datei' in der laufenden Sitzung leitet
    auch Hostzeilen um, ist nicht erkennbar und kein vorgesehener Aufruf.

    Add-PromptContext legt Zeilen samt Schwere ab (Hinweise, Aufloesungszeilen,
    Unterordnerliste, Blockueberschriften, bei Umleitung Banner und Plan), und
    die naechste Frage verarbeitet sie ueber Join-PromptContext. Im Prompt ist
    die Frage immer die LETZTE Zeile; ohne Kontext ist der Prompt zeichengleich
    zum bisherigen. Ein Kontext gilt genau einer Frage und wird danach
    verworfen. Zwei Leerzeilen hintereinander legt Add-PromptContext nie ab.
    Join-PromptContext steht OBERHALB von Read-OperatorLine -- nur so sieht ein
    Test, der die Eingabenaht ersetzt, den vollstaendigen Prompt.

    ZWEI BESCHRIFTUNGEN FUER JA/NEIN (Entscheidung Projektinhaber
    2026-09-30). Bestehende Fragen behalten "[j/n, Vorgabe: ja]" bzw.
    "[j/n, Vorgabe: nein]" zeichengleich; nur die neuen Fragen der
    Schrittfuehrung (Phase 9) tragen ueber -ShortLabel die Kurzform "[J/n]"
    bzw. "[j/N]" aus Get-YesNoLabel. Angenommene Eingaben sind in beiden
    Formen dieselben. Eine "?"-Erklaerung an Ja/Nein-Fragen gibt es nicht
    mehr (HLP-01 gestrichen, Entscheidung Projektinhaber 2026-10-04).

    Read-OptionalText ist die Frageform, bei der Enter ausdruecklich
    zulaessig ist und "uebernehmen" bedeutet -- ohne Scheinvorgabe im Prompt.

    TASTEN LIEST NUR Read-OperatorKey (W-09-1, Entscheidung Projektinhaber
    2026-10-01). Es ist die einzige Tastenlesestelle des Moduls, so wie
    Read-OperatorLine die einzige Zeilenlesestelle ist. Den Tastenmodus
    entscheidet Test-KeyChannelOffen AUSSCHLIESSLICH ueber die uebergebene
    Kapazitaet (Feld SupportsKeyInput), nie ueber den modulweiten
    Zwischenspeicher: eine echte Kapazitaet aus einem frueheren Testfall
    duerfte sonst in einer offenen Konsole den Tastenmodus ausloesen, und das
    Tastenlesen hielte den Testlauf an. Ohne Kapazitaet, ohne das Feld oder
    mit falsch laeuft der Nummerndialog. Ob Tasten ueberhaupt lesbar sind,
    erhebt Test-OperatorKeyInput einmal vorab je Lauf (D-14).

    KEINE NORMALISIERUNG DES WEITERGEREICHTEN WERTES. Read-RequiredText gibt
    die Eingabe UNVERAENDERT zurueck -- kein Trim, keine Normalform, keine
    Faltung der Gross-/Kleinschreibung. Die Leerraumpruefung ist eine
    Gueltigkeitsfrage und veraendert den Wert nicht. Die einzige Trimmstelle
    fuer Gruppenangaben bleibt Resolve-TrusteeSid, die einzige fuer Pfade
    Resolve-OperatorPath.
#>

# Die abgelegten Kontextzeilen der naechsten Frage, je Zeile ein Datensatz mit
# Text und Severity. Modulweit, damit jede Dialogfunktion Zeilen ablegen kann,
# ohne sie durch jede Signatur zu faedeln. Invoke-DemFsProvisioning leert sie
# zu Laufbeginn.
$script:PromptKontext = New-Object System.Collections.Generic.List[object]

# Der Rueckfragekanal: die vorab erhobene Kapazitaet des Laufs, oder nichts.
# Nichts heisst Prompt -- der gemessene sichere Weg.
$script:PromptKanal = $null

function Add-PromptContext {
    <#
    .SYNOPSIS
        Legt Zeilen fuer die naechste Frage ab (G-04-3a, G-04-4d).

    .DESCRIPTION
        Die Zeilen erscheinen VOR der naechsten Frage -- im Prompt oder, bei
        nicht umgeleitetem Kanal, ueber die Ausgabenaht -- und werden danach
        verworfen. Eine leere Zeichenkette ist eine Leerzeile; eine leere
        Sammlung legt nichts ab. Eine Zeichenkette mit Zeilenumbruechen wird in
        ihre Zeilen geteilt. Eine Leerzeile wird NICHT abgelegt, wenn die
        zuletzt abgelegte Zeile bereits leer ist: zwei Leerzeilen hintereinander
        entstehen im Kontext nie.

    .PARAMETER Line
        Zeichenketten oder Zeilensaetze (Text, Severity, wahlweise Segments).
        Ein Zeilensatz behaelt seine eigene Schwere und seine farbigen
        Abschnitte; im Prompt zaehlt nur sein Text.

    .PARAMETER Severity
        Steuert ausschliesslich die Farbe im nicht umgeleiteten Kanal. Im
        Prompt bleibt sie ohne Wirkung; der Text traegt die Aussage allein
        (D-14).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [object[]] $Line,

        [Parameter()]
        [ValidateSet('OK', 'Warning', 'Error', 'None', 'Heading')]
        [string] $Severity = 'None'
    )

    foreach ($eintrag in @($Line)) {

        if ($null -eq $eintrag) { continue }

        if (($eintrag -isnot [string]) -and ($null -ne $eintrag.PSObject.Properties['Text'])) {

            $schwere = $Severity
            if ($null -ne $eintrag.PSObject.Properties['Severity']) { $schwere = [string] $eintrag.Severity }
            $abschnitte = $null
            if ($null -ne $eintrag.PSObject.Properties['Segments']) { $abschnitte = $eintrag.Segments }

            $script:PromptKontext.Add([pscustomobject] @{ Text = [string] $eintrag.Text; Severity = $schwere; Segments = $abschnitte })
            continue
        }

        foreach ($zeile in [regex]::Split([string] $eintrag, '\r?\n')) {

            if ([string]::IsNullOrEmpty($zeile) -and ($script:PromptKontext.Count -gt 0)) {
                $letzte = $script:PromptKontext[$script:PromptKontext.Count - 1]
                if ([string]::IsNullOrEmpty([string] $letzte.Text)) { continue }
            }

            $script:PromptKontext.Add([pscustomobject] @{ Text = [string] $zeile; Severity = $Severity })
        }
    }
}

function Set-PromptChannel {
    <#
    .SYNOPSIS
        Legt den Rueckfragekanal des Laufs fest (G-04-4d).

    .DESCRIPTION
        Nimmt die EINMAL VORAB erhobene Kapazitaet entgegen (D-14). Meldet sie
        OutputRedirected falsch, erreicht die Ausgabenaht die Konsole, und der
        Kontext geht farbig dorthin. Null setzt den Kanal zurueck: dann reist
        der Kontext im Prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Capability
    )

    $script:PromptKanal = $Capability
}

function Test-PromptChannelOffen {
    <#
    .SYNOPSIS
        Wahr, wenn ein Kanal gesetzt ist und seine Ausgabe NICHT umgeleitet
        ist. Intern zu Join-PromptContext.

    .DESCRIPTION
        Das Feld wird ueber PSObject.Properties gelesen: das Modul laeuft unter
        Set-StrictMode, und eine Kapazitaet ohne OutputRedirected gilt als nicht
        erwiesen offen -- dann bleibt es beim Prompt.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -eq $script:PromptKanal) { return $false }
    if ($null -eq $script:PromptKanal.PSObject.Properties['OutputRedirected']) { return $false }

    return (-not [bool] $script:PromptKanal.OutputRedirected)
}

function Clear-PromptContext {
    <#
    .SYNOPSIS
        Verwirft alle abgelegten Kontextzeilen.

    .DESCRIPTION
        Zu Laufbeginn gerufen: ein abgebrochener Vorlauf im selben Prozess darf
        der ersten Frage des naechsten Laufs keinen fremden Kontext mitgeben.
    #>
    [CmdletBinding()]
    param()

    $script:PromptKontext.Clear()
}

function Join-PromptContext {
    <#
    .SYNOPSIS
        Bringt die abgelegten Zeilen vor die Frage und verwirft sie. Intern zu
        den Fragefunktionen dieser Datei.

    .DESCRIPTION
        Ist der Kanal gesetzt und NICHT umgeleitet, gehen die Zeilen samt
        Schwere ueber die Ausgabenaht an die Konsole, und die Frage kommt
        unveraendert zurueck (G-04-4d). In jedem anderen Fall werden sie, durch
        den Zeilenumbruch der Plattform getrennt, VOR die Frage gesetzt; die
        Frage ist dann die LETZTE Zeile. Ohne abgelegte Zeilen kommt die Frage
        unveraendert zurueck -- ein Prompt ohne Kontext bleibt zeichengleich
        zum bisherigen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Question
    )

    if ($script:PromptKontext.Count -eq 0) { return $Question }

    if (Test-PromptChannelOffen) {

        $zeilen = $script:PromptKontext.ToArray()
        $script:PromptKontext.Clear()

        Write-OperatorLine -Capability $script:PromptKanal -Line $zeilen

        return $Question
    }

    $teile = New-Object System.Collections.Generic.List[string]
    foreach ($zeile in $script:PromptKontext) { $teile.Add([string] $zeile.Text) }
    $teile.Add($Question)

    $script:PromptKontext.Clear()

    return [string]::Join([System.Environment]::NewLine, $teile.ToArray())
}

function Read-OperatorLine {
    <#
    .SYNOPSIS
        Liest eine Zeile vom Operator. Die einzige Eingabestelle des Moduls.

    .DESCRIPTION
        Duenn und ohne jede Entscheidung -- genau wie die Seams in
        HostFacts.ps1. Die gelesene Zeichenkette wird UNVERAENDERT
        zurueckgegeben; jede Deutung faellt in der aufrufenden Dialogfunktion.

    .PARAMETER Prompt
        Der angezeigte Fragetext. Er reist unveraendert an das Cmdlet und ist
        damit zugleich der Mitschrieb, an dem ein Test belegt, dass eine Frage
        ueberhaupt gestellt wurde.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Prompt
    )

    return [string] (Read-Host -Prompt (ConvertTo-KonsolenText -Text $Prompt))
}

function Read-OperatorKey {
    <#
    .SYNOPSIS
        Liest eine Taste vom Operator, ohne Echo. Die einzige Tastenlesestelle
        des Moduls (W-09-1).

    .DESCRIPTION
        Duenn und ohne jede Entscheidung, wie Read-OperatorLine. Gerufen nur
        im Tastenmodus von Schritt 1 von Weg 1, und den gibt es nur mit einer
        uebergebenen Kapazitaet, die SupportsKeyInput meldet
        (Test-KeyChannelOffen). Im Test filterlos ersetzt.

    .OUTPUTS
        [pscustomobject] mit Key (Name der ConsoleKey) und Char (das Zeichen),
        beides als Zeichenkette.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $taste = [System.Console]::ReadKey($true)

    return [pscustomobject] @{
        Key  = [string] $taste.Key
        Char = [string] $taste.KeyChar
    }
}

function Test-OperatorKeyInput {
    <#
    .SYNOPSIS
        Ob dieser Lauf einzelne Tasten lesen kann. Einmal vorab je Lauf aus
        Get-ConsoleCapability gerufen (D-14, W-09-1).

    .DESCRIPTION
        Falsch bei umgeleiteter Ausgabe, bei umgeleiteter Eingabe, ohne
        Rohkonsole des Hosts, bei einem anderen Host als ConsoleHost und wenn
        schon das Abfragen einer wartenden Taste wirft. Die Abfrage laeuft bei
        jedem Lauf -- dasselbe Muster wie Test-UmlautDarstellbar -- und ist
        kein selten gefahrener Ausnahmezweig im Dialog.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [bool] $OutputRedirected
    )

    if ($OutputRedirected) { return $false }
    if ([bool] [System.Console]::IsInputRedirected) { return $false }
    if ($null -eq $Host.UI) { return $false }
    if ($null -eq $Host.UI.RawUI) { return $false }
    if (-not [string]::Equals([string] $Host.Name, 'ConsoleHost', [System.StringComparison]::Ordinal)) { return $false }

    try {
        $null = [System.Console]::KeyAvailable
    }
    catch {
        return $false
    }

    return $true
}

function Test-KeyChannelOffen {
    <#
    .SYNOPSIS
        Wahr, wenn die UEBERGEBENE Kapazitaet Tasteneingabe meldet (W-09-1).

    .DESCRIPTION
        Liest nur die uebergebene Kapazitaet, nie $script:ConsoleCapability
        (Begruendung im Dateikopf). Das Feld wird ueber PSObject.Properties
        gelesen: das Modul laeuft unter Set-StrictMode, und eine Kapazitaet
        ohne SupportsKeyInput gilt als nicht erwiesen tastenfaehig.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Capability
    )

    if ($null -eq $Capability) { return $false }
    if ($null -eq $Capability.PSObject.Properties['SupportsKeyInput']) { return $false }

    return [bool] $Capability.SupportsKeyInput
}

function Send-PromptContext {
    <#
    .SYNOPSIS
        Gibt abgelegte Kontextzeilen sofort ueber die Ausgabenaht aus und
        verwirft sie (W-09-1).

    .DESCRIPTION
        Fuer den Tastenmodus: dort stellt keine Frage den Kontext voran, also
        geht er vor dem ersten Zeichnen hinaus -- sonst stuende er in falscher
        Reihenfolge hinter der Liste. Ohne abgelegte Zeilen geschieht nichts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Capability
    )

    if ($script:PromptKontext.Count -eq 0) { return }

    $zeilen = $script:PromptKontext.ToArray()
    $script:PromptKontext.Clear()

    Write-OperatorLine -Capability $Capability -Line $zeilen
}

function Read-YesNoAnswer {
    <#
    .SYNOPSIS
        Stellt eine Ja/Nein-Frage mit sichtbarem Vorgabewert (FLOW-01, D-05).

    .DESCRIPTION
        Akzeptiert j, ja, n und nein ohne Ruecksicht auf Gross-/Kleinschreibung.
        Eine leere Eingabe nimmt den Vorgabewert; alles andere fuehrt zu einer
        erneuten Frage (FLOW-06). Kein Menue und keine Nummernliste: das
        funktioniert in jedem Terminal und braucht keinen Eingabeparser.

        Der Vorgabewert steht IM PROMPT. Eine Vorgabe, die man nicht sieht,
        ist keine.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Prompt,

        [Parameter()]
        [bool] $Default = $true,

        # Kurzform "[J/n]" / "[j/N]" -- nur fuer die neuen Fragen der
        # Schrittfuehrung (Entscheidung Projektinhaber 2026-09-30).
        [Parameter()]
        [switch] $ShortLabel
    )

    $vorgabe = if ($Default) { 'ja' } else { 'nein' }

    if ($ShortLabel) {
        $beschriftung = '{0} {1}' -f $Prompt, (Get-YesNoLabel -Default $Default)
    }
    else {
        $beschriftung = '{0} [j/n, Vorgabe: {1}]' -f $Prompt, $vorgabe
    }

    while ($true) {

        # Je Versuch neu gebaut: ein Hinweis aus dem vorigen Versuch haengt
        # damit genau am naechsten Prompt.
        $wert = ([string] (Read-OperatorLine -Prompt (Join-PromptContext -Question $beschriftung))).Trim()

        if ([string]::IsNullOrWhiteSpace($wert)) { return $Default }

        foreach ($ja in @('j', 'ja')) {
            if ([string]::Equals($wert, $ja, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }

        foreach ($nein in @('n', 'nein')) {
            if ([string]::Equals($wert, $nein, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }

        Write-OperatorHint -Text '    Bitte mit j oder n antworten. Enter übernimmt die Vorgabe.'
    }
}

function Get-YesNoLabel {
    <#
    .SYNOPSIS
        Die Kurzform der Ja/Nein-Beschriftung: "[J/n]" bei Vorgabe ja,
        "[j/N]" bei Vorgabe nein. Der Grossbuchstabe ist die Vorgabe.

    .DESCRIPTION
        Nur fuer die neuen Fragen der Schrittfuehrung (Phase 9). Bestehende
        Fragen behalten ihre Beschriftung zeichengleich (Entscheidung
        Projektinhaber 2026-09-30).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [bool] $Default
    )

    if ($Default) { return '[J/n]' }

    return '[j/N]'
}

function Read-OptionalText {
    <#
    .SYNOPSIS
        Fragt eine Freitextangabe, bei der Enter zulaessig ist und
        "uebernehmen" bedeutet (Phase 9, ERF-01).

    .DESCRIPTION
        Wie Read-RequiredText, aber eine leere oder nur aus Leerraum
        bestehende Eingabe gilt als '' und geht als '' an den Validator
        bzw. zurueck. Der Prompt traegt keine Scheinvorgabe -- was Enter
        bewirkt, sagt der Fragetext selbst.

        Eine abgewiesene Eingabe fuehrt zu Hinweis und erneuter Frage
        (FLOW-06). Die Rueckgabe ist sonst die UNVERAENDERTE Eingabe.

    .PARAMETER Validator
        Wie bei Read-RequiredText: Wahrheitswert oder Datensatz mit IsValid
        und Reason.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Prompt,

        [Parameter()]
        [AllowNull()]
        [scriptblock] $Validator = $null
    )

    while ($true) {

        $wert = [string] (Read-OperatorLine -Prompt (Join-PromptContext -Question $Prompt))

        if ([string]::IsNullOrWhiteSpace($wert)) { $wert = '' }

        if ($null -eq $Validator) { return $wert }

        $befund = ConvertTo-ValidationResult -Value (& $Validator $wert)

        if ([bool] $befund.IsValid) { return $wert }

        $grund = [string] $befund.Reason
        if ([string]::IsNullOrWhiteSpace($grund)) { $grund = 'Die Angabe wurde als ungültig abgewiesen.' }

        Write-OperatorHint -Text ('    {0}' -f $grund)
    }
}

function Read-RequiredText {
    <#
    .SYNOPSIS
        Fragt so lange, bis eine gueltige Freitextangabe vorliegt (FLOW-06).

    .DESCRIPTION
        Leere und nur aus Leerraum bestehende Eingaben gelten nie als gueltig --
        es sei denn, ein Vorschlagswert steht bereit; dann uebernimmt Enter
        genau diesen.

        Die Rueckgabe ist die UNVERAENDERTE Eingabe. Wer hier trimmt, legt eine
        zweite Wahrheit ueber die Schreibweise an, und die Aufloesung prueft
        anschliessend gegen die falsche.

    .PARAMETER Validator
        Ein Skriptblock, der den Wert entgegennimmt und entweder einen
        Wahrheitswert oder einen Datensatz mit den Feldern IsValid und Reason
        liefert. Reason wird dem Operator angezeigt -- eine Abweisung ohne
        Begruendung ist eine Sackgasse. Ein mehrzeiliger Reason reist
        unveraendert, ein einzeiliger bekommt vier Leerzeichen Einzug. Ein
        optionales Feld Severity ('Error') faerbt den Hinweis als Fehler;
        ohne es bleibt er ein Warnhinweis (VAL-01).

    .PARAMETER DefaultValue
        Der Vorschlagswert. Leer bedeutet: es gibt keinen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Prompt,

        [Parameter()]
        [AllowNull()]
        [scriptblock] $Validator = $null,

        [Parameter()]
        [AllowEmptyString()]
        [string] $DefaultValue = ''
    )

    $hatVorgabe = -not [string]::IsNullOrWhiteSpace($DefaultValue)

    $beschriftung = if ($hatVorgabe) { '{0} [Vorgabe: {1}]' -f $Prompt, $DefaultValue } else { $Prompt }

    while ($true) {

        $wert = [string] (Read-OperatorLine -Prompt (Join-PromptContext -Question $beschriftung))

        if ([string]::IsNullOrWhiteSpace($wert)) {

            if (-not $hatVorgabe) {
                Write-OperatorHint -Text '    Die Angabe darf nicht leer sein.'
                continue
            }

            $wert = $DefaultValue
        }

        if ($null -eq $Validator) { return $wert }

        $befund = ConvertTo-ValidationResult -Value (& $Validator $wert)

        if ([bool] $befund.IsValid) { return $wert }

        $grund = [string] $befund.Reason
        if ([string]::IsNullOrWhiteSpace($grund)) { $grund = 'Die Angabe wurde als ungültig abgewiesen.' }

        # Ein mehrzeiliger Grund ist bereits gegliedert und eingerueckt
        # (G-04-4f) und reist unveraendert; nur ein einzeiliger bekommt den
        # Einzug. Die Schwere reist mit dem Befund (VAL-01: Error fuer einen
        # abgewiesenen Zielpfad), sonst Warning wie bisher.
        if ($grund.Contains("`n")) {
            Write-OperatorHint -Severity ([string] $befund.Severity) -Text $grund
        }
        else {
            Write-OperatorHint -Severity ([string] $befund.Severity) -Text ('    {0}' -f $grund)
        }
    }
}

function Confirm-TypedWord {
    <#
    .SYNOPSIS
        D-11: bestaetigt wird durch Tippen eines Wortes, nicht durch Enter.

    .DESCRIPTION
        Verglichen wird die GETRIMMTE Eingabe ohne Ruecksicht auf
        Gross-/Kleinschreibung. Enter allein ergibt ausdruecklich falsch --
        genau das ist der Unterschied zwischen einer Bestaetigung und einem
        Weiterklicken (FLOW-07).

        Genau EIN Versuch. Eine Wiederholschleife machte aus der Ablehnung eine
        Sackgasse; D-12 verlangt dagegen den sauberen Abbruch.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Prompt,

        [Parameter(Mandatory)]
        [string] $Word
    )

    $beschriftung = '{0} [zum Bestätigen {1} tippen]' -f $Prompt, $Word

    $wert = ([string] (Read-OperatorLine -Prompt (Join-PromptContext -Question $beschriftung))).Trim()

    if ([string]::IsNullOrEmpty($wert)) { return $false }

    return [string]::Equals($wert, $Word, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-ValidationResult {
    <#
    .SYNOPSIS
        Bringt die Rueckgabe eines Validators auf die Form IsValid/Reason.
        Intern zu Read-RequiredText.

    .DESCRIPTION
        Ein Validator darf schlicht wahr oder falsch liefern; dann fehlt die
        Begruendung und der Hinweistext bleibt allgemein. Liefert er einen
        Datensatz mit IsValid und Reason, erscheint die Begruendung.

        Ein Skriptblock kann mehr als einen Wert in den Strom schreiben.
        Massgeblich ist der LETZTE -- das ist der Rueckgabewert im Sinne von
        PowerShell.

        Das optionale Feld Severity (Warning oder Error) bestimmt die
        Hinweisschwere der Abweisung; fehlt es, gilt Warning (VAL-01).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Value
    )

    $werte = @($Value)

    if ($werte.Count -eq 0) {
        return [pscustomobject] @{ IsValid = $false; Reason = ''; Severity = 'Warning' }
    }

    $letzter = $werte[$werte.Count - 1]

    if ($null -eq $letzter) {
        return [pscustomobject] @{ IsValid = $false; Reason = ''; Severity = 'Warning' }
    }

    if ($letzter -is [bool]) {
        return [pscustomobject] @{ IsValid = [bool] $letzter; Reason = ''; Severity = 'Warning' }
    }

    if ($null -ne $letzter.PSObject.Properties['IsValid']) {

        $grund = ''
        if ($null -ne $letzter.PSObject.Properties['Reason']) { $grund = [string] $letzter.Reason }

        $schwere = 'Warning'
        if (($null -ne $letzter.PSObject.Properties['Severity']) -and
            [string]::Equals([string] $letzter.Severity, 'Error', [System.StringComparison]::Ordinal)) {
            $schwere = 'Error'
        }

        return [pscustomobject] @{ IsValid = [bool] $letzter.IsValid; Reason = $grund; Severity = $schwere }
    }

    return [pscustomobject] @{ IsValid = [bool] $letzter; Reason = ''; Severity = 'Warning' }
}
