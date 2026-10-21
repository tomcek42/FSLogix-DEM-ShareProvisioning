@{

    # =====================================================================
    #  DemFsAcl -- die Share-Templates als reine Daten.
    #
    #  Eigene Datei und kein Abschnitt in AclTemplates.psd1. Drei Gruende,
    #  jeder fuer sich ausreichend:
    #
    #  1. AclTemplates.psd1 ist das Compliance-Artefakt fuer das NTFS-Soll;
    #     ihre Git-Historie ist der Nachweis. Eine zweite, anders geformte
    #     Datenart darin verwaessert genau diese Historie.
    #  2. Die Schemata haben nichts gemeinsam. Eine ACL-Zeile traegt Rights,
    #     Inheritance, Propagation und Type; eine Share-Zeile traegt Access
    #     mit drei zulaessigen Werten und ueberhaupt keine Vererbung.
    #  3. Get-AclTemplate traegt einen Doppelvertrag (-Kind ist
    #     Nachschlagschluessel UND Sollwert der Gegenprobe). Er liesse sich
    #     nicht auf zwei Datenarten erweitern, ohne die Gegenprobe zu
    #     schwaechen, die SPEC-07 traegt.
    #
    #  Wie bei den ACL-Templates: Konstanten-Only, Kommentare sind Lesehilfe
    #  und NIE die Quelle der Wahrheit -- jeder Beleg steht als Datenfeld
    #  (Status, Source, Section). Die Datei enthaelt NIEMALS ein absichtlich
    #  fehlerhaftes Template; Negativfaelle leben ausschliesslich im Testcode.
    #
    #  Felder je Eintrag -- fuenf Pflichtfelder plus ein optionales:
    #     Trustee   Token derselben Grammatik wie bei den ACL-Templates
    #     Access    Read, Change oder Full
    #     Status    Verified oder Derived
    #     Source    URL
    #     Section   Abschnittsangabe, moeglichst mit woertlichem Zitat
    #     OptGroup  Name einer abwaehlbaren Gruppe (optional)
    #
    #  WICHTIG ZUR ABGRENZUNG: die Welt-SID erscheint hier auf SHARE-Ebene
    #  und ausschliesslich mit Change. Das Projektverbot in CLAUDE.md lautet
    #  "kein Everyone mit VOLLZUGRIFF auf NTFS" -- ein anderer Sachverhalt.
    #  Ein Share-Eintrag der Welt-SID mit Full ist trotzdem ausgeschlossen,
    #  und Test-ShareTemplateSchema weist ihn ab.
    # =====================================================================

    'FSLogix-Profiles' = @{

        Kind = 'FSLogix-Profiles'

        Entries = @(

            # Microsoft spezifiziert fuer einen gewoehnlichen Windows-Fileserver
            # KEINE Share-Berechtigung -- die FSLogix-Seite gibt Share-Rollen
            # ausschliesslich fuer Azure Files vor. Deshalb Derived und nicht
            # Verified.
            #
            # Ausdruecklich die Gruppe der authentifizierten Konten und NICHT
            # die Welt-SID: strikt enger bei null Betriebskosten. Full und
            # nicht Change, weil die Verwaltungsgruppe sonst ueber SMB weder
            # Besitz uebernehmen noch Berechtigungen aendern koennte.
            @{
                Trustee = 'WellKnown:AuthenticatedUsers'
                Access = 'Full'
                Status = 'Derived'
                Source = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
                Section = 'SMB share-level permissions -- NICHT vom Hersteller spezifiziert fuer einen gewoehnlichen Windows-Fileserver; Microsoft gibt Share-Rollen ausschliesslich fuer Azure Files an. Abgeleitet nach dem Muster "Freigabe weit, NTFS regelt" (FEATURES.md Paragraph 1.1)'
            }
        )
    }

    'FSLogix-Redirections' = @{

        Kind = 'FSLogix-Redirections'

        Entries = @(

            # Microsoft nennt fuer die Ablage von redirections.xml nur den
            # Pfad (RedirXMLSourceFolder) und KEINE Share-Berechtigung. Deshalb
            # Derived. Dasselbe Muster wie FSLogix-Profiles: die Gruppe der
            # authentifizierten Konten und NICHT die Welt-SID; das Lesen
            # regelt das verifizierte NTFS-ACL darunter. Keine Optionsgruppe
            # (Inhaberentscheid 2026-09-25).
            @{
                Trustee = 'WellKnown:AuthenticatedUsers'
                Access = 'Full'
                Status = 'Derived'
                Source = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=profiles'
                Section = 'RedirXMLSourceFolder -- NICHT vom Hersteller spezifiziert; Microsoft beschreibt nur den Pfad. Abgeleitet nach dem Muster "Freigabe weit, NTFS regelt" wie FSLogix-Profiles (FEATURES.md Paragraph 1.1 und 1.6, Inhaberentscheid 2026-09-25)'
            }
        )
    }

    'DEMConfig' = @{

        Kind = 'DEMConfig'

        Entries = @(

            # Herstellerwoertlich. Die Zeile steht in der Requirements-Tabelle
            # der Konfigurationsfreigabe unter "Share permissions".
            @{
                Trustee = 'WellKnown:WorldEveryone'
                Access = 'Change'
                Status = 'Verified'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare'
                Section = 'Requirements > Share permissions, Satz 1: "The Everyone group must have Change permissions applied."'
            }

            # Change auf Share-Ebene deckelt JEDEN -- auch die
            # Verwaltungsgruppe -- bei Modify ueber SMB. Wer ACLs ueber die
            # Freigabe statt lokal auf dem Fileserver reparieren will, braucht
            # diesen zweiten Eintrag. Omnissa erwaehnt ihn fuer die
            # Konfigurationsfreigabe NICHT (fuer die Profilfreigabe schon),
            # also Derived und abwaehlbar.
            @{
                Trustee = '<AdminGroup>'
                Access = 'Full'
                Status = 'Derived'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare'
                Section = 'Requirements > Share permissions -- der Hersteller nennt fuer die Konfigurationsfreigabe KEINEN zweiten Share-Eintrag. Abgeleitet, weil Change auf Share-Ebene auch die Gruppe der Administratoren bei Modify deckelt (FEATURES.md Paragraph 1.2, Absatz "Note")'
                OptGroup = 'ShareAdminFullControl'
            }
        )
    }

    'DEMProfiles' = @{

        Kind = 'DEMProfiles'

        Entries = @(

            # Herstellerwoertlich, gleichlautend zur Konfigurationsfreigabe.
            @{
                Trustee = 'WellKnown:WorldEveryone'
                Access = 'Change'
                Status = 'Verified'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'Requirements > Share permissions, Satz 1: "The Everyone group must have Change permissions applied."'
            }

            # Die EINZIGE Ordnerart, fuer die der Hersteller einen zweiten,
            # benannten Share-Eintrag vorgibt. Verified, aber abwaehlbar: das
            # Helpdesk Support Tool ist beim Hersteller selbst als optional
            # gefuehrt, und das Wort "optional" steht woertlich in der Zeile.
            @{
                Trustee = '<HelpdeskGroup>'
                Access = 'Full'
                Status = 'Verified'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'Requirements > Share permissions, Satz 2: "Helpdesk staff using the optional Helpdesk Support Tool must have Full Control permissions applied."'
                OptGroup = 'Helpdesk'
            }
        )
    }

    'DEMComputerLogs' = @{

        Kind = 'DEMComputerLogs'

        Entries = @(

            # GEPRUEFTE ABWESENHEIT, keine Recherchelucke: der DEM 2606
            # Installation and Configuration Guide hat fuer eine
            # Computerprotokoll-Freigabe keine Seite und keine
            # Berechtigungstabelle -- nachgeschlagen gegen den vollstaendigen
            # Seitenindex des Leitfadens. Weitersuchen bringt nichts.
            #
            # Die Zeile spiegelt die beiden DEM-Freigaben und ist ausdruecklich
            # Derived. Der Scheinwiderspruch zum Satz in CLAUDE.md ("Everyone
            # nur auf Share-Ebene der BEIDEN DEM-Shares") ist eine
            # Formulierungs- und keine Sachfrage: das dortige Verbot gilt
            # Everyone mit VOLLZUGRIFF auf NTFS.
            @{
                Trustee = 'WellKnown:WorldEveryone'
                Access = 'Change'
                Status = 'Derived'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'Kein Herstellerbeleg -- abgeleitet aus ProfileArchivesShare. Fuer die Computerprotokoll-Freigabe existiert nachweislich KEINE Herstellervorgabe, auch nicht fuer die Freigabeberechtigung (FEATURES.md Paragraph 1.4)'
            }
        )
    }
}
