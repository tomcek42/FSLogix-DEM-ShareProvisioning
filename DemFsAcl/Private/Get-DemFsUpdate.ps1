<#
    Aktualisierung aus der GitHub-Veroeffentlichung (Wunsch Projektinhaber
    2026-10-21).

    Beim Start fragt der Einstieg die neueste Veroeffentlichung ab, vergleicht
    sie mit der eigenen Version und bietet -- nur im Buendel -- an, sie
    herunterzuladen und zu starten. Diese Datei ist die Engine dazu: kein
    Eingabe- und kein Ausgabeaufruf, jede Funktion liefert ein Ergebnisobjekt
    (D-04, OUT-07). Gefragt und ausgegeben wird in der Orchestrierung.

    WAS DIE PRUEFSUMME LEISTET UND WAS NICHT. GitHub nennt je Release-Anhang
    eine SHA-256-Summe (Feld digest). Sie belegt, dass die Datei vollstaendig
    und unveraendert so angekommen ist, wie sie veroeffentlicht wurde. Gegen
    eine boeswillig veroeffentlichte Version hilft sie nicht -- das leistete
    erst eine Authenticode-Signatur. Ohne Pruefsumme wird nichts ausgefuehrt.

    KEINE SCHLEIFE. Ein Release, dessen Tag hoeher steht als die Version im
    Buendel, fuehrte sonst bei jedem Start zum naechsten Download. Deshalb muss
    die Version im heruntergeladenen Buendel dem Tag entsprechen, und der
    gestartete Nachfolger bekommt DEMFSACL_KEIN_UPDATE=1 mit.

    Unter Windows PowerShell 5.1 ist TLS 1.2 nicht auf jedem Server
    voreingestellt; github.com nimmt nichts Aelteres an.
#>

$script:UpdateQuelle = 'tomcek42/FSLogix-DEM-ShareProvisioning'
$script:UpdateAnhang = 'FSLogix-DEM-ShareProvisioning.ps1'

function ConvertTo-DemFsVersion {
    <#
    .SYNOPSIS
        Liest "v1.0", "1.0" oder "1.0.0" als dreistellige Version; $null, wenn
        der Text keine Version ist.

    .DESCRIPTION
        Dreistellig aufgefuellt, weil [version]'1.0' kleiner ist als
        [version]'1.0.0' -- der Tag v1.0 erschiene sonst aelter als die
        Modulversion 1.0.0.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $treffer = [regex]::Match($Text.Trim(), '^[vV]?(\d+)\.(\d+)(?:\.(\d+))?$')

    if (-not $treffer.Success) { return $null }

    $build = 0
    if ($treffer.Groups[3].Success) { $build = [int] $treffer.Groups[3].Value }

    return [version]::new([int] $treffer.Groups[1].Value, [int] $treffer.Groups[2].Value, $build)
}

function Get-DemFsVersion {
    <#
    .SYNOPSIS
        Die eigene Version: im Buendel aus dem Vorlauf, sonst aus dem Manifest.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param()

    $buendel = Get-Variable -Name BuendelVersion -Scope Script -ValueOnly -ErrorAction SilentlyContinue

    if ($null -ne $buendel) { return (ConvertTo-DemFsVersion -Text ([string] $buendel)) }

    $modul = $MyInvocation.MyCommand.Module

    if ($null -eq $modul) { return $null }

    return (ConvertTo-DemFsVersion -Text ([string] $modul.Version))
}

function Test-DemFsBundle {
    <#
    .SYNOPSIS
        Wahr, wenn das Werkzeug als Einzeldatei-Buendel laeuft.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $buendel = Get-Variable -Name BuendelVersion -Scope Script -ValueOnly -ErrorAction SilentlyContinue

    return ($null -ne $buendel)
}

function Enable-DemFsTls12 {
    <#
    .SYNOPSIS
        Nimmt TLS 1.2 in die Protokolle des Prozesses auf.
    #>
    [CmdletBinding()]
    param()

    $tls12 = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
}

function Get-DemFsLatestRelease {
    <#
    .SYNOPSIS
        Fragt die neueste Veroeffentlichung ab: Version, Download-Adresse und
        SHA-256 des Buendels.

    .DESCRIPTION
        Wirft nie. Ohne Netz, bei Zeitueberschreitung oder unerwarteter Antwort
        ist Success falsch und Reason nennt den Grund -- der Start darf an der
        Pruefung nicht scheitern, Fileserver haben oft kein Internet.

    .OUTPUTS
        [pscustomobject] mit Success, Reason, Version, Tag, Url, AssetUrl,
        Sha256.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [int] $TimeoutSec = 5
    )

    $ergebnis = [pscustomobject] @{
        Success  = $false
        Reason   = ''
        Version  = $null
        Tag      = ''
        Url      = ''
        AssetUrl = ''
        Sha256   = ''
    }

    $adresse = 'https://api.github.com/repos/{0}/releases/latest' -f $script:UpdateQuelle

    try {
        Enable-DemFsTls12
        $antwort = Invoke-RestMethod -Uri $adresse -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    catch {
        $ergebnis.Reason = ([string] $_.Exception.Message).Trim()
        return $ergebnis
    }

    $tag = [string] $antwort.tag_name
    $version = ConvertTo-DemFsVersion -Text $tag

    if ($null -eq $version) {
        $ergebnis.Reason = 'Die Veröffentlichung trägt keine lesbare Versionsnummer ({0}).' -f $tag
        return $ergebnis
    }

    $anhang = @(@($antwort.assets) | Where-Object {
            ($null -ne $_) -and [string]::Equals([string] $_.name, $script:UpdateAnhang, [System.StringComparison]::Ordinal)
        })

    if ($anhang.Count -ne 1) {
        $ergebnis.Reason = 'Die Veröffentlichung {0} enthält die Datei {1} nicht.' -f $tag, $script:UpdateAnhang
        return $ergebnis
    }

    $summe = ''
    if ($null -ne $anhang[0].PSObject.Properties['digest']) {
        $digest = [regex]::Match([string] $anhang[0].digest, '^sha256:([0-9a-fA-F]{64})$')
        if ($digest.Success) { $summe = $digest.Groups[1].Value.ToLowerInvariant() }
    }

    $ergebnis.Success = $true
    $ergebnis.Version = $version
    $ergebnis.Tag = $tag
    $ergebnis.Url = [string] $antwort.html_url
    $ergebnis.AssetUrl = [string] $anhang[0].browser_download_url
    $ergebnis.Sha256 = $summe

    return $ergebnis
}

function Save-DemFsUpdate {
    <#
    .SYNOPSIS
        Laedt das Buendel der Veroeffentlichung, prueft es und ersetzt damit
        das laufende Skript; die bisherige Datei bleibt als Sicherung liegen.

    .DESCRIPTION
        Reihenfolge: in einen eigenen temporaeren Ordner laden, SHA-256 gegen
        die Veroeffentlichung, fehlerfrei parsen, Version im Buendel gleich der
        Veroeffentlichung. Erst danach wird die laufende Datei angefasst: sie
        wird als <Name>.<Version>.bak.ps1 kopiert und dann ueberschrieben.
        Schlaegt ein Schritt fehl, bleibt die laufende Datei unveraendert.
        Windows PowerShell hat das laufende Skript beim Start vollstaendig
        gelesen; das Ueberschreiben stoert den laufenden Prozess nicht.

    .OUTPUTS
        [pscustomobject] mit Success, Reason, Path, BackupPath.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Release,

        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [Parameter(Mandatory)]
        [version] $CurrentVersion
    )

    $ergebnis = [pscustomobject] @{
        Success    = $false
        Reason     = ''
        Path       = $ScriptPath
        BackupPath = ''
    }

    if ([string]::IsNullOrEmpty([string] $Release.Sha256)) {
        $ergebnis.Reason = 'Die Veröffentlichung nennt keine SHA-256-Prüfsumme; ungeprüft wird nichts ausgeführt.'
        return $ergebnis
    }

    $ordner = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'DemFsAcl-' + [guid]::NewGuid().ToString('N'))
    $neu = [System.IO.Path]::Combine($ordner, $script:UpdateAnhang)

    try {
        $null = [System.IO.Directory]::CreateDirectory($ordner)

        try {
            Enable-DemFsTls12
            # Die Fortschrittsanzeige bremst Invoke-WebRequest unter 5.1 um ein Vielfaches.
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri ([string] $Release.AssetUrl) -OutFile $neu -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        }
        catch {
            $ergebnis.Reason = 'Download fehlgeschlagen: {0}' -f ([string] $_.Exception.Message).Trim()
            return $ergebnis
        }

        # Ueber .NET statt Get-FileHash: das Cmdlet fehlt, wenn der Modulpfad
        # Microsoft.PowerShell.Utility 7.0 vorschiebt (gemessen 2026-10-21).
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.IO.File]::ReadAllBytes($neu)
            $summe = -join @($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
        }
        finally {
            $sha.Dispose()
        }

        if (-not [string]::Equals($summe, [string] $Release.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            $ergebnis.Reason = 'Die Prüfsumme der heruntergeladenen Datei stimmt nicht mit der Veröffentlichung überein.'
            return $ergebnis
        }

        $marken = $null
        $fehler = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($neu, [ref] $marken, [ref] $fehler)

        if (@($fehler).Count -gt 0) {
            $ergebnis.Reason = 'Die heruntergeladene Datei ist kein gültiges Skript ({0} Parsefehler).' -f @($fehler).Count
            return $ergebnis
        }

        $text = [System.IO.File]::ReadAllText($neu, [System.Text.UTF8Encoding]::new($false))
        $kennung = [regex]::Match($text, "(?m)^\`$script:BuendelVersion = '([0-9.]+)'")
        $geladen = $null
        if ($kennung.Success) { $geladen = ConvertTo-DemFsVersion -Text $kennung.Groups[1].Value }

        if (($null -eq $geladen) -or ($geladen -ne $Release.Version)) {
            $ergebnis.Reason = 'Die heruntergeladene Datei trägt nicht die Version {0}.' -f $Release.Version
            return $ergebnis
        }

        $verzeichnis = [System.IO.Path]::GetDirectoryName($ScriptPath)
        $stamm = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
        $sicherung = [System.IO.Path]::Combine($verzeichnis, ('{0}.{1}.bak.ps1' -f $stamm, $CurrentVersion))

        try {
            [System.IO.File]::Copy($ScriptPath, $sicherung, $true)
            [System.IO.File]::Copy($neu, $ScriptPath, $true)
        }
        catch {
            $ergebnis.Reason = 'Die Datei konnte nicht ersetzt werden: {0}' -f ([string] $_.Exception.Message).Trim()
            return $ergebnis
        }

        $ergebnis.Success = $true
        $ergebnis.BackupPath = $sicherung
        return $ergebnis
    }
    finally {
        # Datei und Ordner einzeln, nicht rekursiv: ACL-07 verbietet -Recurse im
        # ganzen Modul, und der Ordner enthaelt nur diese eine Datei.
        try {
            if ([System.IO.File]::Exists($neu)) { [System.IO.File]::Delete($neu) }
            if ([System.IO.Directory]::Exists($ordner)) { [System.IO.Directory]::Delete($ordner, $false) }
        }
        catch {
            $null = $_
        }
    }
}

function Start-DemFsUpdatedScript {
    <#
    .SYNOPSIS
        Startet das aktualisierte Skript im selben Konsolenfenster und liefert
        seinen Rueckgabewert.

    .DESCRIPTION
        Ueber System.Diagnostics.Process ohne Umleitung: der Nachfolger erbt
        Konsole und Standardkanaele. Ein Aufruf per & lieferte seine Ausgabe in
        die Pipeline dieser Funktion, und der Nachfolger hielte die Ausgabe fuer
        umgeleitet (D-14). DEMFSACL_KEIN_UPDATE=1 gilt nur fuer den Nachfolger.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath
    )

    $angaben = [System.Diagnostics.ProcessStartInfo]::new()
    $angaben.FileName = [System.IO.Path]::Combine(
        [System.Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    $angaben.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
    $angaben.UseShellExecute = $false
    $angaben.EnvironmentVariables['DEMFSACL_KEIN_UPDATE'] = '1'

    $prozess = [System.Diagnostics.Process]::Start($angaben)
    $prozess.WaitForExit()

    return [int] $prozess.ExitCode
}
