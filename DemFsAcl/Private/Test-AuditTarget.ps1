<#
    Test-AuditTarget -- die rein lesende Pruefung je Ziel (AUDIT-05, D-14,
    D-15).

    GELESEN WIRD JE ZIEL GENAU EINMAL, ueber Get-AuditSnapshot und damit ueber
    die eine Lesestelle Get-ActualAceSet. Derselbe Schnappschuss speist die
    Gruppenableitung (Get-AuditProductProposal) und die Pruefung -- eine zweite
    Lesung hiesse, dass Vorschlag und Befund zwei verschiedene Staende sehen
    koennten, und eine zweite Lesestelle hoebe die Zusage aus VERIFY-07 auf.

    VERGLICHEN WIRD MIT DEM UNVERAENDERTEN VERGLEICHER Compare-AceSet, streng
    gegen das gebundene Soll (D-14). Kein eigener Vergleich, keine eigene
    Normalisierung.

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
        Finding Unreadable, damit Select-AuditDeviation sie nicht anbietet.

        Die Freigabedetails tragen den Freigabenamen (Feld ShareName): daran
        waehlt Select-AuditDeviation die anzugleichende Freigabe.

    .PARAMETER Target
        Die Ziele, jeweils mit Kind, Path, Desired, Binding und ShareOptGroup.

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
    if ($null -ne $Target.PSObject.Properties['ShareOptGroup']) { $shareOpt = @($Target.ShareOptGroup) }

    $soll = @(ConvertTo-ShareDesired -Template (Get-ShareTemplate -Kind $kind) -Binding $Target.Binding -IncludeOptGroup $shareOpt)
    $herkunft = Get-ShareProvenance -Desired $soll

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
            $befunde = @(Compare-ShareAccess -Desired $soll -Actual @($ist))

            foreach ($befund in $befunde) {
                $befund | Add-Member -NotePropertyName 'ShareName' -NotePropertyValue $name -Force
            }

            $fehlend = @($befunde | Where-Object { [string] $_.Finding -ceq 'Missing' }).Count
            $unerwartet = @($befunde | Where-Object { [string] $_.Finding -ceq 'Unexpected' }).Count
            $status = if ($befunde.Count -gt 0) { 'Error' } else { 'OK' }

            $saetze.Add((New-ProvisioningResult -Kind $kind -Path $pfad -Stage 'ShareVerify' -Status $status `
                        -Message ('Freigabe "{0}": {1} fehlend, {2} unerwartet.' -f $name, $fehlend, $unerwartet) `
                        -Detail $befunde `
                        -Provenance $herkunft.Provenance -Source $herkunft.Source -Section $herkunft.Section))
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

function Select-AuditDeviation {
    <#
    .SYNOPSIS
        Die Ziele, die zum Angleichen angeboten werden (D-02, Planerentscheid
        10 und 11 aus 05-02).

    .DESCRIPTION
        ANGEBOTEN WIRD NUR EINE BEWIESENE ABWEICHUNG: ein Fehlerbefund aus dem
        Vergleich -- ein ACE-Befund aus Compare-AceSet (NTFS), ein
        Freigabebefund aus Compare-ShareAccess (Freigabe), eine fehlende
        Freigabe (Freigabe fehlt) oder ein falsches Caching (Caching).

        NICHT LESBAR HEISST NICHT ANGEBOTEN. Traegt ein Satz des Ziels einen
        Befund Unreadable -- ACL, Freigabeliste oder eine Freigabe --, ist dort
        nichts bewiesen, und die Schreibstrecke wuerde ACL und Freigabe
        gemeinsam anfassen. Geraten wird nichts.

        MEHRERE FREIGABEN AUF EINEM PFAD: angeglichen wird die erste
        abweichende in ordinaler Reihenfolge, sonst die erste; die uebrigen
        stehen in KeptShareNames und bleiben unveraendert -- die
        Schreibstrecke kennt je Ziel genau einen Freigabenamen.

        Die Zuordnung Satz -> Ziel laeuft ueber Ordnerart UND Pfad
        (Get-TargetResult, G-04-1a).

    .OUTPUTS
        Je abweichendem Ziel ein Datensatz mit Kind, Path, RelativePath,
        ShareName (leer = keine Freigabe), KeptShareNames, Reason (Kurzformen),
        Binding, AclOptGroup und ShareOptGroup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Result
    )

    $auswahl = New-Object System.Collections.Generic.List[object]

    foreach ($ziel in @($Target)) {

        if ($null -eq $ziel) { continue }

        $eigene = @(Get-TargetResult -Result @($Result) -Target $ziel)

        if (@($eigene | Where-Object { Test-AuditUnreadable -Result $_ }).Count -gt 0) { continue }

        $gruende = New-Object System.Collections.Generic.List[string]
        $abweichendeFreigabe = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        $fehler = @($eigene | Where-Object { [string] $_.Status -ceq 'Error' })

        if (@($fehler | Where-Object { [string] $_.Stage -ceq 'AclVerify' }).Count -gt 0) { $gruende.Add('NTFS') }

        foreach ($satz in @($fehler | Where-Object { [string] $_.Stage -ceq 'ShareVerify' })) {
            foreach ($befund in @($satz.Detail)) {
                if ($null -eq $befund) { continue }
                if ($null -eq $befund.PSObject.Properties['Finding']) { continue }

                $art = [string] $befund.Finding

                if ($art -ceq 'ShareMissing') {
                    if (-not $gruende.Contains('Freigabe fehlt')) { $gruende.Add('Freigabe fehlt') }
                }
                elseif (($art -ceq 'Missing') -or ($art -ceq 'Unexpected')) {
                    if (-not $gruende.Contains('Freigabe')) { $gruende.Add('Freigabe') }
                    if ($null -ne $befund.PSObject.Properties['ShareName']) { $null = $abweichendeFreigabe.Add([string] $befund.ShareName) }
                }
            }
        }

        foreach ($satz in @($fehler | Where-Object { [string] $_.Stage -ceq 'ShareCaching' })) {
            if (-not $gruende.Contains('Caching')) { $gruende.Add('Caching') }
            foreach ($befund in @($satz.Detail)) {
                if (($null -ne $befund) -and ($null -ne $befund.PSObject.Properties['ShareName'])) {
                    $null = $abweichendeFreigabe.Add([string] $befund.ShareName)
                }
            }
        }

        if ($gruende.Count -eq 0) { continue }

        $freigaben = [string[]] @(@($ziel.ShareNames) | Where-Object { -not [string]::IsNullOrEmpty([string] $_) })
        [System.Array]::Sort($freigaben, [System.StringComparer]::Ordinal)

        $name = ''
        foreach ($kandidat in $freigaben) {
            if ($abweichendeFreigabe.Contains($kandidat)) { $name = $kandidat; break }
        }
        if ([string]::IsNullOrEmpty($name) -and ($freigaben.Count -gt 0)) { $name = $freigaben[0] }

        $auswahl.Add([pscustomobject] @{
                Kind           = [string] $ziel.Kind
                Path           = [string] $ziel.Path
                RelativePath   = [string] $ziel.RelativePath
                ShareName      = $name
                KeptShareNames = @($freigaben | Where-Object { $_ -cne $name })
                Reason         = $gruende.ToArray()
                Binding        = $ziel.Binding
                AclOptGroup    = @($ziel.AclOptGroup)
                ShareOptGroup  = @($ziel.ShareOptGroup)
            })
    }

    return $auswahl.ToArray()
}

function Test-AuditUnreadable {
    <#
    .SYNOPSIS
        Wahr, wenn ein Ergebnissatz einen Befund "nicht lesbar" traegt. Intern.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object] $Result
    )

    foreach ($befund in @($Result.Detail)) {
        if ($null -eq $befund) { continue }
        if ($null -eq $befund.PSObject.Properties['Finding']) { continue }
        if ([string] $befund.Finding -ceq 'Unreadable') { return $true }
    }

    return $false
}
