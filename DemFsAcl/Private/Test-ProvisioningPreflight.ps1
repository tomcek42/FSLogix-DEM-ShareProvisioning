<#
    Test-ProvisioningPreflight -- das lesende Gate vor dem ersten
    Schreibzugriff (PRE-01 bis PRE-08).

    EINMAL GESAMMELT UEBER ALLE ZIELE (D-09): ein Aufruf, alle Ziele, alle
    Befunde auf einmal. Nicht je Ziel unmittelbar vor dessen Schreiben -- nur
    so haelt die Zusage "bevor irgendetwas geschrieben wurde".

    DIE TRENNUNG, DIE D-09 UND D-06 VEREINBART: jeder Befund traegt ein Feld
    Scope.
      Host    -- gilt fuer den ganzen Lauf (PRE-01, PRE-02). Ein Error dieser
                 Art sperrt jedes Ziel; es wird nichts geschrieben.
      Target  -- gilt nur fuer sein Ziel (PRE-03 bis PRE-08). Ein Error
                 disqualifiziert genau dieses Ziel, die uebrigen laufen weiter.
    Ohne diese Trennung widersprechen sich D-06 und Erfolgskriterium 1.

    DAS AUSNAHMENETZ JE ZIEL (G-04-1c): wirft eine Zielpruefung, wird daraus
    ein Error-Befund mit Scope Target fuer genau dieses Ziel, und die Funktion
    kehrt normal zurueck. Grund ist Lauf 4 auf dem Zielserver -- eine
    unlesbare Zielwurzel liess die Inhaltszaehlung werfen und beendete den
    ganzen Lauf, auch fuer das fehlerfreie Ziel.

    LAUFINTERNE KONFLIKTE (G-04-1b): gleicher Pfad, ineinander liegende Pfade
    und gleicher Freigabename zweier Ziele desselben Laufs sind je ein Error
    auf beiden Zielen. Die Regel steht einmal, in Get-TargetConflict.

    Die Funktion ist REIN LESEND. Die einzige Pruefung mit einem schreibenden
    Aussenkontakt -- die Schreibprobe fuer PRE-07 -- steckt vollstaendig in der
    Seam Test-TargetWritable in HostFacts.ps1 und ist dort im Test ersetzbar.

    Keine Ausgabe, keine Rueckfrage: die Funktion liefert eine Sammlung von
    ProvisioningResult mit Stage gleich Preflight.
#>

function Test-ProvisioningPreflight {
    <#
    .SYNOPSIS
        Prueft Host und alle geplanten Ziele in einem gesammelten Durchlauf und
        liefert alle Befunde auf einmal.

    .PARAMETER Target
        Je Element mindestens Kind, Path, ShareName und Desired.

    .OUTPUTS
        Sammlung von ProvisioningResult mit Stage gleich Preflight. Jeder
        Befund traegt zusaetzlich Check und Scope.

    .EXAMPLE
        Test-ProvisioningPreflight -Target $ziele
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Target
    )

    $befunde = New-Object System.Collections.Generic.List[object]

    # ======================================================================
    #  Hostbefunde -- einmal je Lauf, nicht je Ziel.
    # ======================================================================

    # --- PRE-01: Rechteerhoehung --------------------------------------------
    if (-not (Test-IsElevated)) {
        $befunde.Add((New-PreflightFinding -Check 'PRE-01' -Scope 'Host' -Status 'Error' `
                    -Message 'Die Sitzung ist nicht erhöht. Das Setzen von NTFS-Rechten und das Anlegen von Freigaben braucht eine erhöhte Sitzung -- bitte die Konsole als Administrator starten und den Lauf wiederholen. Es wurde nichts geschrieben.'))
    }

    # --- PRE-02: die beiden geforderten Privilegien (D-12) ------------------
    # SeSecurityPrivilege wird ausdruecklich NICHT gefordert: das Werkzeug
    # schreibt ausschliesslich den Access-Abschnitt (ACL-05), eine
    # Systemzugriffsliste kommt nie vor, und eine zusaetzlich geforderte
    # Berechtigung waere eine Huerde ohne Gegenwert.
    $gehalten = @(Get-HeldPrivilege)

    foreach ($konstante in @('SeRestorePrivilege', 'SeTakeOwnershipPrivilege')) {

        if ($gehalten -notcontains $konstante) {
            $befunde.Add((New-PreflightFinding -Check 'PRE-02' -Scope 'Host' -Status 'Error' `
                        -Message ('Der laufenden Sitzung fehlt das Privileg {0}. Es wird zum Setzen der Zielrechte gebraucht; bitte den Lauf mit einem Konto wiederholen, das es hält. Es wurde nichts geschrieben.' -f $konstante)))
        }
    }

    # ======================================================================
    #  Zielbefunde -- je Ziel. Ein gescheitertes Ziel stoppt die uebrigen
    #  nicht (D-06); gesammelt wird trotzdem in EINEM Durchlauf (D-09).
    #
    #  DAS AUSNAHMENETZ JE ZIEL (G-04-1c). Der ganze Pruefblock eines Ziels
    #  -- PRE-04 bis PRE-08 -- steht in einem try, und vor jeder Einzelpruefung
    #  wird ihre Kennung in $laufendePruefung festgehalten. Wirft eine lesende
    #  Pruefung, wird daraus ein Error-Befund mit genau dieser Kennung fuer
    #  genau dieses Ziel; die Funktion kehrt normal zurueck, und die uebrigen
    #  Ziele laufen weiter. Lauf 4 auf dem Zielserver: die Inhaltszaehlung
    #  von PRE-08 warf auf einem Ordner ohne Leserecht, die Ausnahme verliess
    #  das Gate und beendete den Lauf auch fuer das fehlerfreie Ziel.
    #  Ein Netz je Einzelpruefung vergaesse die naechste neue Pruefung; ein
    #  Netz um die ganze Funktion braeche Phase-3-D-06. Die Hostpruefungen
    #  PRE-01 und PRE-02 bleiben ausserhalb -- das Netz gilt Zielen.
    # ======================================================================
    foreach ($ziel in @($Target)) {

        $kind = [string] $ziel.Kind
        $pfad = [string] $ziel.Path
        $laufendePruefung = 'PRE-04'

        try {

            # --- PRE-04: die Pfad-Sperrliste -------------------------------
            # Sie laeuft VOR jeder Pruefung, die den Pfad anfasst: die
            # Volumeabfrage wirft auf einem Netzwerkpfad, statt ihn sauber
            # abzuweisen. Die Reihenfolge ist damit nicht kosmetisch.
            $laufendePruefung = 'PRE-04'
            $pfadGruende = @(Test-TargetPathSafety -LiteralPath $pfad)

            foreach ($grund in $pfadGruende) {
                $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check 'PRE-04' `
                            -Scope 'Target' -Status 'Error' -Message $grund))
            }

            # Ist der Pfad selbst untauglich, sind die uebrigen Zielpruefungen
            # nicht nur ueberfluessig, sondern gefaehrlich: sie wuerfen.
            if ($pfadGruende.Count -gt 0) { continue }

            # --- PRE-03: ACL-Faehigkeit als Positivliste -------------------
            # Positivliste und nicht Sperrliste, damit ein unbekanntes
            # Dateisystem abgelehnt und nicht als faehig unterstellt wird.
            $laufendePruefung = 'PRE-03'
            $format = ''
            $formatFehler = ''

            try { $format = [string] (Get-VolumeFormat -LiteralPath $pfad) }
            catch { $formatFehler = $_.Exception.Message }

            $faehig = $false
            foreach ($zugelassen in @('NTFS', 'ReFS')) {
                if ([string]::Equals($format, $zugelassen, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $faehig = $true
                    break
                }
            }

            if (-not $faehig) {

                $benennung = if ([string]::IsNullOrWhiteSpace($format)) { '(nicht ermittelbar)' } else { $format }
                $zusatz = if ([string]::IsNullOrEmpty($formatFehler)) { '' } else { ' Grund: ' + $formatFehler }

                $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check 'PRE-03' `
                            -Scope 'Target' -Status 'Error' `
                            -Message ('Das Zielvolume führt das Dateisystem {0}. Zugelassen sind ausschließlich NTFS und ReFS -- nur sie tragen die hier gesetzten Rechte; bitte ein anderes Ziel wählen.{1}' -f $benennung, $zusatz)))
            }

            # --- PRE-05: belegter Freigabename (D-10) ----------------------
            $laufendePruefung = 'PRE-05'
            $freigabeName = ''
            if ($null -ne $ziel.PSObject.Properties['ShareName']) {
                $freigabeName = [string] $ziel.ShareName
            }

            if (-not [string]::IsNullOrWhiteSpace($freigabeName)) {

                $bestehend = Get-ExistingShare -Name $freigabeName

                if ($null -ne $bestehend) {

                    $bestehenderPfad = [string] $bestehend.Path

                    # INHABERENTSCHEID VOM 2026-09-22 (G-04-4g): eine Freigabe
                    # auf DEMSELBEN Pfad ist der Normalfall jedes
                    # Wiederholungslaufs und kein Befund, der warnen darf -- ein
                    # zweiter Lauf ueber korrektem Stand endete sonst immer mit
                    # WARNUNG (lauf5_2.txt). Sie ist ein Hinweis mit Status OK;
                    # ob wirklich etwas angeglichen werden muss, entscheidet der
                    # Share-Provisioner nach Vorablesung, und nur eine
                    # tatsaechliche Angleichung ergibt dort Warning. Ein ANDERER
                    # Pfad bleibt ein Error.
                    if ((ConvertTo-PfadPraefix -LiteralPath $bestehenderPfad) -eq (ConvertTo-PfadPraefix -LiteralPath $pfad)) {
                        $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check 'PRE-05' `
                                    -Scope 'Target' -Status 'OK' `
                                    -Message ('Der Freigabename "{0}" besteht bereits und zeigt auf denselben Pfad. Die Freigabe wird nach dem Schreiben geprüft und nur bei Abweichung angeglichen.' -f $freigabeName)))
                    }
                    else {
                        $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check 'PRE-05' `
                                    -Scope 'Target' -Status 'Error' `
                                    -Message ('Der Freigabename "{0}" ist bereits vergeben und zeigt auf "{1}" statt auf das Ziel. Der Name gehört damit jemand anderem; bitte einen anderen Namen wählen oder die bestehende Freigabe zuerst klären.' -f $freigabeName, $bestehenderPfad)))
                    }
                }
            }

            # --- PRE-06: der Operator behaelt Zugriff (D-11, G-04-1d) ------
            # Geprueft wird NICHT, ob die vordefinierte Verwaltungsgruppe im
            # Template steht, sondern ob der ausfuehrende Operator ueber eine
            # seiner Tokengruppen tatsaechlich Zugriff behaelt. Das
            # herstellerkonforme FSLogix-Soll ohne Opt-in enthaelt keine
            # Verwaltungsgruppe -- eine Warnung, die bei jedem Normallauf
            # feuert, wird ignoriert und ist damit schlimmer als keine.
            #
            # EINSTUFUNG NACH INHABERENTSCHEID VOM 2026-09-21: Error, wenn fuer
            # das Ziel eine Freigabe geplant ist -- das Anlegen der Freigabe
            # scheitert nach dem Schreiben des geschuetzten ACL sicher mit
            # Zugriff-verweigert (alle vier Serverlaeufe). Ohne geplante
            # Freigabe bleibt es eine Warnung.
            #
            # Ein Recht auf der Laufwerkswurzel hilft hier nicht: das Ziel-ACL
            # schuetzt die Vererbung (SetAccessRuleProtection), und nichts von
            # oben reicht bis in das Ziel. Deshalb nennt die Meldung diesen
            # Weg nicht.
            #
            # Der Ausweg Admin-Opt-in existiert nur, wo das Template ihn
            # fuehrt. Gelesen wird das aus Desired.OptDecisions -- derselben
            # Quelle, aus der Expand-AclTemplate das Soll gebaut hat --, nicht
            # aus dem Namen der Ordnerart.
            $laufendePruefung = 'PRE-06'
            $soll = $null
            if ($null -ne $ziel.PSObject.Properties['Desired']) { $soll = $ziel.Desired }

            if ($null -ne $soll) {

                $operatorSid = @(@(Get-OperatorSid) | ForEach-Object { [string] $_.Value })

                # Mindestens Lesen samt Rechteleserecht -- numerisch
                # verglichen, nie ueber eine Druckform: die Rechteaufzaehlung
                # fuehrt Aliase.
                $benoetigt = [int] ([System.Security.AccessControl.FileSystemRights]::Read)
                $zulassend = [System.Security.AccessControl.AccessControlType]::Allow
                $behaeltZugriff = $false

                foreach ($ace in @($soll.Aces)) {

                    if ($ace.Rule.AccessControlType -ne $zulassend) { continue }
                    if ($operatorSid -notcontains ([string] $ace.Sid.Value)) { continue }
                    if ((([int] $ace.Rule.FileSystemRights) -band $benoetigt) -ne $benoetigt) { continue }

                    $behaeltZugriff = $true
                    break
                }

                if (-not $behaeltZugriff) {

                    $freigabeGeplant = -not [string]::IsNullOrWhiteSpace($freigabeName)
                    $stufe = if ($freigabeGeplant) { 'Error' } else { 'Warning' }

                    $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check 'PRE-06' `
                                -Scope 'Target' -Status $stufe `
                                -Message (Get-OperatorZugriffMeldung -Desired $soll -FreigabeGeplant $freigabeGeplant)))
                }
            }

            # --- PRE-07: die Schreibprobe ----------------------------------
            $laufendePruefung = 'PRE-07'
            $probe = Test-TargetWritable -LiteralPath $pfad

            if (-not [bool] $probe.Writable) {
                $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check 'PRE-07' `
                            -Scope 'Target' -Status 'Error' `
                            -Message ('Der Zielpfad ist nicht beschreibbar; es wurde nichts angelegt. {0}' -f [string] $probe.Reason)))
            }

            # --- PRE-08: vorhandener Inhalt --------------------------------
            # Gezaehlt werden die Kindelemente OHNE Abstieg, und ausschliesslich
            # ueber die Seam Get-TargetEntryCount: sie ist die einzige Stelle
            # mit diesem Aussenkontakt, und nur so ist der Fall aus Lauf 4 im
            # Test herstellbar. v1 setzt leere Ordner voraus; ein Abstieg waere
            # zugleich der erste Schritt zu der rekursiven Reparatur, die das
            # Projekt ausdruecklich ausschliesst.
            # Weg 3 passt bestehende Ablagen an: dort ist Inhalt der Normalfall,
            # und ein Hinweis darauf waere bei jedem Lauf Rauschen.
            if (($null -ne $ziel.PSObject.Properties['SkipContentCheck']) -and [bool] $ziel.SkipContentCheck) { continue }

            $laufendePruefung = 'PRE-08'
            $anzahl = [int] (Get-TargetEntryCount -LiteralPath $pfad)

            if ($anzahl -gt 0) {
                $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check 'PRE-08' `
                            -Scope 'Target' -Status 'Warning' `
                            -Message ('Unterhalb des Zielordners liegen bereits {0} Element(e). Der Ordner wird übernommen und sein Inhalt nicht angetastet; bitte prüfen, ob das gewollt ist.' -f $anzahl)))
            }
        }
        catch {
            # Der Meldungstext der Ausnahme wird unveraendert weitergegeben:
            # auf einem deutschen Server ist er bereits ein deutscher Satz, und
            # eine eigene Uebersetzung je Ausnahmetyp waere eine zweite
            # Wahrheit ueber denselben Fehler.
            $befunde.Add((New-PreflightFinding -Kind $kind -Path $pfad -Check $laufendePruefung `
                        -Scope 'Target' -Status 'Error' `
                        -Message ('Die Prüfung {0} für "{1}" ließ sich nicht durchführen: {2} Für dieses Ziel wird nichts geschrieben; die übrigen Ziele laufen weiter.' -f $laufendePruefung, $pfad, $_.Exception.Message)))
        }
    }

    # ======================================================================
    #  Laufinterne Konflikte (G-04-1b) -- die Ziele untereinander. Jeder
    #  Konflikt ist ein Error auf BEIDEN beteiligten Zielen, nie eine Warnung:
    #  eine Warnung liesse den Lauf beide Ziele schreiben, und das zuletzt
    #  geschriebene ACL ueberschriebe das vorige (Lauf 1 bis 3). Die Sperre
    #  entsteht ohne weitere Aenderung in Get-PreflightSperre.
    # ======================================================================
    foreach ($konflikt in @(Get-TargetConflict -Target $Target)) {
        $befunde.Add((New-PreflightFinding -Kind ([string] $konflikt.Kind) -Path ([string] $konflikt.Path) `
                    -Check ([string] $konflikt.Check) -Scope 'Target' -Status 'Error' `
                    -Message ('{0} Für dieses Ziel wird nichts geschrieben.' -f [string] $konflikt.Message)))
    }

    return $befunde.ToArray()
}

function Get-TargetConflict {
    <#
    .SYNOPSIS
        Die laufinternen Konflikte zwischen den Zielen eines Laufs (G-04-1b).
        Rein, ohne Dateisystemzugriff.

    .DESCRIPTION
        DIE EINE WAHRHEIT UEBER LAUFINTERNE KONFLIKTE. Das Preflight baut daraus
        Error-Befunde; der Dialog ruft dieselbe Funktion, um einen kollidierenden
        Pfad oder Namen sofort erneut zu erfragen. Deshalb liefert sie je
        Konflikt einen Datensatz mit fertigem Meldungstext und nicht nur wahr
        oder falsch -- eine zweite Vergleichsregel im Dialog drifted gegen diese.

        Verglichen wird jedes geordnete Paar (i, j) mit i ungleich j -- ueber
        den Index, nicht ueber die Ordnerart. Ein Paar mit Konflikt ergibt damit
        ZWEI Datensaetze, je einen aus der Sicht jedes Ziels.

        Beide Pfadseiten laufen durch ConvertTo-PfadPraefix; verglichen wird
        ordinal ohne Ruecksicht auf Gross-/Kleinschreibung.

    .PARAMETER Target
        Je Element mindestens Kind und Path, optional ShareName. ShareName wird
        ueber PSObject.Properties gelesen: der Dialog uebergibt Kandidaten ohne
        dieses Feld, und das Modul laeuft unter Set-StrictMode.

    .OUTPUTS
        Datensaetze mit Kind, Path, Check, Type, OtherKind, OtherPath,
        ShareName und Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target
    )

    $ziele = @(@($Target) | Where-Object { $null -ne $_ })
    $konflikte = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $ziele.Count; $i++) {

        $kind = [string] $ziele[$i].Kind
        $pfad = [string] $ziele[$i].Path
        $praefix = ConvertTo-PfadPraefix -LiteralPath $pfad

        for ($j = 0; $j -lt $ziele.Count; $j++) {

            if ($i -eq $j) { continue }

            $andereKind = [string] $ziele[$j].Kind
            $anderPfad = [string] $ziele[$j].Path
            $anderPraefix = ConvertTo-PfadPraefix -LiteralPath $anderPfad

            # --- Gleicher Pfad ----------------------------------------------
            if ((-not [string]::IsNullOrEmpty($praefix)) -and (-not [string]::IsNullOrEmpty($anderPraefix)) -and
                [string]::Equals($praefix, $anderPraefix, [System.StringComparison]::OrdinalIgnoreCase)) {

                $konflikte.Add([pscustomobject] @{
                        Kind      = $kind
                        Path      = $pfad
                        Check     = 'PRE-04'
                        Type      = 'SamePath'
                        OtherKind = $andereKind
                        OtherPath = $anderPfad
                        ShareName = ''
                        Message   = ('Die Ordnerarten "{0}" und "{1}" sind beide für den Pfad "{2}" geplant. Auf einem gemeinsamen Pfad überschreibt das zuletzt geschriebene ACL das vorige, und keine der beiden Freigaben läge über dem ACL, gegen das sie verifiziert wurde; bitte je Ordnerart einen eigenen Pfad wählen.' -f $kind, $andereKind, $pfad)
                    })
            }
            # --- Ineinander liegende Pfade ------------------------------------
            # Das abschliessende Trennzeichen aus ConvertTo-PfadPraefix ist der
            # ganze Grund, warum X:\Data nicht als Vorfahre von X:\Database gilt.
            elseif ((-not [string]::IsNullOrEmpty($praefix)) -and (-not [string]::IsNullOrEmpty($anderPraefix)) -and
                ($praefix.StartsWith($anderPraefix, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $anderPraefix.StartsWith($praefix, [System.StringComparison]::OrdinalIgnoreCase))) {

                $innen = $praefix.StartsWith($anderPraefix, [System.StringComparison]::OrdinalIgnoreCase)
                $lage = if ($innen) { 'innerhalb' } else { 'oberhalb' }

                $konflikte.Add([pscustomobject] @{
                        Kind      = $kind
                        Path      = $pfad
                        Check     = 'PRE-04'
                        Type      = 'NestedPath'
                        OtherKind = $andereKind
                        OtherPath = $anderPfad
                        ShareName = ''
                        Message   = ('Der Pfad "{0}" der Ordnerart "{1}" liegt {2} des Pfades "{3}" der Ordnerart "{4}". Ineinander liegende Freigabewurzeln sind unzulässig: das ACL der inneren Wurzel ist ein Eingriff in einen Unterordner der äußeren Freigabe; bitte getrennte Pfade wählen.' -f $pfad, $kind, $lage, $anderPfad, $andereKind)
                    })
            }

            # --- Gleicher Freigabename ----------------------------------------
            # SMB-Freigabenamen unterscheiden Gross-/Kleinschreibung nicht --
            # der Vergleich tut es deshalb auch nicht. Leere oder fehlende Namen
            # sind nie ein Konflikt.
            $name = ''
            if ($null -ne $ziele[$i].PSObject.Properties['ShareName']) { $name = ([string] $ziele[$i].ShareName).Trim() }
            $anderName = ''
            if ($null -ne $ziele[$j].PSObject.Properties['ShareName']) { $anderName = ([string] $ziele[$j].ShareName).Trim() }

            if ((-not [string]::IsNullOrEmpty($name)) -and (-not [string]::IsNullOrEmpty($anderName)) -and
                [string]::Equals($name, $anderName, [System.StringComparison]::OrdinalIgnoreCase)) {

                $konflikte.Add([pscustomobject] @{
                        Kind      = $kind
                        Path      = $pfad
                        Check     = 'PRE-05'
                        Type      = 'SameShareName'
                        OtherKind = $andereKind
                        OtherPath = $anderPfad
                        ShareName = $name
                        Message   = ('Der Freigabename "{0}" ist in diesem Lauf zweimal vergeben: an die Ordnerart "{1}" und an die Ordnerart "{2}" ("{3}"). Ein Freigabename kann nur auf einen Ordner zeigen; bitte je Ordnerart einen eigenen Namen wählen.' -f $name, $kind, $andereKind, $anderPfad)
                    })
            }
        }
    }

    return $konflikte.ToArray()
}

function Get-OperatorZugriffMeldung {
    <#
    .SYNOPSIS
        Der Meldungstext von PRE-06 -- Befund, Folge und ein fuer die
        Ordnerart gangbarer Ausweg (G-04-1d). Intern zu
        Test-ProvisioningPreflight.

    .DESCRIPTION
        Das Admin-Opt-in wird nur genannt, wenn das Soll die Optionsgruppe
        SystemAndBuiltinAdmins fuehrt und sie abgewaehlt ist. Gelesen wird das
        aus Desired.OptDecisions (Felder OptGroup und Included) ueber
        PSObject.Properties; ein Soll ohne dieses Feld bekommt den Ausweg ohne
        Opt-in. Fuer die DEM-Ordnerarten gibt es diese Optionsgruppe nicht --
        in allen vier Serverlaeufen zeigte der alte Text dorthin.

        Der Ausweg ueber die Gruppe der Administratoren (G-04-4c: so heisst die
        Rolle <AdminGroup> in jedem Anzeigetext) steht in JEDEM Fall darin, samt
        der Neuanmeldung: erst das neue Anmeldetoken traegt eine frisch
        zugeordnete Gruppe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Desired,

        [Parameter(Mandatory)]
        [bool] $FreigabeGeplant
    )

    $optInMoeglich = $false

    if ($null -ne $Desired.PSObject.Properties['OptDecisions']) {
        foreach ($entscheidung in @($Desired.OptDecisions)) {

            if ($null -eq $entscheidung) { continue }
            if ($null -eq $entscheidung.PSObject.Properties['OptGroup']) { continue }
            if ($null -eq $entscheidung.PSObject.Properties['Included']) { continue }

            if (([string] $entscheidung.OptGroup -ceq 'SystemAndBuiltinAdmins') -and (-not [bool] $entscheidung.Included)) {
                $optInMoeglich = $true
                break
            }
        }
    }

    $befund = 'Unter dem geplanten Ziel-ACL behält das ausführende Konto über keine seiner Tokengruppen Zugriff auf den Ordner.'

    $folge = if ($FreigabeGeplant) {
        'Das Anlegen der Freigabe scheitert danach sicher mit Zugriff verweigert; für dieses Ziel wird deshalb nichts geschrieben.'
    }
    else {
        'Der Ordner ist nach dem Lauf nur noch über den Besitzerweg erreichbar.'
    }

    $ausweg = New-Object System.Collections.Generic.List[string]

    if ($optInMoeglich) {
        $ausweg.Add('Ausweg: das Admin-Opt-in mitwählen (Optionsgruppe SystemAndBuiltinAdmins) -- es trägt die lokale Administratorengruppe des Servers und das Systemkonto ein.')
        $ausweg.Add('Oder: den Lauf mit einem Konto Ausführen, das der gewählten Gruppe der Administratoren angehört, oder eine Gruppe der Administratoren wählen, der das ausführende Konto angehört.')
    }
    else {
        $ausweg.Add('Ausweg: den Lauf mit einem Konto Ausführen, das der gewählten Gruppe der Administratoren angehört, oder eine Gruppe der Administratoren wählen, der das ausführende Konto angehört.')
    }

    $ausweg.Add('Nach der Aufnahme in eine Gruppe ist eine Neuanmeldung nötig -- erst das neue Anmeldetoken trägt die Gruppe.')

    return (@($befund, $folge) + @($ausweg.ToArray())) -join ' '
}

function New-PreflightFinding {
    <#
    .SYNOPSIS
        Baut einen Preflight-Befund. Intern zu Test-ProvisioningPreflight.

    .DESCRIPTION
        Die Einordnung reist doppelt: als NoteProperty Check und Scope direkt
        am Ergebnissatz -- dort liest sie der Sperrwaechter der Apply-Engine --
        und als strukturierter Befunddatensatz im Detail-Array mit den Feldern
        Check, Scope, Severity und Message. Letzteres ist die Form, aus der die
        Zusammenfassung der Phase 4 gruppiert, ohne Text zu zerlegen.

        New-ProvisioningResult traegt die eingefrorene Ergebnisform mit genau
        zehn Feldern und wird dafuer nicht aufgebohrt: eine elfte Spalte fuer
        eine Stufe traefe acht Konsumenten, die sie nie brauchen.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [AllowEmptyString()] [string] $Kind = '',
        [Parameter()] [AllowEmptyString()] [string] $Path = '',
        [Parameter(Mandatory)] [string] $Check,
        [Parameter(Mandatory)] [ValidateSet('Host', 'Target')] [string] $Scope,
        [Parameter(Mandatory)] [ValidateSet('OK', 'Warning', 'Error')] [string] $Status,
        [Parameter(Mandatory)] [string] $Message
    )

    $datensatz = [pscustomobject] @{
        Check    = $Check
        Scope    = $Scope
        Severity = $Status
        Message  = $Message
    }

    $ergebnis = New-ProvisioningResult -Kind $Kind -Path $Path -Stage 'Preflight' `
        -Status $Status -Message $Message -Detail @($datensatz)

    $ergebnis | Add-Member -NotePropertyName 'Check' -NotePropertyValue $Check
    $ergebnis | Add-Member -NotePropertyName 'Scope' -NotePropertyValue $Scope

    return $ergebnis
}

function Test-TargetPathSafety {
    <#
    .SYNOPSIS
        PRE-04: prueft einen Zielpfad gegen die vier Ablehnungsfaelle und
        liefert je Fall einen deutschen Grundtext. Intern zu
        Test-ProvisioningPreflight.

    .DESCRIPTION
        Reine Pfadarithmetik -- kein Dateisystemzugriff. Die vier Faelle:

        1. Laufwerkswurzel -- der normalisierte Pfad ist gleich seinem eigenen
           GetPathRoot().
        2. UNC -- der Pfad beginnt mit zwei Trennzeichen oder wird als UNC
           erkannt. Der erweiterte Praefix wird als Eingabeform ebenfalls
           abgelehnt statt still normalisiert.
        3. Systempfad -- der Pfad liegt auf oder unterhalb eines Ordners aus
           einer zur LAUFZEIT erhobenen Liste. AUSDRUECKLICH KEIN PFADLITERAL:
           der Programmordner heisst auf aelterem deutschem Windows anders, und
           eine hartkodierte Liste waere genau der Lokalisierungsfehler, gegen
           den dieses Werkzeug gebaut ist.
        4. Benutzercontainer-Muster -- der letzte Pfadbestandteil sieht aus wie
           ein von FSLogix angelegter Profilordner. Quelle: FEATURES.md
           Paragraph 1.6, Konsequenztabelle Zeile 1 -- ein per Hand angelegter
           Benutzerordner gehoert dem Administrator, der Ersteller-Besitzer
           liefe ins Leere und der Nutzer bekaeme ein temporaeres Profil.

        Der Praefixvergleich laeuft ordinal und ohne Gross-/Kleinschreibung,
        und BEIDE Seiten bekommen vor dem Vergleich ein Trennzeichen angehaengt
        -- sonst finge D:\Data faelschlich auch D:\Database.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $LiteralPath
    )

    $gruende = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($LiteralPath)) {
        $gruende.Add('Der Zielpfad ist leer. Bitte einen lokalen Ordnerpfad auf einem Datenlaufwerk angeben, etwa D:\Freigaben\Profile.')
        return $gruende.ToArray()
    }

    $roh = $LiteralPath.Trim()

    # --- Fall 2a: erweiterter Praefix, abgelehnt statt normalisiert ---------
    if ($roh.StartsWith('\\?\', [System.StringComparison]::Ordinal) -or
        $roh.StartsWith('//?/', [System.StringComparison]::Ordinal)) {
        $gruende.Add(('Der Zielpfad "{0}" verwendet die erweiterte Pfadform. Diese Eingabeform wird abgelehnt statt still umgeschrieben; bitte den gewöhnlichen Laufwerkspfad angeben.' -f $roh))
        return $gruende.ToArray()
    }

    # --- Fall 2b: UNC ueber die Rohform ------------------------------------
    if (($roh.Length -ge 2) -and (Test-IsPfadTrennzeichen -Zeichen $roh[0]) -and (Test-IsPfadTrennzeichen -Zeichen $roh[1])) {
        $gruende.Add(('Der Zielpfad "{0}" ist ein Netzwerkpfad. Dieses Werkzeug arbeitet auf dem Fileserver selbst und braucht einen lokalen Laufwerkspfad -- über eine Freigabe lässt sich der Vererbungsschutz nicht zuverlässig setzen.' -f $roh))
        return $gruende.ToArray()
    }

    # --- Normalisieren ------------------------------------------------------
    $voll = ''
    try {
        $voll = [System.IO.Path]::GetFullPath($roh)
    }
    catch {
        $gruende.Add(('Der Zielpfad "{0}" ist nicht auswertbar: {1}' -f $roh, $_.Exception.Message))
        return $gruende.ToArray()
    }

    # --- Fall 2c: UNC ueber die Uri-Auswertung ------------------------------
    try {
        $uri = $null
        if ([System.Uri]::TryCreate($voll, [System.UriKind]::Absolute, [ref] $uri)) {
            if ($uri.IsUnc) {
                $gruende.Add(('Der Zielpfad "{0}" wird als Netzwerkpfad erkannt. Dieses Werkzeug braucht einen lokalen Laufwerkspfad.' -f $voll))
                return $gruende.ToArray()
            }
        }
    }
    catch {
        # Eine nicht auswertbare Uri ist kein Befund: die Rohform oben hat den
        # UNC-Fall bereits abgedeckt.
    }

    $vergleichsZiel = ConvertTo-PfadPraefix -LiteralPath $voll

    # --- Fall 1: Laufwerkswurzel -------------------------------------------
    $wurzel = [System.IO.Path]::GetPathRoot($voll)
    if (-not [string]::IsNullOrEmpty($wurzel)) {
        if ($vergleichsZiel -eq (ConvertTo-PfadPraefix -LiteralPath $wurzel)) {
            $gruende.Add(('Der Zielpfad "{0}" ist eine Laufwerkswurzel. Eine Laufwerkswurzel als Freigabeziel setzt den Vererbungsschutz auf das gesamte Laufwerk; bitte einen Unterordner angeben.' -f $voll))
        }
    }

    # --- Fall 3: Systempfad, zur Laufzeit erhoben ---------------------------
    foreach ($kennung in (Get-SystemFolderKennung)) {

        $systemPfad = [System.Environment]::GetFolderPath($kennung)

        if ([string]::IsNullOrEmpty($systemPfad)) { continue }

        if ($vergleichsZiel.StartsWith((ConvertTo-PfadPraefix -LiteralPath $systemPfad),
                [System.StringComparison]::OrdinalIgnoreCase)) {
            $gruende.Add(('Der Zielpfad "{0}" liegt auf oder unterhalb des Systemordners "{1}". Ein Freigabeziel gehört auf ein Datenlaufwerk, nicht in einen vom Betriebssystem verwalteten Ordner.' -f $voll, $systemPfad))
        }
    }

    # --- Fall 4: Benutzercontainer-Muster -----------------------------------
    $blatt = [System.IO.Path]::GetFileName($voll.TrimEnd([char] 92, [char] 47))

    if ((-not [string]::IsNullOrEmpty($blatt)) -and
        (($blatt -match '^S-1-5-21-.*_') -or ($blatt -match '_S-1-5-21-'))) {
        $gruende.Add(('Der letzte Bestandteil "{0}" des Zielpfades sieht aus wie ein bereits angelegter Benutzer-Profilordner. Solche Ordner legt FSLogix selbst an; sie von Hand anzulegen gibt sie dem Administrator und der Nutzer bekäme ein temporäres Profil. Bitte die Freigabewurzel angeben, nicht einen Benutzerordner darunter.' -f $blatt))
    }

    return $gruende.ToArray()
}

function Get-SystemFolderKennung {
    <#
    .SYNOPSIS
        Die Ordnerkennungen der PRE-04-Systempfadliste. Intern zu
        Test-TargetPathSafety.

    .DESCRIPTION
        ENUMGLIEDER, KEINE ZEICHENKETTEN -- und zwei bewusste Auslassungen:

        Das Systemverzeichnis und sein 32-Bit-Gegenstueck stehen NICHT in der
        Liste. Beide sind echte Nachfahren des Windows-Ordners und damit vom
        Praefixvergleich bereits erfasst; ihre Enumglieder wuerden im AST
        zusaetzlich einen Zeichenkettenknoten erzeugen, der die IDENT-08-Pruefung
        in Tests/NoEnglishPrincipals.Tests.ps1 aufloesen wuerde. Gemessen, nicht
        vermutet: ein statischer Gliedzugriff erscheint im AST als
        StringConstantExpressionAst mit dem Gliednamen als Wert.

        Das Benutzerprofil steht ebenfalls NICHT in der Liste. Es ist kein vom
        Betriebssystem verwalteter Ordner, sondern ein Datenordner -- und der
        temporaere Ordner jeder angemeldeten Sitzung liegt darunter, auf dem
        die gesamte unprivilegierte Testsuite nach D-14 arbeitet. Ihn zu
        sperren hiesse, jeden Scratch-Pfad zu sperren.
    #>
    [CmdletBinding()]
    [OutputType([System.Environment+SpecialFolder[]])]
    param()

    return @(
        [System.Environment+SpecialFolder]::Windows
        [System.Environment+SpecialFolder]::ProgramFiles
        [System.Environment+SpecialFolder]::ProgramFilesX86
        [System.Environment+SpecialFolder]::CommonProgramFiles
        [System.Environment+SpecialFolder]::CommonApplicationData
    )
}

function ConvertTo-PfadPraefix {
    <#
    .SYNOPSIS
        Normalisiert einen Pfad zur vergleichbaren Praefixform: voll
        qualifiziert und mit genau einem abschliessenden Trennzeichen.

    .DESCRIPTION
        Das abschliessende Trennzeichen ist der ganze Zweck: ohne es faenge der
        Praefixvergleich fuer D:\Data faelschlich auch D:\Database. Beide Seiten
        laufen durch dieselbe Funktion -- eine zweite Normalisierung waere eine
        zweite Wahrheit ueber dieselbe Regel.

        Wird auch vom Sperrwaechter in Invoke-AclApply benutzt, der einen
        Preflight-Befund seinem Ziel zuordnet.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $LiteralPath
    )

    if ([string]::IsNullOrWhiteSpace($LiteralPath)) { return '' }

    $wert = $LiteralPath.Trim()

    try { $wert = [System.IO.Path]::GetFullPath($wert) }
    catch { }

    return ($wert.TrimEnd([char] 92, [char] 47) + [System.IO.Path]::DirectorySeparatorChar)
}

function Test-IsPfadTrennzeichen {
    <#
    .SYNOPSIS
        Wahr, wenn das Zeichen eines der beiden Pfadtrennzeichen ist. Intern zu
        Test-TargetPathSafety.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [char] $Zeichen
    )

    return ($Zeichen -eq [System.IO.Path]::DirectorySeparatorChar) -or
           ($Zeichen -eq [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-TargetPathInputError {
    <#
    .SYNOPSIS
        VAL-01: die fruehe Eingabepruefung eines Freigabeziels -- eine
        Teilmenge des Preflights aus DENSELBEN Praedikaten.

    .DESCRIPTION
        Der Dialog fragt hier, ob ein gerade eingegebener Zielpfad ein Fall
        ist, den das Preflight spaeter sicher abwiese. Entschieden wird
        ausschliesslich ueber die Funktionen, mit denen auch
        Test-ProvisioningPreflight entscheidet -- eine zweite Pfadregel im
        Dialog drifted gegen diese:

        1. Test-TargetPathSafety (PRE-04): Laufwerkswurzel, Netzwerkpfad,
           erweiterte Pfadform, Systemordner, Benutzercontainer-Muster. Je
           Grund ein Fehlersatz.
        2. Nur wenn 1. nichts findet: Get-VolumeFormat (PRE-03). Wirft die
           Seam oder liefert sie keine Bezeichnung, fehlt das Laufwerk oder
           ist nicht bereit -- ein Fehlersatz.
           Ein Dateisystem ausser NTFS/ReFS ist KEIN Eingabefehler; das bleibt
           Sache des Preflights.
        3. Get-TargetConflict (PRE-04) ueber die bisherigen Ziele plus den
           Kandidaten: je Konflikt der eigenen Ordnerart ein Fehlersatz mit dem
           Konfliktdatensatz im Feld Conflict.

        BEWUSST NICHT GEPRUEFT wird, was vom Zustand des Hosts statt vom Pfad
        abhaengt: das Dateisystem selbst, Schreibprobe, Freigabebelegung,
        Aussperrung und Inhalt (PRE-03 ausser dem fehlenden Laufwerk, PRE-05
        bis PRE-08). Das Preflight bleibt vollstaendig und unveraendert vor dem
        Schreiben (VAL-02); diese Funktion ist eine fruehere Kopie derselben
        Entscheidung, nie ihr Ersatz.

        Rein lesend, keine Ausgabe, keine Rueckfrage.

    .PARAMETER LiteralPath
        Der bereits ueber Resolve-OperatorPath normalisierte Zielpfad.

    .PARAMETER Kind
        Die Ordnerart des Kandidaten.

    .PARAMETER Target
        Die in diesem Lauf bereits erhobenen Ziele (Kind, Path).

    .OUTPUTS
        Fehlersaetze mit Check, Reason und Conflict. Leer, wenn der Pfad bei
        der Eingabe nicht abzuweisen ist.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Target = @()
    )

    $fehler = New-Object System.Collections.Generic.List[object]

    # --- 1. PRE-04: die Pfad-Sperrliste ---------------------------------------
    foreach ($grund in @(Test-TargetPathSafety -LiteralPath $LiteralPath)) {
        $fehler.Add([pscustomobject] @{ Check = 'PRE-04'; Reason = [string] $grund; Conflict = $null })
    }

    # --- 2. PRE-03, nur das fehlende Laufwerk ---------------------------------
    # Dieselbe Reihenfolge wie im Preflight: die Volumeabfrage wirft auf einem
    # untauglichen Pfad, statt ihn sauber abzuweisen.
    #
    # GEMESSEN (2026-09-30, Windows PowerShell 5.1): fuer ein fehlendes
    # Laufwerk wirft die Seam NICHT, sie liefert eine leere Bezeichnung. Das
    # Preflight wertet beides als "(nicht ermittelbar)" und weist ab; die
    # Eingabepruefung tut deshalb dasselbe fuer Wurf UND leere Rueckgabe.
    if ($fehler.Count -eq 0) {

        $format = ''
        $fehlt = $false

        try { $format = [string] (Get-VolumeFormat -LiteralPath $LiteralPath) }
        catch { $fehlt = $true }

        if ($fehlt -or [string]::IsNullOrWhiteSpace($format)) {

            $laufwerk = $LiteralPath
            try { $laufwerk = [System.IO.Path]::GetPathRoot($LiteralPath) }
            catch { }

            $fehler.Add([pscustomobject] @{
                    Check    = 'PRE-03'
                    Reason   = ('Das Laufwerk "{0}" ist auf diesem Server nicht vorhanden oder nicht bereit.' -f $laufwerk)
                    Conflict = $null
                })
        }
    }

    # --- 3. PRE-04: laufinterne Konflikte -------------------------------------
    $kandidat = [pscustomobject] @{ Kind = $Kind; Path = $LiteralPath }
    $bisher = @(@($Target) | Where-Object { $null -ne $_ })

    foreach ($konflikt in @(Get-TargetConflict -Target (@($bisher) + @($kandidat)))) {

        if (-not ([string] $konflikt.Kind -ceq $Kind)) { continue }
        if (-not ([string] $konflikt.Check -ceq 'PRE-04')) { continue }

        $fehler.Add([pscustomobject] @{ Check = 'PRE-04'; Reason = [string] $konflikt.Message; Conflict = $konflikt })
    }

    return $fehler.ToArray()
}
