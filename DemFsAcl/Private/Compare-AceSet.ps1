<#
    Compare-AceSet -- der Verifizierer (VERIFY-03 bis VERIFY-06).

    Nimmt OBJEKTE entgegen, nie einen Pfad zum Lesen: das DesiredAcl aus
    Expand-AclTemplate und den Ist-Schnappschuss aus ConvertTo-ActualAceSet
    bzw. Get-ActualAceSet. Genau das macht den Vergleich fixture-getrieben und
    offline pruefbar. -Path wird nur in das Ergebnis durchgereicht.

    Semantik:
      - Mengen, nicht Folgen. Windows schreibt die ACE-Reihenfolge kanonisch
        um; ein positionsbezogener Vergleich waere konstruktionsbedingt falsch.
      - Exakte Maskengleichheit. Eine enthaltende Pruefung ("Ist hat
        mindestens Soll") liesse ein zu weit gefasstes ACL still durchgehen.
      - Normalisiert wird ausschliesslich in ConvertTo-AceKey.
      - Doppelte Soll-Schluessel werden zusammengefasst, ohne Befund: bindet
        der Bediener die vordefinierte Verwaltungsgruppe als Admin-Gruppe,
        fallen zwei DEMConfig-ACEs zusammen, und Windows fasst sie beim
        Schreiben ohnehin zusammen. Der zuerst gesehene Soll-Datensatz traegt
        die Provenienz.

    Befundarten: Missing (AceAbsent), Unexpected (AceExtra),
    InheritanceMismatch (FlagPair, Protection, InheritedAcePresent).

    Rueckgabe ist New-ProvisioningResult -- die eingefrorene Ergebnisform,
    keine zweite. Keine Ausgabe, keine Rueckfrage.
#>

function Compare-AceSet {
    <#
    .SYNOPSIS
        Vergleicht ein DesiredAcl mit einem Ist-Schnappschuss und liefert ein
        ProvisioningResult mit Stage AclVerify.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Desired,

        [Parameter(Mandatory)]
        [object] $Actual,

        [AllowEmptyString()]
        [string] $Path = ''
    )

    $ordinal = [System.StringComparer]::Ordinal

    # --- Soll: Schluessel -> Paar (normalisiert, Binder-Datensatz) -----------
    $soll = New-Object 'System.Collections.Generic.Dictionary[string,object]' $ordinal
    foreach ($ace in @($Desired.Aces)) {
        $norm = ConvertTo-AceKey -Ace $ace.Rule
        if (-not $soll.ContainsKey($norm.Key)) {
            $soll.Add($norm.Key, [pscustomobject] @{ Norm = $norm; Record = $ace })
        }
    }

    # --- Ist: Schluessel -> normalisierter Datensatz (keine Herkunft) --------
    $ist = New-Object 'System.Collections.Generic.Dictionary[string,object]' $ordinal
    foreach ($regel in @($Actual.Aces)) {
        $norm = ConvertTo-AceKey -Ace $regel
        if (-not $ist.ContainsKey($norm.Key)) {
            $ist.Add($norm.Key, $norm)
        }
    }

    # --- Mengendifferenzen, deterministisch ordinal sortiert ------------------
    $fehlend = New-Object System.Collections.Generic.List[string]
    foreach ($k in $soll.Keys) {
        if (-not $ist.ContainsKey($k)) { $fehlend.Add($k) }
    }
    $fehlend.Sort($ordinal)

    $zusaetzlich = New-Object System.Collections.Generic.List[string]
    foreach ($k in $ist.Keys) {
        if (-not $soll.ContainsKey($k)) { $zusaetzlich.Add($k) }
    }
    $zusaetzlich.Sort($ordinal)

    # --- Paarbildung: gleiche SID, Typ und Maske, nur anderes Flagpaar ------
    # Ohne sie erschiene eine falsche Gilt-fuer-Angabe als zwei
    # zusammenhanglose Befunde. (OI)(CI)(IO) gegen (OI)(CI) ist auf einem
    # Profilshare der Unterschied zwischen "jeder sieht nur sein Profil" und
    # "jeder sieht jedes". Eine abweichende MASKE wird ausdruecklich nicht
    # gepaart -- sie ist ein anderes Recht, keine Vererbungsabweichung.
    # Je Soll-Datensatz hoechstens ein Partner; ein gepaarter Ist-Datensatz
    # steht fuer kein zweites Paar zur Verfuegung. Beide Listen sind sortiert,
    # die Zuordnung ist damit deterministisch.
    $befundeFlag = New-Object System.Collections.Generic.List[object]
    $restFehlend = New-Object System.Collections.Generic.List[string]
    $vergeben = New-Object 'System.Collections.Generic.HashSet[string]' $ordinal

    foreach ($k in $fehlend) {
        $s = $soll[$k].Norm
        $partner = $null
        foreach ($z in $zusaetzlich) {
            if ($vergeben.Contains($z)) { continue }
            $i = $ist[$z]
            if (($i.Sid -ceq $s.Sid) -and ($i.AccessControlType -eq $s.AccessControlType) -and ($i.Rights -eq $s.Rights)) {
                $partner = $z
                break
            }
        }

        if ($null -eq $partner) {
            $restFehlend.Add($k)
            continue
        }

        [void] $vergeben.Add($partner)
        $sollBeschriftung = ConvertTo-AppliesTo -Inheritance $s.Inheritance -Propagation $s.Propagation
        $istNorm = $ist[$partner]
        $istBeschriftung = ConvertTo-AppliesTo -Inheritance $istNorm.Inheritance -Propagation $istNorm.Propagation

        $befundeFlag.Add((New-AceFinding -Finding 'InheritanceMismatch' -Reason 'FlagPair' -Norm $s -Record $soll[$k].Record `
                    -AppliesTo $sollBeschriftung.AppliesTo `
                    -Expected (Format-AppliesTo $sollBeschriftung) `
                    -Actual (Format-AppliesTo $istBeschriftung) `
                    -Message 'Der ACE trägt das richtige Recht, gilt aber für den falschen Bereich (Vererbungsflags).'))
    }

    $befundeFehlend = New-Object System.Collections.Generic.List[object]
    $befundeZusaetzlich = New-Object System.Collections.Generic.List[object]

    foreach ($k in $restFehlend) {
        $paar = $soll[$k]
        $befundeFehlend.Add((New-AceFinding -Finding 'Missing' -Reason 'AceAbsent' -Norm $paar.Norm -Record $paar.Record `
                    -Expected 'vorhanden' -Actual 'fehlt' `
                    -Message 'Ein im Soll vorgesehener ACE fehlt auf dem Ordner.'))
    }

    foreach ($k in $zusaetzlich) {
        if ($vergeben.Contains($k)) { continue }
        $befundeZusaetzlich.Add((New-AceFinding -Finding 'Unexpected' -Reason 'AceExtra' -Norm $ist[$k] -Record $null `
                    -Expected 'nicht vorgesehen' -Actual 'vorhanden' `
                    -Message 'Der Ordner trägt einen ACE, den das Soll nicht vorsieht.'))
    }

    # --- Vererbungsschutz als eigene Zusage, ausserhalb des ACE-Diffs --------
    # Andere Abhilfe, deshalb eigener Befund: Protection repariert man ueber
    # SetAccessRuleProtection, geerbte Reste ueber das Neuschreiben des
    # Deskriptors.
    $befundeSchutz = New-Object System.Collections.Generic.List[object]

    if ([bool] $Desired.ProtectInheritance) {
        $schutzRecord = [pscustomobject] @{
            Trustee = ''
            Status  = [string] $Desired.ProtectInheritanceStatus
            Source  = [string] $Desired.ProtectInheritanceSource
            Section = [string] $Desired.ProtectInheritanceSection
        }

        if (-not [bool] $Actual.IsProtected) {
            $befundeSchutz.Add((New-AceFinding -Finding 'InheritanceMismatch' -Reason 'Protection' -Norm $null -Record $schutzRecord `
                        -Expected 'True' -Actual 'False' `
                        -Message 'Der Vererbungsschutz ist abgeschaltet; der Ordner erbt Berechtigungen vom übergeordneten Ordner.'))
        }

        $geerbt = @($Actual.Inherited).Count
        if ($geerbt -gt 0) {
            $befundeSchutz.Add((New-AceFinding -Finding 'InheritanceMismatch' -Reason 'InheritedAcePresent' -Norm $null -Record $schutzRecord `
                        -Expected '0' -Actual ([string] $geerbt) `
                        -Message ('Der Ordner trägt {0} geerbte ACE(s), obwohl das Soll Vererbungsschutz verlangt.' -f $geerbt)))
        }
    }

    $befunde = New-Object System.Collections.Generic.List[object]
    foreach ($b in $befundeFehlend) { $befunde.Add($b) }
    foreach ($b in $befundeZusaetzlich) { $befunde.Add($b) }
    foreach ($b in $befundeFlag) { $befunde.Add($b) }
    foreach ($b in $befundeSchutz) { $befunde.Add($b) }

    $anzahlFehlend = $befundeFehlend.Count
    $anzahlZusaetzlich = $befundeZusaetzlich.Count
    $anzahlVererbung = $befundeFlag.Count + $befundeSchutz.Count

    $status = if ($befunde.Count -eq 0) { 'OK' } else { 'Error' }
    $meldung = 'ACL-Vergleich: {0} fehlend, {1} unerwartet, {2} Vererbungsabweichung.' -f
        $anzahlFehlend, $anzahlZusaetzlich, $anzahlVererbung

    return New-ProvisioningResult -Kind ([string] $Desired.Kind) -Path $Path -Stage 'AclVerify' `
        -Status $status -Message $meldung -Detail $befunde.ToArray()
}

function Format-AppliesTo {
    <#
    .SYNOPSIS
        Gilt-fuer-Bezeichnung samt Buchstabenform, z. B.
        "Nur Unterordner und Dateien (OI)(CI)(IO)". Intern zu Compare-AceSet.
    #>
    param([Parameter(Mandatory)] [object] $Beschriftung)

    if ([string]::IsNullOrEmpty([string] $Beschriftung.Icacls)) {
        return [string] $Beschriftung.AppliesTo
    }
    return ('{0} {1}' -f $Beschriftung.AppliesTo, $Beschriftung.Icacls)
}

function New-AceFinding {
    <#
    .SYNOPSIS
        Baut einen Befund-Datensatz mit dreizehn Feldern. Intern zu
        Compare-AceSet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Finding,
        [Parameter(Mandatory)] [string] $Reason,
        [AllowNull()] [object] $Norm,
        [AllowNull()] [object] $Record,
        [AllowEmptyString()] [string] $Expected = '',
        [AllowEmptyString()] [string] $Actual = '',
        [AllowEmptyString()] [string] $Message = '',
        [AllowEmptyString()] [string] $AppliesTo = ''
    )

    $sid = ''
    $rights = 0
    $rightsHex = ''

    if ($null -ne $Norm) {
        $sid = [string] $Norm.Sid
        $rights = [int] $Norm.Rights
        $rightsHex = '0x{0:X}' -f $rights
        if ([string]::IsNullOrEmpty($AppliesTo)) {
            $AppliesTo = (ConvertTo-AppliesTo -Inheritance $Norm.Inheritance -Propagation $Norm.Propagation).AppliesTo
        }
    }

    $trustee = ''
    $herkunft = ''
    $quelle = ''
    $abschnitt = ''

    if ($null -ne $Record) {
        $trustee = [string] $Record.Trustee
        $herkunft = [string] $Record.Status
        $quelle = [string] $Record.Source
        $abschnitt = [string] $Record.Section
    }

    return [pscustomobject] @{
        Finding   = $Finding
        Reason    = $Reason
        Sid       = $sid
        Trustee   = $trustee
        Rights    = $rights
        RightsHex = $rightsHex
        AppliesTo = $AppliesTo
        Expected  = $Expected
        Actual    = $Actual
        Message   = $Message
        Status    = $herkunft
        Source    = $quelle
        Section   = $abschnitt
    }
}
