function Get-DataPath {
    <#
    .SYNOPSIS
        Liefert den vollstaendigen Pfad einer Datei unterhalb von DemFsAcl/Data.

    .DESCRIPTION
        Reine Pfadarithmetik -- kein Dateisystemzugriff, keine Pruefung auf
        Existenz. Der Aufrufer entscheidet, was mit dem Pfad geschieht.

    .EXAMPLE
        Get-DataPath -FileName 'AclTemplates.psd1'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $FileName
    )

    # Ausdruecklich $script:ModuleRoot aus dem .psm1 und nicht $PSScriptRoot:
    # diese Datei wird per Punktoperator geladen, $PSScriptRoot zeigt hier auf
    # Private/ und damit eine Ebene zu tief (RESEARCH Pattern 7).
    return [System.IO.Path]::Combine($script:ModuleRoot, 'Data', $FileName)
}
