#Requires -Version 5.1
<#
.SYNOPSIS
    Baut aus den Modulquellen genau eine lauffaehige Datei
    dist/FSLogix-DEM-ShareProvisioning.ps1 (BUILD-01 bis BUILD-06).

.DESCRIPTION
    Am 2026-09-21 brach ein Serverlauf ab, weil nur die Einstiegsdatei kopiert
    worden war. Eine einzelne Datei macht diesen Fehler unmoeglich. Der Preis
    dafuer darf nicht sein, dass die Quellen ihre Struktur verlieren -- deshalb
    entsteht das Buendel AUS den unveraenderten Quellen, und keine Quelldatei
    wird fuer das Buendel angepasst.

    Das Skript nimmt KEINEN einzigen Parameter, auch keinen optionalen
    (BUILD-01). Alles, was es braucht, leitet es aus seiner eigenen Lage ab:
    die Repositoriumswurzel ist das Elternverzeichnis von $PSScriptRoot.

    Ablauf:
      1. Quelltext einlesen -- ueber ReadAllBytes, mit einer UTF8Encoding, die
         bei ungueltigen Bytes wirft.
      2. Quellen sammeln -- Private, Interaction, Public, je Ordner ordinal;
         ohne den Dateizugriff des Moduls (Get-DataPath, Get-DataTable).
      3. Datentabellen einbetten -- als ein Get-DataTable, das die Tabellen aus
         dem Code liefert; ohne Herstellerbelege und ohne Kommentare.
      4. Vorlauf -- StrictMode und $script:MitBelegen = $false.
      5. Quellen ohne Kommentare, je Funktion nur die .SYNOPSIS.
      6. Einstieg aus FSLogix-DEM-ShareProvisioning.ps1 uebernehmen, ohne Modulimport.
      7. Zwei Kopfzeilen (Quell-Commit, Erzeugungszeit mit Quellstand), dann
         mit BOM und CRLF schreiben.

    Das Ergebnis ist ein eigenstaendiges Skript ohne Bezug auf eine andere
    Datei. Die Quellen unter DemFsAcl/ bleiben unveraendert und fuehren
    weiterhin Kommentare und Belege.

    Der Bauer wirft bei einem fehlenden Anker, bei einer ungueltigen
    UTF-8-Quelle und bei einer Datendatei, die nicht aus genau einem
    Hashtable-Ausdruck besteht. Alle drei Faelle heissen: die Quellen und das
    Buendel sind auseinandergelaufen -- das soll laut auffallen, nicht still.

.NOTES
    DER AUFRUF ERFOLGT AUSNAHMSLOS PER -File, nie per -Command:

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Tools/Build-DemFsBundle.ps1

    Das Ergebnis liegt unter dist/ und ist ueber .gitignore von der
    Versionierung ausgenommen (verbindliche Entscheidung vom 2026-09-23).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 1. Konstanten -----------------------------------------------------------

# Das Bauskript liegt in Tools/ -- eine Ebene hoeher ist die
# Repositoriumswurzel. Ueber .NET statt ueber Split-Path: dessen -LiteralPath
# und -Parent liegen in verschiedenen Parametersaetzen.
$Wurzel = [System.IO.Path]::GetDirectoryName($PSScriptRoot)

$Crlf = "`r`n"

# Die beiden Zeilen, die beim Uebernehmen des Einstiegs entfallen: im Buendel
# gibt es kein Modul zu laden. Sie stehen als Anker und nicht als Musterausdruck
# -- ein Regulaerausdruck traefe morgen auch eine umformulierte Zeile, und genau
# das soll er nicht.
$AnkerManifest = @'
$manifestPfad = [System.IO.Path]::Combine($PSScriptRoot, 'DemFsAcl', 'DemFsAcl.psd1')
'@

$AnkerImport = @'
Import-Module -Name $manifestPfad -Force
'@

# Die Kopfbeschriftungen stehen als Formatvorlagen mit Platzhalter und NICHT
# als fertig zusammengesetzte Zeilen. Der Versionierungswaechter erkennt ein
# eingechecktes Buendel an der FERTIGEN Commit-Zeile -- der Bauer darf dabei
# nicht selbst zum Treffer werden.
$VorlageCommit  = '# Quell-Commit: {0}'
$VorlageErzeugt = '# Erzeugt: {0}, Quellstand {1}'

# --- 2. Hilfsfunktionen ------------------------------------------------------

function ConvertTo-Crlf {
    <#
    .SYNOPSIS
        Vereinheitlicht alle Zeilenenden eines Textes auf CRLF.
    .DESCRIPTION
        Erst alles auf LF zusammenfuehren, dann einmal auf CRLF aufweiten --
        ein direktes LF nach CRLF machte aus einem vorhandenen CRLF ein CRCRLF.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    return $Text.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
}

function Read-Quelltext {
    <#
    .SYNOPSIS
        Liest eine Quelldatei als Text: ohne BOM, mit CRLF, ohne #Requires.
    .DESCRIPTION
        Bewusst ueber ReadAllBytes. Get-Content dekodiert bereits und wuerde
        eine ungueltige Bytefolge stillschweigend durch Ersatzzeichen ersetzen;
        die UTF8Encoding hier wirft stattdessen (zweites Argument $true).

        Die #Requires-Zeilen der Quellen entfallen: das Buendel fuehrt genau
        eine solche Zeile, und die setzt der Bauer selbst als erste Zeile.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)

    $start = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $start = 3
    }

    # throwOnInvalidBytes = $true: eine kaputte Quelle stirbt hier und nicht
    # erst als Mojibake in einem Ausgabetext auf dem Zielserver.
    $enc = [System.Text.UTF8Encoding]::new($false, $true)

    try {
        $text = $enc.GetString($bytes, $start, ($bytes.Length - $start))
    }
    catch {
        throw [System.IO.InvalidDataException]::new(
            ('Die Quelldatei "{0}" ist kein gueltiges UTF-8: {1}' -f $LiteralPath, $_.Exception.Message))
    }

    $text = ConvertTo-Crlf -Text $text

    $zeilen = @(
        @($text -split $Crlf) |
            Where-Object { -not $_.TrimStart().StartsWith('#Requires') }
    )

    return ($zeilen -join $Crlf)
}

function Get-OrdinalDatei {
    <#
    .SYNOPSIS
        Liefert die vollen Pfade aller Dateien eines Ordners mit der gegebenen
        Erweiterung, ordinal nach Dateiname sortiert.
    .DESCRIPTION
        Auswahl ueber die Erweiterung und ausdruecklich nicht ueber -Filter oder
        -Include: -Include wird neben -LiteralPath stillschweigend ignoriert,
        -Filter geht ueber die Windows-Wildcardmaschine und traefe auch '.ps1x'.
        Dieselbe Begruendung wie im .psm1.

        Ordinal statt Sort-Object -Property Name: die gebietsschema-abhaengige
        Sortierung gewichtet Bindestriche anders, und der Bau soll auf einer
        anders lokalisierten Maschine dieselbe Datei erzeugen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Ordner,

        [Parameter(Mandatory)]
        [string] $Erweiterung
    )

    if (-not (Test-Path -LiteralPath $Ordner)) {
        throw [System.IO.DirectoryNotFoundException]::new(
            ('Der Quellordner "{0}" fehlt -- ein Buendel ohne ihn waere eine stille Teilkopie.' -f $Ordner))
    }

    $dateien = @(
        Get-ChildItem -LiteralPath $Ordner -File |
            Where-Object { $_.Extension -eq $Erweiterung }
    )

    if ($dateien.Count -eq 0) {
        throw [System.IO.FileNotFoundException]::new(
            ('Im Ordner "{0}" liegt keine Datei mit der Erweiterung "{1}" -- ein Buendel ohne diesen Teil waere eine stille Teilkopie.' -f
                $Ordner, $Erweiterung))
    }

    $namen = [string[]] @($dateien | ForEach-Object { $_.Name })
    [System.Array]::Sort($namen, [System.StringComparer]::Ordinal)

    return [string[]] @($namen | ForEach-Object { [System.IO.Path]::Combine($Ordner, $_) })
}

function Assert-Datentabelle {
    <#
    .SYNOPSIS
        Weist nach, dass ein Text aus genau einem Hashtable-Ausdruck besteht.
    .DESCRIPTION
        Das Buendel laedt die Datendateien als Skriptblock und damit in der
        VOLLEN Sprache, waehrend Import-PowerShellDataFile die eingeschraenkte
        benutzt. Unschaedlich ist das nur, solange die Datei wirklich eine reine
        Datentabelle ist -- eine reine Tabelle verhaelt sich in beiden gleich.
        Diese Pruefung ist der Beleg dafuer und kein Formalismus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $marken = $null
    $fehler = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref] $marken, [ref] $fehler)

    if (@($fehler).Count -gt 0) {
        throw [System.IO.InvalidDataException]::new(
            ('Die Datendatei "{0}" hat {1} Parsefehler; der erste lautet: {2}' -f
                $LiteralPath, @($fehler).Count, @($fehler)[0].Message))
    }

    $anweisungen = @($ast.EndBlock.Statements)

    if ($anweisungen.Count -ne 1) {
        throw [System.IO.InvalidDataException]::new(
            ('Die Datendatei "{0}" besteht aus {1} Anweisungen statt aus genau einer.' -f
                $LiteralPath, $anweisungen.Count))
    }

    $ausdruck = $null
    $anweisung = $anweisungen[0]

    if ($anweisung -is [System.Management.Automation.Language.PipelineAst]) {
        $glieder = @($anweisung.PipelineElements)
        if ($glieder.Count -eq 1 -and
            $glieder[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $ausdruck = $glieder[0].Expression
        }
    }

    if ($null -eq $ausdruck -or
        $ausdruck -isnot [System.Management.Automation.Language.HashtableAst]) {
        throw [System.IO.InvalidDataException]::new(
            ('Die Datendatei "{0}" besteht nicht aus genau einem Hashtable-Ausdruck.' -f $LiteralPath))
    }
}

function Invoke-Git {
    <#
    .SYNOPSIS
        Ruft git auf und liefert Rueckgabewert und Ausgabezeilen.
    .DESCRIPTION
        $ErrorActionPreference wird fuer den Aufruf abgesenkt: bei 'Stop' macht
        die Umleitung 2>&1 aus einer harmlosen git-Diagnosezeile einen
        abbrechenden Fehler. Entschieden wird hier ueber den Rueckgabewert.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]] $Argumente
    )

    $alteVorgabe = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $ausgabe = @(& git @Argumente 2>&1 | ForEach-Object { [string] $_ })
        $rueckgabe = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $alteVorgabe
    }

    return [pscustomobject]@{
        ExitCode = $rueckgabe
        Ausgabe  = $ausgabe
    }
}

function Remove-Datenschluessel {
    <#
    .SYNOPSIS
        Entfernt aus einer Datentabelle jedes Schluessel-Wert-Paar mit einem der
        genannten Schluessel, in jeder Schachtelungstiefe.
    .DESCRIPTION
        Ueber den Syntaxbaum, nicht ueber Muster: ein Wert kann Zeilenumbrueche,
        Anfuehrungszeichen oder ein Gleichheitszeichen enthalten. Nach dem
        Entfernen wird neu geparst und nachgewiesen, dass kein solcher
        Schluessel mehr vorkommt -- ein halb bereinigtes Buendel soll nicht
        entstehen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string[]] $Schluessel,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $finde = {
        param([string] $Quelle)

        $marken = $null
        $fehler = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Quelle, [ref] $marken, [ref] $fehler)

        if (@($fehler).Count -gt 0) {
            throw [System.InvalidOperationException]::new(
                ('"{0}" ist beim Entfernen der Belegfelder nicht parsebar: {1}' -f $LiteralPath, @($fehler)[0].Message))
        }

        $tabellen = @($ast.FindAll({ param($k) $k -is [System.Management.Automation.Language.HashtableAst] }, $true))

        foreach ($tabelle in $tabellen) {
            foreach ($paar in @($tabelle.KeyValuePairs)) {
                $k = $paar.Item1
                if ($k -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $Schluessel -ccontains $k.Value) {
                    [pscustomobject] @{ Start = $k.Extent.StartOffset; Ende = $paar.Item2.Extent.EndOffset }
                }
            }
        }
    }

    $bereiche = @(& $finde $Text | Sort-Object -Property Start -Descending)

    $sb = [System.Text.StringBuilder]::new($Text)
    foreach ($b in $bereiche) {
        $null = $sb.Remove($b.Start, $b.Ende - $b.Start)
    }

    $ohne = $sb.ToString()

    $rest = @(& $finde $ohne)
    if ($rest.Count -gt 0) {
        throw [System.InvalidOperationException]::new(
            ('In "{0}" stehen nach dem Entfernen noch {1} Belegfelder.' -f $LiteralPath, $rest.Count))
    }

    return $ohne
}

function ConvertTo-SynopsisHilfe {
    <#
    .SYNOPSIS
        Verdichtet einen Hilfekommentar auf seinen .SYNOPSIS-Abschnitt, ohne
        projektinterne Verweise, neu umbrochen.
    .DESCRIPTION
        Das Buendel ist zur Weitergabe bestimmt. Verweise wie "(Phase 5, D-11)"
        oder ein Vorspann "PRE-06:" zeigen in die Planungsunterlagen dieses
        Repositoriums und sind ausserhalb davon bedeutungslos. UTF-8 und
        SHA-256 sehen aus wie solche Kennungen und sind ausgenommen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Kommentar,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Einzug
    )

    $woerter = [System.Collections.Generic.List[string]]::new()
    $imAbschnitt = $false

    foreach ($zeile in @($Kommentar.Replace("`r`n", "`n") -split "`n")) {
        $t = $zeile.Trim()
        if ($t -ieq '.SYNOPSIS') { $imAbschnitt = $true; continue }
        if (-not $imAbschnitt) { continue }
        if ($t.StartsWith('.') -or $t.StartsWith('#>')) { break }
        foreach ($w in @($t -split '\s+')) {
            if ($w.Length -gt 0) { $woerter.Add($w) }
        }
    }

    $satz = ($woerter -join ' ')

    $kennung = '(?:Phase \d+|D\d+|(?!UTF-|SHA-)[A-Z][A-Za-z]*-\d+(?:-\d+)?[a-z]?|\d{2}-\d{2})'
    $verweis = ('^(?:{0}(?:\s*(?:/|und|bis)\s*{0})*|Planerentscheide? [\d ,und]+(?:aus \d{{2}}-\d{{2}})?|\S+\.md\b.*|Welle \d+)$' -f $kennung)

    # Klammern ohne innere Klammern: jeder durch Komma getrennte Teil, der ein
    # Verweis ist, faellt weg; bleibt nichts uebrig, faellt die Klammer weg.
    $satz = [regex]::Replace($satz, '\s*\(([^()]*)\)', {
        param($treffer)
        $reste = @(
            $treffer.Groups[1].Value -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_.Length -gt 0 -and $_ -notmatch $verweis }
        )
        if ($reste.Count -eq 0) { return '' }
        if ($reste.Count -eq @($treffer.Groups[1].Value -split ',').Count) { return $treffer.Value }
        return (' (' + ($reste -join ', ') + ')')
    })
    $satz = [regex]::Replace($satz, ('^{0}(?:\s*,\s*{0})*\s*:\s*' -f $kennung), '')
    $satz = $satz.Trim()

    if ($satz.Length -eq 0) { return '' }

    $satz = $satz.Substring(0, 1).ToUpperInvariant() + $satz.Substring(1)

    $breite = [System.Math]::Max(40, 80 - $Einzug.Length - 4)
    $zeilen = [System.Collections.Generic.List[string]]::new()
    $aktuell = ''

    foreach ($w in @($satz -split ' ')) {
        if ($aktuell.Length -gt 0 -and ($aktuell.Length + 1 + $w.Length) -gt $breite) {
            $zeilen.Add($aktuell)
            $aktuell = $w
        }
        elseif ($aktuell.Length -eq 0) { $aktuell = $w }
        else { $aktuell = $aktuell + ' ' + $w }
    }
    if ($aktuell.Length -gt 0) { $zeilen.Add($aktuell) }

    $teile = @('<#', ($Einzug + '.SYNOPSIS'))
    foreach ($z in $zeilen) { $teile += ($Einzug + '    ' + $z) }
    $teile += ($Einzug + '#>')

    return ($teile -join $Crlf)
}

function Remove-Kommentar {
    <#
    .SYNOPSIS
        Entfernt aus PowerShell-Quelltext jeden Kommentar ausser der auf
        .SYNOPSIS verdichteten Funktionshilfe.
    .DESCRIPTION
        Gearbeitet wird auf den Marken des Parsers, nicht mit Mustern -- ein
        Rautezeichen in einer Zeichenkette ist kein Kommentar. Danach werden
        Zeilenenden getrimmt und Leerzeilenfolgen auf eine verdichtet, jedoch
        nie innerhalb einer mehrzeiligen Zeichenkette: deren Inhalt ist
        Ausgabetext und bleibt zeichengleich.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $marken = $null
    $fehler = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref] $marken, [ref] $fehler)

    if (@($fehler).Count -gt 0) {
        throw [System.IO.InvalidDataException]::new(
            ('"{0}" hat {1} Parsefehler; der erste lautet: {2}' -f
                $LiteralPath, @($fehler).Count, @($fehler)[0].Message))
    }

    $kommentare = @($marken | Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment })
    [System.Array]::Reverse($kommentare)

    $sb = [System.Text.StringBuilder]::new($Text)

    foreach ($k in $kommentare) {
        $start = $k.Extent.StartOffset
        $ende = $k.Extent.EndOffset
        $ersatz = ''

        if ($k.Text.StartsWith('<#') -and $k.Text -match '(?im)^\s*\.SYNOPSIS\s*$') {
            $zeilenAnfang = 0
            if ($start -gt 0) { $zeilenAnfang = $Text.LastIndexOf("`n", $start - 1) + 1 }
            $einzug = $Text.Substring($zeilenAnfang, $start - $zeilenAnfang)
            if ($einzug.Trim().Length -ne 0) { $einzug = '' }
            $ersatz = ConvertTo-SynopsisHilfe -Kommentar $k.Text -Einzug $einzug
        }
        elseif ($start -gt 0 -and $ende -lt $Text.Length -and
                -not [char]::IsWhiteSpace($Text[$start - 1]) -and
                -not [char]::IsWhiteSpace($Text[$ende])) {
            $ersatz = ' '
        }

        $null = $sb.Remove($start, $ende - $start).Insert($start, $ersatz)
    }

    $ohne = $sb.ToString()

    $marken = $null
    $fehler = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($ohne, [ref] $marken, [ref] $fehler)

    if (@($fehler).Count -gt 0) {
        throw [System.InvalidOperationException]::new(
            ('"{0}" ist nach dem Entfernen der Kommentare nicht mehr parsebar: {1}' -f
                $LiteralPath, @($fehler)[0].Message))
    }

    $zeichenketten = @(
        [System.Management.Automation.Language.TokenKind]::StringLiteral
        [System.Management.Automation.Language.TokenKind]::StringExpandable
        [System.Management.Automation.Language.TokenKind]::HereStringLiteral
        [System.Management.Automation.Language.TokenKind]::HereStringExpandable
    )

    $geschuetzt = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($m in @($marken)) {
        if ($zeichenketten -contains $m.Kind -and
            $m.Extent.EndLineNumber -gt $m.Extent.StartLineNumber) {
            for ($n = $m.Extent.StartLineNumber + 1; $n -le $m.Extent.EndLineNumber; $n++) {
                $null = $geschuetzt.Add($n)
            }
        }
    }

    $aus = [System.Collections.Generic.List[string]]::new()
    $vorigeLeer = $true
    $nummer = 0

    foreach ($zeile in @($ohne -split $Crlf)) {
        $nummer++
        if ($geschuetzt.Contains($nummer)) {
            $aus.Add($zeile)
            $vorigeLeer = $false
            continue
        }
        $z = $zeile.TrimEnd()
        if ($z.Length -eq 0) {
            $oeffnet = $aus.Count -gt 0 -and ($aus[$aus.Count - 1].EndsWith('{') -or $aus[$aus.Count - 1].EndsWith('('))
            if (-not $vorigeLeer -and -not $oeffnet) { $aus.Add('') }
            $vorigeLeer = $true
            continue
        }
        $schliesst = $z.TrimStart().StartsWith('}') -or $z.TrimStart().StartsWith(')')
        if ($schliesst -and $vorigeLeer -and $aus.Count -gt 0 -and $aus[$aus.Count - 1].Length -eq 0) {
            $aus.RemoveAt($aus.Count - 1)
        }
        $aus.Add($z)
        $vorigeLeer = $false
    }

    while ($aus.Count -gt 0 -and $aus[$aus.Count - 1].Length -eq 0) {
        $aus.RemoveAt($aus.Count - 1)
    }

    return ($aus -join $Crlf)
}

# --- 3. Quellen sammeln ------------------------------------------------------

$ModulOrdner = [System.IO.Path]::Combine($Wurzel, 'DemFsAcl')

# Beide Dateien sind der Dateizugriff des Moduls. Das Buendel ersetzt sie durch
# ein Get-DataTable, das die Tabellen aus dem Code liefert (Abschnitt 4).
$NurImModul = @('Get-DataPath.ps1', 'Get-DataTable.ps1')

$Quellpfade = [System.Collections.Generic.List[string]]::new()

foreach ($unterordner in @('Private', 'Interaction', 'Public')) {
    $ordner = [System.IO.Path]::Combine($ModulOrdner, $unterordner)
    foreach ($pfad in (Get-OrdinalDatei -Ordner $ordner -Erweiterung '.ps1')) {
        if ($NurImModul -contains [System.IO.Path]::GetFileName($pfad)) { continue }
        $Quellpfade.Add($pfad)
    }
}

foreach ($name in $NurImModul) {
    if (-not (Test-Path -LiteralPath ([System.IO.Path]::Combine($ModulOrdner, 'Private', $name)))) {
        throw [System.IO.FileNotFoundException]::new(
            ('Die Moduldatei "Private/{0}" fehlt. Bauskript und Modul sind auseinandergelaufen.' -f $name))
    }
}

# --- 4. Datentabellen einbetten ----------------------------------------------

$DatenOrdner = [System.IO.Path]::Combine($ModulOrdner, 'Data')
$Datenpfade = Get-OrdinalDatei -Ordner $DatenOrdner -Erweiterung '.psd1'

# Das Buendel fuehrt keine Herstellerbelege (Entscheidung 2026-09-23). Sie
# dienen nur der Belegzeile in der Ausgabe; ACL, Freigaben und Vergleich
# haengen an keinem dieser Felder. Der Vorlauf setzt dazu
# $script:MitBelegen = $false, siehe Test-MitBeleg.
$Belegschluessel = @(
    'Status', 'Source', 'Section'
    'ProtectInheritanceStatus', 'ProtectInheritanceSource', 'ProtectInheritanceSection'
)

$Tabellennamen = [System.Collections.Generic.List[string]]::new()
$Zweige = [System.Collections.Generic.List[string]]::new()

foreach ($pfad in $Datenpfade) {

    $text = Read-Quelltext -LiteralPath $pfad
    Assert-Datentabelle -Text $text -LiteralPath $pfad

    $text = Remove-Datenschluessel -Text $text -Schluessel $Belegschluessel -LiteralPath $pfad
    $text = Remove-Kommentar -Text $text -LiteralPath $pfad

    $name = [System.IO.Path]::GetFileNameWithoutExtension($pfad)
    $Tabellennamen.Add($name)

    # Die Tabelle wird JE AUFRUF neu ausgewertet: jeder Aufrufer bekommt wie
    # beim Lesen der Datei ein frisches Objekt und kann es nicht fuer den
    # naechsten veraendern.
    $eingerueckt = @(
        @($text -split $Crlf) | ForEach-Object {
            if ($_.Length -eq 0) { '' } else { '            ' + $_ }
        }
    ) -join $Crlf

    $Zweige.Add(("        '{0}' {{" -f $name))
    $Zweige.Add(('            return ' + $eingerueckt.TrimStart()))
    $Zweige.Add('        }')
}

$Datenblock = @(
    'function Get-DataTable {'
    '    <#'
    '    .SYNOPSIS'
    '        Liefert eine der eingebauten Datentabellen als Hashtable.'
    '    #>'
    '    [CmdletBinding()]'
    '    [OutputType([hashtable])]'
    '    param('
    '        [Parameter(Mandatory)]'
    ("        [ValidateSet({0})]" -f (@($Tabellennamen | ForEach-Object { "'{0}'" -f $_ }) -join ', '))
    '        [string] $Name'
    '    )'
    ''
    '    switch ($Name) {'
    @($Zweige)
    '    }'
    '}'
) -join $Crlf

# --- 5. Vorlauf --------------------------------------------------------------

# Aus dem .psm1 zaehlt nur Set-StrictMode; seine Ladeschleife und
# $script:ModuleRoot sind im Buendel gegenstandslos.
#
# SELBSTHEILUNG BEI VERLORENEM BOM (Serverlauf 2026-09-25). Wird das Buendel
# ohne BOM weitergegeben -- etwa ueber die Zwischenablage in einen Editor, der
# UTF-8 ohne Signatur speichert --, liest Windows PowerShell 5.1 es als ANSI,
# und jeder Umlaut erscheint als zwei Fremdzeichen (Mojibake). Der Probe-Literal besteht
# aus genau einem Umlaut: richtig gelesen hat er die Laenge 1, als ANSI gelesen
# die Laenge 2. Dann liest das Buendel sich selbst als UTF-8 neu ein und laeuft
# als Skriptblock; dessen exit beendet das Skript mit dem Rueckgabewert des
# Laufs. Der Literal entsteht hier aus seinem Zeichencode, damit das Bauskript
# selbst ASCII bleibt. Tests/Bundle.Tests.ps1 belegt, dass das Buendel auch als
# ANSI gelesen fehlerfrei parst -- sonst kaeme die Probe gar nicht zum Zug.
$Vorlauf = @'
Set-StrictMode -Version Latest
$script:MitBelegen = $false
if ('__UMLAUT__'.Length -ne 1) {
    $utf8OhneBom = [System.Text.UTF8Encoding]::new($false)
    $eigeneQuelle = [System.IO.File]::ReadAllText($PSCommandPath, $utf8OhneBom)
    & ([scriptblock]::Create($eigeneQuelle))
    exit $LASTEXITCODE
}
'@.Replace('__UMLAUT__', [string] [char] 0xE4)

# --- 6. Quellen ausschreiben -------------------------------------------------

# Die Quellen gehen OHNE ihre Kommentare ins Buendel; erhalten bleibt je
# Funktion die auf .SYNOPSIS verdichtete Hilfe. Die Begruendungen gehoeren zum
# Repositorium, nicht zur weitergegebenen Datei (Entscheidung 2026-09-23).
$QuellTeile = [System.Collections.Generic.List[string]]::new()

foreach ($pfad in $Quellpfade) {
    $QuellTeile.Add((Remove-Kommentar -Text (Read-Quelltext -LiteralPath $pfad) -LiteralPath $pfad))
    $QuellTeile.Add('')
}

$Quellblock = ($QuellTeile -join $Crlf)

# --- 7. Einstieg uebernehmen -------------------------------------------------

$EinstiegPfad = [System.IO.Path]::Combine($Wurzel, 'FSLogix-DEM-ShareProvisioning.ps1')
$EinstiegQuelle = Read-Quelltext -LiteralPath $EinstiegPfad

$marken = $null
$fehler = $null
$einstiegAst = [System.Management.Automation.Language.Parser]::ParseInput(
    $EinstiegQuelle, [ref] $marken, [ref] $fehler)

if (@($fehler).Count -gt 0) {
    throw [System.IO.InvalidDataException]::new(
        ('Das Einstiegsskript "{0}" hat {1} Parsefehler.' -f $EinstiegPfad, @($fehler).Count))
}

$einstiegAnweisungen = @($einstiegAst.EndBlock.Statements)

if ($einstiegAnweisungen.Count -eq 0) {
    throw [System.IO.InvalidDataException]::new(
        ('Das Einstiegsskript "{0}" enthaelt keine Anweisung.' -f $EinstiegPfad))
}

# Ab der Startstelle der ERSTEN Anweisung: damit faellt der Kommentarkopf weg,
# dessen Satz ueber das Laden des Nachbarordners im Buendel schlicht falsch waere.
$Einstieg = $EinstiegQuelle.Substring($einstiegAnweisungen[0].Extent.StartOffset)

$einstiegZeilen = @($Einstieg -split $Crlf)

foreach ($anker in @($AnkerManifest, $AnkerImport)) {

    $treffer = @($einstiegZeilen | Where-Object { $_.Trim() -eq $anker })

    if ($treffer.Count -ne 1) {
        throw [System.InvalidOperationException]::new(
            ('Der Anker "{0}" kommt in "{1}" {2} mal vor statt genau einmal. Wurzelskript und Buendel sind auseinandergelaufen.' -f
                $anker, $EinstiegPfad, $treffer.Count))
    }
}

$Einstieg = @(
    $einstiegZeilen |
        Where-Object { $_.Trim() -ne $AnkerManifest -and $_.Trim() -ne $AnkerImport }
) -join $Crlf

$Einstieg = Remove-Kommentar -Text $Einstieg -LiteralPath $EinstiegPfad

# --- 8. Quellstand erheben ---------------------------------------------------

# Ohne belegbaren Quellstand entsteht kein Buendel: ein Buendel, dessen Herkunft
# niemand nachrechnen kann, ist genau das Problem, das BUILD-06 abstellen soll.
$CommitLauf = Invoke-Git -Argumente @('-C', $Wurzel, 'rev-parse', 'HEAD')

if ($CommitLauf.ExitCode -ne 0) {
    throw [System.InvalidOperationException]::new(
        ('git rev-parse HEAD endete mit {0}. Ohne belegbaren Quellstand entsteht kein Buendel. Meldung: {1}' -f
            $CommitLauf.ExitCode, ($CommitLauf.Ausgabe -join ' ')))
}

$QuellCommit = ([string] (@($CommitLauf.Ausgabe)[0])).Trim()

if ($QuellCommit -cnotmatch '^[0-9a-f]{40}$') {
    throw [System.InvalidOperationException]::new(
        ('git rev-parse HEAD lieferte "{0}" statt 40 Hexstellen. Ohne belegbaren Quellstand entsteht kein Buendel.' -f
            $QuellCommit))
}

# Der Pfadfilter ist Teil der Zusage: eine Aenderung unter .planning/ veraendert
# das Buendel nicht und darf seinen Kopf nicht bewegen.
$StandLauf = Invoke-Git -Argumente @(
    '-C', $Wurzel, 'status', '--porcelain', '--', 'DemFsAcl', 'FSLogix-DEM-ShareProvisioning.ps1')

if ($StandLauf.ExitCode -ne 0) {
    throw [System.InvalidOperationException]::new(
        ('git status --porcelain endete mit {0}. Meldung: {1}' -f
            $StandLauf.ExitCode, ($StandLauf.Ausgabe -join ' ')))
}

$StandZeilen = @($StandLauf.Ausgabe | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$Quellstand = 'sauber'
if ($StandZeilen.Count -gt 0) { $Quellstand = 'mit lokalen Aenderungen' }

# InvariantCulture ausdruecklich: auf einem de-DE-Server liefert die
# Standardformatierung sonst eine andere Schreibweise. Feste Laenge (20
# Zeichen), damit zwei Baulaeufe dieselbe Bytezahl ergeben.
$Zeitpunkt = [System.DateTime]::UtcNow.ToString(
    'yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

# --- 9. Zusammensetzen -------------------------------------------------------

# Zwei Kopfzeilen unter #Requires, dann der Rumpf. Keine Marker, kein Verweis
# auf eine andere Datei: das Buendel ist ein eigenstaendiges Skript.
$Kopf = @(
    '#Requires -Version 5.1'
    ($VorlageCommit -f $QuellCommit)
    ($VorlageErzeugt -f $Zeitpunkt, $Quellstand)
) -join $Crlf

$Rumpf = @(
    $Vorlauf
    ''
    $Datenblock
    ''
    $Quellblock
    $Einstieg
) -join $Crlf

$Inhalt = ConvertTo-Crlf -Text ($Kopf + $Crlf + $Rumpf + $Crlf)

# --- 10. Schreiben -----------------------------------------------------------

$AusgabeOrdner = [System.IO.Path]::Combine($Wurzel, 'dist')

if (-not (Test-Path -LiteralPath $AusgabeOrdner)) {
    $null = New-Item -Path $AusgabeOrdner -ItemType Directory -Force
}

$Ausgabepfad = [System.IO.Path]::Combine($AusgabeOrdner, 'FSLogix-DEM-ShareProvisioning.ps1')

# UTF8Encoding mit Signatur: ohne BOM liest Windows PowerShell 5.1 die Datei als
# ANSI, und jeder deutsche Umlaut in einem Ausgabetext wird zu Mojibake.
[System.IO.File]::WriteAllText($Ausgabepfad, $Inhalt, [System.Text.UTF8Encoding]::new($true))

$Bytezahl = [System.IO.File]::ReadAllBytes($Ausgabepfad).Length
$Zeilenzahl = @($Inhalt.TrimEnd() -split $Crlf).Count

Write-Output ('Buendel: {0} ({1} Bytes, {2} Zeilen)' -f $Ausgabepfad, $Bytezahl, $Zeilenzahl)
