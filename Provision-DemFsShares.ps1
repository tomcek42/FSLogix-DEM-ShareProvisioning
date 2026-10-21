#Requires -Version 5.1
<#
.SYNOPSIS
    Der Einstieg des Werkzeugs: laedt das Modul und fuehrt den Dialog (D-01).

.DESCRIPTION
    Das Skript nimmt KEINE Parameter, auch keine optionalen. Damit entfaellt
    jede Frage nach der Argumentweitergabe zwischen den Schalen, und derselbe
    Aufruf ist unter PowerShell 7 wie unter Git Bash unveraendert gueltig.

    Es setzt zuerst PSModulePath neu zusammen -- dieselbe Massnahme wie in
    Tests/Invoke-Tests.ps1 und Tests/Show-TemplateSummary.ps1. Der
    Benutzermodulordner steht bewusst mit in der Liste: weder die Machine- noch
    die User-Umgebungsvariable fuehrt ihn, und Get-AclTemplate haengt ueber
    Import-PowerShellDataFile genau daran. Muss vor dem ersten Cmdlet-Aufruf
    stehen, deshalb ausschliesslich .NET und Intrinsics.

    Nach dem Banner fragt der Dialog nach dem Weg (D-01):
      Weg 1 -- Ablagen neu einrichten: Ordner, NTFS-ACL, Freigabe anlegen.
      Weg 2 -- Bestehende Struktur pruefen: ein Wurzelverzeichnis einlesen,
               die gewaehlten Ordner auf NTFS-ACL, Freigabe, Offline-Caching
               und Besitzer pruefen und berichten. Abweichende Ziele lassen
               sich danach -- nur auf Nachfrage, Vorgabe nein -- ueber
               denselben Schreibpfad wie Weg 1 angleichen.
      Weg 3 -- NTFS-Berechtigungen anpassen: Gruppen hinzufuegen, ersetzen
               oder entfernen.
    Nach jedem Durchlauf kehrt der Dialog ins Hauptmenue zurueck; 0 beendet.

    Der Rueckgabewert kommt aus dem Feld ExitCode des Laufs (D-16): 0 nur bei
    durchweg OK, 1 bei Warnungen, 2 bei Fehlern, 3 bei verweigerter
    Bestaetigung. Bei mehreren Durchlaeufen gilt der hoechste Wert. Damit ist das Werkzeug ohne Aenderung skriptbar, und eine
    Warnung -- oft ein Sicherheitsbefund -- geht nicht als Erfolg durch.

    Im Pruefweg (D-17): 0 Soll erfuellt (nicht gewaehlte Ordner und ein
    abweichender Besitzer zaehlen nicht), 1 Warnungen, 2 Rechte-, Freigabe- oder
    Caching-Abweichung oder fehlende Erhoehung. Nach einem Angleichen gilt
    der Wert des Schreibpfads; wird das JA dort nicht getippt, gilt der Wert
    des Pruefberichts (es wurde nichts angeglichen).

.NOTES
    DER AUFRUF ERFOLGT AUSNAHMSLOS PER -File, nie per -Command. Ein Aufruf ohne
    Skriptdatei erbt den PSModulePath der aufrufenden Schale, und der
    Zuruecksetzer oben liefe damit ins Leere:

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Provision-DemFsShares.ps1

    Die Sitzung muss erhoeht sein. Ist sie es nicht, meldet PRE-01 das als
    Abbruchbefund, und es wird nichts geschrieben.
#>

# --- 1. PSModulePath zuruecksetzen -------------------------------------------
$userModuleDir = [System.IO.Path]::Combine(
    [Environment]::GetFolderPath('MyDocuments'), 'WindowsPowerShell', 'Modules')

$scopeParts = @(
    $userModuleDir
    [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
    [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
)

$env:PSModulePath = [string]::Join(';',
    [string[]] $scopeParts.Where({ -not [string]::IsNullOrWhiteSpace($_) }))

$ErrorActionPreference = 'Stop'

# --- 2. Modul laden und Dialog fuehren ---------------------------------------
try {
    Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

    $manifestPfad = [System.IO.Path]::Combine($PSScriptRoot, 'DemFsAcl', 'DemFsAcl.psd1')

    Import-Module -Name $manifestPfad -Force

    $lauf = Invoke-DemFsProvisioning -Menu

    exit ([int] $lauf.ExitCode)
}
catch {
    # Auf den Ausnahmetyp, nicht auf den Ausnahmetext: die Meldungen der
    # .NET-Laufzeit kommen auf einem de-DE-Server deutsch zurueck.
    Write-Output ('FEHLER {0}: {1}' -f $_.Exception.GetType().FullName, $_.Exception.Message)
    exit 2
}
