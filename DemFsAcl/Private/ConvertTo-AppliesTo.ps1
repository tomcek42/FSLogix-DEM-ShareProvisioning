<#
    ConvertTo-AppliesTo -- die EINZIGE Stelle des Werkzeugs, die die sieben
    Gilt-fuer-Kombinationen kennt. Keine zweite Kopie der Tabelle irgendwo im
    Werkzeug: die naechste Kopie driftet.

    Quelle: .planning/research/FEATURES.md Abschnitt 1.0, Notationstabelle,
    in derselben Reihenfolge.

    Die Funktion WIRFT NICHT. Ein Paar ausserhalb der sieben liefert
    IsStandard = $false. Die Ist-Seite eines Vergleichs darf legitim ein achtes
    Paar tragen (etwa mit NoPropagateInherit) -- der Vergleich soll das als
    Befund melden, nicht selbst daran scheitern. Die Politik, dass ein
    TEMPLATE nur die sieben fuehren darf, liegt beim Binder
    (Expand-AclTemplate).

    Normalisierung vor dem Nachschlagen: ist Inheritance 0, wird Propagation
    auf 0 gesetzt. Das ist die in 02-01 eingefrorene Regel
    (ausdruecklich-beidseitig); die Messung in
    Tests/Fixtures/AclRoundTrip.Measured.psd1 zeigt, dass der .NET-Konstruktor
    genauso verfaehrt. Wer die Zeile fuer redundant haelt: sie ist es nur fuer
    Regeln aus dem Konstruktor, nicht fuer Werte aus einer SDDL-Zeile.

    Gerechnet wird ausschliesslich mit [int], nie ueber .ToString(): die
    Flagtypen sind Flags-Enums, und ihre Druckform ist keine Vergleichsbasis.
#>

function ConvertTo-AppliesTo {
    <#
    .SYNOPSIS
        Beschriftet ein InheritanceFlags/PropagationFlags-Paar mit seiner
        Gilt-fuer-Bezeichnung und icacls-Buchstabenform.

    .OUTPUTS
        [pscustomobject] mit AppliesTo, Icacls, Inheritance, Propagation, IsStandard.
    #>
    [CmdletBinding()]
    param(
        # [object], damit Enum und benannte Zeichenkettenform gleichermassen passen.
        [Parameter(Mandatory)]
        [object] $Inheritance,

        [Parameter(Mandatory)]
        [object] $Propagation
    )

    $i = [int] ([System.Security.AccessControl.InheritanceFlags] $Inheritance)
    $p = [int] ([System.Security.AccessControl.PropagationFlags] $Propagation)

    if ($i -eq 0) {
        $p = 0
    }

    # Schluessel "Inheritance|Propagation". ContainerInherit = 1,
    # ObjectInherit = 2, InheritOnly = 2.
    $tabelle = @{
        '0|0' = @('Nur dieser Ordner', '')                                  # FEATURES 1.0, Zeile 1
        '3|0' = @('Dieser Ordner, Unterordner und Dateien', '(OI)(CI)')     # FEATURES 1.0, Zeile 2
        '1|0' = @('Dieser Ordner und Unterordner', '(CI)')                  # FEATURES 1.0, Zeile 3
        '2|0' = @('Dieser Ordner und Dateien', '(OI)')                      # FEATURES 1.0, Zeile 4
        '3|2' = @('Nur Unterordner und Dateien', '(OI)(CI)(IO)')            # FEATURES 1.0, Zeile 5
        '1|2' = @('Nur Unterordner', '(CI)(IO)')                            # FEATURES 1.0, Zeile 6
        '2|2' = @('Nur Dateien', '(OI)(IO)')                                # FEATURES 1.0, Zeile 7
    }

    $schluessel = '{0}|{1}' -f $i, $p

    if ($tabelle.ContainsKey($schluessel)) {
        $bezeichnung = $tabelle[$schluessel][0]
        $icacls = $tabelle[$schluessel][1]
        $standard = $true
    }
    else {
        $bezeichnung = '(nicht standardisiert)'
        $icacls = ''
        $standard = $false
    }

    return [pscustomobject] @{
        AppliesTo   = $bezeichnung
        Icacls      = $icacls
        Inheritance = $i
        Propagation = $p
        IsStandard  = $standard
    }
}
