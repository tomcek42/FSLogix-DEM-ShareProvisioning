@{

    # =====================================================================
    #  DemFsAcl -- die Namensliste der Bestandspruefung (Phase 5, D-05, D-08).
    #
    #  Welcher Ordnername welche Ordnerart bezeichnet. Verglichen wird der
    #  VOLLE Ordnername ohne Beachtung der Gross-/Kleinschreibung -- kein
    #  Namensbestandteil, keine Heuristik. "DEMConfigAlt" ist damit KEIN
    #  DEMConfig-Ordner, und das ist Absicht: ein falsch geratenes Ziel wuerde
    #  gegen das falsche Soll geprueft.
    #
    #  EINZIGE AUSNAHME: FSLogix-Redirections (W-09-2, Entscheidung
    #  Projektinhaber 2026-10-01). Diese Ordnerart wird zusaetzlich an jedem
    #  Namen erkannt, der einen Teilnamen aus KindContains enthaelt (ordinal,
    #  ohne Gross-/Kleinschreibung). Ausgewertet wird das nur in
    #  Resolve-AuditKindName; ein exakter Name aus Kinds geht vor, ein
    #  Sammelordnername ebenso. Die Erkennung bleibt Vorschlag: bestaetigt
    #  wird vor dem ersten Lesen, geschrieben nur nach Angebot und getipptem
    #  JA, und nur an der Wurzel.
    #
    #  Die Liste ist erweiterbar. Get-AuditKindNameMap prueft sie beim Laden
    #  und wirft, wenn ein Name doppelt vorkommt (auch ueber Ordnerarten und
    #  Sammelordner hinweg), leer ist, ein Pfadtrennzeichen enthaelt oder eine
    #  unbekannte Ordnerart nennt -- dieselbe Haltung wie SPEC-07 bei den
    #  Templates. Teilnamen laesst sie nur fuer FSLogix-Redirections zu und
    #  weist volle Namen anderer Ordnerarten und Sammelordnernamen ab, die
    #  einen Teilnamen enthalten.
    #
    #  Konstanten-Only: Import-PowerShellDataFile weist jeden dynamischen
    #  Ausdruck ab. Kommentare ueberleben das Laden nicht; sie sind Lesehilfe.
    # =====================================================================

    Kinds = @{
        'FSLogix-Profiles' = @('FSLogix', 'FSLogix-Profiles', 'Profiles')

        # Die Ablage fuer redirections.xml (Phase 7, RDX-04). Der Name
        # "Redirections" ist allgemein -- auch Ziele einer Ordnerumleitung
        # heissen so. Die Erkennung ist deshalb nur ein Vorschlag: bestaetigt
        # wird vor dem ersten Lesen (D-09), geschrieben nur nach Angebot und
        # getipptem JA, und nur an der Wurzel. Die drei vollen Namen sind die
        # kanonischen Schreibweisen; ueber KindContains wird zusaetzlich jeder
        # Name mit "Redirection" vorgeschlagen -- auch FolderRedirection o. ae.
        'FSLogix-Redirections' = @('FSLogix-Redirections', 'FSLogixRedirections', 'Redirections')

        'DEMConfig'        = @('DEMConfig', 'DEM-Config')
        'DEMProfiles'      = @('DEMProfiles', 'DEM-Profiles')
        'DEMComputerLogs'  = @('DEMComputerLogs', 'DEMLogs')
    }

    # Teilnamen je Ordnerart (W-09-2). Zugelassen nur fuer FSLogix-Redirections.
    KindContains = @{
        'FSLogix-Redirections' = @('Redirection')
    }

    # Ein Ordner mit einem dieser Namen ist ein moeglicher DEM-Sammelordner
    # (D-08): liegen darunter erkannte DEM-Ordner und zeigt keine Freigabe auf
    # ihn, wird er selbst nicht geprueft.
    CollectionNames = @('DEM')
}
