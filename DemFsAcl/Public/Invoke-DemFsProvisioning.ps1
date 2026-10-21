<#
    Invoke-DemFsProvisioning -- die Orchestrierung und die EINE zusaetzliche
    oeffentliche Funktion dieses Werkzeugs (D-01, D-02, D-06, D-10, D-11,
    D-12, D-16).

    DIE SIEBEN ENGINES BLEIBEN PRIVAT. Von aussen kommt damit niemand an
    Invoke-AclApply vorbei am Preflight -- die Zusage "eine Lesestelle, eine
    Schreibstelle" ist strukturell geschuetzt und nicht nur vereinbart.

    DIE REIHENFOLGE IST DER INHALT DIESER DATEI:
      1. Kapazitaet einmal vorab erheben (D-14) und als Rueckfragekanal
         setzen (G-04-4d): nicht umgeleitet geht der Kontext einer Frage
         farbig ueber die Ausgabenaht, umgeleitet reist er im Prompt. Danach
         das Startbanner (G-04-4e) -- auf der Ausgabenaht und, bei Umleitung,
         zusaetzlich im Prompt der ersten Frage.
     1b. Die Modusfrage (Phase 5, D-01): "Ablagen neu einrichten" fuehrt
         weiter durch diese Datei, "Bestehende Struktur pruefen" verzweigt in
         Invoke-DemFsAudit und endet mit dessen Rueckgabe -- dieselbe Form
         { ExitCode, Confirmed, Target, Result }.
      2. Alles erheben: Ordnerarten, Gruppen, Pfade, Freigabenamen (D-06).
      3. Je Ziel das Soll binden -- Expand-AclTemplate ruft die Orchestrierung,
         nicht die Dialogschicht.
      4. Test-ProvisioningPreflight EINMAL ueber ALLE Ziele, bevor irgendetwas
         geschrieben wird (D-06, Phase-3-D-09).
      5. Plan und Preflight-Befunde in EINEM Bild (D-09, D-10).
      6. Sperrt ein Preflight-Befund mit Scope Host den ganzen Lauf, wird die
         Bestaetigungsfrage GAR NICHT ERST gestellt (Erfolgskriterium 1 der
         Phase 3). Sonst: getippte Bestaetigung; Enter genuegt ausdruecklich
         nicht (D-11). Bei Ablehnung endet der Lauf sauber und ohne einen
         einzigen Schreibzugriff (D-12).
         Ist die Ausgabe umgeleitet, steht der Plan samt Preflight-Befunden
         ZUSAETZLICH im Prompt der Bestaetigungsfrage (G-04-3a): unter
         '> datei' erreicht nur der Prompt die Konsole, und ein "JA" ohne den
         Plan daneben waere eine blinde Bestaetigung. Ohne Umleitung erscheint
         der Plan genau einmal. In beiden Faellen steht er auf der Ausgabenaht
         und damit in der Datei -- sie ist der Beleg des Laufs.
      7. Schreiben: ACL ueber alle Ziele, danach je verifiziertem Ziel die
         Freigabe.
      8. Zusammenfassung und Rueckgabewert (D-16).

    DIE SCHRITTE 3 BIS 8 STEHEN IN Invoke-ProvisioningWrite (Phase 5, Plan
    05-02). Invoke-DemFsProvisioning erhebt (Schritte 1 und 2) und uebergibt;
    der Pruefweg ruft dieselbe Funktion, um abweichende Ziele anzugleichen.
    Es gibt damit genau EINE Schreibstrecke fuer beide Wege -- Reihenfolge,
    Preflight-Sperre, getipptes JA und SHARE-03 gelten fuer beide gleich.

    HIER WIRD DIE AUSNAHME DES SHARE-PROVISIONERS IN EIN ERGEBNIS VERWANDELT.
    Invoke-ShareApply WIRFT ueber einem roten ACL-Ergebnis, statt einen
    Fehlerbefund zu liefern -- Phase 3 hat diese Umwandlung ausdruecklich
    hierher verschoben, weil ein zurueckgegebener Satz mit Stufe Share die
    Zusage aus Phase-3-D-05 braeche.

    KEIN EINGABE-CMDLET UND KEIN AUSGABE-CMDLET IN DIESER DATEI. Beides laeuft
    ueber die Nahtstellen der Interaktionsschicht (D-04, FLOW-08, OUT-07).
#>

function Invoke-DemFsProvisioning {
    <#
    .SYNOPSIS
        Fuehrt den vollstaendigen Provisionierungslauf: Dialog, Preflight,
        Planvorschau, Bestaetigung, Schreiben, Zusammenfassung.

    .DESCRIPTION
        Die Rueckgabe ist EIN Objekt mit ExitCode, Confirmed, Target und
        Result. Result ist die FLACHE ERGEBNISSAMMLUNG und ausdruecklich kein
        Text: der spaetere Logdatei-Nachbau bleibt damit ein
        Export-Csv-Einzeiler ueber dieselbe Sammlung (OUT-06, OPS-01).

    .PARAMETER Menu
        Nach jedem Durchlauf zurueck ins Hauptmenue, bis der Operator Beenden
        waehlt (Serverlauf 2026-09-25). Ohne den Schalter genau ein Durchlauf.
        Der Einstieg Provision-DemFsShares.ps1 setzt ihn. Nur mit dem Schalter
        folgt auf jeden Durchlauf die Abschlussfrage [M]/[R]/[E]; [R] zeigt
        den Detailbericht je Ziel und ist der Detailmodus (OUT-05 v1.3, D-01,
        D-02).

    .OUTPUTS
        [pscustomobject] mit ExitCode, Confirmed, Target und Result.

    .EXAMPLE
        $lauf = Invoke-DemFsProvisioning -Menu
        exit $lauf.ExitCode
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch] $Menu
    )

    # --- 1. Kapazitaet einmal vorab (D-14) ---------------------------------
    $kapazitaet = Start-DemFsDialog

    if ($Menu) { return (Invoke-DemFsMenuLoop -Capability $kapazitaet) }

    # --- 1b. Modusfrage (Phase 5, D-01) -------------------------------------
    $modus = Read-RunMode

    if ($modus -ceq 'Exit') { return (Merge-DemFsRunResult -Run @()) }

    return (Invoke-DemFsRunMode -Mode $modus -Capability $kapazitaet)
}

function Invoke-DemFsMenuLoop {
    <#
    .SYNOPSIS
        Das Hauptmenue so lange, bis der Operator Beenden waehlt
        (Serverlauf 2026-09-25). Intern zu Invoke-DemFsProvisioning -Menu.

    .DESCRIPTION
        Jeder Durchlauf ist ein vollstaendiger Lauf -- eigene Gruppenerhebung,
        eigener Plan, eigenes getipptes JA. Nach dem ersten Durchlauf ist
        Beenden die Vorgabe des Menues.

        Nach jedem Durchlauf folgt die Abschlussfrage "[M] Hauptmenue /
        [R] Bericht anzeigen / [E] Beenden" mit Vorgabe E (OUT-05 v1.3,
        D-02). R gibt den Detailbericht des Durchlaufs aus
        (Format-RunDetailReport) und fragt erneut -- [R] ist der Detailmodus,
        es gibt keinen weiteren Schalter (D-01). M fuehrt ins Hauptmenue, E
        beendet.

    .OUTPUTS
        [pscustomobject] mit ExitCode, Confirmed, Target und Result ueber alle
        Durchlaeufe; ExitCode ist der hoechste Wert eines Durchlaufs, 0 ohne
        Durchlauf.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    $kapazitaet = $Capability
    $laeufe = New-Object System.Collections.Generic.List[object]

    while ($true) {

        $vorgabe = if ($laeufe.Count -eq 0) { '1' } else { '0' }
        $modus = Read-RunMode -DefaultChoice $vorgabe

        if ($modus -ceq 'Exit') { break }

        # NAV-01 (09-02): keine eigene Menuezeile nach dem Durchlauf -- den
        # Kopf "Hauptmenü" stellt Read-RunMode vor jede Optionsliste.
        $lauf = Invoke-DemFsRunMode -Mode $modus -Capability $kapazitaet
        $laeufe.Add($lauf)

        # OUT-05 (v1.3), D-02: die Abschlussfrage steht NUR hier, in der
        # Menueschleife. [R] ist der Detailmodus (D-01): der Bericht entsteht
        # aus den Zielen des Durchlaufs und dem Rollenspeicher -- der ist an
        # dieser Stelle noch der des Durchlaufs, Reset-TrusteeRoleStore laeuft
        # erst zu Beginn des naechsten.
        $ziele = @()
        if (($null -ne $lauf) -and ($null -ne $lauf.PSObject.Properties['Target'])) {
            $ziele = @(@($lauf.Target) | Where-Object { $null -ne $_ })
        }

        $abschluss = Read-RunCloseChoice

        while ($abschluss -ceq 'Report') {
            Write-OperatorLine -Capability $kapazitaet -Line @(
                Format-RunDetailReport -Target $ziele -Group (Get-TrusteeRoleStore))
            $abschluss = Read-RunCloseChoice
        }

        if ($abschluss -ceq 'Exit') { break }
    }

    Write-OperatorLine -Capability $kapazitaet -Line @(
        (New-OperatorTextLine -Text 'Beendet.')
        (New-OperatorTextLine -Text '')
    )

    return (Merge-DemFsRunResult -Run $laeufe.ToArray())
}

function Start-DemFsDialog {
    <#
    .SYNOPSIS
        Kapazitaet erheben, Rueckfragekanal setzen, Startbanner ausgeben.
        Liefert die Kapazitaet. Intern.

    .DESCRIPTION
        G-04-4e: das Banner steht auf der Ausgabenaht und damit auch in einer
        umgeleiteten Datei. Unter Umleitung reist es ausserdem mit der ersten
        Frage -- dasselbe Muster wie der Plan an der Bestaetigung (G-04-3a).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $kapazitaet = Get-ConsoleCapability

    Reset-TrusteeRoleStore
    Clear-PromptContext
    Set-PromptChannel -Capability $kapazitaet

    $banner = @(Get-StartBanner)

    Write-OperatorLine -Capability $kapazitaet -Line $banner

    if (($null -ne $kapazitaet.PSObject.Properties['OutputRedirected']) -and [bool] $kapazitaet.OutputRedirected) {
        foreach ($zeile in $banner) {
            Add-PromptContext -Line @([string] $zeile.Text) -Severity ([string] $zeile.Severity)
        }
    }

    return $kapazitaet
}

function Merge-DemFsRunResult {
    <#
    .SYNOPSIS
        Fasst die Rueckgaben mehrerer Durchlaeufe zusammen: hoechster
        ExitCode, Confirmed wenn einer bestaetigt wurde, Ziele und Ergebnisse
        aneinandergereiht. Intern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Run
    )

    $code = 0
    $bestaetigt = $false
    $ziele = New-Object System.Collections.Generic.List[object]
    $ergebnisse = New-Object System.Collections.Generic.List[object]

    foreach ($lauf in @($Run | Where-Object { $null -ne $_ })) {
        if ([int] $lauf.ExitCode -gt $code) { $code = [int] $lauf.ExitCode }
        if ([bool] $lauf.Confirmed) { $bestaetigt = $true }
        foreach ($z in @($lauf.Target)) { if ($null -ne $z) { $ziele.Add($z) } }
        foreach ($e in @($lauf.Result)) { if ($null -ne $e) { $ergebnisse.Add($e) } }
    }

    return [pscustomobject] @{
        ExitCode  = $code
        Confirmed = $bestaetigt
        Target    = $ziele.ToArray()
        Result    = $ergebnisse.ToArray()
    }
}

function Invoke-DemFsRunMode {
    <#
    .SYNOPSIS
        Ein Durchlauf des gewaehlten Weges: Anlegen, Pruefen oder Anpassen.
        Intern.

    .DESCRIPTION
        Die Gruppenerhebung beginnt je Durchlauf neu: eine im vorigen
        Durchlauf bestaetigte Gruppe darf nicht still in den naechsten
        wandern.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Provision', 'Audit', 'Adjust')]
        [string] $Mode,

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    $kapazitaet = $Capability

    Reset-TrusteeRoleStore

    if ($Mode -ceq 'Audit') {
        return (Invoke-DemFsAudit -Capability $kapazitaet)
    }

    # Weg 3 (2026-09-24): NTFS-Berechtigungen erkannter Ablagen anpassen.
    if ($Mode -ceq 'Adjust') {
        return (Invoke-DemFsAdjust -Capability $kapazitaet)
    }

    # --- 2. Alles erheben (D-06) -------------------------------------------
    $ziele = @(Read-ProvisioningTarget -Capability $kapazitaet)

    if ($ziele.Count -eq 0) {
        return [pscustomobject] @{
            ExitCode  = (Get-ProvisioningExitCode -Result @() -Confirmed $false -NothingSelected)
            Confirmed = $false
            Target    = @()
            Result    = @()
        }
    }

    # --- Schritt 5 von Weg 1: Pruefung und Ausfuehrung (NAV-01) ----------
    # Der Schritt beginnt mit einer Ausgabe -- dem Plan --, sein Kopf geht
    # deshalb ueber die Ausgabenaht und steht vor der ersten Planzeile
    # (Kanalregel, Read-WizardStep.ps1). Die Schrittfolge kommt aus den
    # Ordnerarten der erhobenen Ziele, dieselbe Wahrheit wie im Dialog.
    $arten = @($ziele | ForEach-Object { [string] $_.Kind })

    Write-OperatorLine -Capability $kapazitaet -Line @(Get-StepHeaderRecord -Key 'Check' `
            -Sequence @(Get-WizardStepSequence -Mode Provision -Kind $arten))

    # --- 3. bis 8. Die Schreibstrecke ------------------------------------
    # Ausgelagert in Invoke-ProvisioningWrite (Phase 5, Plan 05-02): der
    # Pruefweg gleicht abweichende Ziele ueber GENAU DIESELBE Strecke an. Ein
    # zweiter Schreibablauf waere eine zweite Wahrheit ueber Reihenfolge und
    # Sperren.
    return (Invoke-ProvisioningWrite -Target $ziele -Capability $kapazitaet)
}

function Invoke-ProvisioningWrite {
    <#
    .SYNOPSIS
        Die Schreibstrecke beider Wege: Soll binden, Preflight, Plan,
        Hostsperre, getipptes JA, Schreiben, Freigabestufe, Zusammenfassung,
        Rueckgabeobjekt (Schritte 3 bis 8). Nicht exportiert.

    .DESCRIPTION
        Weg 1 (Invoke-DemFsProvisioning) ruft sie nach dem Dialog, der
        Pruefweg (Invoke-DemFsAudit) nach dem Angebot mit den abweichenden
        Zielen. Die Schritte stehen hier wortgleich so, wie sie vor der
        Auslagerung in Invoke-DemFsProvisioning standen;
        Tests/Orchestration.Tests.ps1 laeuft dafuer ohne eine Aenderung
        (Regressionsbeweis).

        Rueckgabewerte wie bisher: 0/1/2 nach Zustand, 2 bei Hostsperre, 3
        bei nicht getipptem JA.

    .PARAMETER Target
        Die Ziele, je mit Kind, Path, ShareName, IsExisting, Binding,
        AclOptGroup und ShareOptGroup.

    .PARAMETER Capability
        Die einmal vorab erhobene Konsolenkapazitaet (D-14).

    .OUTPUTS
        [pscustomobject] mit ExitCode, Confirmed, Target und Result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object[]] $Target,

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    $kapazitaet = $Capability
    $ziele = @($Target)

    # --- 3. Soll binden ----------------------------------------------------
    foreach ($ziel in $ziele) {

        $soll = Expand-AclTemplate `
            -Template (Get-AclTemplate -Kind ([string] $ziel.Kind)) `
            -Binding $ziel.Binding `
            -IncludeOptGroup @($ziel.AclOptGroup)

        $ziel | Add-Member -NotePropertyName 'Desired' -NotePropertyValue $soll -Force
    }

    # --- 4. Preflight, einmal ueber alle Ziele ------------------------------
    $preflight = @(Test-ProvisioningPreflight -Target $ziele)

    # --- 5. Plan und Befunde in einem Bild ----------------------------------
    # EINMAL gebaut: dieselben Zeilen gehen an die Ausgabenaht und, bei
    # Umleitung, in den Bestaetigungsprompt.
    $planzeilen = @(Format-ProvisioningPlan -Target $ziele -PreflightResult $preflight `
            -Capability $kapazitaet -Group (Get-TrusteeRoleStore))

    Write-OperatorLine -Capability $kapazitaet -Line $planzeilen

    # --- 6. Getippte Bestaetigung (D-11) ------------------------------------
    # DAVOR die eine Frage, die gar nicht erst gestellt wird: sperrt ein
    # Preflight-Befund mit Scope Host den gesamten Lauf, bliebe nach einer
    # Bestaetigung nichts zu tun. Erfolgskriterium 1 der Phase 3 verlangt den
    # Abbruch, BEVOR irgendetwas geschrieben wurde -- eine Frage an dieser
    # Stelle waere eine Aufforderung ohne Gegenstand.
    if (Test-HostSperre -PreflightResult $preflight) {

        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Severity 'Error' -Text 'Das Preflight sperrt den gesamten Lauf. Es wurde nichts angelegt und nichts geändert.')
            (New-OperatorTextLine -Text '')
        )

        return [pscustomobject] @{
            ExitCode  = (Get-ProvisioningExitCode -Result $preflight -Confirmed $false -Blocked)
            Confirmed = $false
            Target    = $ziele
            Result    = @($preflight)
        }
    }

    # G-04-3a: unter Umleitung reist der Plan mit der Frage. Das Feld wird
    # ueber PSObject.Properties gelesen -- das Modul laeuft unter
    # Set-StrictMode, und eine Kapazitaet ohne das Feld gilt als nicht
    # umgeleitet.
    $umgeleitet = ($null -ne $kapazitaet.PSObject.Properties['OutputRedirected']) -and [bool] $kapazitaet.OutputRedirected

    if ($umgeleitet) {
        Add-PromptContext -Line @($planzeilen | ForEach-Object { [string] $_.Text })
    }

    $bestaetigt = Confirm-TypedWord -Prompt 'Soll das jetzt geschrieben werden?' -Word 'JA'

    if (-not $bestaetigt) {

        # D-12: sauber beenden. Kein Ruecksprung in den Dialog -- der Ablauf ist
        # rein interaktiv, kurz und wird selten gefahren.
        Write-OperatorLine -Capability $kapazitaet -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Severity 'Warning' -Text 'Abgebrochen. Es wurde nichts angelegt und nichts geändert.')
            (New-OperatorTextLine -Text '')
        )

        return [pscustomobject] @{
            ExitCode  = (Get-ProvisioningExitCode -Result $preflight -Confirmed $false)
            Confirmed = $false
            Target    = $ziele
            Result    = @($preflight)
        }
    }

    # --- 7. Schreiben --------------------------------------------------------
    $ergebnisse = New-Object System.Collections.Generic.List[object]

    foreach ($satz in @($preflight)) { $ergebnisse.Add($satz) }

    $aclSaetze = @(Invoke-AclApplySet -Target $ziele -PreflightResult $preflight)

    foreach ($satz in $aclSaetze) { $ergebnisse.Add($satz) }

    foreach ($ziel in $ziele) {

        $verify = Select-AclVerifyResult -Result $aclSaetze -Kind ([string] $ziel.Kind) -LiteralPath ([string] $ziel.Path)

        # Kein verifiziertes ACL -- kein Freigabeversuch. Das ist SHARE-03 und
        # zugleich die Bedingung, unter der Phase-3-D-05 traegt: bei roter
        # Verifikation entsteht ueberhaupt kein Ergebnissatz mit Stufe Share.
        if ($null -eq $verify) { continue }
        if ([string] $verify.Status -cne 'OK') { continue }

        try {
            foreach ($satz in @(Invoke-ShareApply `
                        -Kind ([string] $ziel.Kind) `
                        -LiteralPath ([string] $ziel.Path) `
                        -ShareName ([string] $ziel.ShareName) `
                        -Binding $ziel.Binding `
                        -AclVerifyResult $verify `
                        -IncludeOptGroup @($ziel.ShareOptGroup))) {

                $ergebnisse.Add($satz)
            }
        }
        catch {
            # DIE STELLE, AN DIE PHASE 3 DIESE UMWANDLUNG VERSCHOBEN HAT. Ein
            # gescheitertes Ziel stoppt die uebrigen nicht (Phase-3-D-06).
            #
            # DER SATZ BESCHREIBT DEN ZUSTAND, DER WIRKLICH VORLIEGT (G-04-3b).
            # Die Freigabestufe laeuft erst nach geschriebenem und
            # verifiziertem ACL -- ein "unberuehrt" waere hier falsch. Ob eine
            # Freigabe besteht, wird nachgelesen statt behauptet: die Stufe
            # kann auch NACH dem Anlegen abgebrochen sein.
            $grund = $_.Exception.Message
            $bestehend = Get-ExistingShare -Name ([string] $ziel.ShareName)

            if ($null -eq $bestehend) {
                $meldung = 'Das NTFS-ACL ist geschrieben und verifiziert; die Freigabe wurde nicht angelegt. Grund: {0}' -f $grund
            }
            else {
                $meldung = 'Das NTFS-ACL ist geschrieben und verifiziert; die Freigabestufe brach ab. Eine Freigabe "{0}" besteht, ihre Berechtigungen sind nicht verifiziert. Grund: {1}' -f [string] $bestehend.Name, $grund
            }

            $ergebnisse.Add((New-ProvisioningResult `
                        -Kind ([string] $ziel.Kind) -Path ([string] $ziel.Path) `
                        -Stage 'Share' -Status 'Error' -Message $meldung))
        }
    }

    $alle = $ergebnisse.ToArray()

    # --- 8. Zusammenfassung und Rueckgabewert -------------------------------
    Write-OperatorLine -Capability $kapazitaet -Line @(
        Format-ProvisioningSummary -Result $alle -Target $ziele `
            -Capability $kapazitaet -Group (Get-TrusteeRoleStore) `
            -ServerName (Get-ServerDnsName) -Table)

    return [pscustomobject] @{
        ExitCode  = (Get-ProvisioningExitCode -Result $alle -Confirmed $true)
        Confirmed = $true
        Target    = $ziele
        Result    = $alle
    }
}

function Select-AclVerifyResult {
    <#
    .SYNOPSIS
        Der Ergebnissatz der ACL-Verifikation zu einem Ziel -- Ordnerart UND
        Pfad --, oder nichts. Intern zur Orchestrierung.

    .DESCRIPTION
        BEIDE SEITEN DURCH DIESELBE NORMALISIERUNG. Ein gruener Befund zu einem
        anderen Pfad ist kein Beleg fuer diesen -- genau diese Verwechslung
        legte eine Freigabe ueber ein ungeprueftes ACL. Assert-AclVerified
        prueft es ein zweites Mal und wirft; diese Auswahl haelt den Fall aber
        schon davor vom Provisioner fern.

        DIE ORDNERART GEHOERT ZUM SCHLUESSEL (G-04-1a). Ein gruener Satz einer
        anderen Ordnerart auf demselben Pfad ist kein Beleg fuer dieses Ziel:
        in Lauf 3 lagen drei DEM-Ordnerarten auf e:\DEM, und die Auswahl nach
        dem Pfad allein gab jedem Ziel den ersten Satz -- den des zuerst
        geschriebenen Templates, waehrend auf dem Ordner schon das ACL des
        zuletzt geschriebenen lag. Die Ordnerart wird ordinal verglichen; ihre
        Werte sind feste Literale aus einem ValidateSet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    $zielPraefix = ConvertTo-PfadPraefix -LiteralPath $LiteralPath

    foreach ($satz in @($Result)) {

        if ($null -eq $satz) { continue }
        if ([string] $satz.Stage -cne 'AclVerify') { continue }
        if ([string] $satz.Kind -cne $Kind) { continue }

        if ((ConvertTo-PfadPraefix -LiteralPath ([string] $satz.Path)) -eq $zielPraefix) {
            return $satz
        }
    }

    return $null
}
