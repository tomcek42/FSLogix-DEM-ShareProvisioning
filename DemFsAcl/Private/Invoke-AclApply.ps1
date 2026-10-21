<#
    Invoke-AclApply -- die Apply-Engine (ACL-01 bis ACL-08, VERIFY-01).

    DIE REIHENFOLGE IST EINE SICHERHEITSINVARIANTE, KEINE VORLIEBE:
    Sperre -> Ordner -> ACL -> Ruecklesen und Verifizieren. Die
    Schreib-API meldet Erfolg auch bei Teilfehlschlag; ohne Ruecklesen ist ein
    gruenes Ergebnis eine Behauptung. Das ist der halbe Existenzgrund des
    Werkzeugs -- die andere Haelfte ist, dass dabei kein Benutzer ausgesperrt
    und kein bestehendes Profil zerstoert wird.

    GELESEN WIRD UEBER Get-ActualAceSet, die eine Lesestelle aus Phase 2, und
    nicht ueber das Lese-Cmdlet: ein zweiter Lesepfad brueche die Zusage aus
    Erfolgskriterium 7 der Phase 2 und machte Tests/AclReadSeam.Tests.ps1 rot.

    VERGLICHEN WIRD UEBER Compare-AceSet mit -Desired und -Actual als OBJEKTE.
    Die Engine reicht nie einen Pfad in den Vergleicher -- das ist die Zusage,
    die den Vergleicher fixture-getrieben und offline pruefbar haelt.

    KEIN RUECKBAU BEI ROTER VERIFIKATION (D-05): Ordner, geschriebenes ACL und
    Befunde bleiben stehen. Ein Rueckbau zerstoerte genau die Diagnose, fuer die
    die Verifikationsstufe existiert. In diesem Fall entsteht ausserdem KEIN
    Ergebnissatz einer Freigabestufe -- das ist die Bedingung, unter der
    SHARE-03 in Plan 03-02 ueberhaupt erst greifen kann.

    Kein Write-Host, kein Read-Host, kein Write-Warning: die Engine gibt
    Ergebnisobjekte zurueck, ausgegeben wird erst in Phase 4.

    DER BEFUNDPARAMETER IST PFLICHT (D-03, Phase 4). Vorher trug er einen
    Vorgabewert, und ein Aufrufer, der ihn vergass, schrieb ohne Sperre --
    der Verifizierer der Phase 3 hat genau diesen stillen Umweg benannt.
    Invoke-AclApplySet zieht mit, weil sie den Wert nur weiterreicht: bliebe
    sie optional, wanderte der Umweg eine Ebene nach oben. AllowNull und
    AllowEmptyCollection bleiben beide stehen -- ein bewusst leerer Satz ist
    weiterhin moeglich, aber ausdruecklich zu tippen.
#>

function Invoke-AclApply {
    <#
    .SYNOPSIS
        Legt die Zielwurzel an oder uebernimmt sie, schreibt das Soll-ACL,
        liest zurueck und verifiziert.

    .PARAMETER Kind
        Die Ordnerart; reist unveraendert in jeden Ergebnissatz.

    .PARAMETER LiteralPath
        Die Zielwurzel. GENAU DIESER EINE PFAD wird beschrieben: kein Abstieg,
        keine Schleife ueber Kindelemente, kein -Recurse (ACL-07).

    .PARAMETER Desired
        Das DesiredAcl aus Expand-AclTemplate.

    .PARAMETER PreflightResult
        Die Befundsammlung aus Test-ProvisioningPreflight. Enthaelt sie fuer
        dieses Ziel einen Abbruchbefund, wird nichts geschrieben.

        PFLICHT (D-03). AllowNull und AllowEmptyCollection bleiben stehen: ein
        bewusst leerer Befundsatz ist weiterhin moeglich -- aber er ist
        ausdruecklich zu tippen. Damit laesst sich das Preflight-Gate nicht
        mehr stillschweigend umgehen, und die Symmetrie zu
        Invoke-ShareApply -AclVerifyResult ist hergestellt.

    .OUTPUTS
        Sammlung von ProvisioningResult mit den Stages Preflight, Directory,
        Acl und AclVerify.

    .EXAMPLE
        Invoke-AclApply -Kind 'FSLogix-Profiles' -LiteralPath 'D:\Freigaben\Profile' -Desired $soll -PreflightResult $befunde
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [object] $Desired,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult
    )

    $ergebnisse = New-Object System.Collections.Generic.List[object]

    # --- 1. Sperre ----------------------------------------------------------
    $sperre = Get-PreflightSperre -PreflightResult $PreflightResult -LiteralPath $LiteralPath

    if ($null -ne $sperre) {
        # Der Sperrsatz nennt die FOLGE und die Pruefkennung, nicht den
        # Befundtext ein zweites Mal (G-04-3b): der Befund selbst steht bereits
        # in der Ergebnissammlung. Der volle Grund bleibt in Detail, damit
        # Aufrufer ausserhalb der Orchestrierung ihn weiterhin haben.
        $kennung = ''
        if ($null -ne $sperre.PSObject.Properties['Check']) { $kennung = [string] $sperre.Check }

        $klammer = if ([string]::IsNullOrWhiteSpace($kennung)) { '' } else { ' ({0})' -f $kennung }

        $ergebnisse.Add((New-ProvisioningResult -Kind $Kind -Path $LiteralPath -Stage 'Preflight' -Status 'Error' `
                    -Message ('Gesperrt durch einen Preflight-Abbruchbefund{0}: es wurde kein Ordner angelegt und kein ACL geschrieben.' -f $klammer) `
                    -Detail @($sperre.Detail)))
        return $ergebnisse.ToArray()
    }

    # --- 2. Ordner (ACL-01) -------------------------------------------------
    # Fehlende Elternordner entstehen mit; sie bekommen KEIN ACL. Geschrieben
    # wird ausschliesslich die Zielwurzel.
    $bestand = [System.IO.Directory]::Exists($LiteralPath)

    if ($bestand) {
        $ordnerMeldung = 'Die bestehende Zielwurzel wurde übernommen; ihr Inhalt bleibt unberührt.'
    }
    else {
        $null = [System.IO.Directory]::CreateDirectory($LiteralPath)
        $ordnerMeldung = 'Die Zielwurzel wurde neu angelegt; Benutzerordner darunter legt der Dienst selbst an.'
    }

    $ergebnisse.Add((New-ProvisioningResult -Kind $Kind -Path $LiteralPath -Stage 'Directory' -Status 'OK' `
                -Message $ordnerMeldung))

    # --- 3. ACL (ACL-02, ACL-03, ACL-05, ACL-07, ACL-08) --------------------
    $deskriptor = New-DesiredDirectorySecurity -Desired $Desired
    Set-DirectoryAcl -LiteralPath $LiteralPath -DirectorySecurity $deskriptor

    $ergebnisse.Add((New-ProvisioningResult -Kind $Kind -Path $LiteralPath -Stage 'Acl' -Status 'OK' `
                -Message ('Der Soll-Deskriptor wurde auf die Zielwurzel geschrieben: {0} Einträge, Vererbungsschutz gesetzt, geerbte Einträge entfernt.' -f @($Desired.Aces).Count) `
                -Provenance ([string] $Desired.ProtectInheritanceStatus) `
                -Source ([string] $Desired.ProtectInheritanceSource) `
                -Section ([string] $Desired.ProtectInheritanceSection)))

    # --- 4. Ruecklesen und Verifizieren (VERIFY-01) -------------------------
    $ist = Get-ActualAceSet -LiteralPath $LiteralPath
    $pruefung = Compare-AceSet -Desired $Desired -Actual $ist -Path $LiteralPath

    # --- 5. Duplikatpruefung (ACL-06, D-08) ---------------------------------
    # NEBEN den Compare-Befunden, nicht in ihnen: Compare-AceSet fasst
    # bitgleiche Ist-Duplikate bewusst und testgesichert zusammen, und genau
    # diese Zusammenfassung ist der Grund, warum die Zaehlung hier steht.
    $duplikate = @(Test-AceDuplicate -Actual $ist)

    if ($duplikate.Count -gt 0) {

        # Ein Fehlbefund der Compare-Engine bleibt der schwerere; ein Duplikat
        # allein ist eine Warnung.
        $status = if ([string] $pruefung.Status -eq 'Error') { 'Error' } else { 'Warning' }

        $pruefung = New-ProvisioningResult -Kind $Kind -Path $LiteralPath -Stage 'AclVerify' `
            -Status $status `
            -Message ('{0} Zusätzlich: {1} doppelte ACE-Schlüssel im zurückgelesenen ACL.' -f
                [string] $pruefung.Message, $duplikate.Count) `
            -Detail (@($pruefung.Detail) + $duplikate)
    }

    $ergebnisse.Add($pruefung)

    return $ergebnisse.ToArray()
}

function Invoke-AclApplySet {
    <#
    .SYNOPSIS
        Fuehrt Invoke-AclApply ueber eine Zielliste aus und sammelt alle
        Ergebnissaetze flach ein.

    .DESCRIPTION
        EIN GESCHEITERTES ZIEL STOPPT DIE UEBRIGEN NICHT (D-06). Jedes Ziel
        laeuft in einem eigenen try-Block; eine Ausnahme wird zu einem
        Ergebnissatz mit Status Error und beendet den Lauf nicht. Die Rueckgabe
        ist genau die flache Sammlung, die die Orchestrierung in Phase 4 als
        einziges konsumiert.

        WAS DIESE FUNKTION AUSDRUECKLICH NICHT TUT: sie ruft nichts
        Freigabebezogenes auf. Ihr try-Block umschliesst allein
        Invoke-AclApply. Die Stelle, die ACL- und Freigabeergebnisse je Ziel
        zusammenfuehrt, entsteht erst in Phase 4 -- das ist der Phasenschnitt
        und keine offene Kante: Phase 3 liefert die Engines und ihre
        Ergebnisobjekte, Phase 4 verdrahtet und gibt aus.

    .PARAMETER Target
        Je Element mindestens Kind, Path und Desired.

    .PARAMETER PreflightResult
        Die Befundsammlung aus Test-ProvisioningPreflight, einmal fuer alle
        Ziele erhoben (D-09).

        PFLICHT (D-03), und das ist kein zusaetzlicher Umfang, sondern die
        Einloesung derselben Zusage: diese Funktion reicht den Wert an
        Invoke-AclApply weiter. Bliebe sie optional, wanderte der stille Umweg
        um genau eine Ebene nach oben, und die Orchestrierung -- die einzige
        Stelle, die sie ruft -- koennte das gesamte Preflight-Gate weiterhin
        vergessen.

    .OUTPUTS
        Flache Sammlung von ProvisioningResult ueber alle Ziele.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult
    )

    $alle = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in @($Target)) {

        $kind = [string] $ziel.Kind
        $pfad = [string] $ziel.Path

        try {
            foreach ($satz in @(Invoke-AclApply -Kind $kind -LiteralPath $pfad `
                        -Desired $ziel.Desired -PreflightResult $PreflightResult)) {
                $alle.Add($satz)
            }
        }
        catch {
            $alle.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'Acl' -Status 'Error' `
                        -Message ('Die Provisionierung dieses Ziels ist abgebrochen; die übrigen Ziele laufen weiter. Grund: {0}' -f $_.Exception.Message)))
        }
    }

    return $alle.ToArray()
}

function Test-AceDuplicate {
    <#
    .SYNOPSIS
        Zaehlt die ROHEN ACE-Schluessel eines Ist-Schnappschusses und meldet
        jede Wiederholung. Intern zu Invoke-AclApply.

    .DESCRIPTION
        NIMMT EIN OBJEKT ENTGEGEN, NIE EINEN PFAD. Damit ist die Zaehlung rein,
        offline pruefbar und von der einen Lesestelle unabhaengig -- und der
        Fall zweier bitgleicher ACEs, den Windows auf der Platte gar nicht
        entstehen laesst, wird als Schnappschuss von Hand herstellbar.

        WARUM HIER UND NICHT IN Compare-AceSet (D-08): der Vergleicher fasst
        bitgleiche Ist-Duplikate bewusst zusammen, das ist aus Phase 2
        testgesichert, und wer diese Zusammenfassung dort aendert, faellt die
        Entscheidung aus Phase 2 erneut. Deshalb zaehlt die Apply-Engine
        stattdessen die rohen Schluessel nach dem Ruecklesen.

        Normalisiert wird ueber ConvertTo-AceKey -- dieselbe eine
        Normalisierungsstelle wie im Vergleich. Eine zweite waere eine zweite
        Wahrheit ueber dieselbe Regel.

    .PARAMETER Actual
        Der Ist-Schnappschuss aus ConvertTo-ActualAceSet beziehungsweise
        Get-ActualAceSet.

    .OUTPUTS
        Sammlung von Befunden mit Finding gleich DuplicateAce.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Actual
    )

    $ordinal = [System.StringComparer]::Ordinal
    $gruppen = New-Object 'System.Collections.Generic.Dictionary[string,object]' $ordinal
    $reihenfolge = New-Object System.Collections.Generic.List[string]

    foreach ($regel in @($Actual.Aces)) {

        $norm = ConvertTo-AceKey -Ace $regel

        if (-not $gruppen.ContainsKey($norm.Key)) {
            $gruppen.Add($norm.Key, (New-Object System.Collections.Generic.List[object]))
            $reihenfolge.Add($norm.Key)
        }

        $gruppen[$norm.Key].Add($norm)
    }

    $befunde = New-Object System.Collections.Generic.List[object]

    foreach ($schluessel in $reihenfolge) {

        $treffer = $gruppen[$schluessel]

        if ($treffer.Count -le 1) { continue }

        $befunde.Add([pscustomobject] @{
            Finding   = 'DuplicateAce'
            Reason    = 'DuplicateAceKey'
            Key       = $schluessel
            Sid       = [string] $treffer[0].Sid
            Rights    = [int] $treffer[0].Rights
            RightsHex = '0x{0:X}' -f [int] $treffer[0].Rights
            Count     = $treffer.Count
            Expected  = '1'
            Actual    = [string] $treffer.Count
            Message   = ('Der Ordner trägt denselben ACE {0}-mal (Prinzipal {1}, Maske 0x{2:X}).' -f
                $treffer.Count, [string] $treffer[0].Sid, [int] $treffer[0].Rights)
        })
    }

    return $befunde.ToArray()
}

function Get-PreflightSperre {
    <#
    .SYNOPSIS
        Liefert den ersten Preflight-Abbruchbefund, der dieses Ziel sperrt,
        sonst nichts. Intern zu Invoke-AclApply.

    .DESCRIPTION
        Ein Hostbefund (Scope gleich Host) sperrt jedes Ziel; ein Zielbefund
        sperrt nur sein eigenes. Genau diese Trennung haelt D-06 und
        Erfolgskriterium 1 zugleich ein.

        Ein Befund ohne Feld Scope wird als Zielbefund behandelt und ueber den
        Pfad zugeordnet -- die vorsichtigere Deutung, weil sie den Lauf
        hoechstens zu frueh sperrt statt zu spaet.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PreflightResult,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    if ($null -eq $PreflightResult) { return $null }

    $zielPraefix = ConvertTo-PfadPraefix -LiteralPath $LiteralPath

    foreach ($befund in @($PreflightResult)) {

        if ($null -eq $befund) { continue }
        if ([string] $befund.Status -ne 'Error') { continue }

        $scope = ''
        if ($null -ne $befund.PSObject.Properties['Scope']) {
            $scope = [string] $befund.Scope
        }

        if ($scope -eq 'Host') { return $befund }

        $befundPraefix = ConvertTo-PfadPraefix -LiteralPath ([string] $befund.Path)

        if ((-not [string]::IsNullOrEmpty($befundPraefix)) -and ($befundPraefix -eq $zielPraefix)) {
            return $befund
        }
    }

    return $null
}
