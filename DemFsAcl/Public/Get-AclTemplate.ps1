function Get-AclTemplate {
    <#
    .SYNOPSIS
        Lädt ein ACL-Template zur genannten Ordnerart, validiert es und wirft
        bei Schemabefunden.

    .DESCRIPTION
        Der einzige unterstützte Weg zu einem Template. Die Datendatei direkt
        zu laden umgeht die Schemaprüfung und damit SPEC-07.

        "Abgewiesen" heißt geworfen und nicht gemeldet: ein Aufrufer, der eine
        zurückgegebene Befundliste ignoriert, macht aus einer
        Sicherheitsprüfung eine Protokollzeile.

        Die Funktion gibt zurück oder wirft -- sie druckt nicht. Kein
        Write-Host, kein Write-Warning, kein Read-Host. Die Ausgabe an den
        Bediener entsteht ausschließlich in der Orchestrierung (C-10, C-12).

        -Kind ist der Vertragsschlüssel dieses Aufrufs und nicht die Marke für
        die Fehlermeldung: der Name schlägt den Eintrag nach UND wird an den
        Validator gereicht, der das Kind-Feld des geladenen Templates dagegen
        hält. Beide Angaben zusammen sind die Prüfung -- eine allein könnte
        nichts widerlegen.

    .PARAMETER Kind
        Die angefragte Ordnerart. Zwei Rollen in einer Angabe:

        1. Schlüssel, unter dem der Eintrag in der Templatedatei nachgeschlagen
           wird.
        2. Sollwert, gegen den Test-TemplateSchema das Kind-Feld des geladenen
           Templates prüft.

        Deshalb ist der Parameter NICHT redundant zum Hashtable-Schlüssel.
        Fiele er weg oder würde die Ordnerart nur noch aus dem Feld abgeleitet,
        gäbe es wieder eine einzige Angabe, ein Zahlendreher in der
        handabgeschriebenen Datendatei wäre wieder unsichtbar, und SPEC-07
        verlöre genau die Regel, die ihn fängt.

    .OUTPUTS
        [hashtable] -- das validierte Template.

    .EXAMPLE
        Get-AclTemplate -Kind 'FSLogix-Profiles'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind
    )

    $alle = Get-DataTable -Name 'AclTemplates'

    if (-not $alle.ContainsKey($Kind)) {
        throw [System.InvalidOperationException]::new(
            ('Die Ordnerart "{0}" fehlt in den ACL-Templates.' -f $Kind))
    }

    $template = $alle[$Kind]

    # -Kind wird hier NICHT bloß zur Beschriftung der Befundzeilen
    # weitergereicht: es ist der Sollwert, gegen den der Validator das
    # Kind-Feld des geladenen Templates hält. Der Nachschlag oben liefert die
    # eine Angabe, das Feld im Template die zweite und unabhängige -- erst
    # dadurch kann ein Zahlendreher in der handabgeschriebenen Datendatei
    # überhaupt auffallen.
    #
    # Die Klammerform ist Pflicht und kein Stil: der Validator liefert bei null
    # Befunden nichts, und Set-StrictMode -Version Latest macht .Count auf
    # einer leeren Rückgabe zu einem Fehler.
    $befunde = @(Test-TemplateSchema -Template $template -Kind $Kind)

    if ($befunde.Count -gt 0) {

        $meldung = ('Das Template "{0}" wurde abgewiesen -- {1} Schemabefund(e):{2}{3}' -f
            $Kind,
            $befunde.Count,
            [System.Environment]::NewLine,
            ($befunde -join [System.Environment]::NewLine))

        throw [System.InvalidOperationException]::new($meldung)
    }

    return $template
}
