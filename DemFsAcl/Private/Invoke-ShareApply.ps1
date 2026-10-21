<#
    Invoke-ShareApply -- der Share-Provisioner (SHARE-03 bis SHARE-09).

    DER ERSTE SCHRITT IST KEIN BAUSCHRITT, SONDERN EIN WAECHTER. Die gesamte
    Reihenfolge des Werkzeugs -- Ordner, ACL, verifizieren, Freigabe,
    verifizieren -- laeuft auf diese Datei zu. Eine Freigabe ueber einem
    ungeprueften ACL ist ein Datenabfluss und keine Reihenfolgevorliebe.

    ES GIBT GENAU EINEN MECHANISMUS ZUM SETZEN DER FREIGABEBERECHTIGUNGEN,
    und er ist gemessen: New-SmbShare beziehungsweise Set-SmbShare mit
    -SecurityDescriptor und einem SID-basierten SDDL. Beleg ist
    Tests/Fixtures/SmbShareSddl.Measured.psd1 aus Plan 03-01 (Rule.SddlAccepted
    wahr, aufgenommen auf einem deutsch lokalisierten Windows Server).

    Der zweite, in D-04 erwogene Weg -- den erwarteten Prinzipalnamen ueber
    Translate([NTAccount]) herleiten und an Grant-SmbShareAccess geben -- ist
    GEMESSEN UND VERWORFEN und kommt in diesem Werkzeug nicht vor. Zwei
    Schreibwege hiessen, dass einer von beiden nie gemessen wurde; das ist das
    Gegenteil dessen, wofuer der Spike existiert. Ihn nachtraeglich einzuziehen
    waere kostspielig (Share-Verifikation und Testmenge ein zweites Mal) --
    dafuer ist jede Zeile Freigabecode hier gemessen statt vermutet.

    DER EINZIGE LOKALISIERTE NAME IM GANZEN LAUF ist der Wert, den
    Get-ShareAccessEntry zurueckgibt. Er wird sofort ueber Resolve-TrusteeSid in
    eine SID uebersetzt und danach nur noch fuer eines verwendet: als Argument
    des Entzugs desselben Eintrags (SHARE-05). Kein Literal, kein hergeleiteter
    Name.

    Kein Write-Host, kein Read-Host: die Engine gibt ProvisioningResult-Objekte
    zurueck, ausgegeben wird erst in Phase 4 (C-10, C-12, OUT-07).
#>

function Invoke-ShareApply {
    <#
    .SYNOPSIS
        Legt die Freigabe ueber einer verifizierten NTFS-ACL an oder gleicht
        eine bestehende an, liest in SID-Form zurueck und verifiziert.

    .DESCRIPTION
        Der Ablauf:

        0. WAECHTER (SHARE-03). Traegt -AclVerifyResult nicht Status OK fuer
           denselben Pfad, WIRFT die Funktion und ruft keine einzige SMB-Seam
           auf.
        1. Soll bauen: Share-Template laden, Trustees binden, abgewaehlte
           OptGroup-Eintraege weglassen.
        2. SDDL bauen (New-ShareSecurityDescriptor) -- Treuhaender
           ausschliesslich als SID-Zeichenkette.
        3. Anlegen oder angleichen (SHARE-04, SHARE-06, SHARE-08), dabei
           CreatedByThisRun mitfuehren. Besteht die Freigabe, wird sie VOR dem
           Schreiben gelesen (G-04-4g): stimmen Berechtigungen in SID-Form und
           Offline-Caching bereits mit dem Soll ueberein, wird nichts
           geschrieben und der Satz traegt Status OK; nur eine tatsaechliche
           Angleichung ergibt Warning (AdjustedByThisRun).
        4. Ruecklesen, in SID-Form vergleichen, Unerwartetes entziehen
           (SHARE-05, SHARE-07).
        5. Ein zweites Mal zuruecklesen, vergleichen, Cachingmodus pruefen.
           Bei rotem Befund und CreatedByThisRun wahr die selbst erzeugte
           Freigabe entfernen; eine vorbestehende wird gemeldet und stehen
           gelassen (SHARE-09, D-07).

        WARUM SCHRITT 0 WIRFT UND KEINEN FEHLERBEFUND LIEFERT: Plan 03-01 sagt
        zu, dass bei roter ACL-Verifikation ueberhaupt kein Ergebnissatz mit
        Stage "Share" entsteht (D-05). Ein zurueckgegebener Satz brach diese
        Zusage. Einen Provisioner ueber einem roten ACL aufzurufen ist ein
        Programmierfehler, kein Betriebszustand.

        DER PFADVERGLEICH GEGEN EINE FREMD BELEGTE FREIGABE WIRD HIER NICHT
        WIEDERHOLT: PRE-05 aus Plan 03-01 hat die Unterscheidung gleicher gegen
        anderer Pfad bereits getroffen (D-10). Eine zweite Wahrheit ueber
        denselben Zustand drifted auseinander.

    .PARAMETER Kind
        Die Ordnerart; reist unveraendert in jeden Ergebnissatz.

    .PARAMETER LiteralPath
        Der Pfad, auf den die Freigabe zeigt. Muss derselbe sein, den das
        AclVerify-Ergebnis nennt.

    .PARAMETER ShareName
        Der Freigabename. Erfragt wird er in Phase 4 (SHARE-02), hier kommt er
        fertig herein.

    .PARAMETER Binding
        Die Gruppenbindung fuer die Platzhalter-Token, dieselbe Form wie bei
        Expand-AclTemplate: Token auf SecurityIdentifier oder Zeichenkette.

    .PARAMETER AclVerifyResult
        Der Ergebnissatz der ACL-Verifikation desselben Pfades.

    .PARAMETER IncludeOptGroup
        Die angewaehlten Optionsgruppen des Share-Templates.

    .OUTPUTS
        Sammlung von ProvisioningResult mit den Stages Share und ShareVerify.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [string] $ShareName,

        [Parameter(Mandatory)]
        [hashtable] $Binding,

        [Parameter(Mandatory)]
        [object] $AclVerifyResult,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $IncludeOptGroup = @()
    )

    # --- 0. Waechter (SHARE-03) --------------------------------------------
    Assert-AclVerified -AclVerifyResult $AclVerifyResult -Kind $Kind -LiteralPath $LiteralPath -ShareName $ShareName

    $ergebnisse = New-Object System.Collections.Generic.List[object]

    # --- 1. Soll bauen -------------------------------------------------------
    $template = Get-ShareTemplate -Kind $Kind
    $soll = @(ConvertTo-ShareDesired -Template $template -Binding $Binding -IncludeOptGroup $IncludeOptGroup)

    # Die Provenienz des Templates reist in beide Ergebnissaetze: Phase 4
    # braucht sie fuer das Kennzeichen und kann sie nicht nachschlagen. Ist auch
    # nur ein Eintrag abgeleitet, ist die ganze Zeile abgeleitet -- die
    # vorsichtige Richtung.
    $provenienz = Get-ShareProvenance -Desired $soll

    # --- 2. SDDL bauen -------------------------------------------------------
    $sddl = New-ShareSecurityDescriptor -Desired $soll

    # --- 3. Anlegen oder angleichen (SHARE-04, SHARE-06, SHARE-08) -----------
    $bestehend = Get-ExistingShare -Name $ShareName
    $selbstErzeugt = ($null -eq $bestehend)
    $angeglichen = $false
    $anlegeStatus = 'OK'

    if ($selbstErzeugt) {
        $null = New-ProvisionedShare -Name $ShareName -LiteralPath $LiteralPath `
            -SecurityDescriptor $sddl -CachingMode 'None'
        $anlegeMeldung = 'Die Freigabe wurde neu angelegt, mit dem Soll-Deskriptor und abgeschaltetem Offline-Caching.'
    }
    else {
        # NICHT abbrechen: PRE-05 hat einen fremd belegten Namen bereits
        # disqualifiziert (D-10), dieser Eintrag zeigt also auf denselben Pfad.
        #
        # VORABLESUNG (G-04-4g, Inhaberentscheid 2026-09-22, D-16). Ein
        # Wiederholungslauf ueber korrektem Stand soll ohne Fehlalarm mit 0
        # enden; also wird nur geschrieben, was wirklich abweicht. Gelesen
        # wird ueber dieselben Seams und dieselbe SID-Vergleichsfunktion wie
        # die Verifikation danach -- und die laeuft in JEDEM Fall. Eine
        # falsche "im Soll"-Aussage fiele dort rot auf, nicht still durch.
        # CachingMode wird ueber PSObject.Properties gelesen; fehlt das Feld,
        # gilt es als abweichend.
        $vorBefunde = @(Compare-ShareAccess -Desired $soll `
                -Actual @(ConvertTo-ShareActual -Entry @(Get-ShareAccessEntry -Name $ShareName)))

        $vorCaching = '(nicht gelesen)'
        $cachingImSoll = $false

        if ($null -ne $bestehend.PSObject.Properties['CachingMode']) {
            $vorCaching = [string] $bestehend.CachingMode
            $cachingImSoll = ($vorCaching -eq 'None')
        }

        if (($vorBefunde.Count -eq 0) -and $cachingImSoll) {
            $anlegeMeldung = 'Die bestehende Freigabe entsprach bereits dem Soll; es wurde nichts geändert.'
        }
        else {
            $null = Set-ProvisionedShare -Name $ShareName -SecurityDescriptor $sddl -CachingMode 'None'
            $angeglichen = $true
            $anlegeStatus = 'Warning'
            $anlegeMeldung = ('Die bestehende Freigabe wich vom Soll ab ({0} abweichende Einträge, Offline-Caching vorher "{1}") und wurde angeglichen; sie wurde nicht entfernt und nicht neu angelegt.' -f $vorBefunde.Count, $vorCaching)
        }
    }

    # CreatedByThisRun wandert in das Detail und nicht in einen Meldungstext:
    # es ist die EINZIGE Grundlage der SHARE-09-Entscheidung (D-07) und muss
    # maschinell lesbar bleiben. AdjustedByThisRun sagt, ob an einer
    # bestehenden Freigabe tatsaechlich geschrieben wurde; bei der Neuanlage
    # ist es falsch, dort gilt CreatedByThisRun.
    $ergebnisse.Add((New-ProvisioningResult -Kind $Kind -Path $LiteralPath -Stage 'Share' -Status $anlegeStatus `
                -Message $anlegeMeldung `
                -Detail @([pscustomobject] @{
                    Finding           = 'ShareState'
                    ShareName         = $ShareName
                    CreatedByThisRun  = [bool] $selbstErzeugt
                    AdjustedByThisRun = [bool] $angeglichen
                    Sddl              = $sddl
                }) `
                -Provenance $provenienz.Provenance -Source $provenienz.Source -Section $provenienz.Section))

    # --- 4. Ruecklesen und Entzug (SHARE-05, SHARE-07) ----------------------
    $ist = @(ConvertTo-ShareActual -Entry @(Get-ShareAccessEntry -Name $ShareName))
    $befunde = @(Compare-ShareAccess -Desired $soll -Actual $ist)

    # Je Kontoname hoechstens ein Entzug: Revoke-SmbShareAccess entfernt die
    # Eintraege eines Kontos ohnehin gesammelt, ein zweiter Aufruf liefe ins
    # Leere und faelschte die Aufrufzaehlung.
    $entzogen = New-Object System.Collections.Generic.List[string]

    foreach ($befund in @($befunde | Where-Object { $_.Finding -eq 'Unexpected' })) {

        $konto = [string] $befund.AccountName

        if ([string]::IsNullOrWhiteSpace($konto)) { continue }
        if ($entzogen.Contains($konto)) { continue }

        # GENAU DER WERT, DEN DAS RUECKLESEN GELIEFERT HAT. Kein Literal, kein
        # ueber Translate hergeleiteter Name -- ein in diesem Lauf vom System
        # gelesener Datenwert.
        $null = Revoke-ShareAccessEntry -Name $ShareName -AccountName $konto
        $entzogen.Add($konto)
    }

    # --- 5. Verifizieren (SHARE-07, SHARE-06) -------------------------------
    # Nur das Ruecklesen beweist das Ergebnis; ein Erfolgsbefund ohne zweite
    # Lesung waere eine Behauptung.
    $istNachher = @(ConvertTo-ShareActual -Entry @(Get-ShareAccessEntry -Name $ShareName))
    $endBefunde = New-Object System.Collections.Generic.List[object]

    foreach ($befund in @(Compare-ShareAccess -Desired $soll -Actual $istNachher)) {
        $endBefunde.Add($befund)
    }

    $nachher = Get-ExistingShare -Name $ShareName
    $cachingMode = ''
    if ($null -ne $nachher) { $cachingMode = [string] $nachher.CachingMode }

    if ($cachingMode -ne 'None') {
        $endBefunde.Add([pscustomobject] @{
            Finding  = 'CachingMode'
            Reason   = 'CachingNotDisabled'
            Expected = 'None'
            Actual   = $cachingMode
            Message  = ('Das Offline-Caching der Freigabe ist nicht abgeschaltet (gelesen: "{0}").' -f $cachingMode)
        })
    }

    $status = 'OK'
    if ($endBefunde.Count -gt 0) { $status = 'Error' }

    $meldung = ('Die zurückgelesenen Freigabeberechtigungen stimmen in SID-Form mit dem Soll überein; {0} Eintrag/Einträge entzogen, Offline-Caching abgeschaltet.' -f $entzogen.Count)

    if ($status -eq 'Error') {

        # SHARE-09 UND SEINE GRENZE (D-07). Es entscheidet ALLEIN das Merkmal
        # CreatedByThisRun -- nicht der Befundtyp, nicht der Freigabename und
        # schon gar nicht eine Vermutung ueber den Betriebszustand.
        if ($selbstErzeugt) {
            # Erster Zweig: die soeben selbst erzeugte Freigabe wird wieder
            # entfernt. Es bleibt keine halbfertige Freigabe zurueck.
            $null = Remove-ProvisionedShare -Name $ShareName
            $meldung = ('Die Verifikation der Freigabe hat {0} Befund(e) gemeldet. Die in diesem Lauf erzeugte Freigabe wurde wieder entfernt; Ordner und NTFS-ACL bleiben unberührt.' -f $endBefunde.Count)
        }
        else {
            # Zweiter Zweig: eine VORBESTEHENDE Freigabe wird gemeldet und
            # STEHEN GELASSEN. Sie zu entfernen kappte laufende Zugriffe --
            # genau dafuer wird CreatedByThisRun ueberhaupt mitgefuehrt.
            $meldung = ('Die Verifikation der Freigabe hat {0} Befund(e) gemeldet. Die Freigabe bestand bereits vor diesem Lauf und wurde deshalb gemeldet und stehen gelassen -- ihr Entfernen kappte laufende Zugriffe. Ordner und NTFS-ACL bleiben unberührt.' -f $endBefunde.Count)
        }
    }

    $ergebnisse.Add((New-ProvisioningResult -Kind $Kind -Path $LiteralPath -Stage 'ShareVerify' -Status $status `
                -Message $meldung `
                -Detail $endBefunde.ToArray() `
                -Provenance $provenienz.Provenance -Source $provenienz.Source -Section $provenienz.Section))

    return $ergebnisse.ToArray()
}

function Assert-AclVerified {
    <#
    .SYNOPSIS
        SHARE-03: bricht ab, wenn die NTFS-ACL desselben Pfades nicht
        erfolgreich verifiziert wurde. Intern zu Invoke-ShareApply.

    .DESCRIPTION
        WIRFT UND MELDET NICHT. Siehe die Begruendung im Kopf von
        Invoke-ShareApply: ein zurueckgegebener Ergebnissatz brach die Zusage
        aus D-05, dass im Fehlerfall gar kein Satz mit Stage "Share" entsteht.

        Geprueft werden drei Dinge, und alle sind noetig: der Status, der
        Pfad und die Ordnerart. Ein gruener Befund zu einem ANDEREN Pfad ist
        kein Beleg fuer diesen -- das waere genau die Verwechslung, die eine
        Freigabe ueber ein ungeprueftes ACL legte. Ebenso ist ein gruener
        Befund zu einer anderen Ordnerart auf DEMSELBEN Pfad kein Beleg fuer
        dieses Ziel (G-04-1a, Lauf 3): auf dem Ordner liegt dann das ACL der
        zuletzt geschriebenen Ordnerart, nicht das gegen dieses Soll
        verifizierte. Die Ordnerart wird ordinal verglichen; ihre Werte sind
        feste Literale aus einem ValidateSet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $AclVerifyResult,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [string] $ShareName
    )

    if ($null -eq $AclVerifyResult) {
        throw [System.InvalidOperationException]::new(
            ('Für den Pfad "{0}" liegt kein Ergebnis der ACL-Verifikation vor. Es wurde keine Freigabe "{1}" angelegt (SHARE-03).' -f
                $LiteralPath, $ShareName))
    }

    $status = [string] $AclVerifyResult.Status

    if ($status -cne 'OK') {
        throw [System.InvalidOperationException]::new(
            ('Die ACL-Verifikation des Pfades "{0}" meldet Status "{1}". Eine Freigabe über einem ungeprüften ACL ist ein Datenabfluss; es wurde keine Freigabe "{2}" angelegt (SHARE-03).' -f
                $LiteralPath, $status, $ShareName))
    }

    # Beide Seiten durch dieselbe Normalisierung -- eine zweite waere eine
    # zweite Wahrheit ueber dieselbe Regel.
    $sollPfad = ConvertTo-PfadPraefix -LiteralPath $LiteralPath
    $istPfad = ConvertTo-PfadPraefix -LiteralPath ([string] $AclVerifyResult.Path)

    if ($sollPfad -ne $istPfad) {
        throw [System.InvalidOperationException]::new(
            ('Das vorgelegte Ergebnis der ACL-Verifikation gehört zum Pfad "{0}", die Freigabe soll aber auf "{1}" zeigen. Es wurde keine Freigabe "{2}" angelegt (SHARE-03).' -f
                [string] $AclVerifyResult.Path, $LiteralPath, $ShareName))
    }

    $istKind = [string] $AclVerifyResult.Kind

    if ($istKind -cne $Kind) {
        throw [System.InvalidOperationException]::new(
            ('Das vorgelegte Ergebnis der ACL-Verifikation gehört zur Ordnerart "{0}", die Freigabe ist aber für die Ordnerart "{1}" geplant. Ein grüner Befund einer anderen Ordnerart ist kein Beleg für dieses Ziel; es wurde keine Freigabe "{2}" angelegt (SHARE-03).' -f
                $istKind, $Kind, $ShareName))
    }
}

function ConvertTo-ShareDesired {
    <#
    .SYNOPSIS
        Bindet die Trustee-Token eines Share-Templates an SIDs und laesst
        abgewaehlte Optionsgruppen weg. Intern zu Invoke-ShareApply.

    .DESCRIPTION
        Dieselbe Bindungsgrammatik wie Expand-AclTemplate, damit derselbe
        Aufloeser greift und dieselbe IDENT-08-Freiheit gilt: ein Token mit
        spitzen Klammern kommt aus -Binding, alles uebrige geht durch
        Resolve-TrusteeSid.

        EIN FEHLENDER BINDUNGSWERT DARF NIE ZU EINEM UEBERSPRUNGENEN EINTRAG
        WERDEN. Das waere der stille Rechteverlust, gegen den dieses Werkzeug
        gebaut ist -- also wird geworfen.

    .OUTPUTS
        Sammlung mit Sid (Zeichenkette), Access, Trustee, Status, Source,
        Section und OptGroup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Template,

        [Parameter(Mandatory)]
        [hashtable] $Binding,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $IncludeOptGroup = @()
    )

    $kind = [string] $Template.Kind
    $eintraege = @($Template.Entries)
    $gewaehlt = @(@($IncludeOptGroup) | Where-Object { -not [string]::IsNullOrEmpty($_) })

    $gruppen = New-Object System.Collections.Generic.List[string]
    foreach ($eintrag in $eintraege) {
        if ($eintrag.ContainsKey('OptGroup') -and -not [string]::IsNullOrEmpty([string] $eintrag.OptGroup)) {
            $name = [string] $eintrag.OptGroup
            if (-not $gruppen.Contains($name)) { $gruppen.Add($name) }
        }
    }

    # Ein Tippfehler im Opt-in-Namen darf nicht still zu fehlenden Eintraegen
    # fuehren -- das fiele erst auf dem Fileserver auf.
    foreach ($name in $gewaehlt) {
        if (-not $gruppen.Contains($name)) {
            throw [System.ArgumentException]::new(
                ('Die Optionsgruppe "{0}" kommt im Share-Template "{1}" nicht vor. Bekannt: {2}' -f
                    $name, $kind, ((@($gruppen) | ForEach-Object { $_ }) -join ', ')))
        }
    }

    $datensaetze = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $eintraege.Count; $i++) {

        $eintrag = $eintraege[$i]
        $optGroup = if ($eintrag.ContainsKey('OptGroup')) { [string] $eintrag.OptGroup } else { '' }

        # Abgewaehlt: ueberspringen OHNE Bindungspruefung. Ein Lauf ohne
        # Helpdesk-Werkzeug soll keine Helpdeskgruppe brauchen.
        if ((-not [string]::IsNullOrEmpty($optGroup)) -and ($gewaehlt -notcontains $optGroup)) {
            continue
        }

        $trustee = [string] $eintrag.Trustee

        if ($trustee.StartsWith('<', [System.StringComparison]::Ordinal)) {

            if (-not $Binding.ContainsKey($trustee)) {
                throw [System.InvalidOperationException]::new(
                    ('Das Platzhalter-Token {0} ist für die Ordnerart {1} nicht gebunden (Share-Eintrag {2}).' -f
                        $trustee, $kind, ($i + 1)))
            }

            # Mehrere Gruppen einer Rolle (Feld): je SID ein Eintrag, wie in
            # Expand-AclTemplate.
            $sids = New-Object System.Collections.Generic.List[object]

            foreach ($wert in @($Binding[$trustee])) {

                if ($wert -is [System.Security.Principal.SecurityIdentifier]) {
                    $sids.Add($wert)
                }
                elseif ($wert -is [string]) {
                    $sids.Add((Resolve-TrusteeSid -InputValue $wert))
                }
                else {
                    throw [System.ArgumentException]::new(
                        ('Der Bindungswert für {0} muss ein SecurityIdentifier oder eine Zeichenkette sein.' -f $trustee))
                }
            }

            if ($sids.Count -eq 0) {
                throw [System.InvalidOperationException]::new(
                    ('Das Platzhalter-Token {0} ist für die Ordnerart {1} nicht gebunden (Share-Eintrag {2}).' -f
                        $trustee, $kind, ($i + 1)))
            }
        }
        else {
            $sids = @(Resolve-TrusteeSid -InputValue $trustee)
        }

        foreach ($sid in $sids) {
            $datensaetze.Add([pscustomobject] @{
                Sid      = [string] $sid.Value
                Access   = [string] $eintrag.Access
                Trustee  = $trustee
                Status   = [string] $eintrag['Status']
                Source   = [string] $eintrag['Source']
                Section  = [string] $eintrag['Section']
                OptGroup = $optGroup
            })
        }
    }

    return $datensaetze.ToArray()
}

function ConvertTo-ShareActual {
    <#
    .SYNOPSIS
        Uebersetzt die zurueckgelesenen Freigabeeintraege in SID-Form. Intern zu
        Invoke-ShareApply.

    .DESCRIPTION
        HIER UND NUR HIER BERUEHRT DAS WERKZEUG EINEN LOKALISIERTEN NAMEN. Die
        Messung haelt fest, dass Get-SmbShareAccess Kontonamen in der Sprache
        der Maschine liefert -- auf einem deutschen Server also andere
        Zeichenketten als auf einem englischen. Jeder gelieferte Name laeuft
        deshalb sofort durch Resolve-TrusteeSid; verglichen wird ausschliesslich
        die SID.

        Der Name bleibt trotzdem am Datensatz haengen, und das ist Absicht:
        SHARE-05 entzieht mit genau diesem Wert. Ihn zu verwerfen und spaeter
        neu herzuleiten waere der Fehler, gegen den dieses Werkzeug gebaut ist.

        Ein nicht uebersetzbarer Name ist ein BEFUND und kein Abbruch: der
        Datensatz bekommt eine leere SID und wird dadurch unerwartet -- die
        vorsichtige Richtung, weil sie meldet statt zu schweigen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Entry
    )

    $datensaetze = New-Object System.Collections.Generic.List[object]

    foreach ($eintrag in @($Entry)) {

        if ($null -eq $eintrag) { continue }

        $konto = [string] $eintrag.AccountName
        $sid = ''

        try { $sid = [string] (Resolve-TrusteeSid -InputValue $konto).Value }
        catch { $sid = '' }

        $datensaetze.Add([pscustomobject] @{
            Sid               = $sid
            Access            = [string] $eintrag.AccessRight
            AccountName       = $konto
            AccessControlType = [string] $eintrag.AccessControlType
        })
    }

    return $datensaetze.ToArray()
}

function New-ShareSecurityDescriptor {
    <#
    .SYNOPSIS
        Baut aus dem gebundenen Share-Soll den SDDL-D:-Abschnitt. Intern zu
        Invoke-ShareApply.

    .DESCRIPTION
        REIN, OHNE AUSSENKONTAKT UND OFFLINE PRUEFBAR -- deshalb steht der Bau
        hier und nicht in der Seam.

        DER TREUHAENDER IST AUSSCHLIESSLICH DIE SID-ZEICHENKETTE. Ein Kontoname
        im SDDL waere genau der Lokalisierungsfehler, gegen den dieses Werkzeug
        gebaut ist.

        Die Rechtestufe wird als NUMERISCHE MASKE geschrieben und nicht als
        Zweibuchstabenform: genau diese Form ist in
        Tests/Fixtures/SmbShareSddl.Measured.psd1 gemessen worden.

            Full   0x1f01ff
            Change 0x1301bf
            Read   0x1200a9
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Desired
    )

    $maske = @{
        Full   = '0x1f01ff'
        Change = '0x1301bf'
        Read   = '0x1200a9'
    }

    $bau = New-Object System.Text.StringBuilder
    $null = $bau.Append('D:')

    foreach ($eintrag in @($Desired)) {

        $access = [string] $eintrag.Access

        if (-not $maske.ContainsKey($access)) {
            throw [System.ArgumentException]::new(
                ('Die Rechtestufe "{0}" ist keine der drei zulässigen Freigabestufen.' -f $access))
        }

        $sid = [string] $eintrag.Sid

        if ([string]::IsNullOrWhiteSpace($sid)) {
            throw [System.ArgumentException]::new(
                'Ein Soll-Eintrag ohne SID lässt sich nicht in einen SDDL-Eintrag übersetzen.')
        }

        $null = $bau.AppendFormat('(A;;{0};;;{1})', $maske[$access], $sid)
    }

    return $bau.ToString()
}

function Compare-ShareAccess {
    <#
    .SYNOPSIS
        Vergleicht Soll und Ist der Freigabeberechtigungen als Menge ueber
        (SID, Rechtestufe). Intern zu Invoke-ShareApply.

    .DESCRIPTION
        NIMMT OBJEKTE ENTGEGEN, NIE EINEN FREIGABENAMEN. Damit ist der
        Vergleich rein und offline pruefbar -- dieselbe Zusage wie bei
        Compare-AceSet, und aus demselben Grund: ein Vergleicher, der selbst
        liest, laesst sich nicht gegen einen erfundenen Ist-Zustand fahren.

        Die Befundarten heissen wie dort: Missing fuer einen Soll-Eintrag ohne
        Entsprechung, Unexpected fuer einen Ist-Eintrag ohne Soll. Ein
        Unexpected-Befund traegt zusaetzlich den zurueckgelesenen Kontonamen --
        er ist der Schluessel fuer den Entzug nach SHARE-05.

        Verglichen wird ueber die SID und NIE ueber den Namen. Das ist der Kern
        von SHARE-07 und der Grund, warum das Werkzeug auf deutschem und
        englischem Server dasselbe tut.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Desired,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Actual
    )

    $sollSchluessel = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $istSchluessel = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    foreach ($eintrag in @($Desired)) {
        $null = $sollSchluessel.Add(('{0}|{1}' -f [string] $eintrag.Sid, [string] $eintrag.Access))
    }

    foreach ($eintrag in @($Actual)) {
        $null = $istSchluessel.Add(('{0}|{1}' -f [string] $eintrag.Sid, [string] $eintrag.Access))
    }

    $befunde = New-Object System.Collections.Generic.List[object]

    foreach ($eintrag in @($Desired)) {

        $schluessel = '{0}|{1}' -f [string] $eintrag.Sid, [string] $eintrag.Access
        if ($istSchluessel.Contains($schluessel)) { continue }

        $befunde.Add([pscustomobject] @{
            Finding     = 'Missing'
            Reason      = 'DesiredShareAceMissing'
            Key         = $schluessel
            Sid         = [string] $eintrag.Sid
            Access      = [string] $eintrag.Access
            AccountName = ''
            Expected    = [string] $eintrag.Access
            Actual      = ''
            Message     = ('Dem Prinzipal {0} fehlt die Freigabeberechtigung "{1}".' -f
                [string] $eintrag.Sid, [string] $eintrag.Access)
        })
    }

    foreach ($eintrag in @($Actual)) {

        $schluessel = '{0}|{1}' -f [string] $eintrag.Sid, [string] $eintrag.Access
        if ($sollSchluessel.Contains($schluessel)) { continue }

        $befunde.Add([pscustomobject] @{
            Finding     = 'Unexpected'
            Reason      = 'UnexpectedShareAce'
            Key         = $schluessel
            Sid         = [string] $eintrag.Sid
            Access      = [string] $eintrag.Access
            AccountName = [string] $eintrag.AccountName
            Expected    = ''
            Actual      = [string] $eintrag.Access
            Message     = ('Der Prinzipal {0} trägt die nicht vorgesehene Freigabeberechtigung "{1}".' -f
                [string] $eintrag.Sid, [string] $eintrag.Access)
        })
    }

    return $befunde.ToArray()
}

function Get-ShareProvenance {
    <#
    .SYNOPSIS
        Verdichtet die Provenienz der Soll-Eintraege auf einen Ergebnissatz.
        Intern zu Invoke-ShareApply.

    .DESCRIPTION
        IST AUCH NUR EIN EINTRAG ABGELEITET, IST DIE ZEILE ABGELEITET. Die
        vorsichtige Richtung: ein Kennzeichen darf nie mehr Beleg behaupten als
        vorhanden ist. Eine stille Aufwertung eines Derived-Eintrags zum
        Herstellerbeleg ist projektweit verboten.

        Source und Section kommen aus dem ersten Eintrag der massgeblichen
        Klasse -- bei gemischter Provenienz also aus dem ersten abgeleiteten.
        Die vollstaendige Provenienz je Eintrag steht ohnehin im Template und
        wird von dort gelesen; dieses Feld traegt das Badge der Zusammenfassung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Desired
    )

    $eintraege = @($Desired)

    if ($eintraege.Count -eq 0 -or -not (Test-MitBeleg)) {
        return [pscustomobject] @{ Provenance = ''; Source = ''; Section = '' }
    }

    $abgeleitet = @($eintraege | Where-Object { [string] $_.Status -ceq 'Derived' })

    if ($abgeleitet.Count -gt 0) {
        return [pscustomobject] @{
            Provenance = 'Derived'
            Source     = [string] $abgeleitet[0].Source
            Section    = [string] $abgeleitet[0].Section
        }
    }

    return [pscustomobject] @{
        Provenance = 'Verified'
        Source     = [string] $eintraege[0].Source
        Section    = [string] $eintraege[0].Section
    }
}
