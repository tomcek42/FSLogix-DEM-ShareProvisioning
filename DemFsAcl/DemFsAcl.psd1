#
# Modulmanifest für das Modul "DemFsAcl"
#

@{

# Die diesem Manifest zugeordnete Skript- oder Binärmoduldatei.
RootModule = 'DemFsAcl.psm1'

# Die Versionsnummer dieses Moduls
ModuleVersion = '1.1.1'

# Unterstützte PSEditions
# CompatiblePSEditions = @()

# ID zur eindeutigen Kennzeichnung dieses Moduls
GUID = '2329895b-43e2-4789-8799-6906f81ffb4a'

# Autor dieses Moduls
Author = 'tomcek42'

# Company or vendor of this module
CompanyName = 'Unknown'

# Urheberrechtserklärung für dieses Modul
Copyright = '(c) 2026 tomcek42. Released under the MIT License.'

# Beschreibung der von diesem Modul bereitgestellten Funktionen
Description = 'Creates the folder structure for FSLogix profile containers and Omnissa DEM, sets the NTFS permissions according to the vendor documentation and creates the SMB shares. Not affiliated with Microsoft or Omnissa.'

# Die für dieses Modul mindestens erforderliche Version des Windows PowerShell-Moduls
PowerShellVersion = '5.1'

# Der Name des für dieses Modul erforderlichen Windows PowerShell-Hosts
# PowerShellHostName = ''

# Die für dieses Modul mindestens erforderliche Version des Windows PowerShell-Hosts
# PowerShellHostVersion = ''

# Die für dieses Modul mindestens erforderliche Microsoft .NET Framework-Version. Diese erforderliche Komponente ist nur für die PowerShell Desktop-Edition gültig.
# DotNetFrameworkVersion = ''

# Die für dieses Modul mindestens erforderliche Version der CLR (Common Language Runtime). Diese erforderliche Komponente ist nur für die PowerShell Desktop-Edition gültig.
# CLRVersion = ''

# Die für dieses Modul erforderliche Prozessorarchitektur ("Keine", "X86", "Amd64").
# ProcessorArchitecture = ''

# Die Module, die vor dem Importieren dieses Moduls in die globale Umgebung geladen werden müssen
# RequiredModules = @()

# Die Assemblys, die vor dem Importieren dieses Moduls geladen werden müssen
# RequiredAssemblies = @()

# Die Skriptdateien (PS1-Dateien), die vor dem Importieren dieses Moduls in der Umgebung des Aufrufers ausgeführt werden.
# ScriptsToProcess = @()

# Die Typdateien (.ps1xml), die beim Importieren dieses Moduls geladen werden sollen
# TypesToProcess = @()

# Die Formatdateien (.ps1xml), die beim Importieren dieses Moduls geladen werden sollen
# FormatsToProcess = @()

# Die Module, die als geschachtelte Module des in "RootModule/ModuleToProcess" angegebenen Moduls importiert werden sollen.
# NestedModules = @()

# Aus diesem Modul zu exportierende Funktionen. Um optimale Leistung zu erzielen, verwenden Sie keine Platzhalter und löschen den Eintrag nicht. Verwenden Sie ein leeres Array, wenn keine zu exportierenden Funktionen vorhanden sind.
# Genau drei Ausfuhren (D-02). Die sieben Engines -- Test-ProvisioningPreflight,
# Invoke-AclApply, Invoke-ShareApply, Expand-AclTemplate, Resolve-TrusteeSid,
# Set-DirectoryAcl und Get-ActualAceSet -- bleiben privat. Damit kommt von
# aussen niemand an Invoke-AclApply vorbei am Preflight; die Zusage "eine
# Lesestelle, eine Schreibstelle" ist strukturell geschuetzt statt nur
# vereinbart. Eng anfangen ist Absicht: eine Ausfuhr zurueckzunehmen bricht
# jeden Aufrufer, der sie schon nutzt -- hinzuzufuegen ist jederzeit billig.
FunctionsToExport = @('Get-AclTemplate', 'Get-ShareTemplate', 'Invoke-DemFsProvisioning')

# Aus diesem Modul zu exportierende Cmdlets. Um optimale Leistung zu erzielen, verwenden Sie keine Platzhalter und löschen den Eintrag nicht. Verwenden Sie ein leeres Array, wenn keine zu exportierenden Cmdlets vorhanden sind.
CmdletsToExport = @()

# Die aus diesem Modul zu exportierenden Variablen.
# New-ModuleManifest kommentiert dieses Feld auch bei -VariablesToExport @()
# aus. Ein auskommentiertes Feld ist keine Aussage -- deshalb von Hand gesetzt.
VariablesToExport = @()

# Aus diesem Modul zu exportierende Aliase. Um optimale Leistung zu erzielen, verwenden Sie keine Platzhalter und löschen den Eintrag nicht. Verwenden Sie ein leeres Array, wenn keine zu exportierenden Aliase vorhanden sind.
AliasesToExport = @()

# Aus diesem Modul zu exportierende DSC-Ressourcen
# DscResourcesToExport = @()

# Liste aller Module in diesem Modulpaket
# ModuleList = @()

# Liste aller Dateien in diesem Modulpaket
# FileList = @()

# Die privaten Daten, die an das in "RootModule/ModuleToProcess" angegebene Modul übergeben werden sollen. Diese können auch eine PSData-Hashtabelle mit zusätzlichen von PowerShell verwendeten Modulmetadaten enthalten.
PrivateData = @{

    PSData = @{

        # 'Tags' wurde auf das Modul angewendet und unterstützt die Modulermittlung in Onlinekatalogen.
        # Tags = @()

        # Eine URL zur Lizenz für dieses Modul.
        LicenseUri = 'https://github.com/tomcek42/FSLogix-DEM-ShareProvisioning/blob/main/LICENSE'

        # Eine URL zur Hauptwebsite für dieses Projekt.
        ProjectUri = 'https://github.com/tomcek42/FSLogix-DEM-ShareProvisioning'

        # Eine URL zu einem Symbol, das das Modul darstellt.
        # IconUri = ''

        # 'ReleaseNotes' des Moduls
        # ReleaseNotes = ''

    } # Ende der PSData-Hashtabelle

} # Ende der PrivateData-Hashtabelle

# HelpInfo-URI dieses Moduls
# HelpInfoURI = ''

# Standardpräfix für Befehle, die aus diesem Modul exportiert werden. Das Standardpräfix kann mit "Import-Module -Prefix" überschrieben werden.
# DefaultCommandPrefix = ''

}

