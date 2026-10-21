<#
    Find-AuditTarget -- die Erkennung der Bestandspruefung (AUDIT-02,
    D-05 bis D-08).

    ERKANNT WIRD AM VOLLEN NAMEN UND NUR DORT (D-05). Die Namensliste steht als
    Datendatei unter DemFsAcl/Data/AuditKindNames.psd1; Get-AuditKindNameMap
    laedt und prueft sie. Kein Namensbestandteil, keine Heuristik, kein Blick
    auf den Inhalt eines Ordners -- geraten wird nichts (D-08 aus Phase 4).

    EINZIGE AUSNAHME: FSLogix-Redirections wird zusaetzlich an jedem Namen
    erkannt, der den Teilnamen "Redirection" enthaelt (W-09-2, Entscheidung
    Projektinhaber 2026-10-01). Die Regel steht als Daten unter KindContains
    und wird nur in Resolve-AuditKindName ausgewertet; ein exakter Name geht
    vor. Alles Uebrige bleibt: kein Blick auf Inhalte, kein Abstieg unter
    erkannte Ordner, die Erkennung ist nur Vorschlag.

    GELESEN WIRD NUR DIE ORDNERSTRUKTUR, uber die Seam Get-ChildDirectory. Kein
    ACL, keine Freigabe: die Erkennung entscheidet, WAS geprueft wird, nicht
    OB es stimmt. Die eine ACL-Lesestelle bleibt Get-ActualAceSet.

    KEIN ABSTIEG UNTER EINEN ERKANNTEN ORDNER (D-06). Darunter liegen
    Benutzerordner; sie prueft der Benutzerordner-Bericht auf Wunsch getrennt
    und rein lesend (USR-02, Test-UserFolderSet). Die Erkennung selbst steigt
    weiterhin nie hinab.

    Kein Eingabe- und kein Ausgabe-Cmdlet: die Funktionen geben zurueck oder
    werfen.
#>

function Get-AuditKindNameMap {
    <#
    .SYNOPSIS
        Laedt die Namensliste der Bestandspruefung, prueft sie und liefert die
        Nachschlagetabellen.

    .DESCRIPTION
        Geprueft wird beim Laden, nicht beim Nachschlagen -- dieselbe Haltung
        wie SPEC-07 bei den Templates: eine fehlerhafte Liste wird abgewiesen,
        nicht still teilweise benutzt.

        Abgewiesen wird mit [System.IO.InvalidDataException]:
          - ein Schluessel unter Kinds, der keine der bekannten Ordnerarten ist;
          - ein leerer Name oder einer mit Pfadtrennzeichen;
          - ein Name, der ueber alle Ordnerarten und Sammelordnernamen hinweg
            doppelt vorkommt (ohne Beachtung der Gross-/Kleinschreibung);
          - unter KindContains (W-09-2): eine andere Ordnerart als
            FSLogix-Redirections, ein leerer Teilname, einer mit
            Pfadtrennzeichen, ein doppelter, und einer, den ein voller Name
            einer anderen Ordnerart oder ein Sammelordnername enthaelt.

    .OUTPUTS
        [pscustomobject] mit Kind (Dictionary Name -> Ordnerart) und
        Collection (HashSet der Sammelordnernamen), beide mit
        OrdinalIgnoreCase, sowie Fragment (Array aus Text und Kind, die
        Teilnamen aus KindContains, ordinal nach Kind und Text sortiert).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string] $LiteralPath = ''
    )

    # Ohne Pfad die eingebaute Liste; $LiteralPath traegt dann nur noch die
    # Bezeichnung fuer die Meldungen.
    if ([string]::IsNullOrEmpty($LiteralPath)) {
        $LiteralPath = 'AuditKindNames'
        $daten = Get-DataTable -Name $LiteralPath
    }
    else {
        $daten = Import-PowerShellDataFile -LiteralPath $LiteralPath
    }

    $vergleich = [System.StringComparer]::OrdinalIgnoreCase
    $bekannt = @('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')

    $kind = New-Object 'System.Collections.Generic.Dictionary[string,string]' $vergleich
    $sammel = New-Object 'System.Collections.Generic.HashSet[string]' $vergleich
    $gesehen = New-Object 'System.Collections.Generic.HashSet[string]' $vergleich

    if ((-not $daten.ContainsKey('Kinds')) -or ($daten['Kinds'] -isnot [hashtable])) {
        throw [System.IO.InvalidDataException]::new(
            ('Die Namensliste "{0}" hat keinen Abschnitt Kinds.' -f $LiteralPath))
    }

    foreach ($art in @($daten['Kinds'].Keys)) {

        if ($bekannt -cnotcontains [string] $art) {
            throw [System.IO.InvalidDataException]::new(
                ('Die Namensliste "{0}" nennt die unbekannte Ordnerart "{1}". Bekannt: {2}' -f
                    $LiteralPath, [string] $art, ($bekannt -join ', ')))
        }

        foreach ($name in @($daten['Kinds'][$art])) {
            Assert-AuditName -Name ([string] $name) -Gesehen $gesehen -LiteralPath $LiteralPath
            $kind[[string] $name] = [string] $art
        }
    }

    $sammelnamen = @()
    if ($daten.ContainsKey('CollectionNames')) { $sammelnamen = @($daten['CollectionNames']) }

    foreach ($name in $sammelnamen) {
        Assert-AuditName -Name ([string] $name) -Gesehen $gesehen -LiteralPath $LiteralPath
        $null = $sammel.Add([string] $name)
    }

    # W-09-2: Teilnamen, erst nach allen vollen Namen.
    $teile = New-Object System.Collections.Generic.List[object]

    if ($daten.ContainsKey('KindContains')) {

        if ($daten['KindContains'] -isnot [hashtable]) {
            throw [System.IO.InvalidDataException]::new(
                ('Die Namensliste "{0}" hat einen Abschnitt KindContains, der keine Tabelle ist.' -f $LiteralPath))
        }

        $artenTeil = New-Object System.Collections.Generic.List[string]
        foreach ($art in @($daten['KindContains'].Keys)) { $artenTeil.Add([string] $art) }
        $artenTeil.Sort([System.StringComparer]::Ordinal)

        # Eigenes Set: ein Teilname ist kein voller Name.
        $teilGesehen = New-Object 'System.Collections.Generic.HashSet[string]' $vergleich

        foreach ($art in $artenTeil) {

            if (-not [string]::Equals($art, 'FSLogix-Redirections', [System.StringComparison]::Ordinal)) {
                throw [System.IO.InvalidDataException]::new(
                    ('Die Namensliste "{0}" nennt unter KindContains die Ordnerart "{1}". Teilnamen sind nur für FSLogix-Redirections zugelassen (Entscheidung Projektinhaber 2026-10-01).' -f
                        $LiteralPath, $art))
            }

            $texte = New-Object System.Collections.Generic.List[string]
            foreach ($text in @($daten['KindContains'][$art])) { $texte.Add([string] $text) }
            $texte.Sort([System.StringComparer]::Ordinal)

            foreach ($text in $texte) {
                Assert-AuditFragment -Text $text -Kind $art -Gesehen $teilGesehen -KindMap $kind `
                    -Collection $sammel -LiteralPath $LiteralPath
                $teile.Add([pscustomobject] @{ Text = $text; Kind = $art })
            }
        }
    }

    return [pscustomobject] @{
        Kind       = $kind
        Collection = $sammel
        Fragment   = $teile.ToArray()
    }
}

function Resolve-AuditKindName {
    <#
    .SYNOPSIS
        Die eine Erkennungsregel: Ordnername -> Ordnerart oder leer.

    .DESCRIPTION
        Reihenfolge (W-09-2, D-05): ein leerer Name ist nicht erkannt; ein
        exakter Name aus der Karte liefert seine Ordnerart; ein
        Sammelordnername ist keine Ordnerart; sonst liefert der erste
        Teilname, den der Name enthaelt (ordinal, ohne Gross-/Kleinschreibung),
        seine Ordnerart. Kein -like, -match oder -eq -- die sind
        kulturabhaengig oder deuten Metazeichen.

        Eine Karte ohne Fragment wird nur exakt ausgewertet.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [object] $NameMap
    )

    if ([string]::IsNullOrEmpty($Name)) { return '' }

    if ($NameMap.Kind.ContainsKey($Name)) { return [string] $NameMap.Kind[$Name] }

    if ($NameMap.Collection.Contains($Name)) { return '' }

    if ($null -eq $NameMap.PSObject.Properties['Fragment']) { return '' }

    foreach ($teil in @($NameMap.Fragment)) {
        if ($null -eq $teil) { continue }
        if ($Name.IndexOf([string] $teil.Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return [string] $teil.Kind
        }
    }

    return ''
}

function Assert-AuditName {
    <#
    .SYNOPSIS
        Prueft einen Namen der Namensliste und merkt ihn sich. Intern zu
        Get-AuditKindNameMap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [object] $Gesehen,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw [System.IO.InvalidDataException]::new(
            ('Die Namensliste "{0}" enthält einen leeren Namen.' -f $LiteralPath))
    }

    if (($Name.IndexOf([char] 92) -ge 0) -or ($Name.IndexOf([char] 47) -ge 0)) {
        throw [System.IO.InvalidDataException]::new(
            ('Der Name "{0}" in der Namensliste "{1}" enthält ein Pfadtrennzeichen.' -f $Name, $LiteralPath))
    }

    if (-not $Gesehen.Add($Name)) {
        throw [System.IO.InvalidDataException]::new(
            ('Der Name "{0}" kommt in der Namensliste "{1}" mehrfach vor (ohne Beachtung der Groß-/Kleinschreibung).' -f $Name, $LiteralPath))
    }
}

function Assert-AuditFragment {
    <#
    .SYNOPSIS
        Prueft einen Teilnamen der Namensliste und merkt ihn sich. Intern zu
        Get-AuditKindNameMap.

    .DESCRIPTION
        Abgewiesen wird ein leerer Teilname, einer mit Pfadtrennzeichen, ein
        doppelter (ohne Gross-/Kleinschreibung) und einer, den ein voller Name
        einer anderen Ordnerart oder ein Sammelordnername enthaelt -- sonst
        haenge die Erkennung an der Reihenfolge der Pruefung (W-09-2).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [object] $Gesehen,

        [Parameter(Mandatory)]
        [object] $KindMap,

        [Parameter(Mandatory)]
        [object] $Collection,

        [Parameter(Mandatory)]
        [string] $LiteralPath
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw [System.IO.InvalidDataException]::new(
            ('Die Namensliste "{0}" enthält unter KindContains einen leeren Teilnamen.' -f $LiteralPath))
    }

    if (($Text.IndexOf([char] 92) -ge 0) -or ($Text.IndexOf([char] 47) -ge 0)) {
        throw [System.IO.InvalidDataException]::new(
            ('Der Teilname "{0}" in der Namensliste "{1}" enthält ein Pfadtrennzeichen.' -f $Text, $LiteralPath))
    }

    if (-not $Gesehen.Add($Text)) {
        throw [System.IO.InvalidDataException]::new(
            ('Der Teilname "{0}" kommt in der Namensliste "{1}" mehrfach vor (ohne Beachtung der Groß-/Kleinschreibung).' -f $Text, $LiteralPath))
    }

    foreach ($name in @($KindMap.Keys)) {
        if ([string]::Equals([string] $KindMap[$name], $Kind, [System.StringComparison]::Ordinal)) { continue }
        if (([string] $name).IndexOf($Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw [System.IO.InvalidDataException]::new(
                ('Der Name "{0}" der Ordnerart {1} in der Namensliste "{2}" enthält den Teilnamen "{3}" von {4}.' -f
                    [string] $name, [string] $KindMap[$name], $LiteralPath, $Text, $Kind))
        }
    }

    foreach ($name in @($Collection)) {
        if (([string] $name).IndexOf($Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw [System.IO.InvalidDataException]::new(
                ('Der Sammelordnername "{0}" in der Namensliste "{1}" enthält den Teilnamen "{2}" von {3}.' -f
                    [string] $name, $LiteralPath, $Text, $Kind))
        }
    }
}

function Find-AuditTarget {
    <#
    .SYNOPSIS
        Erkennt unter einem Wurzelverzeichnis die Ordnerarten am Namen.

    .DESCRIPTION
        Heisst die Wurzel selbst wie eine Ordnerart, ist sie das einzige Ziel,
        und darunter wird nicht gesucht (D-07). Sonst werden die unmittelbaren
        Unterordner ueber Get-ChildDirectory gelesen.

        EIN AUFLISTFEHLER DER WURZEL WIRD NICHT GEFANGEN. Die Orchestrierung
        fragt dann die Wurzel erneut -- ein Pruefweg ohne auflistbare Wurzel
        haette keinen Gegenstand.

        Jeder Eintrag traegt Path, RelativePath (die Wurzel selbst heisst "."),
        Level (0, 1, 2), Name, Kind (leer, wenn nicht erkannt), State
        (Recognised, Unrecognised, Collection, Container, DemOpen), Reason und
        ShareNames.

    .OUTPUTS
        [pscustomobject] mit RootPath und Entries.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RootPath,

        [Parameter(Mandatory)]
        [object] $NameMap,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ShareList = @()
    )

    $eintraege = New-Object System.Collections.Generic.List[object]
    $freigaben = @(@($ShareList) | Where-Object { $null -ne $_ })

    $wurzelName = [System.IO.Path]::GetFileName($RootPath.TrimEnd([char] 92, [char] 47))

    # D-07: die Wurzel selbst ist das Ziel.
    $wurzelArt = Resolve-AuditKindName -Name ([string] $wurzelName) -NameMap $NameMap
    if (-not [string]::IsNullOrEmpty($wurzelArt)) {

        $eintraege.Add((New-AuditEntry -Path $RootPath -RelativePath '.' -Level 0 -Name $wurzelName `
                    -Kind $wurzelArt -State 'Recognised' -ShareList $freigaben))

        return [pscustomobject] @{ RootPath = $RootPath; Entries = $eintraege.ToArray() }
    }

    $demArten = @('DEMConfig', 'DEMProfiles', 'DEMComputerLogs')

    foreach ($pfad in @(Get-ChildDirectory -LiteralPath $RootPath)) {

        $name = [System.IO.Path]::GetFileName([string] $pfad)

        # Ebene 1, erkannt: Freigabewurzel -- darunter wird nie gesucht (D-06).
        $nameArt = Resolve-AuditKindName -Name $name -NameMap $NameMap
        if (-not [string]::IsNullOrEmpty($nameArt)) {
            $eintraege.Add((New-AuditEntry -Path ([string] $pfad) -RelativePath $name -Level 1 -Name $name `
                        -Kind $nameArt -State 'Recognised' -ShareList $freigaben))
            continue
        }

        # Ebene 1, nicht erkannt oder Sammelordner: eine Ebene tiefer, nur
        # nach bekannten Namen.
        $istSammel = $NameMap.Collection.Contains($name)
        $kinder = @()
        $fehler = ''

        try { $kinder = @(Get-ChildDirectory -LiteralPath ([string] $pfad)) }
        catch { $fehler = [string] $_.Exception.Message }

        $unter = New-Object System.Collections.Generic.List[object]
        $erkanntDem = $false
        $erkanntIrgend = $false

        foreach ($kind in $kinder) {

            $kindName = [System.IO.Path]::GetFileName([string] $kind)
            $relativ = '{0}\{1}' -f $name, $kindName

            $art = Resolve-AuditKindName -Name $kindName -NameMap $NameMap
            if (-not [string]::IsNullOrEmpty($art)) {

                $erkanntIrgend = $true
                if ($demArten -ccontains $art) { $erkanntDem = $true }

                $unter.Add((New-AuditEntry -Path ([string] $kind) -RelativePath $relativ -Level 2 -Name $kindName `
                            -Kind $art -State 'Recognised' -ShareList $freigaben))
            }
            elseif ($istSammel) {
                # Nur unter einem DEM-Ordner werden nicht erkannte Unterordner
                # gelistet (Planerentscheid 2) -- sonst explodierte die Liste
                # in einer Datenwurzel.
                $unter.Add((New-AuditEntry -Path ([string] $kind) -RelativePath $relativ -Level 2 -Name $kindName `
                            -State 'Unrecognised' -Reason 'nicht erkannt' -ShareList $freigaben))
            }
        }

        $eigeneFreigaben = @(Get-AuditPathShare -LiteralPath ([string] $pfad) -ShareList $freigaben)

        if ($istSammel) {

            if (-not [string]::IsNullOrEmpty($fehler)) {
                $zustand = 'DemOpen'; $grund = 'nicht lesbar: {0}' -f $fehler
            }
            elseif ($eigeneFreigaben.Count -gt 0) {
                $zustand = 'DemOpen'; $grund = 'freigegeben als {0}' -f ($eigeneFreigaben -join ', ')
            }
            elseif (-not $erkanntDem) {
                $zustand = 'DemOpen'; $grund = 'enthält keinen erkannten DEM-Ordner'
            }
            else {
                $zustand = 'Collection'; $grund = ''
            }
        }
        elseif (-not [string]::IsNullOrEmpty($fehler)) {
            $zustand = 'Unrecognised'; $grund = 'nicht lesbar: {0}' -f $fehler
        }
        elseif ($erkanntIrgend) {
            $zustand = 'Container'; $grund = ''
        }
        else {
            $zustand = 'Unrecognised'; $grund = 'nicht erkannt'
        }

        $eintraege.Add((New-AuditEntry -Path ([string] $pfad) -RelativePath $name -Level 1 -Name $name `
                    -State $zustand -Reason $grund -ShareList $freigaben))

        foreach ($eintrag in $unter) { $eintraege.Add($eintrag) }
    }

    return [pscustomobject] @{ RootPath = $RootPath; Entries = $eintraege.ToArray() }
}

function New-AuditEntry {
    <#
    .SYNOPSIS
        Baut einen Erkennungseintrag. Intern zu Find-AuditTarget.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $RelativePath,
        [Parameter(Mandatory)] [int] $Level,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter()] [AllowEmptyString()] [string] $Kind = '',
        [Parameter(Mandatory)] [string] $State,
        [Parameter()] [AllowEmptyString()] [string] $Reason = '',
        [Parameter()] [AllowNull()] [AllowEmptyCollection()] [object[]] $ShareList = @()
    )

    return [pscustomobject] @{
        Path         = $Path
        RelativePath = $RelativePath
        Level        = $Level
        Name         = $Name
        Kind         = $Kind
        State        = $State
        Reason       = $Reason
        ShareNames   = @(Get-AuditPathShare -LiteralPath $Path -ShareList $ShareList)
    }
}

function Get-AuditPathShare {
    <#
    .SYNOPSIS
        Die Namen der Freigaben, die auf genau diesen Pfad zeigen, ordinal
        sortiert.

    .DESCRIPTION
        Verglichen wird ueber ConvertTo-PfadPraefix -- die eine
        Pfadnormalisierung fuer Vergleiche. Eine zweite Normalisierung hier
        waere eine zweite Wahrheit ueber dieselbe Regel.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ShareList = @()
    )

    $ziel = ConvertTo-PfadPraefix -LiteralPath $LiteralPath
    $namen = New-Object System.Collections.Generic.List[string]

    foreach ($freigabe in @($ShareList)) {

        if ($null -eq $freigabe) { continue }
        if ($null -eq $freigabe.PSObject.Properties['Path']) { continue }

        $pfad = [string] $freigabe.Path
        if ([string]::IsNullOrWhiteSpace($pfad)) { continue }

        if ([string]::Equals((ConvertTo-PfadPraefix -LiteralPath $pfad), $ziel, [System.StringComparison]::OrdinalIgnoreCase)) {
            $namen.Add([string] $freigabe.Name)
        }
    }

    $namen.Sort([System.StringComparer]::Ordinal)

    return $namen.ToArray()
}
