<#
    Resolve-OperatorPath -- die EINE Normalisierungs- und Pruefstelle jeder
    Pfadeingabe (FLOW-05, C-09).

    Jede Pfadangabe dieses Werkzeugs laeuft hier durch: der Zielpfad der
    Neuanlage, die Bestandswurzel und der aus der Unterordner-Nummernliste
    zusammengesetzte Pfad. Eine zweite Normalisierungsstelle waere eine zweite
    Wahrheit ueber denselben Pfad -- und die eine, die gerade nicht benutzt
    wurde, drifted.

    REIN, OHNE DATEISYSTEMZUGRIFF UND OHNE EXISTENZPRUEFUNG. Ob das Ziel
    taugt -- Laufwerkswurzel, Systempfad, UNC-Pfad, beschreibbar, leer --
    entscheidet ausschliesslich Test-ProvisioningPreflight. Die Dialogschicht
    wiederholt diese Pruefungen NICHT: zwei Wahrheiten ueber die Tauglichkeit
    eines Zielpfades driften auseinander, und die Freigabe entstuende dann ueber
    dem Pfad, den die falsche freigegeben hat.

    Die Funktion druckt nicht und fragt nicht. Sie gibt einen Datensatz mit vier
    Feldern zurueck; ueber die Wiederholung entscheidet der Aufrufer im Dialog.
#>

function Resolve-OperatorPath {
    <#
    .SYNOPSIS
        Normalisiert eine Pfadeingabe und meldet, ob sie als Zielangabe taugt.

    .DESCRIPTION
        Der Ablauf, in dieser Reihenfolge:

        1. Trimmen, umschliessende Anfuehrungszeichen entfernen, erneut trimmen.
           Aus der Zwischenablage kopierte Pfade tragen regelmaessig beides --
           dieselbe Bereinigung wie in Resolve-TrusteeSid.
        2. Leere Angabe abweisen.
        3. Platzhalterzeichen abweisen. Das Werkzeug arbeitet ausnahmslos mit
           -LiteralPath; eine Maske, die zufaellig auf genau einen Ordner passt,
           waere die gefaehrlichste aller Eingaben.
        4. Ueber GetFullPath in absolute Form bringen.
        5. Abschliessende Trennzeichen abschneiden -- ausser bei einer
           Laufwerkswurzel, die ohne ihr Trennzeichen das AKTUELLE Verzeichnis
           des Laufwerks bezeichnete und damit etwas anderes waere.

    .OUTPUTS
        [pscustomobject] mit Path, LeafName, IsValid und Reason.

    .EXAMPLE
        Resolve-OperatorPath -InputValue 'D:\Freigaben\Profile\'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $InputValue
    )

    $roh = ([string] $InputValue).Trim().Trim('"').Trim()

    if ([string]::IsNullOrWhiteSpace($roh)) {
        return New-OperatorPathResult -Reason 'Die Pfadangabe ist leer. Erwartet wird ein Ordnerpfad einschließlich Laufwerk, etwa D:\Freigaben\Profile.'
    }

    if (($roh.IndexOf([char] 42) -ge 0) -or ($roh.IndexOf([char] 63) -ge 0)) {
        return New-OperatorPathResult -Reason ('Die Pfadangabe "{0}" enthält ein Platzhalterzeichen. Dieses Werkzeug arbeitet ausnahmslos mit wortwörtlichen Pfaden; bitte den Pfad vollständig ausschreiben.' -f $roh)
    }

    $voll = ''

    try {
        $voll = [System.IO.Path]::GetFullPath($roh)
    }
    catch {
        return New-OperatorPathResult -Reason ('Die Pfadangabe "{0}" ist nicht auswertbar: {1}' -f $roh, $_.Exception.Message)
    }

    if ([string]::IsNullOrWhiteSpace($voll)) {
        return New-OperatorPathResult -Reason ('Die Pfadangabe "{0}" ergibt keinen auswertbaren Pfad.' -f $roh)
    }

    $ohneEnde = $voll.TrimEnd([char] 92, [char] 47)

    if ([string]::IsNullOrEmpty($ohneEnde)) {
        $gekuerzt = $voll
    }
    elseif ($ohneEnde.EndsWith(':', [System.StringComparison]::Ordinal)) {
        # Laufwerkswurzel: das Trennzeichen gehoert dazu. "D:" allein bezeichnet
        # das aktuelle Verzeichnis des Laufwerks und damit etwas anderes.
        $gekuerzt = $ohneEnde + [System.IO.Path]::DirectorySeparatorChar
    }
    else {
        $gekuerzt = $ohneEnde
    }

    return [pscustomobject] @{
        Path     = $gekuerzt
        LeafName = [string] [System.IO.Path]::GetFileName($gekuerzt)
        IsValid  = $true
        Reason   = ''
    }
}

function New-OperatorPathResult {
    <#
    .SYNOPSIS
        Baut den Abweisungsfall von Resolve-OperatorPath. Intern.

    .DESCRIPTION
        Der Grund reist als Feld und nicht als Ausnahme: eine ungueltige
        Pfadeingabe ist der Normalfall am Dialog und fuehrt zur erneuten Frage,
        nicht zum Abbruch (FLOW-06).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Reason
    )

    return [pscustomobject] @{
        Path     = ''
        LeafName = ''
        IsValid  = $false
        Reason   = $Reason
    }
}
