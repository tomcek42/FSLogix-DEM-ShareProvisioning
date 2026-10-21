<#
    Die sechs vordefinierten Prinzipale als Literal-SID-Zeichenketten.

    Warum Literale und nicht [System.Security.Principal.WellKnownSidType]:
    die Enumeration ist eine Zweimodus-API. Die sechs absoluten Werte lassen
    sich mit domainSid = $null bilden, die drei domänenrelativen
    (AccountDomainUsersSid, AccountDomainAdminsSid, AccountComputersSid)
    werfen dabei nachweislich eine ArgumentNullException. Literale sind
    außerdem gegen die Microsoft-SID-Tabelle direkt diffbar.

    Die Werte werden NICHT zur Ladezeit über eine Namensauflösung ermittelt.
    Ein namensbasierter Aufbau funktioniert auf einer englischen
    Entwicklungsmaschine und scheitert auf dem deutschen Zielserver -- genau
    der Fehler, den dieses Werkzeug beseitigen soll (IDENT-01, C-03).

    Die Schlüsselnamen sind bindend und kein Stilthema: Hashtable-Schlüssel
    tauchen im AST als Zeichenkettenliterale auf. Ein Schlüssel mit dem
    englischen Prinzipalnamen erzeugte in der IDENT-08-Prüfung von Plan 05
    einen Fehlalarm, den man dann per Ausnahme entschärfen müsste -- und eine
    wachsende Ausnahmeliste in einem Sicherheitsgate ist der Anfang vom Ende.
    Die deutschen Entsprechungen stehen deshalb als Kommentar daneben;
    Kommentare sind im AST unsichtbar.
#>

$script:WellKnownSid = @{
    WorldEveryone      = 'S-1-1-0'        # de: Jeder
    CreatorOwner       = 'S-1-3-0'        # de: ERSTELLER-BESITZER
    AuthenticatedUsers = 'S-1-5-11'       # de: Authentifizierte Benutzer
    System             = 'S-1-5-18'       # de: NT-AUTORITÄT\SYSTEM
    BuiltinAdmins      = 'S-1-5-32-544'   # de: VORDEFINIERT\Administratoren
    BuiltinUsers       = 'S-1-5-32-545'   # de: VORDEFINIERT\Benutzer
}

function Get-WellKnownSid {
    <#
    .SYNOPSIS
        Löst ein Trustee-Token der Form WellKnown:<Schluessel> zu einem
        SecurityIdentifier auf.

    .DESCRIPTION
        Schlägt ausschließlich in $script:WellKnownSid nach. Konstruiert
        niemals einen Prinzipalnamen und ruft niemals .Translate() auf --
        der Schreibpfad dieses Werkzeugs kennt nur SIDs (IDENT-01, IDENT-02,
        C-03).

        Ein unbekanntes Token führt zu einer ArgumentException. Geprüft wird
        im Testcode grundsätzlich der Ausnahmetyp und nicht der
        Ausnahmetext -- die Meldungen der .NET-Laufzeit kommen auf einem
        deutschen Server deutsch zurück.

    .EXAMPLE
        Get-WellKnownSid -Token 'WellKnown:CreatorOwner'
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Principal.SecurityIdentifier])]
    param(
        [Parameter(Mandatory)]
        [string] $Token
    )

    $praefix = 'WellKnown:'

    if (-not $Token.StartsWith($praefix, [System.StringComparison]::Ordinal)) {
        throw [System.ArgumentException]::new(
            ('Das Token "{0}" trägt nicht das Präfix "{1}".' -f $Token, $praefix))
    }

    $schluessel = $Token.Substring($praefix.Length)

    if (-not $script:WellKnownSid.ContainsKey($schluessel)) {
        throw [System.ArgumentException]::new(
            ('Das Token "{0}" bezeichnet keinen der sechs vordefinierten Prinzipale.' -f $Token))
    }

    return [System.Security.Principal.SecurityIdentifier]::new($script:WellKnownSid[$schluessel])
}
