function Get-DataTable {
    <#
    .SYNOPSIS
        Liefert eine der drei Datentabellen des Moduls als Hashtable.

    .DESCRIPTION
        Die eine Nahtstelle zwischen Code und Daten. Im Modul liest sie die
        gleichnamige .psd1 unter DemFsAcl/Data; das Einzeldatei-Buendel ersetzt
        genau diese Funktion durch eine, die die Tabellen aus dem Code liefert.
        Damit kennt keine andere Funktion einen Dateinamen, und das Buendel
        kommt ohne jeden Bezug auf eine Datei aus.

    .EXAMPLE
        Get-DataTable -Name 'AclTemplates'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AclTemplates', 'ShareTemplates', 'AuditKindNames')]
        [string] $Name
    )

    # -LiteralPath: alle Pfadeingaben dieses Werkzeugs laufen ohne
    # Wildcard-Interpretation (C-09).
    return (Import-PowerShellDataFile -LiteralPath (Get-DataPath -FileName ($Name + '.psd1')))
}
