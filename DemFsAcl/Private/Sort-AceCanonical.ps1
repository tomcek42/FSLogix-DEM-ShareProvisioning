<#
    Sort-AceCanonical -- kanonische und deterministische ACE-Reihenfolge, mit
    Deny-Sperre.

    EINGABEFORM, bindend: der ACE-Datensatz, wie ihn Expand-AclTemplate
    erzeugt. Gelesen werden genau sechs Felder unmittelbar vom Datensatz --
    AccessControlType, IsInherited, Sid, Rights, Inheritance, Propagation --
    und NIE ueber Rule. DemFsAcl.psm1 setzt Set-StrictMode -Version Latest; ein
    fehlendes Feld waere ein Laufzeitfehler statt $null. Diese Leseliste und die
    Feldliste des Datensatzes in Expand-AclTemplate sind DIESELBE Zusage: wer
    eine aendert, aendert beide.

    Das Vorhandensein der Felder wird ueber psobject.Properties geprueft und mit
    einer benannten ArgumentException abgewiesen. Das ist keine Nachsicht,
    sondern das Gegenteil: eine Sperre, die vorher an einer Feldabfrage
    stolpert oder defensiv umgangen wird, sperrt nichts.

    DENY: wirft. Deny wertet vor Allow aus und ist die klassische Ursache
    unwiederbringlicher Aussperrungen; keines der drei Herstellerdokumente
    nennt einen. Dass das Templateschema Deny bereits abweist, macht diese
    Sperre nicht ueberfluessig -- ab Phase 3 kommen auch Datensaetze aus einem
    zurueckgelesenen Deskriptor hier an.

    Kanonisch nach Windows-Lesart: explizit Deny, explizit Allow, geerbt Deny,
    geerbt Allow. Da Deny nie durchkommt, bleiben zwei Klassen. Innerhalb der
    Klasse deterministisch ueber einen Schluessel aus SID-Wert, Zugriffstyp,
    Maske, Inheritance und Propagation -- numerisch, nie ueber Enum-Namen, und
    ordinal verglichen, nie kulturabhaengig. Die Arrayreihenfolge des Templates
    ist keine tragfaehige Grundlage (Luecken durch Opt-in); an diesem
    Determinismus haengt die Idempotenzzusage ACL-06 der Phase 3.
#>

function Sort-AceCanonical {
    <#
    .SYNOPSIS
        Sortiert ACE-Datensaetze kanonisch und deterministisch und weist Deny ab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Ace
    )

    $pflichtfelder = @('AccessControlType', 'IsInherited', 'Sid', 'Rights', 'Inheritance', 'Propagation')

    for ($n = 0; $n -lt $Ace.Count; $n++) {
        $datensatz = $Ace[$n]
        if ($null -eq $datensatz) {
            throw [System.ArgumentException]::new(
                ('Sort-AceCanonical: Eintrag {0} ist leer.' -f $n))
        }
        $vorhanden = @($datensatz.psobject.Properties | ForEach-Object { $_.Name })
        foreach ($feld in $pflichtfelder) {
            if ($vorhanden -notcontains $feld) {
                throw [System.ArgumentException]::new(
                    ('Sort-AceCanonical: Eintrag {0} fehlt das Feld "{1}".' -f $n, $feld))
            }
        }
    }

    $schluessel = New-Object System.Collections.Generic.List[string]

    for ($n = 0; $n -lt $Ace.Count; $n++) {
        $datensatz = $Ace[$n]

        $typ = [System.Security.AccessControl.AccessControlType] $datensatz.AccessControlType
        if ($typ -eq [System.Security.AccessControl.AccessControlType]::Deny) {
            throw [System.InvalidOperationException]::new(
                ('Deny-Eintrag für den Prinzipal {0} abgewiesen. Das Werkzeug schreibt keinen einzigen Deny-ACE.' -f $datensatz.Sid))
        }

        $klasse = if ([bool] $datensatz.IsInherited) { 1 } else { 0 }

        # Der Eingabeindex steht nur als letzter Bestandteil im Schluessel, um
        # den Datensatz nach dem Sortieren wiederzufinden. Er entscheidet
        # ausschliesslich zwischen vollstaendig gleichen ACEs, deren Reihenfolge
        # untereinander bedeutungslos ist.
        $schluessel.Add(('{0}|{1}|{2}|{3:D10}|{4}|{5}|{6:D6}' -f
            $klasse,
            ([string] $datensatz.Sid),
            [int] $typ,
            [long] ([int] $datensatz.Rights -band 0xFFFFFFFFL),
            [int] $datensatz.Inheritance,
            [int] $datensatz.Propagation,
            $n))
    }

    # List[string].Sort mit ordinalem Vergleicher: Array.Sort(keys, items, ...)
    # wird von der Overload-Aufloesung in 5.1 nicht verlaesslich getroffen
    # (gemessen: unsortierte Rueckgabe), und Sort-Object vergleicht
    # kulturabhaengig, wobei Bindestriche in SIDs teils ignoriert werden.
    $schluessel.Sort([System.StringComparer]::Ordinal)

    $ergebnis = New-Object System.Collections.Generic.List[object]
    foreach ($s in $schluessel) {
        $index = [int] $s.Substring($s.LastIndexOf('|') + 1)
        $ergebnis.Add($Ace[$index])
    }

    return @($ergebnis.ToArray())
}
