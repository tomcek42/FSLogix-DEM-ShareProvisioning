<#
    ConvertTo-ActualAceSet -- reine Aufbereitung eines DirectorySecurity zum
    Ist-Schnappschuss. Kein Zugriff auf das Dateisystem; gelesen wird
    ausschliesslich in Get-ActualAceSet.

    DER KERN DER LOKALISIERUNGSZUSAGE steckt im dritten Argument der beiden
    GetAccessRules-Aufrufe: [SecurityIdentifier]. Die bequemere Eigenschaft
    Access liefert NTAccount-typisierte Regeln -- sie ist damit lokalisiert
    (VORDEFINIERT\Administratoren auf de-DE) und wirft ueber einem verwaisten
    Prinzipal. Ein Schnappschuss mit SIDs ist auf deutschem wie englischem
    Server derselbe. Das dritte Argument ist deshalb keine Formalie und darf
    nicht "vereinfacht" werden.

    Sddl wird ausschliesslich fuer den Bericht erhoben und niemals verglichen:
    die Zeichenkette ist nicht kanonisch (ACE-Reihenfolge, Synchronize-Bit,
    Kurzformen wie FA gegen Zahlmasken).

    Aces und Inherited stehen in @(...), damit .Count unter
    Set-StrictMode -Version Latest auch bei null Treffern traegt -- dieselbe
    Disziplin, die New-ProvisioningResult fuer Detail fuehrt.
#>

function ConvertTo-ActualAceSet {
    <#
    .SYNOPSIS
        Bereitet ein DirectorySecurity zum SID-typisierten Ist-Schnappschuss
        auf.

    .OUTPUTS
        [pscustomobject] mit Path, Aces, Inherited, IsProtected, Owner, Sddl.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Security.AccessControl.DirectorySecurity] $DirectorySecurity,

        [string] $Path = ''
    )

    $sidTyp = [System.Security.Principal.SecurityIdentifier]

    return [pscustomobject] @{
        Path        = $Path
        Aces        = @($DirectorySecurity.GetAccessRules($true, $false, $sidTyp))
        Inherited   = @($DirectorySecurity.GetAccessRules($false, $true, $sidTyp))
        IsProtected = [bool] $DirectorySecurity.AreAccessRulesProtected
        Owner       = $DirectorySecurity.GetOwner($sidTyp)
        Sddl        = $DirectorySecurity.Sddl
    }
}
