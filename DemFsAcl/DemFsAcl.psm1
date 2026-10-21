#Requires -Version 5.1

Set-StrictMode -Version Latest

<#
    DemFsAcl -- Wurzeldatei des Moduls.

    Set-StrictMode steht bewusst als erste Anweisung: damit ist die
    Pitfall-6-Disziplin ab hier tragend statt optional. Eine Funktion, die eine
    moeglicherweise leere Liste liefert, muss beim Aufrufer in @(...) stehen --
    PowerShell entrollt eine leere Liste zu nichts, und $null.Count ist unter
    StrictMode ein Fehler.
#>

# Die Modulwurzel wird hier gesetzt und nicht in den geladenen Einzeldateien.
# In einer per Punktoperator aus Private/ geladenen Datei zeigt $PSScriptRoot
# auf Private/ und damit eine Ebene zu tief (RESEARCH Pattern 7).
$script:ModuleRoot = $PSScriptRoot

# Private vor Interaction vor Public. Interaction steht nach Private, weil die
# Dialogschicht private Funktionen ruft, und vor Public, weil die
# Orchestrierung auf ihr aufsetzt. Der eigene Ordner ist die technische
# Umsetzung von D-04: damit wird FLOW-08 ("kein Eingabeaufruf unterhalb der
# Dialogschicht") als Ordnerregel pruefbar statt als gepflegte Ausnahmeliste
# von Funktionsnamen, die veraltet.
foreach ($unterordner in @('Private', 'Interaction', 'Public')) {

    $ordner = [System.IO.Path]::Combine($script:ModuleRoot, $unterordner)

    if (-not (Test-Path -LiteralPath $ordner)) {
        continue
    }

    # Auswahl ueber die Erweiterung: -Filter '*.ps1' geht ueber die
    # Windows-Wildcardmaschine und traefe auch '*.ps1x'.
    # @(...) beim Aufrufer, damit .Count auch bei null Treffern traegt.
    $quellen = @(
        Get-ChildItem -LiteralPath $ordner -File |
            Where-Object { $_.Extension -eq '.ps1' } |
            Sort-Object -Property Name
    )

    foreach ($quelle in $quellen) {
        . $quelle.FullName
    }
}
