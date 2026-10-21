<#
    Invoke-DemFsAudit -- die Orchestrierung des Pruefwegs (Phase 5, AUDIT-01
    bis AUDIT-06). NICHT exportiert: der einzige oeffentliche Einstieg bleibt
    Invoke-DemFsProvisioning, das nach der Modusfrage hierher verzweigt
    (Phase-4-D-02).

    DIE REIHENFOLGE IST DER INHALT DIESER DATEI:
      1. Erhoehte Sitzung, sonst Ende mit Rueckgabewert 2, bevor irgendetwas
         erfragt wird (Planerentscheid 4 aus 05-01): Freigaben und die ACLs
         fremder Ordner lassen sich sonst nicht lesen, und jeder Befund waere
         "nicht lesbar".
      2. Genau ein Wurzelverzeichnis (D-03); laesst es sich nicht auflisten,
         Hinweis und erneute Frage.
      3. Erkennung und bestaetigte Zuordnung (D-05 bis D-10) -- VOR dem ersten
         Lesezugriff auf ein ACL.
      4. Je Ziel GENAU EINE Lesung (Get-AuditSnapshot).
      5. Je Produkt (FSLogix vor DEM) Gruppen am Schnappschuss ablesen und
         bestaetigen (D-11 bis D-13), dann je Ziel das Soll binden.
      6. Strenge Pruefung je Ziel (D-14, D-15).
      7. Bericht und Rueckgabewert (D-16 bis D-18).
      8. Nur bei bewiesener Abweichung das Angebot, anzugleichen (D-02,
         AUDIT-07), Vorgabe nein. Nach Ja laufen die abweichenden Ziele durch
         Invoke-ProvisioningWrite -- dieselbe Schreibstrecke wie Weg 1.
      9. Nur auf Wunsch, Vorgabe nein: die Benutzerordner der ersten Ebene
         rein lesend pruefen -- USR-01 bis USR-10; kein Angebot, kein
         Schreiben. Jeder Ausgang nach der Zuordnung laeuft hier durch, der
         Rueckgabewert ist der hoehere aus Lauf und Bericht.

    BIS ZUR ZUSAGE WIRD NICHTS GESCHRIEBEN (D-02). Keine Schreib-Seam, keine
    Schreibprobe; Tests/Audit.Tests.ps1 haelt das je Durchstichfall nach. Die
    Schreibprobe PRE-07 gehoert zum Preflight der Schreibstrecke und laeuft
    erst nach dem Ja auf das Angebot, ACL und Freigabe erst nach dem
    getippten JA (Planerentscheid 8 aus 05-02). Schritt 9 schreibt nie, auch
    nicht nach einer Zusage in Schritt 8 (Tests/UserFolderReadOnly.Tests.ps1).

    KEIN EINGABE-CMDLET UND KEIN AUSGABE-CMDLET IN DIESER DATEI (FLOW-08,
    OUT-07).
#>

function Invoke-DemFsAudit {
    <#
    .SYNOPSIS
        Der rein lesende Pruefweg: Wurzel, Erkennung, Zuordnung, abgelesene
        Gruppen, Pruefung, Bericht.

    .OUTPUTS
        [pscustomobject] mit ExitCode, Confirmed, Target und Result -- dieselbe
        Form wie Invoke-DemFsProvisioning. Confirmed heisst "geschrieben" und
        ist im reinen Pruefweg falsch.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    # --- 1. Erhoehte Sitzung -------------------------------------------------
    if (-not (Test-IsElevated)) {

        Write-OperatorLine -Capability $Capability -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Severity 'Error' -Text 'Die Bestandsprüfung braucht eine erhöhte Sitzung: Freigaben und die ACLs fremder Ordner lassen sich sonst nicht lesen. Bitte die Konsole als Administrator starten. Es wurde nichts geprüft und nichts geändert.')
            (New-OperatorTextLine -Text '')
        )

        return [pscustomobject] @{
            ExitCode  = (Get-ProvisioningExitCode -Result @() -Blocked)
            Confirmed = $false
            Target    = @()
            Result    = @()
        }
    }

    # --- 2. Wurzel und Erkennung -------------------------------------------
    $namen = Get-AuditKindNameMap

    # Die Freigaben des Servers EINMAL vor der Erkennung. Ein Fehlschlag ist
    # ein Befund, kein Abbruch (D-15): die Erkennung laeuft ohne
    # Freigabenamen weiter.
    $freigabeListe = @()
    $freigabeFehler = ''

    try {
        $freigabeListe = @(Get-ShareList)
    }
    catch {
        # Der Grund reist bis in die Pruefung: dort wird er ein Fehlerbefund
        # jedes Ziels (D-15, Plan 05-02).
        $freigabeFehler = [string] $_.Exception.Message
        Write-OperatorHint -Text ('    Die Freigaben des Servers lassen sich nicht lesen: {0} -- die Erkennung läuft ohne Freigabenamen weiter.' -f $_.Exception.Message)
    }

    while ($true) {

        $wurzel = Read-AuditRoot

        try {
            $scan = Find-AuditTarget -RootPath ([string] $wurzel.Path) -NameMap $namen -ShareList $freigabeListe
            break
        }
        catch {
            Write-OperatorHint -Text ('    Das Wurzelverzeichnis "{0}" lässt sich nicht auflisten: {1}' -f [string] $wurzel.Path, $_.Exception.Message)
        }
    }

    # --- 3. Zuordnung, bestaetigt vor dem ersten Lesezugriff ----------------
    $zuordnung = Read-AuditAssignment -Scan $scan
    $ziele = @(@($zuordnung.Target) | Where-Object { $null -ne $_ })

    $ergebnisse = New-Object System.Collections.Generic.List[object]

    # Nicht gewaehlte oder nicht erkannte Ordner erscheinen weder im Bericht
    # noch im Rueckgabewert (Serverlauf 2026-09-25): der Operator hat sie
    # selbst nicht gewaehlt, eine Warnung darueber war nur Rauschen.

    if ($ziele.Count -eq 0) {
        Write-OperatorLine -Capability $Capability -Line @(
            (New-OperatorTextLine -Text '')
            (New-OperatorTextLine -Severity 'Warning' -Text 'Es wurde kein Ordner zur Prüfung zugeordnet.')
        )
    }

    # --- 4. Je Ziel genau eine Lesung ---------------------------------------
    $schnapp = Get-AuditSnapshot -Target $ziele

    # --- 5. Gruppen je Produkt, dann das Soll je Ziel -----------------------
    # NAV-03: Schritt 2 "Gruppen und Optionen bestaetigen" -- nur mit
    # mindestens einem Ziel; der Kopf reist als Kontext mit der ersten Frage
    # der Produktschleife, je Produkt danach eine Produktzeile.
    $optionen = @{}
    $folge = @(Get-WizardStepSequence -Mode Audit)

    if ($ziele.Count -gt 0) {
        Add-PromptContext -Severity 'Heading' -Line @(Get-DialogUeberschriftZeile -Key 'AuditGroups' -Sequence $folge)
    }

    foreach ($produkt in @('FSLogix', 'DEM')) {

        $eigene = @($ziele | Where-Object { (Get-KindProduct -Kind ([string] $_.Kind)) -ceq $produkt })
        if ($eigene.Count -eq 0) { continue }

        Add-PromptContext -Line @('')
        Add-PromptContext -Severity 'Heading' -Line @(('  {0}' -f (Get-ProductHeading -Product $produkt -Kind @($eigene | ForEach-Object { [string] $_.Kind }))))

        # Helpdesk (D-13): abgelesen an der ersten Freigabe des ersten
        # DEMProfiles-Ziels. Ein Lesefehler heisst: kein Vorschlag.
        $helpdeskIst = $null
        $helpdeskPfad = ''

        $profilZiel = @($eigene | Where-Object { [string] $_.Kind -ceq 'DEMProfiles' } | Sort-Object -Property { [string] $_.Path })

        if (($produkt -ceq 'DEM') -and ($profilZiel.Count -gt 0) -and (@($profilZiel[0].ShareNames).Count -gt 0)) {

            $freigabe = [string] @($profilZiel[0].ShareNames)[0]
            $helpdeskPfad = 'Freigabe "{0}"' -f $freigabe

            try { $helpdeskIst = @(ConvertTo-ShareActual -Entry @(Get-ShareAccessEntry -Name $freigabe)) }
            catch { $helpdeskIst = $null }
        }

        $vorschlag = Get-AuditProductProposal -Product $produkt -Target $eigene -Snapshot $schnapp `
            -HelpdeskShareActual $helpdeskIst -HelpdeskPath $helpdeskPfad
        $arten = @($eigene | ForEach-Object { [string] $_.Kind } | Select-Object -Unique)

        $bestaetigt = Read-AuditGroupBinding -Product $produkt -Proposal $vorschlag -Kind $arten
        $optionen[$produkt] = @($bestaetigt.OptGroup)
    }

    $gebunden = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in $ziele) {

        $art = [string] $ziel.Kind
        $aclOpt = @(Get-AuditKindOptGroup -Kind $art -OptGroup @($optionen[(Get-KindProduct -Kind $art)]))
        $shareOpt = @(Get-FixedOptGroup -Kind $art -Scope 'Share')
        $bindung = Read-GroupBinding -Kind $art -AclOptGroup $aclOpt -ShareOptGroup $shareOpt

        $freigaben = @(@($ziel.ShareNames) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) })

        $gebunden.Add([pscustomobject] @{
                Kind          = $art
                Path          = [string] $ziel.Path
                RelativePath  = [string] $ziel.RelativePath
                ShareNames    = $freigaben
                ShareName     = $(if ($freigaben.Count -gt 0) { $freigaben -join ', ' } else { '(keine)' })
                IsExisting    = $true
                Binding       = $bindung
                AclOptGroup   = $aclOpt
                ShareOptGroup = $shareOpt
                Desired       = (Expand-AclTemplate -Template (Get-AclTemplate -Kind $art) -Binding $bindung -IncludeOptGroup $aclOpt)
            })
    }

    $gepruefte = $gebunden.ToArray()

    # --- 6. Strenge Pruefung je Ziel ----------------------------------------
    # NTFS, Freigabe, Caching, Besitzer (D-14). Die Besitzernamen entstehen
    # hier und nur fuer die Anzeige (IDENT-06); verglichen wird ueber die SID.
    $besitzerNamen = @{}

    foreach ($eintrag in @($schnapp.Values)) {

        if (($null -eq $eintrag) -or ($null -eq $eintrag.Actual)) { continue }
        if ($null -eq $eintrag.Actual.PSObject.Properties['Owner']) { continue }
        if ($null -eq $eintrag.Actual.Owner) { continue }

        $besitzer = [string] $eintrag.Actual.Owner.Value
        if (-not $besitzerNamen.ContainsKey($besitzer)) {
            $besitzerNamen[$besitzer] = Get-TrusteeDisplayName -Sid $eintrag.Actual.Owner
        }
    }

    foreach ($satz in @(Test-AuditTarget -Target $gepruefte -Snapshot $schnapp `
                -ShareList $freigabeListe -ShareListError $freigabeFehler -OwnerName $besitzerNamen)) {
        $ergebnisse.Add($satz)
    }

    $alle = $ergebnisse.ToArray()

    # --- 7. Bericht und Rueckgabewert ---------------------------------------
    # NAV-03: Schritt 3 beginnt mit einer Ausgabe -- der Kopf geht ueber die
    # Ausgabenaht. Angebot, Schreibstrecke und Benutzerordner gehoeren dazu.
    Write-OperatorLine -Capability $Capability -Line @(Get-StepHeaderRecord -Key 'AuditReport' -Sequence $folge)

    Write-OperatorLine -Capability $Capability -Line @(
        Format-AuditReport -Target $gepruefte -Result $alle -Capability $Capability -Group (Get-TrusteeRoleStore) `
            -Owner (Get-AuditOwnerTable -Target $gepruefte -Snapshot $schnapp -OwnerName $besitzerNamen))

    # Der Pruefweg gilt fuer die Rueckgabewertregel als bestaetigt -- es gab
    # nichts zu bestaetigen (D-17). Confirmed bleibt falsch: es wurde nichts
    # geschrieben.
    $pruefCode = Get-ProvisioningExitCode -Result $alle -Confirmed $true

    $pruefbericht = [pscustomobject] @{
        ExitCode  = $pruefCode
        Confirmed = $false
        Target    = $gepruefte
        Result    = $alle
    }

    # --- 8. Angebot: abweichende Ziele angleichen (D-02, AUDIT-07) ----------
    # Nur bei bewiesener Abweichung, Vorgabe nein. Ohne Zusage bleibt es ein
    # reiner Prueflauf -- keine Schreib-Seam, auch keine Schreibprobe PRE-07
    # (Planerentscheid 8): die gehoert zum Preflight und damit zur
    # Schreibstrecke.
    $abweichend = @(Select-AuditDeviation -Target $gepruefte -Result $alle)

    $ergebnis = $pruefbericht

    if (($abweichend.Count -gt 0) -and (Read-AuditAdjustOffer -Deviation $abweichend)) {

        $schreibZiele = @(Read-AuditAdjustTarget -Target $abweichend)

        # DIESELBE Schreibstrecke wie Weg 1: Soll binden, Preflight ueber alle
        # anzugleichenden Ziele, Plan, getipptes JA, Schreiben mit Ruecklesen,
        # Freigabe erst nach verifiziertem ACL, Zusammenfassung.
        $lauf = Invoke-ProvisioningWrite -Target $schreibZiele -Capability $Capability

        # Rueckgabewertregel (D-17, Planerentscheid 9): nach einem Angleichen
        # bestimmt der Schreibpfad den Wert. Wurde JA nicht getippt (3), gilt
        # der Pruefbericht -- es wurde nichts angeglichen, die Abweichungen
        # bestehen fort. Eine Hostsperre im Preflight bleibt 2.
        if ([bool] $lauf.Confirmed) {
            $code = [int] $lauf.ExitCode
        }
        elseif ([int] $lauf.ExitCode -eq 3) {
            $code = $pruefCode
        }
        else {
            $code = 2
        }

        $ergebnis = [pscustomobject] @{
            ExitCode  = $code
            Confirmed = [bool] $lauf.Confirmed
            Target    = $gepruefte
            Result    = @(@($alle) + @($lauf.Result))
        }
    }

    # --- 9. Benutzerordner, nur auf Wunsch (USR-01 bis USR-10) -------------
    # Ganz am Ende: ein Angleichen der Wurzel ist dann schon geschrieben und
    # vererbt, der Bericht zeigt den Stand danach. Rein lesend -- kein
    # Angebot, kein Schreibaufruf, auch nicht bei auffaelligen Ordnern.
    $benutzerordner = Invoke-UserFolderReport -Target $gepruefte -Capability $Capability

    return (Join-UserFolderOutcome -Run $ergebnis -UserFolder $benutzerordner)
}

function Invoke-UserFolderReport {
    <#
    .SYNOPSIS
        Der Benutzerordner-Bericht am Ende von Weg 2: Frage, Lesen, Ausgabe,
        Ergebnissaetze (USR-01, USR-08 bis USR-10). Intern.

    .DESCRIPTION
        Ohne Profilablage unter den geprueften Zielen wird nicht gefragt. Nach
        Nein oder Enter wird kein Benutzerordner gelesen. Nach Ja wird je
        Profilablage die erste Ebene ueber Test-UserFolderSet bewertet; die
        Pfade aller geprueften Ziele sind ausgenommen -- eine Ablage unter
        einer Ablage ist kein Benutzerordner. Namen entstehen nur fuer die SIDs,
        die der Bericht anzeigt (IDENT-06).

        REIN LESEND. Kein Angebot, keine Reparaturfrage, kein Schreibaufruf
        (USR-09); Tests/UserFolderReadOnly.Tests.ps1 haelt das ueber die
        Aufrufhuelle fest.

    .OUTPUTS
        [pscustomobject] mit Asked, Checked, ExitCode (0 ohne Pruefung),
        Report (die Ablageberichte) und Result (die Ergebnissaetze der Stufe
        UserFolder, als Array).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter()]
        [AllowNull()]
        [object] $Capability = $null
    )

    $wurzeln = @(Select-UserFolderRoot -Target $Target)

    if ($wurzeln.Count -eq 0) {
        return [pscustomobject] @{ Asked = $false; Checked = $false; ExitCode = 0; Report = [object[]] @(); Result = [object[]] @() }
    }

    if (-not (Read-UserFolderOffer -Root $wurzeln)) {
        return [pscustomobject] @{ Asked = $true; Checked = $false; ExitCode = 0; Report = [object[]] @(); Result = [object[]] @() }
    }

    $ausgenommen = [string[]] @(@($Target) | Where-Object { $null -ne $_ } | ForEach-Object { [string] $_.Path })

    $berichte = New-Object System.Collections.Generic.List[object]

    foreach ($wurzel in $wurzeln) {

        # Bei vielen Ordnern sieht der Operator, dass etwas laeuft.
        Write-OperatorLine -Capability $Capability -Line @(
            (New-OperatorTextLine -Text ('  Lese die Benutzerordner unter "{0}" ...' -f [string] $wurzel.Path)))

        $berichte.Add((Test-UserFolderSet -Target $wurzel -ExcludePath $ausgenommen))
    }

    $bericht = $berichte.ToArray()

    $namen = @{}
    foreach ($sid in @(Get-UserFolderDisplaySid -Report $bericht)) {
        $namen[[string] $sid] = Get-TrusteeDisplayName -Sid ([System.Security.Principal.SecurityIdentifier]::new([string] $sid))
    }

    Write-OperatorLine -Capability $Capability -Line @(Format-UserFolderReport -Report $bericht -Name $namen)

    $saetze = [object[]] @(ConvertTo-UserFolderResult -Report $bericht)

    return [pscustomobject] @{
        Asked    = $true
        Checked  = $true
        ExitCode = (Get-ProvisioningExitCode -Result $saetze -Confirmed $true)
        Report   = $bericht
        Result   = $saetze
    }
}

function Join-UserFolderOutcome {
    <#
    .SYNOPSIS
        Verrechnet den Benutzerordner-Bericht in das Laufergebnis von Weg 2
        (USR-10). Intern.

    .DESCRIPTION
        Der Rueckgabewert ist der hoehere aus Lauf und Bericht -- aber nur,
        wenn geprueft wurde. Kein Bericht senkt einen Wert. Die
        Ergebnissaetze der Stufe UserFolder stehen hinter denen des Laufs;
        Confirmed und Target bleiben unveraendert. Ein nicht bestaetigtes
        Angleichen (3) ist vorher bereits auf den Pruefwert abgebildet.

    .OUTPUTS
        [pscustomobject] mit ExitCode, Confirmed, Target und Result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Run,

        [Parameter(Mandatory)]
        [object] $UserFolder
    )

    $code = [int] $Run.ExitCode
    $saetze = [object[]] @($Run.Result)

    if ([bool] $UserFolder.Checked) {
        $code = [System.Math]::Max($code, [int] $UserFolder.ExitCode)
        $saetze = [object[]] (@($saetze) + @($UserFolder.Result))
    }

    return [pscustomobject] @{
        ExitCode  = [int] $code
        Confirmed = [bool] $Run.Confirmed
        Target    = $Run.Target
        Result    = $saetze
    }
}

function Get-AuditOwnerTable {
    <#
    .SYNOPSIS
        Je geprueftem Ziel der Besitzer fuer die Pruefungstabelle: Pfad ->
        Name und ob er zu den ueblichen Besitzern gehoert. Intern.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [hashtable] $Snapshot,

        [Parameter(Mandatory)]
        [hashtable] $OwnerName
    )

    $karte = @{}

    foreach ($ziel in @($Target)) {

        if ($null -eq $ziel) { continue }
        $pfad = [string] $ziel.Path
        if (-not $Snapshot.ContainsKey($pfad)) { continue }

        $eintrag = $Snapshot[$pfad]
        if (($null -eq $eintrag) -or ($null -eq $eintrag.Actual)) { continue }
        if ($null -eq $eintrag.Actual.PSObject.Properties['Owner']) { continue }
        if ($null -eq $eintrag.Actual.Owner) { continue }

        $sid = [string] $eintrag.Actual.Owner.Value
        $name = $sid
        if ($OwnerName.ContainsKey($sid)) { $name = [string] $OwnerName[$sid] }

        $karte[$pfad] = [pscustomobject] @{ Name = $name; Expected = (Test-AuditOwnerExpected -Target $ziel -Sid $sid) }
    }

    return $karte
}
