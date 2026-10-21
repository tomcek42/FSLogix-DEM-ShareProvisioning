<#
    ConvertTo-AceKey -- die EINE Normalisierungsstelle des Vergleichs
    (VERIFY-03, VERIFY-04). Soll- und Ist-Seite laufen durch dieselbe Funktion;
    eine zweite Normalisierung irgendwo im Werkzeug waere eine zweite Wahrheit
    ueber dieselbe Regel.

    DIE ENTSCHEIDUNG (Plan 02-01, Aufgabe 2, eingefroren): ausdruecklich-
    beidseitig.
      1. Rechtemaske als [int]; bei Zugriffstyp Allow wird 0x100000
         (Synchronize) hineingeODERt.
      2. InheritanceFlags und PropagationFlags als [int]; ist Inheritance 0,
         wird Propagation auf 0 gesetzt.
    Beides auf BEIDEN Seiten und ausdruecklich hier, nicht implizit dem
    .NET-Konstruktor ueberlassen.

    MESSBELEG: Tests/Fixtures/AclRoundTrip.Measured.psd1, Block Rule
    (SynchronizeAutoOrAt = Constructor, PropagationNormalizedAt = Constructor,
    NormalizeSide = ausdruecklich-beidseitig). Die Messung zeigt, dass der
    FileSystemAccessRule-Konstruktor beides bereits tut -- Modify (0x301BF)
    kommt als 0x1301BF zurueck. Fuer Regeln aus dem Konstruktor ist die
    Veroderung hier deshalb idempotent. Sie bleibt trotzdem noetig: Regeln aus
    einer SDDL-Zeile oder aus einem kuenftigen Lesepfad gehen nicht durch
    diesen Konstruktor, und der Vergleich darf nicht davon abhaengen, auf
    welchem Weg eine Regel entstanden ist. Tests/Compare-AceSet.Tests.ps1
    nagelt die Seite fest (Soll UND Ist tragen 1245631).

    Gerechnet wird ausschliesslich numerisch. FileSystemRights ist ein
    Flags-Enum mit Aliasen -- 4 druckt sich als AppendData oder als
    CreateDirectories --, und keine Zusage darf an einer Druckform haengen.

    STOLPERDRAHT: eine IdentityReference, die kein SecurityIdentifier ist,
    bricht ab. Ein NTAccount im Vergleichspfad ist ein lokalisierter Name, und
    genau gegen den Vergleich ueber lokalisierte Namen ist das Werkzeug gebaut.
    Die Pruefung faengt jede kuenftige Lesestelle ab, die das dritte Argument
    von GetAccessRules vergisst.

    Rein: kein Dateisystemzugriff, keine Ausgabe.
#>

function ConvertTo-AceKey {
    <#
    .SYNOPSIS
        Normalisiert eine FileSystemAccessRule zum Vergleichsdatensatz.

    .OUTPUTS
        [pscustomobject] mit Key, Sid, AccessControlType, Rights, Inheritance,
        Propagation, IsInherited. Key = "SID|Typ|Maske|Inheritance|Propagation".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemAccessRule] $Ace
    )

    if ($Ace.IdentityReference -isnot [System.Security.Principal.SecurityIdentifier]) {
        throw [System.ArgumentException]::new(
            ('ConvertTo-AceKey erwartet eine SID-typisierte Regel, erhalten: {0}. Lesestellen müssen GetAccessRules(..., [SecurityIdentifier]) verwenden.' -f
                $Ace.IdentityReference.GetType().Name))
    }

    $typ = [int] $Ace.AccessControlType
    $maske = [int] $Ace.FileSystemRights

    if ($Ace.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
        $maske = $maske -bor 0x100000
    }

    $inheritance = [int] $Ace.InheritanceFlags
    $propagation = [int] $Ace.PropagationFlags

    if ($inheritance -eq 0) {
        $propagation = 0
    }

    $sid = $Ace.IdentityReference.Value

    return [pscustomobject] @{
        Key               = ('{0}|{1}|{2}|{3}|{4}' -f $sid, $typ, $maske, $inheritance, $propagation)
        Sid               = $sid
        AccessControlType = $typ
        Rights            = $maske
        Inheritance       = $inheritance
        Propagation       = $propagation
        IsInherited       = [bool] $Ace.IsInherited
    }
}
