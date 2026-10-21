<#
    New-ProvisioningResult -- die Ergebnisform des Werkzeugs, eingefroren,
    bevor es einen einzigen Konsumenten gibt.

    Warum jetzt und nicht dann, wenn sie gebraucht wird: die Phasen 3 bis 8
    binden alle an diese Form. Eine Feldumbenennung spaeter beruehrte acht
    Aufrufstellen; jetzt kostet sie nichts. Deshalb fuehrt die
    Verantwortungstabelle der Recherche die Form ausdruecklich als
    Liefergegenstand dieser Phase.

    Die Funktion DRUCKT NICHT. Das ist die Regel, an der die spaetere Logdatei
    haengt: die Engines geben Ergebnisobjekte zurueck, ausgegeben wird
    ausschliesslich in der Orchestrierung (C-10, OUT-07). Damit bleibt die
    zurueckgestellte Logdatei ein Export-Csv-Einzeiler ueber dieselbe
    Objektsammlung (OPS-01). Ein Write-Host irgendwo unterhalb der
    Orchestrierung verbaut das dauerhaft.
#>

function New-ProvisioningResult {
    <#
    .SYNOPSIS
        Baut einen Ergebnissatz einer Provisionierungsstufe.

    .DESCRIPTION
        Reine Fabrikfunktion: nimmt Parameter entgegen, gibt ein
        PSCustomObject mit genau zehn Feldern zurueck. Kein Seiteneffekt,
        keine Ausgabe.

        Die zehn Felder:

        Kind        Ordnerart, oder leer bei Stufen ohne Ziel.
        Path        Zielpfad.
        Stage       Die Stufe, die das Ergebnis erzeugt hat. Vorgesehene
                    Werte: Plan, Preflight, Directory, Acl, AclVerify, Share,
                    ShareVerify. Bewusst ohne ValidateSet -- die Stufenliste
                    waechst mit den Phasen 3 bis 8, und ein Gate an dieser
                    Stelle erzwaenge eine Aenderung an dieser Datei je neuer
                    Stufe, ohne dafuer irgendetwas abzusichern.
        Status      OK, Warning oder Error. Mit ValidateSet erzwungen:
                    OUT-01 verlangt genau drei unterscheidbare Zustaende, und
                    ein vierter, der sich spaeter einschleicht, macht die
                    Zusammenfassung mehrdeutig.
        Message     Der lesbare, lokalisierte Text.
        Detail      Die strukturierten Befunde der Compare-Engine aus Phase 3,
                    getrennt nach fehlend, unerwartet und
                    Vererbungsabweichung.
        Provenance  Verified, Derived oder leer -- die Grundlage fuer das
                    Kennzeichen in der Ausgabe (OUT-05).
        Source      Quellenangabe desselben Kennzeichens (URL).
        Section     Abschnittsangabe desselben Kennzeichens.
        Timestamp   Setzt die Funktion selbst; ausdruecklich kein Parameter.

    .EXAMPLE
        New-ProvisioningResult -Kind 'FSLogix-Profiles' -Path 'D:\FSLogix' -Stage 'AclVerify' -Status 'OK'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Kind = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Stage = '',

        [Parameter(Mandatory)]
        [ValidateSet('OK', 'Warning', 'Error')]
        [string] $Status,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Message = '',

        # Standardwert leeres Array, damit Detail auch ohne Uebergabe
        # zaehlbar ist. Siehe die Klammerform beim Zusammenbau unten.
        #
        # AllowNull neben AllowEmptyCollection: der Standardwert greift nur,
        # wenn der Parameter WEGGELASSEN wird. Eine Engine, die -Detail
        # $befunde durchreicht, uebergibt ihn immer -- und wenn $befunde leer
        # geblieben ist, steht dort $null. Genau diese Eingabe wird unten
        # normalisiert.
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Detail = @(),

        [Parameter()]
        [ValidateSet('Verified', 'Derived', '')]
        [string] $Provenance = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Source = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Section = ''
    )

    # Genau eine Pruefung, und zwar auf $null selbst -- KEIN Durchlauf ueber
    # die Elemente. Ein Where-Object oder ein vergleichbarer Filter wuerde ein
    # $null-Element aus einer echten Befundliste der Compare-Engine verwerfen
    # und aus einem lauten Typfehler einen stillen Datenverlust machen. Die
    # Funktion sortiert nicht, dedupliziert nicht und filtert nicht: die
    # Reihenfolge in Detail ist die Uebergabereihenfolge.
    if ($null -eq $Detail) {
        $Detail = @()
    }

    return [pscustomobject] @{
        Kind       = $Kind
        Path       = $Path
        Stage      = $Stage
        Status     = $Status
        Message    = $Message

        # Die Klammerform steht hier beim ZUSAMMENBAU und nicht im Aufrufer,
        # weil das Feld selbst der Vertrag ist: Detail ist immer ein Array,
        # auch wenn nichts uebergeben wurde. Unter Set-StrictMode -Version
        # Latest ist .Count auf einer leeren Rueckgabe sonst ein Fehler --
        # und dieser Fehler traefe acht spaetere Konsumenten statt eines
        # (RESEARCH Pitfall 6).
        #
        # Die Klammerform allein traegt den $null-Fall NICHT: bei -Detail
        # $null lieferte sie wieder $null, und die Zusage brach auf genau der
        # Eingabe, gegen die sie schuetzt. Deshalb steht die Normalisierung
        # oben im Rumpf und nicht im Aufrufer -- acht spaetere Konsumenten
        # sehen den Aufrufer nicht, sie sehen nur dieses Feld.
        Detail     = @($Detail)

        Provenance = $Provenance
        Source     = $Source
        Section    = $Section

        # Wird von der Funktion selbst gesetzt. Ein Parameter dafuer waere
        # eine Einladung, den Zeitpunkt zu faelschen; die Ortszeit ist
        # richtig, weil der Ergebnissatz in einer Konsolenzusammenfassung auf
        # genau diesem Server gelesen wird.
        Timestamp  = [datetime]::Now
    }
}
