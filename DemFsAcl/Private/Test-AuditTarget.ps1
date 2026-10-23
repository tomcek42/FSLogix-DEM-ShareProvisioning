<#
    Test-AuditTarget -- die rein lesende Pruefung je Ziel (AUDIT-05, D-14,
    D-15).

    GELESEN WIRD JE ZIEL GENAU EINMAL, ueber Get-AuditSnapshot und damit ueber
    die eine Lesestelle Get-ActualAceSet. Derselbe Schnappschuss speist die
    Gruppenableitung (Get-AuditTargetBinding) und die Pruefung -- eine zweite
    Lesung hiesse, dass Ableitung und Befund zwei verschiedene Staende sehen
    koennten, und eine zweite Lesestelle hoebe die Zusage aus VERIFY-07 auf.

    VERGLICHEN WIRD MIT DEM UNVERAENDERTEN VERGLEICHER Compare-AceSet, streng
    gegen das Soll, das aus den am Ziel abgelesenen Gruppen gebunden ist
    (D-14, seit 2026-10-22 alle Gruppen je Rolle). Kein eigener Vergleich,
    keine eigene Normalisierung. Eine Pflichtrolle ohne Gruppe meldet die
    Pruefung selbst (Befund RoleMissing).

    EIN NICHT LESBARES ZIEL IST EIN FEHLERBEFUND GENAU DIESES ZIELS, KEIN
    ABBRUCH (D-15). Die Ausnahme der Lesestelle wird zum Feld Error des
    Schnappschusses und von dort zu einem Ergebnissatz.

    Kein Schreiben, keine Ausgabe, keine Rueckfrage.
#>

function Get-AuditSnapshot {
    <#
    .SYNOPSIS
        Liest je Ziel genau einmal das ACL und liefert Pfad -> { Actual, Error }.

    .DESCRIPTION
        Eine Ausnahme der Lesestelle wird zu Error mit der Ausnahmemeldung; der
        Lauf geht mit dem naechsten Ziel weiter (D-15).

    .OUTPUTS
        [hashtable] Pfad -> [pscustomobject] mit Actual und Error.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target
    )

    $schnapp = @{}

    foreach ($ziel in @($Target)) {

        if ($null -eq $ziel) { continue }

        $pfad = [string] $ziel.Path
        if ($schnapp.ContainsKey($pfad)) { continue }

        try {
            $schnapp[$pfad] = [pscustomobject] @{ Actual = (Get-ActualAceSet -LiteralPath $pfad); Error = '' }
        }
        catch {
            $schnapp[$pfad] = [pscustomobject] @{ Actual = $null; Error = [string] $_.Exception.Message }
        }
    }

    return $schnapp
}

function Get-AuditSnapshotEntry {
    <#
    .SYNOPSIS
        Der Schnappschuss eines Pfades, oder nichts. Intern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Snapshot,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    if ($Snapshot.ContainsKey($LiteralPath)) { return $Snapshot[$LiteralPath] }

    return $null
}

function Test-AuditTarget {
    <#
    .SYNOPSIS
        Prueft je Ziel das NTFS-ACL der Wurzel streng gegen das gebundene
        Soll, dazu Freigabe, Offline-Caching und Besitzer (AUDIT-05, D-14).

    .DESCRIPTION
        Je Ziel, in dieser Reihenfolge:
        - AclVerify: ist der Schnappschuss fehlerhaft, EIN Satz mit Zustand
          Error und dem Grund; sonst unveraendert Compare-AceSet.
        - ShareVerify: die Freigaben auf den Pfad (Get-AuditPathShare), je
          Freigabe Compare-ShareAccess in SID-Form gegen das Share-Template --
          dieselbe Vergleichsstrecke wie die Verifikation beim Anlegen. Keine
          Freigabe ist ein Fehler (D-04), mehrere sind zusaetzlich ein Hinweis
          (Planerentscheid 11 aus 05-02).
        - ShareCaching: je Freigabe OK nur bei CachingMode None; ein
          fehlendes Feld gilt als abweichend (Muster Invoke-ShareApply).
        - Owner: ein Hinweis, nie ein Fehler -- das Werkzeug setzt den
          Besitzer nie (ACL-05). Erwartet sind die lokale
          Administratorengruppe, das Systemkonto und die gebundene Gruppe der
          Administratoren (Planerentscheid 12 aus 05-02).

        NICHT LESBAR IST EIN BEFUND DIESES ZIELS, KEIN ABBRUCH (D-15): eine
        nicht lesbare Freigabeliste wird ein Fehler jedes Ziels, eine nicht
        lesbare Freigabe ein Fehler nur ihres Ziels -- jeweils mit Detail
        Finding Unreadable.

        Die Freigabesaetze tragen den Freigabenamen (ShareName), die gelesenen
        Eintraege (ShareActual) und die abgelesenen Helpdesk-Gruppen
        (HelpdeskSid) -- daraus baut die Gruppenuebersicht ihre Freigabespalte.

    .PARAMETER Target
        Die Ziele, jeweils mit Kind, Path, Desired, Binding, MissingRole und
        ShareOptGroup.

    .PARAMETER ShareList
        Die einmal gelesene Freigabeliste des Servers.

    .PARAMETER ShareListError
        Der Grund, falls die Freigabeliste nicht lesbar war; sonst leer.

    .PARAMETER OwnerName
        SID-Zeichenkette -> Anzeigename, nur fuer die Meldung (IDENT-06).

    .OUTPUTS
        ProvisioningResult-Saetze.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [hashtable] $Snapshot,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ShareList = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ShareListError = '',

        [Parameter()]
        [AllowNull()]
        [hashtable] $OwnerName = $null
    )

    $saetze = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in @($Target)) {

        if ($null -eq $ziel) { continue }

        $pfad = [string] $ziel.Path
        $schnapp = Get-AuditSnapshotEntry -Snapshot $Snapshot -LiteralPath $pfad
        $lesbar = ($null -ne $schnapp) -and ($null -ne $schnapp.Actual)

        if (-not $lesbar) {

            $grund = if ($null -eq $schnapp) { 'nicht gelesen' } else { [string] $schnapp.Error }
            $meldung = 'Das ACL von "{0}" ist nicht lesbar: {1}' -f $pfad, $grund

            $saetze.Add((New-ProvisioningResult -Kind ([string] $ziel.Kind) -Path $pfad -Stage 'AclVerify' `
                        -Status 'Error' -Message $meldung -Detail @(
                        [pscustomobject] @{ Finding = 'Unreadable'; Reason = 'AclNotReadable'; Message = $meldung }
                    )))
        }
        else {
            $saetze.Add((Compare-AceSet -Desired $ziel.Desired -Actual $schnapp.Actual -Path $pfad))

            # Eine Pflichtrolle ohne Gruppe sieht der Vergleicher nicht: das
            # Soll ist aus dem Ist abgelesen und hat fuer sie keinen Eintrag.
            $fehlend = @()
            if ($null -ne $ziel.PSObject.Properties['MissingRole']) { $fehlend = @(@($ziel.MissingRole) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) }) }

            $rollenKarte = Get-TokenRoleMap

            foreach ($token in $fehlend) {

                $meldung = 'Am ACL von "{0}" steht keine {1}: kein Eintrag trägt deren Rechte.' -f $pfad, (Get-TrusteeRoleLabel -Role ([string] $rollenKarte[[string] $token]))

                $saetze.Add((New-ProvisioningResult -Kind ([string] $ziel.Kind) -Path $pfad -Stage 'AclVerify' `
                            -Status 'Error' -Message $meldung -Detail @(
                            [pscustomobject] @{ Finding = 'RoleMissing'; Reason = 'NoGroupWithRoleRights'; Token = [string] $token; Message = $meldung }
                        )))
            }
        }

        foreach ($satz in @(Test-AuditShare -Target $ziel -ShareList $ShareList -ShareListError $ShareListError)) {
            $saetze.Add($satz)
        }

        # Bei nicht lesbarem ACL kein Besitzersatz: der Besitzer stammt aus
        # derselben Lesung.
        if ($lesbar) {
            foreach ($satz in @(Test-AuditOwner -Target $ziel -Actual $schnapp.Actual -OwnerName $OwnerName)) {
                $saetze.Add($satz)
            }
        }
    }

    return $saetze.ToArray()
}

function Test-AuditShare {
    <#
    .SYNOPSIS
        Freigabe- und Caching-Pruefung eines Ziels (Stufen ShareVerify und
        ShareCaching). Intern zu Test-AuditTarget.

    .DESCRIPTION
        Liest ausschliesslich ueber die Seam Get-ShareAccessEntry; die
        Freigabeliste kommt fertig herein (Get-ShareList, einmal je Lauf).
        Kein SMB-Cmdlet hier (ShareWriteSeam-Gate).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ShareList = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ShareListError = ''
    )

    $kind = [string] $Target.Kind
    $pfad = [string] $Target.Path
    $saetze = New-Object System.Collections.Generic.List[object]

    if (-not [string]::IsNullOrEmpty($ShareListError)) {

        $meldung = 'Die Freigaben des Servers ließen sich nicht abfragen: {0}' -f $ShareListError

        $saetze.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareVerify' -Status 'Error' -Message $meldung `
                    -Detail @([pscustomobject] @{ Finding = 'Unreadable'; Reason = 'ShareListNotReadable'; Message = $meldung })))
        return $saetze.ToArray()
    }

    $namen = @(Get-AuditPathShare -LiteralPath $pfad -ShareList $ShareList)

    if ($namen.Count -eq 0) {

        $meldung = 'Auf "{0}" zeigt keine Freigabe; das Soll sieht eine vor.' -f $pfad

        $saetze.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareVerify' -Status 'Error' -Message $meldung `
                    -Detail @([pscustomobject] @{ Finding = 'ShareMissing'; Reason = 'NoShareOnPath'; Message = $meldung })))
        return $saetze.ToArray()
    }

    $shareOpt = @()
    if ($null -ne $Target.PSObject.Properties['ShareOptGroup']) { $shareOpt = @(@($Target.ShareOptGroup) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) }) }

    $bindung = @{}
    if ($Target.Binding -is [hashtable]) { foreach ($token in @($Target.Binding.Keys)) { $bindung[$token] = $Target.Binding[$token] } }

    if ($namen.Count -gt 1) {
        $saetze.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareVerify' -Status 'Warning' `
                    -Message ('Auf "{0}" zeigen {1} Freigaben: {2}.' -f $pfad, $namen.Count, ($namen -join ', '))))
    }

    foreach ($name in $namen) {

        # --- Berechtigungen, in SID-Form -----------------------------------
        $ist = @()
        $lesefehler = ''

        try { $ist = @(ConvertTo-ShareActual -Entry @(Get-ShareAccessEntry -Name $name)) }
        catch { $lesefehler = [string] $_.Exception.Message }

        if (-not [string]::IsNullOrEmpty($lesefehler)) {

            $meldung = 'Die Berechtigungen der Freigabe "{0}" sind nicht lesbar: {1}' -f $name, $lesefehler

            $saetze.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareVerify' -Status 'Error' -Message $meldung `
                        -Detail @([pscustomobject] @{ Finding = 'Unreadable'; Reason = 'ShareNotReadable'; ShareName = $name; Message = $meldung })))
        }
        else {
            # Helpdesk je Freigabe aus ihren eigenen Eintraegen (Weg 2 seit
            # 2026-10-22): jede abgelesene Helpdesk-Gruppe ist gueltig.
            $helpdesk = @()
            $opt = @($shareOpt | Where-Object { $_ -cne 'Helpdesk' })

            if ($kind -ceq 'DEMProfiles') {
                $helpdesk = @(Get-AuditHelpdeskSid -ShareActual @($ist))
                if ($helpdesk.Count -gt 0) {
                    $bindung['<HelpdeskGroup>'] = [System.Security.Principal.SecurityIdentifier[]] @($helpdesk | ForEach-Object { [System.Security.Principal.SecurityIdentifier]::new($_) })
                    $opt = @($opt) + @('Helpdesk')
                }
            }

            $soll = @(ConvertTo-ShareDesired -Template (Get-ShareTemplate -Kind $kind) -Binding $bindung -IncludeOptGroup @($opt))
            $herkunft = Get-ShareProvenance -Desired $soll

            $befunde = @(Compare-ShareAccess -Desired $soll -Actual @($ist))

            foreach ($befund in $befunde) {
                $befund | Add-Member -NotePropertyName 'ShareName' -NotePropertyValue $name -Force
            }

            $fehlend = @($befunde | Where-Object { [string] $_.Finding -ceq 'Missing' }).Count
            $unerwartet = @($befunde | Where-Object { [string] $_.Finding -ceq 'Unexpected' }).Count
            $status = if ($befunde.Count -gt 0) { 'Error' } else { 'OK' }

            $satz = New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareVerify' -Status $status `
                -Message ('Freigabe "{0}": {1} fehlend, {2} unerwartet.' -f $name, $fehlend, $unerwartet) `
                -Detail $befunde `
                -Provenance $herkunft.Provenance -Source $herkunft.Source -Section $herkunft.Section

            # Die gelesenen Eintraege reisen fuer die Gruppenuebersicht mit --
            # sie liest die Freigabe nicht ein zweites Mal.
            $satz | Add-Member -NotePropertyName 'ShareName' -NotePropertyValue $name -Force
            $satz | Add-Member -NotePropertyName 'ShareActual' -NotePropertyValue ([object[]] @($ist)) -Force
            $satz | Add-Member -NotePropertyName 'HelpdeskSid' -NotePropertyValue ([string[]] @($helpdesk)) -Force

            $saetze.Add($satz)
        }

        # --- Offline-Caching ----------------------------------------------
        # Aus dem Listeneintrag, ueber PSObject.Properties: fehlt das Feld,
        # gilt es als abweichend.
        $eintrag = @(@($ShareList) | Where-Object {
                ($null -ne $_) -and [string]::Equals([string] $_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase)
            })

        $caching = '(nicht gelesen)'
        if (($eintrag.Count -gt 0) -and ($null -ne $eintrag[0].PSObject.Properties['CachingMode'])) {
            $caching = [string] $eintrag[0].CachingMode
        }

        if ($caching -ceq 'None') {
            $saetze.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareCaching' -Status 'OK' `
                        -Message ('Das Offline-Caching der Freigabe "{0}" ist abgeschaltet.' -f $name)))
        }
        else {
            $meldung = 'Das Offline-Caching der Freigabe "{0}" ist "{1}"; das Soll ist None.' -f $name, $caching

            $saetze.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareCaching' -Status 'Error' -Message $meldung `
                        -Detail @([pscustomobject] @{
                            Finding   = 'CachingMode'
                            Reason    = 'CachingNotDisabled'
                            ShareName = $name
                            Expected  = 'None'
                            Actual    = $caching
                            Message   = $meldung
                        })))
        }
    }

    return $saetze.ToArray()
}

function Test-AuditOwner {
    <#
    .SYNOPSIS
        Der Besitzer der Wurzel zur Information (Stufe Owner, D-14,
        Planerentscheid 12 aus 05-02). Intern zu Test-AuditTarget.

    .DESCRIPTION
        Immer OK. Ein Besitzer ausserhalb von lokaler Administratorengruppe,
        Systemkonto und gebundener Gruppe der Administratoren
        (Test-AuditOwnerExpected) wird nur erwaehnt: in der Pruefungstabelle
        steht sein Name, farbig und mit Fussnote. Bis 2026-09-25 war er eine
        Warnung; der Projektinhaber fand das verwirrend, weil ein anderer
        Besitzer die Funktion nicht beeintraechtigt (Serverlauf 2026-09-25).
        Das Werkzeug setzt den Besitzer nie (ACL-05).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [object] $Actual,

        [Parameter()]
        [AllowNull()]
        [hashtable] $OwnerName = $null
    )

    if ($null -eq $Actual.PSObject.Properties['Owner']) { return @() }
    if ($null -eq $Actual.Owner) { return @() }

    $sid = [string] $Actual.Owner.Value

    $name = $sid
    if (($null -ne $OwnerName) -and $OwnerName.ContainsKey($sid)) { $name = [string] $OwnerName[$sid] }

    if (Test-AuditOwnerExpected -Target $Target -Sid $sid) {
        return @(New-ProvisioningResult -Kind ([string] $Target.Kind) -Path ([string] $Target.Path) -Stage 'Owner' -Status 'OK' `
                -Message ('Besitzer der Wurzel ist {0} ({1}).' -f $name, $sid))
    }

    return @(New-ProvisioningResult -Kind ([string] $Target.Kind) -Path ([string] $Target.Path) -Stage 'Owner' -Status 'OK' `
            -Message ('Besitzer der Wurzel ist {0} ({1}) -- zur Information: ein anderer Besitzer beeinträchtigt die Funktion nicht; das Werkzeug setzt den Besitzer nie.' -f $name, $sid))
}

function Test-AuditOwnerExpected {
    <#
    .SYNOPSIS
        Wahr, wenn der Besitzer die lokale Administratorengruppe, das
        Systemkonto oder die gebundene Gruppe der Administratoren ist --
        verglichen ueber die SID. Intern.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [string] $Sid
    )

    $erwartet = New-Object System.Collections.Generic.List[string]
    $erwartet.Add([string] (Get-WellKnownSid -Token 'WellKnown:BuiltinAdmins').Value)
    $erwartet.Add([string] (Get-WellKnownSid -Token 'WellKnown:System').Value)

    if (($null -ne $Target.PSObject.Properties['Binding']) -and ($Target.Binding -is [hashtable]) -and $Target.Binding.ContainsKey('<AdminGroup>')) {
        foreach ($admin in @($Target.Binding['<AdminGroup>'])) {
            if ($admin -is [System.Security.Principal.SecurityIdentifier]) { $erwartet.Add([string] $admin.Value) }
            else { $erwartet.Add([string] $admin) }
        }
    }

    return $erwartet.Contains($Sid)
}
