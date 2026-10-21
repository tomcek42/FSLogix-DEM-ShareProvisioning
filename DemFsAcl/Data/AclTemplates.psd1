@{

    # =====================================================================
    #  DemFsAcl -- die ACL-Templates als reine Daten.
    #
    #  Diese Datei ist das Compliance-Artefakt des Werkzeugs: ihre
    #  Git-Historie ist der Nachweis, dass das Soll der Herstellervorgabe
    #  entspricht. Sie enthält deshalb NIEMALS ein absichtlich fehlerhaftes
    #  Template -- Negativfälle leben ausschließlich im Testcode.
    #
    #  Konstanten-Only. Import-PowerShellDataFile weist jeden dynamischen
    #  Ausdruck ab: keine Typbeschleuniger, keine Variablen, keine
    #  Cmdlet-Aufrufe, kein [ordered].
    #
    #  Zwei Eigenschaften des Ladevorgangs bestimmen die Form dieser Datei:
    #
    #  1. Kommentare überleben das Laden nicht. Die Kommentare hier sind
    #     Lesehilfe, NIE die Quelle der Wahrheit. Jeder Beleg steht als
    #     Datenfeld (Status, Source, Section) -- das ist der technische
    #     Grund hinter SPEC-02.
    #  2. Die Schlüsselreihenfolge einer Hashtable geht verloren. Die
    #     ACE-Reihenfolge kommt deshalb ausschließlich aus dem Aces-Array.
    #
    #  Trustee-Tokengrammatik (eingefroren in Plan 02, Task 1):
    #     WellKnown:CreatorOwner, WellKnown:System, WellKnown:BuiltinAdmins,
    #     WellKnown:BuiltinUsers, WellKnown:AuthenticatedUsers,
    #     WellKnown:WorldEveryone
    #     <AdminGroup>, <UserGroup>, <ComputerGroup>, <HelpdeskGroup>
    #
    #  Das Präfix ist kein Stil: ein Token mit Präfix ist kein
    #  Prinzipalname und kollidiert nie mit der IDENT-08-Prüfung.
    # =====================================================================

    'FSLogix-Profiles' = @{

        Kind = 'FSLogix-Profiles'

        # Als einzige der vier Ordnerarten ist der Vererbungsschutz hier
        # herstellerwörtlich befohlen: "/inheritance:r" im icacls-Block und
        # "Select Disable inheritance" mit dem Hinweis "removed inherited
        # permissions instead of copying" in der Explorer-Anleitung.
        # Deshalb Verified und nicht Derived.
        ProtectInheritance = $true
        ProtectInheritanceStatus = 'Verified'
        ProtectInheritanceSource = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
        ProtectInheritanceSection = 'Apply Windows ACL(s) using Windows Explorer, Schritt 5 -- "Select Disable inheritance" mit dem Hinweis "removed inherited permissions instead of copying"; gleichlautend "Apply Windows ACL(s) using icacls", erste Zeile /inheritance:r'

        Aces = @(

            # ACE 1 -- Herstellertabelle "Recommended ACL(s)", Zeile 1.
            # Modify und nicht FullControl: FSLogix entzieht dem Profilbesitzer
            # bewusst ChangePermissions und TakeOwnership. Bei den DEM-Shares
            # bekommt derselbe Prinzipal FullControl -- das ist in keinem der
            # beiden Dokumente ein Tippfehler und wird nicht angeglichen.
            @{
                Trustee = 'WellKnown:CreatorOwner'
                Rights = 'Modify'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'InheritOnly'
                Type = 'Allow'
                Status = 'Verified'
                Source = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
                Section = 'Configure Windows ACL(s) > Recommended ACL(s), Tabellenzeile 1: CREATOR OWNER, Modify (Read / Write), Subfolders and files only'
            }

            # ACE 2 -- Herstellertabelle "Recommended ACL(s)", Zeile 2.
            @{
                Trustee = '<AdminGroup>'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Verified'
                Source = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
                Section = 'Configure Windows ACL(s) > Recommended ACL(s), Tabellenzeile 2: CONTOSO\Domain Admins, Full Control, This folder, subfolders and files'
            }

            # ACE 3 -- Herstellertabelle "Recommended ACL(s)", Zeile 3.
            # "This folder only" ist der Kern der Isolationszusage: der ACE ist
            # bewusst NICHT vererbbar, damit die Rechte des einen Benutzers nie
            # in das Profil eines anderen hineinreichen. Die eigentlichen
            # Rechte am eigenen Profil entstehen über ACE 1.
            @{
                Trustee = '<UserGroup>'
                Rights = 'Modify'
                Inheritance = 'None'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Verified'
                Source = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
                Section = 'Configure Windows ACL(s) > Recommended ACL(s), Tabellenzeile 3: CONTOSO\Domain Users, Modify (Read / Write), This folder only'
            }

            # ACE 4 -- NICHT in der Herstellertabelle.
            # Wörtlich befolgt lässt /inheritance:r plus /grant:r die Wurzel mit
            # genau drei ACEs zurück; das Systemkonto wird dabei entfernt.
            # Dieselbe Herstellerseite widerspricht sich jedoch im
            # SIDDirSDDL-Beispiel, das (A;OICI;FA;;;SY) führt. Deshalb Derived
            # und Optional -- die Auswertung des Opt-ins ist SPEC-06 und damit
            # Phase 2. Still hinzugefügt wird hier nichts.
            @{
                Trustee = 'WellKnown:System'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Optional = $true
                OptGroup = 'SystemAndBuiltinAdmins'
                Source = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
                Section = 'Create your SDDL string, Schritt 7 -- der veröffentlichte SIDDirSDDL-Beispielwert enthält (A;OICI;FA;;;SY); die Tabelle Recommended ACL(s) führt dieses Konto nicht'
            }

            # ACE 5 -- NICHT in der Herstellertabelle und auch nicht im
            # SIDDirSDDL-Beispiel. Beleg ist allein der Fließtext derselben
            # Seite. Optional, weil die vom Bediener genannte Verwaltungsgruppe
            # den dateiserverlokalen Zugriff bereits abdecken kann.
            @{
                Trustee = 'WellKnown:BuiltinAdmins'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Optional = $true
                OptGroup = 'SystemAndBuiltinAdmins'
                Source = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
                Section = 'Configure Windows ACL(s), Fliesstext: "you need to ensure any other administrative groups have Full Control from an operational perspective" -- keine Tabellenzeile, keine SDDL-Zeile'
            }
        )
    }

    'FSLogix-Redirections' = @{

        Kind = 'FSLogix-Redirections'

        # ================================================================
        #  KEIN HERSTELLERBELEG -- diese Ordnerart ist durchgängig
        #  ABGELEITET. Microsoft beschreibt die Einstellung
        #  RedirXMLSourceFolder nur als Pfad und veröffentlicht für die
        #  Ablage von redirections.xml keine Rechtetabelle (FEATURES.md
        #  Paragraph 1.6). Das Muster ist DEMConfig: eine LESENDE Ablage,
        #  die Verwalter pflegen und die Benutzer beim Anmelden nur lesen.
        #
        #  Die lokale Administratorengruppe und das Systemkonto stehen FEST
        #  im Soll und sind nicht abwählbar (Inhaberentscheid 2026-09-25).
        #
        #  Der Test dazu heißt Regressionssperre: er sperrt stille
        #  Änderungen an diesem Block und belegt KEINE Konformität mit einer
        #  Herstellervorgabe -- es gibt keine. Jedes Feld ist Derived.
        # ================================================================
        ProtectInheritance = $true
        ProtectInheritanceStatus = 'Derived'
        ProtectInheritanceSource = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=profiles'
        ProtectInheritanceSection = 'RedirXMLSourceFolder: "Path where FSLogix looks for the redirections.xml file to copy from and into the user''s profile." -- Microsoft beschreibt nur den Pfad und sagt zum Vererbungsschutz NICHTS. Werkzeugentscheidung nach dem Muster DEMConfig, weil ein geerbtes Schreibrecht fuer Benutzer die lesende Ablage aushebelte (FEATURES.md Paragraph 1.6)'

        Aces = @(

            # ACE 1 -- fest, nicht abwählbar (Inhaberentscheid 2026-09-25).
            @{
                Trustee = 'WellKnown:BuiltinAdmins'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=profiles'
                Section = 'ABGELEITET: "Administratoren" gedeutet als vordefinierte lokale Gruppe des Servers, fest im Soll und nicht abwaehlbar (Inhaberentscheid 2026-09-25); Microsoft nennt fuer RedirXMLSourceFolder keine Rechtetabelle'
            }

            # ACE 2 -- fest, nicht abwählbar (Inhaberentscheid 2026-09-25).
            @{
                Trustee = 'WellKnown:System'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=profiles'
                Section = 'ABGELEITET: Systemkonto fest im Soll fuer dateiserverlokale Dienste (Sicherung, Virenschutz, Indizierung), nicht abwaehlbar (Inhaberentscheid 2026-09-25)'
            }

            # ACE 3 -- zweite Deutung von "Administratoren" wie bei DEMConfig.
            @{
                Trustee = '<AdminGroup>'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=profiles'
                Section = 'ABGELEITET: die Gruppe der Administratoren aus dem FSLogix-Block pflegt redirections.xml; zweite Deutung von "Administratoren" wie bei DEMConfig (FEATURES.md Paragraph 1.6)'
            }

            # ACE 4 -- NUR Lesen und Ausführen. Ein Schreibrecht ließe jeden
            # Benutzer redirections.xml für alle ändern.
            @{
                Trustee = '<UserGroup>'
                Rights = 'ReadAndExecute'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=profiles'
                Section = 'ABGELEITET: Benutzer lesen redirections.xml beim Anmelden und erhalten kein Schreibrecht; Muster DEMConfig, Requirements > NTFS security permissions, Satz 2 (FEATURES.md Paragraph 1.6)'
            }
        )
    }

    'DEMConfig' = @{

        Kind = 'DEMConfig'

        # Omnissa sagt zum Vererbungsschutz dieser Freigabe NICHTS -- FEATURES.md
        # §1.2 hält das ausdrücklich als "NOT STATED" fest. Deshalb Derived und
        # nicht Verified. Die Entscheidung selbst ist trotzdem richtig: ein von
        # oben geerbtes Schreibrecht für Benutzer verletzte unmittelbar die
        # herstellerwörtliche Zusage "end users do not have Write permissions".
        ProtectInheritance = $true
        ProtectInheritanceStatus = 'Derived'
        ProtectInheritanceSource = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare'
        ProtectInheritanceSection = 'Requirements, Zeile "NTFS security permissions" -- der Hersteller sagt zum Vererbungsschutz NICHTS ("NOT STATED"). Das Abschalten und Entfernen ist eine Werkzeugentscheidung, keine Herstelleranweisung; sie sichert die woertliche Zusage "end users do not have Write permissions" gegen ein geerbtes Schreibrecht ab'

        Aces = @(

            # ACE 1 -- Herstellerzeile "Administrators must have Full Control
            # permissions applied to This folder, subfolders and files."
            # Die Formulierung nennt nur "Administrators" und laesst offen, ob
            # die vordefinierte lokale Gruppe, eine Domaenengruppe oder eine
            # DEM-Verwaltungsgruppe gemeint ist. Projektentscheidung: BEIDE
            # Identitaeten eintragen und als Interpretation kennzeichnen. Genau
            # deshalb ist ACE 1 Derived, obwohl das Recht selbst woertlich
            # dasteht -- belegt ist das Recht, nicht der Prinzipal.
            @{
                Trustee = 'WellKnown:BuiltinAdmins'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare'
                Section = 'Requirements > NTFS security permissions, Satz 1: "Administrators must have Full Control permissions applied to This folder, subfolders and files." -- Deutung des Prinzipals als vordefinierte lokale Gruppe, deckt den dateiserverlokalen Verwalter ab'
            }

            # ACE 2 -- dieselbe Herstellerzeile, zweite Deutung. Die
            # DEM-Verwaltungskonsole laeuft von einem Arbeitsplatz aus; eine
            # Gruppe auf Domaenenebene ist funktional erforderlich. Eine
            # Reduktion auf einen der beiden Eintraege waere keine
            # Vereinfachung, sondern eine inhaltliche Aenderung am
            # Compliance-Artefakt.
            @{
                Trustee = '<AdminGroup>'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare'
                Section = 'Requirements > NTFS security permissions, Satz 1, zweite Deutung desselben Wortes "Administrators": die vom Bediener genannte Gruppe der Administratoren auf Domaenenebene, weil die DEM-Verwaltungskonsole von einem Arbeitsplatz aus laeuft'
            }

            # ACE 3 -- der einzige vererbbare Benutzer-ACE aller vier
            # Ordnerarten, und das ist Absicht: DEMConfig ist die einzige
            # LESENDE Ordnerart. Weil der Benutzer hier nichts schreiben darf,
            # ist die Vererbung nach unten ungefaehrlich. Die Isolationsregel
            # greift folgerichtig nicht -- dieses Template fuehrt kein
            # WellKnown:CreatorOwner.
            @{
                Trustee = '<UserGroup>'
                Rights = 'ReadAndExecute'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Verified'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare'
                Section = 'Requirements > NTFS security permissions, Satz 2: "End users must have Read & execute permissions applied to This folder, subfolders and files."'
            }

            # ACE 4 -- der Hersteller fuehrt ihn selbst als optional. In der
            # veroeffentlichten SDDL-Zeile steht er folgerichtig in eckigen
            # Klammern und gehoert damit nicht in den Fixture-Vergleich.
            @{
                Trustee = '<ComputerGroup>'
                Rights = 'ReadAndExecute'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Verified'
                Optional = $true
                OptGroup = 'ComputerEnvironmentSettings'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare'
                Section = 'Requirements > NTFS security permissions, Note: "If you want to use Dynamic Environment Manager computer environment settings, remote computer accounts must also have Read & execute permissions applied to This folder, subfolders and files."'
            }
        )
    }

    'DEMProfiles' = @{

        Kind = 'DEMProfiles'

        # Wie bei DEMConfig sagt Omnissa zum Vererbungsschutz nichts. Hier
        # wiegt die Werkzeugentscheidung am schwersten: ein einziger geerbter
        # Benutzer-ACE mit Schreibrecht hebt die herstellerwörtliche Zusage auf,
        # dass die Rechtesetzung "limits the user to their own folder".
        ProtectInheritance = $true
        ProtectInheritanceStatus = 'Derived'
        ProtectInheritanceSource = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
        ProtectInheritanceSection = 'Requirements, Zeile "NTFS security permissions" -- der Hersteller sagt zum Vererbungsschutz NICHTS. Das Abschalten und Entfernen ist eine Werkzeugentscheidung; sie haelt die woertliche Zusage "limits the user to their own folder" aufrecht, die ein geerbter Benutzer-ACE mit Schreibrecht vollstaendig aufhoebe'

        Aces = @(

            # ACE 1 -- Herstellerzeile "For Dynamic Environment Manager
            # administrators and help desk: Full Control applied to This folder,
            # subfolders and files."
            @{
                Trustee = '<AdminGroup>'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Verified'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'Requirements > NTFS security permissions, Satz 1: "For Dynamic Environment Manager administrators and help desk: Full Control applied to This folder, subfolders and files."'
            }

            # ACE 2 -- "Create folders / append data" ist die Oberflaechenvokabel
            # fuer CreateDirectories, denselben Zahlenwert wie AppendData (0x4).
            # Der Wert wird als benannte Vokabel gefuehrt und nie als Zahl: eine
            # Zahl castete klaglos und verstecke einen Zahlendreher.
            #
            # KEIN Traverse hinzufuegen, auch nicht hilfsbereit. Der Hersteller
            # gewaehrt auf der Wurzel ausschliesslich das Anlegen; die
            # Durchquerung leistet in der Praxis das Standardprivileg zur
            # Umgehung der Traversierungspruefung.
            @{
                Trustee = '<UserGroup>'
                Rights = 'CreateDirectories'
                Inheritance = 'None'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Verified'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'Requirements > NTFS security permissions, Satz 2: "For End users: Create folders / append data applied to This folder only."'
            }

            # ACE 3 -- FullControl und NICHT Modify. Der Unterschied zu
            # FSLogix-Profiles ist in beiden Herstellerdokumenten Absicht:
            # Microsoft entzieht dem Profilbesitzer bewusst ChangePermissions
            # und TakeOwnership, Omnissa tut das nicht. Die beiden Werte werden
            # nicht angeglichen, und die beiden Aces-Arrays werden nicht
            # zusammengelegt -- eine Deduplizierung ersetzte still die Vorgabe
            # des einen Herstellers durch die des anderen.
            @{
                Trustee = 'WellKnown:CreatorOwner'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'InheritOnly'
                Type = 'Allow'
                Status = 'Verified'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'Requirements > NTFS security permissions, Satz 4: "For Creator Owner: Full Control applied to Subfolders and files only."'
            }

            # ACE 4 -- vom Hersteller selbst als optional gefuehrt.
            @{
                Trustee = '<ComputerGroup>'
                Rights = 'CreateDirectories'
                Inheritance = 'None'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Verified'
                Optional = $true
                OptGroup = 'ComputerEnvironmentSettings'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'Requirements > NTFS security permissions, Note: "If you want to use Dynamic Environment Manager computer environment settings, remote computer accounts must also have Create folders / append data permissions applied to This folder only."'
            }
        )
    }

    'DEMComputerLogs' = @{

        Kind = 'DEMComputerLogs'

        # ================================================================
        #  KEIN HERSTELLERBELEG -- diese Ordnerart ist durchgängig
        #  ABGELEITET. Der DEM-2606-Leitfaden führt keine Seite und keine
        #  Berechtigungstabelle für eine Protokollfreigabe; das wurde gegen
        #  den vollständigen Seitenindex des Leitfadens geprüft. Das ist
        #  eine geprüfte Abwesenheit und keine Recherchelücke --
        #  weitersuchen bringt nichts.
        #
        #  Kein einziges Feld dieses Blocks trägt deshalb Verified. Ein
        #  Template, das vollständig aussieht, ist genau deshalb noch kein
        #  belegtes Template.
        # ================================================================
        ProtectInheritance = $true
        ProtectInheritanceStatus = 'Derived'
        ProtectInheritanceSource = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/FlexEngineConfigurationforComputerEnvironmentSettings'
        ProtectInheritanceSection = 'Note: "Computer accounts rather than user accounts access the file shares that host the configuration folder and the log file. See Omnissa Dynamic Environment Manager Configuration Share and Profile Archives Share for information about Share permissions and NTFS security permissions." -- ABGELEITET: dieser Verweis ist die gesamte Grundlage. Uebernommen wird die Werkzeugentscheidung der beiden verwiesenen Freigaben (https://docs.omnissa.com/DEMInstallConfigGuide-V2606/DynamicEnvironmentManagerConfigurationShare und .../ProfileArchivesShare), wo der Hersteller zum Vererbungsschutz ebenfalls nichts sagt'

        Aces = @(

            # ACE 1 -- abgeleitet aus DEMProfiles ACE 1.
            @{
                Trustee = '<AdminGroup>'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'ABGELEITET aus Requirements > NTFS security permissions, Satz 1 der Profilarchiv-Freigabe ("administrators and help desk: Full Control"), uebertragen auf ein Schreibziel mit Computerkonten statt Benutzerkonten'
            }

            # ACE 2 -- abgeleitet aus DEMProfiles ACE 2, aber mit ZWEI Rechten
            # statt einem: die Einstellung LogFileName ist ein vollstaendiger
            # UNC-Pfad EINSCHLIESSLICH Dateiname. Das Protokoll kann als flache
            # Datei direkt in der Wurzel landen und nicht nur in einem
            # Unterordner je Computer.
            #
            # Ihm nicht ersatzweise Modify geben: Modify traegt zusaetzlich
            # ListDirectory und liesse jeden Sitzungshost die
            # Protokolldateinamen aller anderen Hosts aufzaehlen, ohne dass das
            # irgendeinen Zweck erfuellte.
            #
            # Dieser ACE ist als einziger Computerkonten-ACE der vier
            # Ordnerarten NICHT optional -- bei DEMConfig und DEMProfiles fuehrt
            # der Hersteller ihn selbst als optional, hier ist der
            # Computerkonten-Zugriff der gesamte Zweck der Ordnerart. Wer den
            # Wert fuer <ComputerGroup> liefert, entscheiden die Phasen 2 und 7;
            # hier wird das Token nur zugelassen, nicht gebunden.
            @{
                Trustee = '<ComputerGroup>'
                Rights = 'CreateFiles, CreateDirectories'
                Inheritance = 'None'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/FlexEngineConfigurationforComputerEnvironmentSettings'
                Section = 'ABGELEITET aus der Registrierungseinstellung LogFileName: "Location of the log file, specified as a fully qualified UNC path, including the filename." -- der Dateiname im Pfad erzwingt CreateFiles zusaetzlich zu dem aus der Profilarchiv-Freigabe uebernommenen CreateDirectories'
            }

            # ACE 3 -- abgeleitet aus DEMProfiles ACE 3: jede Maschine besitzt
            # ihr eigenes Protokoll und kann nur dieses fortschreiben.
            @{
                Trustee = 'WellKnown:CreatorOwner'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'InheritOnly'
                Type = 'Allow'
                Status = 'Derived'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/ProfileArchivesShare'
                Section = 'ABGELEITET aus Requirements > NTFS security permissions, Satz 4 der Profilarchiv-Freigabe ("For Creator Owner: Full Control applied to Subfolders and files only"), uebertragen auf eine Ablage je Computer'
            }

            # ACE 4 -- optional, weil er den Fernzugriff NICHT traegt: der Agent
            # laeuft lokal als Systemkonto, meldet sich ueber die Freigabe aber
            # als Maschinenkonto an und ist damit bereits von ACE 2 abgedeckt.
            # Er dient ausschliesslich dateiserverlokalen Vorgaengen wie
            # Sicherung und Virenschutz.
            @{
                Trustee = 'WellKnown:System'
                Rights = 'FullControl'
                Inheritance = 'ContainerInherit, ObjectInherit'
                Propagation = 'None'
                Type = 'Allow'
                Status = 'Derived'
                Optional = $true
                OptGroup = 'SystemLocalOps'
                Source = 'https://docs.omnissa.com/DEMInstallConfigGuide-V2606/PerformInstallationwithComputerEnvironmentSettingsSupport'
                Section = 'ABGELEITET aus der Feststellung, dass die Protokollierung der Computereinstellungen beim Start vom Maschinenkonto beziehungsweise vom Systemkonto geschrieben wird -- ueber die Freigabe traegt jedoch das Maschinenkonto den Zugriff, weshalb dieser Eintrag nur dateiserverlokale Vorgaenge abdeckt und abwaehlbar bleibt'
            }
        )
    }
}
