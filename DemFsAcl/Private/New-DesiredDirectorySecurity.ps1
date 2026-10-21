<#
    New-DesiredDirectorySecurity -- die pruefbare Aufbereitung des
    Soll-Deskriptors (ACL-02, ACL-03, ACL-08).

    REIN: kein Dateisystemzugriff, kein Pfadparameter, keine Ausgabe. Damit
    laesst sich die gesamte Zusage "frisches Objekt, Vererbungsschutz vor den
    Regeln, Reihenfolge unveraendert" offline pruefen, ohne einen einzigen
    Schreibvorgang. Geschrieben wird daneben in Set-DirectoryAcl -- derselbe
    Zuschnitt wie Get-ActualAceSet und ConvertTo-ActualAceSet auf der
    Leseseite.

    DIE REIHENFOLGE IM RUMPF IST DER GANZE PUNKT DER FUNKTION:

    1. Ein FRISCHES DirectorySecurity per Konstruktor. Ein gelesenes ACL
       fortzuschreiben fuehrt zu einem stillen No-Op statt zu einem Fehler --
       das ist einer der vier ACL-Fallstricke aus CLAUDE.md.
    2. SetAccessRuleProtection($true, $false) VOR der ersten Regel. Erster
       Parameter wahr: Vererbung geschuetzt. Zweiter Parameter falsch: geerbte
       Eintraege werden ENTFERNT, nicht kopiert. Umgekehrte Reihenfolge
       uebernaehme die geerbten Eintraege als explizite -- und nichts wuerde
       dabei rot.
    3. Der ACL-08-Waechter, bevor irgendetwas hinzugefuegt wird.
    4. Die Aces des DesiredAcl UNVERAENDERT und in der gelieferten
       Reihenfolge. Expand-AclTemplate liefert bereits kanonisch sortiert
       (ACL-04, in Phase 2 belegt); ein zweites Sortierverstaendnis hier waere
       eine zweite Wahrheit.

    DER WAECHTER IST EINE POSITIVLISTE, UND DAS IST ABSICHT. Durchgelassen
    wird ausschliesslich der zulassende Zugriffstyp; alles andere bricht ab.
    Zwei Gruende: eine Positivliste weist auch einen kuenftigen, hier noch
    unbekannten Zugriffstyp ab, statt ihn stillschweigend zu schreiben -- und
    sie kommt ohne eine Nennung des verweigernden Enumglieds aus, die das
    strukturelle Gate in Tests/AclWriteSeam.Tests.ps1 im Modulschreibpfad
    ausdruecklich in null Dateien erwartet. Verglichen wird ueber den Enumwert,
    nie ueber eine Zeichenkettendarstellung: FileSystemRights und die
    Zugriffstypen sind Enums mit Aliasen, und keine Zusage dieses Werkzeugs
    darf an einer Druckform haengen.
#>

function New-DesiredDirectorySecurity {
    <#
    .SYNOPSIS
        Baut aus einem DesiredAcl einen frischen, geschuetzten
        DirectorySecurity-Deskriptor.

    .PARAMETER Desired
        Das Ergebnis von Expand-AclTemplate: Kind, ProtectInheritance samt
        Provenienzfeldern, Aces mit dem Feld Rule.

    .OUTPUTS
        [System.Security.AccessControl.DirectorySecurity]

    .EXAMPLE
        New-DesiredDirectorySecurity -Desired $soll
    #>
    [CmdletBinding()]
    [OutputType([System.Security.AccessControl.DirectorySecurity])]
    param(
        [Parameter(Mandatory)]
        [object] $Desired
    )

    # 1. Frisches Objekt -- nie ein gelesenes fortschreiben.
    $deskriptor = [System.Security.AccessControl.DirectorySecurity]::new()

    # 2. Schutz VOR den Regeln. Zweites Argument falsch heisst: geerbte
    #    Eintraege entfernen statt kopieren (Erfolgskriterium 4).
    $deskriptor.SetAccessRuleProtection($true, $false)

    $zugelassenerTyp = [System.Security.AccessControl.AccessControlType]::Allow
    $aces = @($Desired.Aces)

    # 3. Der ACL-08-Waechter an der einzigen Stelle, an der ein verweigernder
    #    Eintrag ueberhaupt entstehen koennte.
    for ($k = 0; $k -lt $aces.Count; $k++) {

        if ($aces[$k].Rule.AccessControlType -ne $zugelassenerTyp) {
            throw [System.InvalidOperationException]::new(
                ('Ordnerart {0}, ACE {1} ({2}): der Zugriffstyp mit dem Enumwert {3} ist nicht zugelassen. Dieses Werkzeug schreibt ausschließlich zulassende Einträge -- ein verweigernder Eintrag wertet vor jedem zulassenden aus und ist die klassische Ursache unwiederbringlicher Aussperrungen (ACL-08).' -f
                    [string] $Desired.Kind,
                    ($k + 1),
                    [string] $aces[$k].Trustee,
                    [int] $aces[$k].Rule.AccessControlType))
        }
    }

    # 4. Unveraendert, in der Reihenfolge des Binders.
    foreach ($ace in $aces) {
        $deskriptor.AddAccessRule($ace.Rule)
    }

    return $deskriptor
}
