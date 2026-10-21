<#
    Expand-AclTemplate -- der Binder. Template plus Gruppenbindung plus Opt-in
    ergibt das DesiredAcl, das die Apply-Engine der Phase 3 unveraendert
    schreibt (SPEC-06, ACL-04).

    FORM DER BINDUNGSWERTE -- die wichtigste Entscheidung dieser Datei:
    ein [SecurityIdentifier] wird UNVERAENDERT uebernommen, eine Zeichenkette
    laeuft durch Resolve-TrusteeSid. Beides ist noetig. Resolve-TrusteeSid
    macht im SID-Zweig eine Rueckwaertsprobe ueber die LSA, die fuer eine
    Test-SID ohne erreichbaren Domaenencontroller scheitert. Naehme der Binder
    nur Zeichenketten, haenge jede Binder-Testsuite an einem DC, und die Zusage
    "reine Funktion, offline testbar" waere nicht einloesbar. Der Dialog in
    Phase 4 loest jede Gruppe ohnehin genau einmal auf, spiegelt sie mit SID und
    Anzeigename zurueck (IDENT-06) und reicht danach das SecurityIdentifier
    weiter.

    Well-Known-Token laufen immer ueber Resolve-TrusteeSid -> Get-WellKnownSid:
    ein Nachschlag in der einen Literalkarte, keine LSA-Abfrage, keine zweite
    SID-Zuordnung.

    FELDVERTRAG des ACE-Datensatzes (fuenfzehn Felder): die sechs Felder
    AccessControlType, IsInherited, Sid, Rights, Inheritance, Propagation sind
    zugleich die Leseliste von Sort-AceCanonical. DemFsAcl.psm1 setzt
    Set-StrictMode -Version Latest; fehlte eines, wuerfe die Sortierung -- oder
    jemand entschaerfte sie, und die Deny-Sperre feuerte nicht mehr. Wer eine
    der beiden Listen aendert, aendert beide.

    Zahlen und Typfelder werden an der GEBAUTEN Regel abgelesen, nicht aus dem
    angeforderten Wert: was der Konstruktor mit Synchronize und Propagation tut
    (gemessen in Tests/Fixtures/AclRoundTrip.Measured.psd1), steht damit im
    Datensatz, statt dahinter zu verschwinden.

    Kein Dateisystemzugriff, kein Laden der Templatedatei, keine Ausgabe --
    die Funktion gibt zurueck oder wirft.
#>

function Expand-AclTemplate {
    <#
    .SYNOPSIS
        Bindet ein validiertes ACL-Template an Gruppen-SIDs und Opt-in-Wahl und
        liefert das kanonisch sortierte DesiredAcl.

    .PARAMETER Template
        Ein Template aus Get-AclTemplate -- bereits schemageprueft.

    .PARAMETER Binding
        Schluessel sind Platzhalter-Token (<AdminGroup>, <UserGroup>,
        <ComputerGroup>, <HelpdeskGroup>); Werte ein SecurityIdentifier oder
        eine aufzuloesende Zeichenkette -- oder ein Feld davon: dann je Wert
        ein ACE mit denselben Rechten.

    .PARAMETER IncludeOptGroup
        Namen der Optionsgruppen, deren optionale ACEs aufgenommen werden.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Template,

        [Parameter(Mandatory)]
        [hashtable] $Binding,

        [AllowEmptyCollection()]
        [string[]] $IncludeOptGroup = @()
    )

    $kind = [string] $Template.Kind
    $templateAces = @($Template.Aces)
    $gewaehlt = @($IncludeOptGroup | Where-Object { -not [string]::IsNullOrEmpty($_) })

    # --- Opt-in-Buchfuehrung: alle vorkommenden Gruppen, in Auftrittsreihenfolge
    $gruppen = New-Object System.Collections.Generic.List[string]
    $gruppenGroesse = @{}
    foreach ($ace in $templateAces) {
        if ($ace.ContainsKey('OptGroup') -and -not [string]::IsNullOrEmpty([string] $ace.OptGroup)) {
            $name = [string] $ace.OptGroup
            if (-not $gruppen.Contains($name)) {
                $gruppen.Add($name)
                $gruppenGroesse[$name] = 0
            }
            $gruppenGroesse[$name] = $gruppenGroesse[$name] + 1
        }
    }

    # Ein Tippfehler im Opt-in-Namen darf nicht still zu fehlenden ACEs fuehren --
    # das fiele erst auf dem Fileserver auf.
    foreach ($name in $gewaehlt) {
        if (-not $gruppen.Contains($name)) {
            throw [System.ArgumentException]::new(
                ('Die Optionsgruppe "{0}" kommt im Template "{1}" nicht vor. Bekannt: {2}' -f
                    $name, $kind, ((@($gruppen) | ForEach-Object { $_ }) -join ', ')))
        }
    }

    $datensaetze = New-Object System.Collections.Generic.List[object]

    for ($k = 0; $k -lt $templateAces.Count; $k++) {
        $ace = $templateAces[$k]

        $optional = $ace.ContainsKey('Optional') -and [bool] $ace.Optional
        $optGroup = if ($ace.ContainsKey('OptGroup')) { [string] $ace.OptGroup } else { '' }

        # Abgewaehlt: ueberspringen OHNE Bindungspruefung. Ein Lauf ohne
        # Computerkonten-Einstellungen soll keine Computergruppe brauchen.
        if ($optional -and ($gewaehlt -notcontains $optGroup)) {
            continue
        }

        # --- Trustee aufloesen ------------------------------------------------
        $trustee = [string] $ace.Trustee

        if ($trustee.StartsWith('<', [System.StringComparison]::Ordinal)) {

            # Ein fehlender Bindungswert darf nie zu einem uebersprungenen ACE
            # werden -- das ist der stille Rechteverlust, gegen den das Werkzeug
            # gebaut ist.
            if (-not $Binding.ContainsKey($trustee)) {
                throw [System.InvalidOperationException]::new(
                    ('Das Platzhalter-Token {0} ist für die Ordnerart {1} nicht gebunden (ACE {2}).' -f
                        $trustee, $kind, ($k + 1)))
            }

            # Ein Feld bindet mehrere Gruppen an dieselbe Rolle (Weg 1,
            # Read-AdditionalTrusteeGroup): je SID ein ACE mit denselben Rechten.
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
                    ('Das Platzhalter-Token {0} ist für die Ordnerart {1} nicht gebunden (ACE {2}).' -f
                        $trustee, $kind, ($k + 1)))
            }
        }
        else {
            $sids = @(Resolve-TrusteeSid -InputValue $trustee)
        }

        $rights = [System.Enum]::Parse([System.Security.AccessControl.FileSystemRights], [string] $ace.Rights)
        $inheritance = [System.Enum]::Parse([System.Security.AccessControl.InheritanceFlags], [string] $ace.Inheritance)
        $propagation = [System.Enum]::Parse([System.Security.AccessControl.PropagationFlags], [string] $ace.Propagation)
        $typ = [System.Enum]::Parse([System.Security.AccessControl.AccessControlType], [string] $ace.Type)

        foreach ($sid in $sids) {

            # --- Regel bauen ----------------------------------------------------
            $regel = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $sid, $rights, $inheritance, $propagation, $typ)

            # --- Flagpaar-Politik: nur die sieben dokumentierten Kombinationen --
            $beschriftung = ConvertTo-AppliesTo -Inheritance $regel.InheritanceFlags -Propagation $regel.PropagationFlags

            if (-not $beschriftung.IsStandard) {
                throw [System.InvalidOperationException]::new(
                    ('Ordnerart {0}, ACE {1}: das Flagpaar Inheritance={2} / Propagation={3} ist keine der sieben Gilt-für-Kombinationen.' -f
                        $kind, ($k + 1), [int] $regel.InheritanceFlags, [int] $regel.PropagationFlags))
            }

            $datensaetze.Add([pscustomobject] @{
                Rule              = $regel
                Trustee           = $trustee
                Sid               = $sid
                Rights            = [int] $regel.FileSystemRights
                Inheritance       = [int] $regel.InheritanceFlags
                Propagation       = [int] $regel.PropagationFlags
                AccessControlType = $regel.AccessControlType
                IsInherited       = [bool] $regel.IsInherited
                AppliesTo         = $beschriftung.AppliesTo
                Icacls            = $beschriftung.Icacls
                Status            = [string] $ace['Status']
                Source            = [string] $ace['Source']
                Section           = [string] $ace['Section']
                Optional          = [bool] $optional
                OptGroup          = $optGroup
            })
        }
    }

    $entscheidungen = @(
        foreach ($name in $gruppen) {
            [pscustomobject] @{
                OptGroup = $name
                Included = [bool] ($gewaehlt -contains $name)
                AceCount = [int] $gruppenGroesse[$name]
            }
        }
    )

    $sortiert = @(Sort-AceCanonical -Ace $datensaetze.ToArray())

    return [pscustomobject] @{
        Kind                      = $kind
        ProtectInheritance        = [bool] $Template.ProtectInheritance
        ProtectInheritanceStatus  = [string] $Template['ProtectInheritanceStatus']
        ProtectInheritanceSource  = [string] $Template['ProtectInheritanceSource']
        ProtectInheritanceSection = [string] $Template['ProtectInheritanceSection']
        # Klammerform beim Zusammenbau: das Feld selbst ist der Vertrag.
        Aces                      = @($sortiert)
        OptDecisions              = @($entscheidungen)
    }
}
