<#
    Set-DirectoryAcl -- die EINZIGE Stelle dieses Werkzeugs, die einen
    Sicherheitsdeskriptor auf die Platte schreibt (D-13), spiegelbildlich zu
    Get-ActualAceSet als einziger Lesestelle.

    WARUM DIESE INDIREKTION KEINE ZIERERREI IST: zwei Wege zum Zustand heisst,
    die Verifikation prueft moeglicherweise den anderen. Die Seam nachtraeglich
    einzuziehen hiesse ausserdem, jede Schreibstelle und jeden Test anzufassen,
    der sie ersetzt -- und der Editionsunterschied unten fiele dann in jeder
    einzelnen davon neu an. Die Entscheidung ist in 03-CONTEXT.md als costly
    eingestuft und getroffen.

    Die Funktion ist absichtlich so duenn wie Get-ActualAceSet: die pruefbare
    Aufbereitung liegt daneben in New-DesiredDirectorySecurity und ist dort
    ohne Dateisystem pruefbar. Je weniger hier steht, desto weniger geht
    verloren, wenn ein Test diese Funktion ersetzt.

    DER EINE ORT FUER DEN EDITIONSUNTERSCHIED 5.1 GEGEN 7: in Windows
    PowerShell 5.1 traegt DirectoryInfo.SetAccessControl als Instanzmethode; in
    PowerShell Core wurde sie aus dem Typ entfernt und laeuft ueber die
    Erweiterungsklasse [System.IO.FileSystemAclExtensions]. Beides steht hier
    und ausschliesslich hier.

    GESCHRIEBEN WIRD AUSSCHLIESSLICH DER ACCESS-ABSCHNITT, UND ZWAR
    KONSTRUKTIONSBEDINGT: der uebergebene Deskriptor kommt frisch aus
    New-DesiredDirectorySecurity, dort wurde nie ein Besitzer gesetzt, also ist
    nur der DACL-Abschnitt als geaendert markiert und nur er wird geschrieben
    (ACL-05). Diese Begruendung steht hier, weil sie sonst beim naechsten Umbau
    verloren geht: den Besitzer eines bestehenden Ordners zu aendern ist ein
    zerstoerender Eingriff, den keine Anforderung deckt.

    Kein icacls.exe -- dessen Ausgabe ist lokalisiert und auf deutschem Windows
    nicht auswertbar. Kein Write-Host, kein Read-Host: die Funktion gibt
    zurueck oder wirft.

    ACHTUNG, DER GRUND FUER DIE VERIFIKATIONSSTUFE: ein erfolgreicher Aufruf
    hier ist KEIN Nachweis. Die Schreib-API meldet Erfolg auch bei
    Teilfehlschlag; nur das Ruecklesen in Invoke-AclApply beweist das Ergebnis.
#>

function Set-DirectoryAcl {
    <#
    .SYNOPSIS
        Schreibt einen DirectorySecurity-Deskriptor auf genau einen Ordner.

    .DESCRIPTION
        Kein Abstieg, keine Schleife ueber Kindelemente, kein -Recurse: auf
        einem FSLogix-Share ueberschriebe ein rekursiver Lauf die per
        Ersteller-Besitzer entstandenen Benutzer-ACEs und entzoege jedem Nutzer
        den Zugriff auf sein eigenes Profil (ACL-07).

    .PARAMETER LiteralPath
        Der Zielordner. -LiteralPath und nicht -Path: alle Pfadeingaben dieses
        Werkzeugs laufen ohne Wildcard-Interpretation (C-09).

    .PARAMETER DirectorySecurity
        Der zu schreibende Deskriptor, ueblicherweise aus
        New-DesiredDirectorySecurity.

    .EXAMPLE
        Set-DirectoryAcl -LiteralPath 'D:\Shares\Profiles' -DirectorySecurity $deskriptor
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [System.Security.AccessControl.DirectorySecurity] $DirectorySecurity
    )

    $ordner = [System.IO.DirectoryInfo]::new($LiteralPath)

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        # Windows PowerShell 5.1.
        $ordner.SetAccessControl($DirectorySecurity)
    }
    else {
        # PowerShell 7 und neuer.
        [System.IO.FileSystemAclExtensions]::SetAccessControl($ordner, $DirectorySecurity)
    }
}
