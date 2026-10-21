<#
    Die Frage nach der Aktualisierung beim Start (Wunsch Projektinhaber
    2026-10-21). Vorgabe ja, Kurzform [J/n] -- Entscheidung Projektinhaber.
#>

function Read-UpdateOffer {
    <#
    .SYNOPSIS
        Fragt, ob die neuere Version heruntergeladen und gestartet werden soll.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [version] $CurrentVersion,

        [Parameter(Mandatory)]
        [version] $NewVersion
    )

    Add-PromptContext -Line @(
        ('Neue Version {0} ist veröffentlicht (laufend: {1}).' -f $NewVersion, $CurrentVersion))

    return (Read-YesNoAnswer -Prompt ('Version {0} herunterladen und starten?' -f $NewVersion) -Default $true -ShortLabel)
}
