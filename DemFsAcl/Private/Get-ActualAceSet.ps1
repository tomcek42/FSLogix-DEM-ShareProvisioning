<#
    Get-ActualAceSet -- die EINZIGE Stelle dieses Werkzeugs, die einen
    Sicherheitsdeskriptor von der Platte holt (VERIFY-02, Erfolgskriterium 7
    der Phase 2).

    Jede weitere Lesestelle hebt diese Zusage auf: dann gibt es zwei Wege zum
    Ist-Zustand, und die Verifikation prueft womoeglich gegen den anderen.

    Die Funktion ist absichtlich duenn. Die gesamte Aufbereitung liegt daneben
    in ConvertTo-ActualAceSet und ist dort ohne Dateisystem pruefbar; je
    weniger hier steht, desto weniger geht verloren, wenn ein Test diese
    Funktion ersetzt.

    Kein icacls.exe: dessen Ausgabe ist lokalisiert und auf deutschem Windows
    nicht auswertbar. Kein Write-Host, kein Read-Host -- die Funktion gibt
    zurueck oder wirft.
#>

function Get-ActualAceSet {
    <#
    .SYNOPSIS
        Liest den Deskriptor eines Ordners und liefert den SID-typisierten
        Ist-Schnappschuss.

    .EXAMPLE
        Get-ActualAceSet -LiteralPath 'D:\Shares\Profiles'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $deskriptor = Get-Acl -LiteralPath $LiteralPath
    return ConvertTo-ActualAceSet -DirectorySecurity $deskriptor -Path $LiteralPath
}
