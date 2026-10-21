<#
    Read-TrusteeGroup -- die Gruppenerhebung des Dialogs (IDENT-03, IDENT-04,
    IDENT-06, IDENT-09, FLOW-06).

    ZEICHENGETREU WEITERREICHEN. Die Dialogschicht normalisiert Gruppenangaben
    nicht und vergleicht sie nicht: kein String.Normalize, keine Faltung der
    Gross-/Kleinschreibung, kein eigener Trim auf dem weitergereichten Wert. Die
    einzige Trimmstelle des Werkzeugs bleibt Resolve-TrusteeSid. Ueber Gleichheit
    von Gruppen entscheidet ausschliesslich die zurueckgelieferte SID, ordinal
    ueber Sid.Value verglichen.

    EINE NICHT AUFLOESBARE EINGABE GELANGT NIE IN DEN SCHREIBPFAD: die Aufloesung
    wirft, der Dialog faengt und fragt erneut (FLOW-06). IDENT-07 bleibt davon
    unberuehrt -- die unaufloesbare Eingabe gelangt nie in eine Bindung.

    DIE RUECKWAERTSUEBERSETZUNG SID -> ANZEIGENAME IST HIER DER ZULAESSIGE
    ANZEIGEFALL (IDENT-06). Weitergereicht wird ausschliesslich das
    SecurityIdentifier; der Name erscheint nur auf dem Bildschirm.

    JEDE ROLLE WIRD JE PRODUKT GENAU EINMAL ERHOBEN (G-04-4a) und danach
    ueber alle Ordnerarten dieses Produkts wiederverwendet. Die Produkte sind
    FSLogix und DEM: in der Praxis sind die Gruppen dort oft verschieden, und
    ein gemeinsamer Gruppenblock zwang beide Produkte auf dieselbe Wahl
    (lauf5_1.txt). DEM bietet die FSLogix-Wahl sichtbar an ("dieselbe wie bei
    FSLogix (<Anzeigename>)? [j/n, Vorgabe: ja]") und uebernimmt nie
    stillschweigend. Eine zweite Abfrage derselben Rolle im selben Produkt gibt
    es nicht -- sie waere die zweite Gelegenheit, dieselbe Gruppe verschieden
    zu schreiben. Davon getrennt fragt Weg 1 nach jeder erhobenen Gruppe, ob
    eine WEITERE Gruppe derselben Rolle hinzukommt (Read-AdditionalTrusteeGroup,
    Vorgabe nein, 2026-10-20); das ist eine zusaetzliche, keine erneute Gruppe.

    DIE ROLLENBEZEICHNUNGEN STEHEN AN GENAU EINER STELLE (G-04-4c):
    Get-TrusteeRoleLabel. Die Rolle <AdminGroup> heisst "Gruppe der
    Administratoren" und ist sprachlich von der lokalen Administratorengruppe
    des Servers getrennt, die nur das FSLogix-Opt-in eintraegt.
#>

# Die Rollenspeicher dieses Laufs, je Produkt: FSLogix und DEM, darunter
# Rollenname -> Datensatz mit InputValue, Sid und DisplayName. Sie liegen im
# Modulskopus und nicht beim Aufrufer, damit Read-GroupBinding je Ordnerart
# dieselbe bereits erhobene Gruppe findet. Das ist die EINE Wahrheit ueber
# gebundene Gruppen. Invoke-DemFsProvisioning setzt sie zu Beginn jedes Laufs
# zurueck.
$script:TrusteeRolle = @{ FSLogix = @{}; DEM = @{} }

# Die zusaetzlichen Gruppen je Produkt und Rolle (Weg 1, Wunsch Projektinhaber
# 2026-10-20): Rollenname -> Feld weiterer Datensaetze derselben Form. Der
# Datensatz in $script:TrusteeRolle bleibt die erste Gruppe der Rolle; alle
# Leser, die nur einen Anzeigenamen brauchen, bleiben damit unveraendert.
# Gebunden werden alle zusammen (Get-TrusteeRoleBindingValue).
$script:TrusteeZusatz = @{ FSLogix = @{}; DEM = @{} }

# Ob die Helpdesk-Frage in diesem Lauf bereits gestellt wurde. Sie ist nicht an
# der Rollentabelle ablesbar: "nicht eingetragen" hinterlaesst dort ausdruecklich
# KEINEN Eintrag, und ohne dieses Merkmal waere ein abgelehnter Helpdesk von
# einem noch nicht gefragten nicht zu unterscheiden -- die Frage kaeme ein
# zweites Mal.
$script:HelpdeskGeklaert = $false

function Reset-TrusteeRoleStore {
    <#
    .SYNOPSIS
        Leert die Rollentabelle. Wird zu Beginn jedes Laufs gerufen.

    .DESCRIPTION
        Ohne diesen Schnitt truege ein zweiter Lauf im selben Prozess die
        Gruppen des ersten -- und der Operator saehe eine Bindung, nach der er
        nie gefragt wurde.
    #>
    [CmdletBinding()]
    param()

    $script:TrusteeRolle = @{ FSLogix = @{}; DEM = @{} }
    $script:TrusteeZusatz = @{ FSLogix = @{}; DEM = @{} }
    $script:HelpdeskGeklaert = $false
}

function Get-TrusteeRoleStore {
    <#
    .SYNOPSIS
        Die Rollentabelle eines Produkts, oder eine flache Anzeigetabelle ueber
        beide.

    .DESCRIPTION
        Mit -Product die Rollentabelle dieses Produkts (Rolle -> Datensatz).
        Ohne -Product eine FLACHE ANZEIGETABELLE ueber beide Produkte mit
        Schluesseln wie "FSLogix/Admin" und "DEM/User". Die Planvorschau und
        die Zusammenfassung lesen davon nur die Werte, um je Bindung den
        Anzeigenamen zu zeigen, ohne die SID ein zweites Mal aufzuloesen.
        Zusaetzliche Gruppen stehen dort unter "FSLogix/User+1" usw.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product
    )

    if (-not [string]::IsNullOrEmpty($Product)) { return $script:TrusteeRolle[$Product] }

    $flach = @{}

    foreach ($produkt in @('FSLogix', 'DEM')) {
        foreach ($rolle in @($script:TrusteeRolle[$produkt].Keys)) {
            $flach[('{0}/{1}' -f $produkt, [string] $rolle)] = $script:TrusteeRolle[$produkt][$rolle]
        }
        foreach ($rolle in @($script:TrusteeZusatz[$produkt].Keys)) {
            $weitere = @($script:TrusteeZusatz[$produkt][$rolle])
            for ($i = 0; $i -lt $weitere.Count; $i++) {
                $flach[('{0}/{1}+{2}' -f $produkt, [string] $rolle, ($i + 1))] = $weitere[$i]
            }
        }
    }

    return $flach
}

function Get-TrusteeRoleAdditional {
    <#
    .SYNOPSIS
        Die zusaetzlichen Gruppen einer Rolle in einem Produkt; leer, wenn es
        keine gibt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer', 'Helpdesk')]
        [string] $Role
    )

    if (-not $script:TrusteeZusatz[$Product].ContainsKey($Role)) { return @() }

    return @($script:TrusteeZusatz[$Product][$Role])
}

function Get-TrusteeRoleBindingValue {
    <#
    .SYNOPSIS
        Der Bindungswert einer erhobenen Rolle: die SID, mit zusaetzlichen
        Gruppen ein Feld von SIDs.

    .DESCRIPTION
        Ohne zusaetzliche Gruppe bleibt der Wert ein einzelnes
        SecurityIdentifier -- die Bindungen eines Laufs mit je einer Gruppe
        sind damit dieselben wie vorher. Expand-AclTemplate und
        ConvertTo-ShareDesired bauen je SID des Feldes einen Eintrag; die
        Formatierer gehen mit @(...) darueber (wie bei Get-AdjustBinding).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer', 'Helpdesk')]
        [string] $Role
    )

    $erste = $script:TrusteeRolle[$Product][$Role]
    $weitere = @(Get-TrusteeRoleAdditional -Product $Product -Role $Role)

    if ($weitere.Count -eq 0) { return $erste.Sid }

    $sids = New-Object System.Collections.Generic.List[object]
    $sids.Add($erste.Sid)
    foreach ($satz in $weitere) { $sids.Add($satz.Sid) }

    return , $sids.ToArray()
}

function Read-AdditionalTrusteeGroup {
    <#
    .SYNOPSIS
        Fragt nach einer erhobenen Rollengruppe, ob eine weitere Gruppe
        derselben Rolle hinzukommt -- Vorgabe nein, wiederholt bis nein.

    .DESCRIPTION
        Wunsch Projektinhaber 2026-10-20: in Weg 1 je Rolle (Administratoren,
        Benutzer, Computer) mehr als eine Gruppe. Die weitere Gruppe bekommt
        genau die Rechte der Rolle; sie wird ueber Read-TrusteeGroup erhoben,
        also aufgeloest und zurueckgespiegelt wie die erste. Ueber Gleichheit
        entscheidet die SID: eine schon eingetragene Gruppe wird abgewiesen,
        sonst entstuende ein doppelter Eintrag im Soll.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer')]
        [string] $Role
    )

    $bezeichnung = Get-TrusteeRoleLabel -Role $Role
    $frage = 'Weitere {0} hinzufügen?' -f $bezeichnung

    while (Read-YesNoAnswer -Prompt $frage -Default $false -ShortLabel) {

        $neu = Read-TrusteeGroup -Prompt ('Weitere {0} (Domäne\Gruppe, UPN oder SID)' -f $bezeichnung)

        $vorhanden = @($script:TrusteeRolle[$Product][$Role]) + @(Get-TrusteeRoleAdditional -Product $Product -Role $Role)
        $doppelt = @($vorhanden | Where-Object {
                [string]::Equals([string] $_.Sid.Value, [string] $neu.Sid.Value, [System.StringComparison]::Ordinal)
            })

        if ($doppelt.Count -gt 0) {
            Write-OperatorHint -Text ('    {0} ist für diese Rolle bereits eingetragen.' -f [string] $neu.DisplayName)
            continue
        }

        $script:TrusteeZusatz[$Product][$Role] = @(Get-TrusteeRoleAdditional -Product $Product -Role $Role) + @($neu)
    }

    Add-PromptContext -Line @('')
}

function Set-TrusteeRoleRecord {
    <#
    .SYNOPSIS
        Legt einen bestaetigten Gruppendatensatz in den Rollenspeicher eines
        Produkts (Phase 5, D-11).

    .DESCRIPTION
        Die Bestandspruefung liest Gruppen am vorhandenen ACL ab und laesst sie
        bestaetigen. Der bestaetigte Datensatz landet HIER und nirgends sonst:
        die eine Wahrheit ueber gebundene Gruppen bleibt der Rollenspeicher.
        Read-GroupBinding findet die Rolle danach wie nach einer normalen
        Abfrage und fragt sie nicht erneut.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer', 'Helpdesk')]
        [string] $Role,

        [Parameter(Mandatory)]
        [object] $Record
    )

    $script:TrusteeRolle[$Product][$Role] = $Record
}

function Get-KindProduct {
    <#
    .SYNOPSIS
        Das Produkt einer Ordnerart: FSLogix oder DEM (G-04-4a).

    .DESCRIPTION
        Die Redirections-Ablage gehoert zu FSLogix: Read-GroupBinding findet
        ihre Rollen damit im FSLogix-Rollenspeicher und fragt nichts neu
        (RDX-03, Inhaberentscheid 2026-09-25).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind
    )

    if (($Kind -eq 'FSLogix-Profiles') -or ($Kind -eq 'FSLogix-Redirections')) { return 'FSLogix' }

    return 'DEM'
}

function Get-TrusteeRoleLabel {
    <#
    .SYNOPSIS
        Die Anzeigebezeichnung einer Gruppenrolle -- an genau einer Stelle
        (G-04-4c).

    .DESCRIPTION
        "Gruppe der Administratoren" fuer <AdminGroup>: so benennt der
        Projektinhaber die Rolle, und sie ist damit sprachlich von der lokalen
        Administratorengruppe des Servers getrennt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer', 'Helpdesk')]
        [string] $Role
    )

    if ($Role -eq 'Admin') { return 'Gruppe der Administratoren' }
    if ($Role -eq 'User') { return 'Benutzergruppe' }
    if ($Role -eq 'Computer') { return 'Computergruppe' }

    return 'Helpdesk-Gruppe'
}

function Read-TrusteeGroup {
    <#
    .SYNOPSIS
        Fragt eine Gruppe ab, loest sie auf und spiegelt SID und Anzeigenamen
        zurueck (IDENT-06).

    .DESCRIPTION
        Der Ablauf je Versuch: Read-RequiredText fragt; die Eingabe geht
        ZEICHENGETREU an Resolve-TrusteeSid; bei Erfolg werden SID-Zeichenkette
        und aufgeloester Anzeigename zurueckgespiegelt und bestaetigt. Bei
        Ablehnung oder bei einem Aufloesungsfehler wird erneut gefragt -- der
        Lauf bricht nicht ab (FLOW-06).

        DIE BEIDEN AUSNAHMETYPEN TRAGEN ZWEI VERSCHIEDENE AUSKUENFTE:
        ArgumentException heisst "SID-Syntax ungueltig oder Angabe leer",
        IdentityNotMappedException heisst "existiert nicht oder ist nicht
        aufloesbar". Der Operator sieht den Unterschied, weil er zu zwei
        verschiedenen Abhilfen fuehrt.

    .OUTPUTS
        [pscustomobject] mit InputValue, Sid und DisplayName.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Prompt
    )

    while ($true) {

        $eingabe = Read-RequiredText -Prompt $Prompt

        $sid = $null

        try {
            $sid = Resolve-TrusteeSid -InputValue $eingabe
        }
        catch [System.Security.Principal.IdentityNotMappedException] {
            Write-OperatorHint -Text ('    "{0}" existiert nicht oder ist nicht auflösbar. Bitte Schreibweise und Domänenpräfix prüfen.' -f $eingabe)
            continue
        }
        catch [System.ArgumentException] {
            Write-OperatorHint -Text ('    "{0}" ist als SID syntaktisch ungültig oder die Angabe ist leer.' -f $eingabe)
            continue
        }
        catch {
            Write-OperatorHint -Text ('    "{0}" ließ sich nicht auflösen: {1}' -f $eingabe, $_.Exception.Message)
            continue
        }

        $anzeige = Get-TrusteeDisplayName -Sid $sid

        # Die Rueckspiegelung reist MIT ihrer Bestaetigungsfrage (G-04-3a): unter
        # '> datei' als Teil des Prompts, sonst gruen ueber die Ausgabenaht
        # unmittelbar davor (G-04-4d). Den Kanal waehlt Join-PromptContext.
        Add-PromptContext -Severity 'OK' -Line @(
            ('    Aufgelöst auf: {0}' -f $anzeige)
            ('    SID           : {0}' -f [string] $sid.Value)
        )

        if (Read-YesNoAnswer -Prompt '    Ist das die gemeinte Gruppe?' -Default $true) {

            # Die naechste Frage steht abgesetzt (G-04-4d) -- in beiden
            # Kanaelen, und nie doppelt: Add-PromptContext legt keine zweite
            # Leerzeile hinter eine erste.
            Add-PromptContext -Line @('')

            return [pscustomobject] @{
                InputValue  = $eingabe
                Sid         = $sid
                DisplayName = $anzeige
            }
        }
    }
}

function Get-TrusteeDisplayName {
    <#
    .SYNOPSIS
        Der Anzeigename zu einer SID, sonst die SID selbst. Intern zur
        Interaktionsschicht.

    .DESCRIPTION
        REINER ANZEIGEFALL. Der Name verlaesst diese Schicht nie in Richtung
        Schreibpfad; dort reist ausschliesslich das SecurityIdentifier.

        Scheitert die Rueckwaertsuebersetzung, erscheint die SID selbst. Eine
        nicht uebersetzbare SID ist an dieser Stelle kein Abbruchgrund -- die
        Aufloesung hat bereits bewiesen, dass der Prinzipal existiert.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Sid
    )

    try {
        return [string] $Sid.Translate([System.Security.Principal.NTAccount]).Value
    }
    catch {
        return [string] $Sid.Value
    }
}

function Read-TrusteeRole {
    <#
    .SYNOPSIS
        Erhebt eine Gruppenrolle GENAU EINMAL je Produkt (IDENT-06, G-04-4a).

    .DESCRIPTION
        Drei Stufen:
        1. Die Rolle ist in diesem Produkt schon erhoben: sie wird unveraendert
           wiederverwendet.
        2. Das Produkt ist DEM und FSLogix fuehrt die Rolle: der Dialog bietet
           die FSLogix-Wahl mit ihrem Anzeigenamen an, Vorgabe ja. Bei Ja wird
           derselbe Datensatz uebernommen -- ohne zweite Aufloesung. Nie
           stillschweigend: der Operator sieht, was er uebernimmt.
        3. Sonst, auch nach einem Nein: die Rollenfrage ueber
           Read-TrusteeGroup.
        Nach Stufe 2 und 3 steht vor der naechsten Frage genau eine Leerzeile
        (G-04-4d); Add-PromptContext legt keine zweite hinter eine erste.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer', 'Helpdesk')]
        [string] $Role,

        [Parameter(Mandatory)]
        [ValidateSet('FSLogix', 'DEM')]
        [string] $Product,

        # Nur Weg 1: nach der erhobenen Gruppe "Weitere ... hinzufuegen?"
        # (Read-AdditionalTrusteeGroup). Nie fuer die Helpdesk-Rolle.
        [Parameter()]
        [switch] $OfferAdditional
    )

    $speicher = $script:TrusteeRolle[$Product]

    if ($speicher.ContainsKey($Role)) { return $speicher[$Role] }

    if (($Product -eq 'DEM') -and $script:TrusteeRolle['FSLogix'].ContainsKey($Role)) {

        # Das Angebot nennt alle Gruppen der Rolle und uebernimmt alle.
        $fslogix = $script:TrusteeRolle['FSLogix'][$Role]
        $weitere = @(Get-TrusteeRoleAdditional -Product 'FSLogix' -Role $Role)
        $namen = @(@($fslogix) + $weitere | ForEach-Object { [string] $_.DisplayName }) -join ', '
        $frage = '{0}: dieselbe wie bei FSLogix ({1})?' -f (Get-TrusteeRoleLabel -Role $Role), $namen

        if (Read-YesNoAnswer -Prompt $frage -Default $true) {
            $speicher[$Role] = $fslogix
            if ($weitere.Count -gt 0) { $script:TrusteeZusatz['DEM'][$Role] = $weitere }
            Add-PromptContext -Line @('')
            return $fslogix
        }
    }

    $wert = Read-TrusteeGroup -Prompt (Get-TrusteeRolePrompt -Role $Role)

    $speicher[$Role] = $wert

    if ($OfferAdditional -and ($Role -ne 'Helpdesk')) {
        Read-AdditionalTrusteeGroup -Product $Product -Role $Role
    }
    else {
        Add-PromptContext -Line @('')
    }

    return $wert
}

function Get-TrusteeRolePrompt {
    <#
    .SYNOPSIS
        Der Fragetext je Rolle. Intern zur Interaktionsschicht.

    .DESCRIPTION
        Die vier Gruppen dieser Umgebung stehen als Testdaten in
        Tests/Assert-DomainGroupProvisioning.ps1 und ausdruecklich NICHT hier:
        die Dialogschicht bleibt generisch und fragt. Ein Vorgabewert waere eine
        Umgebungsannahme an genau der Stelle, die das Werkzeug allgemein haelt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'User', 'Computer', 'Helpdesk')]
        [string] $Role
    )

    return '{0} (Domäne\Gruppe, UPN oder SID)' -f (Get-TrusteeRoleLabel -Role $Role)
}

function Read-HelpdeskGroup {
    <#
    .SYNOPSIS
        IDENT-05: klaert die Helpdesk-Gruppe -- genau einmal je Lauf, im
        DEM-Block.

    .DESCRIPTION
        Die Helpdesk-Gruppe gehoert ausschliesslich zu DEM; gearbeitet wird
        deshalb nur im DEM-Rollenspeicher (G-04-4a). Die Abkuerzung bezieht
        sich auf die Gruppe der Administratoren DES DEM-BLOCKS.

        Die Reihenfolge der Fragen ist herstellerbegruendet und nicht
        beliebig (G-04-5a, Projektinhaber 2026-09-22):

        1. "Helpdesk-Gruppe eintragen? (optional, fuer das DEM Helpdesk
           Support Tool)" mit Vorgabe NEIN. Die Frage sagt selbst, dass die
           Gruppe optional ist und wozu sie dient; wer das Werkzeug nicht
           einsetzt, kommt mit Enter weiter. Die fruehere Frage
           "Ueberspringen?" entfaellt -- sie war die verneinte Form derselben
           Wahl und stand erst an zweiter Stelle.
        2. Bei Ja: "Dieselbe wie die Gruppe der Administratoren?" mit Vorgabe
           JA. Das ist der haeufigste Fall und spart eine weitere
           Gruppenabfrage.
        3. Bei Nein darauf: die eigene Gruppenabfrage.

        WARUM UEBERSPRINGEN UEBERHAUPT GEHT: die Helpdesk-Gruppe kommt in
        KEINEM ACL-Template vor -- der Hersteller deckt Verwaltung und Helpdesk
        auf NTFS mit dem einen Eintrag der Gruppe der Administratoren ab. Sie ist
        ausschliesslich ein Treuhaender im Share-Template von DEMProfiles und
        dort herstellerseitig als optional gefuehrt: "Helpdesk staff using the
        optional Helpdesk Support Tool" (FEATURES.md Paragraph 1.3).

        WIRD SIE NICHT EINGETRAGEN, BLEIBT <HelpdeskGroup> UNGEBUNDEN UND DIE
        OPTIONSGRUPPE Helpdesk UNGEWAEHLT -- beides zusammen. Nur eines von
        beiden liesse ConvertTo-ShareDesired ueber dem ungebundenen Token
        werfen.

    .OUTPUTS
        [bool] -- wahr, wenn eine Helpdesk-Gruppe gebunden wurde.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Nur Weg 1, siehe Read-TrusteeRole.
        [Parameter()]
        [switch] $OfferAdditional
    )

    if ($script:HelpdeskGeklaert) { return (Test-HelpdeskBound) }

    $script:HelpdeskGeklaert = $true

    $dem = $script:TrusteeRolle['DEM']

    # Die Gruppe der Administratoren des DEM-Blocks wird hier erhoben, falls
    # sie noch fehlt -- samt Angebot aus FSLogix: ohne sie laesst sich die
    # erste Frage gar nicht beantworten. Die Helpdesk-Gruppe uebernimmt davon
    # nur die erste Gruppe.
    $administratoren = Read-TrusteeRole -Role 'Admin' -Product 'DEM' -OfferAdditional:$OfferAdditional

    # Nach jedem Ausgang genau eine Leerzeile vor der naechsten Frage (G-04-4d).
    # Vorgabe NEIN (G-04-5a): die Gruppe ist herstellerseitig optional.
    if (-not (Read-YesNoAnswer -Prompt 'Helpdesk-Gruppe eintragen? (optional, für das DEM Helpdesk Support Tool)' -Default $false)) {
        Add-PromptContext -Line @('')
        return $false
    }

    # Die Gruppe steht in der Frage, wie beim Angebot aus FSLogix (G-04-4b).
    $frage = 'Helpdesk-Gruppe: dieselbe wie die Gruppe der Administratoren ({0})?' -f [string] $administratoren.DisplayName

    if (Read-YesNoAnswer -Prompt $frage -Default $true) {
        $dem['Helpdesk'] = $administratoren
        Add-PromptContext -Line @('')
        return $true
    }

    $dem['Helpdesk'] = Read-TrusteeGroup -Prompt (Get-TrusteeRolePrompt -Role 'Helpdesk')
    Add-PromptContext -Line @('')

    return $true
}

function Set-HelpdeskResolution {
    <#
    .SYNOPSIS
        Klaert die Helpdesk-Frage ohne Dialog -- mit oder ohne gebundene Gruppe
        (Phase 5, D-13).

    .DESCRIPTION
        Die Bestandspruefung liest die Helpdesk-Gruppe an der DEMProfiles-
        Freigabe ab. Ist sie bestaetigt, kommt der Datensatz in den
        DEM-Rollenspeicher; ist dort keine, gilt die Frage als geklaert und
        die Gruppe als nicht gebunden -- das Soll ist dann
        herstellerwoertlich ohne Helpdesk.

        Test-HelpdeskBound und Get-FixedOptGroup lesen danach unveraendert
        dasselbe EINE Merkmal (IDENT-05); Read-HelpdeskGroup fragt nicht
        mehr.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Record = $null
    )

    $script:HelpdeskGeklaert = $true

    if ($null -ne $Record) { $script:TrusteeRolle['DEM']['Helpdesk'] = $Record }
}

function Test-HelpdeskBound {
    <#
    .SYNOPSIS
        Wahr, wenn in diesem Lauf eine Helpdesk-Gruppe gebunden wurde.

    .DESCRIPTION
        GENAU EINE WAHRHEIT ueber diesen Zustand. Die Optionsgruppe Helpdesk des
        Share-Templates und die Bindung von <HelpdeskGroup> muessen zusammen
        gewaehlt oder zusammen weggelassen werden; zwei getrennte Merkmale
        driften auseinander, und ConvertTo-ShareDesired wuerfe dann ueber dem
        ungebundenen Token.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return [bool] $script:TrusteeRolle['DEM'].ContainsKey('Helpdesk')
}

function Get-TokenRoleMap {
    <#
    .SYNOPSIS
        Die Zuordnung Platzhalter-Token -> Gruppenrolle. Intern zur
        Interaktionsschicht.

    .DESCRIPTION
        GENAU EINE WAHRHEIT ueber diese Zuordnung. Eine zweite Tabelle -- etwa
        je Ordnerart -- drifted gegen die Templatedateien, und der Binder wuerfe
        dann ueber einem ungebundenen Token.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        '<AdminGroup>'    = 'Admin'
        '<UserGroup>'     = 'User'
        '<ComputerGroup>' = 'Computer'
        '<HelpdeskGroup>' = 'Helpdesk'
    }
}

function Get-RequiredTrusteeToken {
    <#
    .SYNOPSIS
        Welche Platzhalter-Token eine Ordnerart unter der gegebenen
        Opt-in-Belegung tatsaechlich braucht. Intern zu Read-GroupBinding.

    .DESCRIPTION
        ABGELESEN AUS DEN TEMPLATES, NICHT AUS EINER LISTE IM DIALOG. Der
        Platzhalterkommentar im Kopf von AclTemplates.psd1 zaehlt ERLAUBTE
        Token auf, nicht benutzte; nur die Eintraege selbst sagen, was gebraucht
        wird. Eine zweite Liste im Dialog drifted gegen die Templates, und der
        Binder wuerfe dann ueber einem ungebundenen Token -- oder, schlimmer,
        der Dialog fragte nach einer Gruppe, die nirgends vorkommt.

        Ein abgewaehlter optionaler Eintrag braucht seine Bindung NICHT: ein
        Lauf ohne Helpdesk-Werkzeug soll keine Helpdeskgruppe brauchen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $AclOptGroup = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $ShareOptGroup = @()
    )

    $acl = @($AclOptGroup)
    $share = @($ShareOptGroup)

    $token = New-Object System.Collections.Generic.List[string]

    foreach ($ace in @((Get-AclTemplate -Kind $Kind).Aces)) {

        $optional = $ace.ContainsKey('Optional') -and [bool] $ace.Optional
        $gruppe = if ($ace.ContainsKey('OptGroup')) { [string] $ace.OptGroup } else { '' }

        if ($optional -and ($acl -notcontains $gruppe)) { continue }

        $trustee = [string] $ace.Trustee

        if (-not $trustee.StartsWith('<', [System.StringComparison]::Ordinal)) { continue }
        if ($token.Contains($trustee)) { continue }

        $token.Add($trustee)
    }

    foreach ($eintrag in @((Get-ShareTemplate -Kind $Kind).Entries)) {

        $gruppe = if ($eintrag.ContainsKey('OptGroup')) { [string] $eintrag.OptGroup } else { '' }

        if ((-not [string]::IsNullOrEmpty($gruppe)) -and ($share -notcontains $gruppe)) { continue }

        $trustee = [string] $eintrag.Trustee

        if (-not $trustee.StartsWith('<', [System.StringComparison]::Ordinal)) { continue }
        if ($token.Contains($trustee)) { continue }

        $token.Add($trustee)
    }

    return $token.ToArray()
}

function Read-GroupBinding {
    <#
    .SYNOPSIS
        Die Gruppenbindung einer Ordnerart -- erhoben, soweit noch nicht
        vorhanden.

    .DESCRIPTION
        Die Rueckgabe hat genau die Form, die Expand-AclTemplate und
        ConvertTo-ShareDesired erwarten: Token auf SecurityIdentifier. Ein Name
        steht dort nie.

        Das Produkt leitet sich aus der Ordnerart ab (G-04-4a); gebunden wird
        aus dem Rollenspeicher dieses Produkts.

    .OUTPUTS
        [hashtable] Token -> SecurityIdentifier.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FSLogix-Profiles', 'FSLogix-Redirections', 'DEMConfig', 'DEMProfiles', 'DEMComputerLogs')]
        [string] $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $AclOptGroup = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $ShareOptGroup = @(),

        # Nur Weg 1, siehe Read-TrusteeRole.
        [Parameter()]
        [switch] $OfferAdditional
    )

    $token = @(Get-RequiredTrusteeToken -Kind $Kind -AclOptGroup $AclOptGroup -ShareOptGroup $ShareOptGroup)
    $karte = Get-TokenRoleMap
    $produkt = Get-KindProduct -Kind $Kind

    $bindung = @{}

    foreach ($name in $token) {

        if (-not $karte.ContainsKey($name)) { continue }

        $rolle = [string] $karte[$name]

        # DIE HELPDESK-ROLLE WIRD HIER NIE ERFRAGT. Sie hat eine eigene
        # Fragefolge mit zwei Vorstufen (IDENT-05, G-04-5a, Read-HelpdeskGroup); eine
        # nackte Gruppenfrage an dieser Stelle uebergaehe beide und naehme dem
        # Operator die herstellerseitig vorgesehene Wahl. Ist sie ungeklaert
        # oder nicht eingetragen, bleibt das Token ungebunden -- und die
        # Optionsgruppe Helpdesk ist dann ebenfalls nicht gewaehlt, sonst wuerfe
        # ConvertTo-ShareDesired.
        if ($rolle -eq 'Helpdesk') {

            if (Test-HelpdeskBound) { $bindung[$name] = $script:TrusteeRolle['DEM']['Helpdesk'].Sid }

            continue
        }

        $null = Read-TrusteeRole -Role $rolle -Product $produkt -OfferAdditional:$OfferAdditional
        $bindung[$name] = Get-TrusteeRoleBindingValue -Product $produkt -Role $rolle
    }

    return $bindung
}
