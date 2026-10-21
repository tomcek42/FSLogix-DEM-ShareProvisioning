function Test-MitBeleg {
    <#
    .SYNOPSIS
        Ob das Soll Herstellerbelege fuehrt (Status, Source, Section).

    .DESCRIPTION
        Im Modul immer wahr: die Datendateien tragen je Eintrag ihren Beleg,
        die Schemapruefung verlangt ihn, und die Ausgabe zeigt ihn unter jeder
        Abweichung. Das Einzeldatei-Buendel laesst die Belege weg und setzt
        dafuer $script:MitBelegen = $false. Dann verlangt die Schemapruefung
        keine Belegfelder, und die Belegzeile entfaellt. ACL, Freigaben und
        Soll-Ist-Vergleich haengen an keinem der drei Felder.

        Ohne gesetzte Variable gilt wahr -- der Modulweg braucht keine eigene
        Anweisung dafuer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $wert = Get-Variable -Name 'MitBelegen' -Scope Script -ValueOnly -ErrorAction SilentlyContinue

    return ($wert -ne $false)
}
