<#
    Resolve-TrusteeSid -- die einzige Komponente dieses Werkzeugs, die etwas
    ueber Prinzipale weiss, und der einzige Ort, der mit einer
    IdentityNotMappedException scheitern kann.

    Was hier hineingeht, ist Freitext des Bedieners oder ein Trustee-Token aus
    der Templatedatei. Was herauskommt, geht unveraendert in eine
    FileSystemAccessRule. Deshalb gilt fuer den Rueckgabewert genau eine
    Regel: ausschliesslich ein SecurityIdentifier, niemals ein Name
    (IDENT-02, C-03). Die Richtung SID -> Anzeigename ist Sache der
    Dialog- und Ausgabeschicht (Phase 7/8) und hat hier keinen Rueckweg.

    BEKANNTE GRENZE, bewusst so gewaehlt: ist kein Domaenencontroller
    erreichbar, wirft die Rueckwaertsprobe im SID-Zweig auch fuer eine
    LEGITIME Domaenen-SID eine IdentityNotMappedException. Das Werkzeug kann
    "existiert nicht" und "gerade nicht nachschlagbar" an dieser Stelle nicht
    unterscheiden. Fuer v1 ist der Abbruch die richtige Wahl -- lieber eine
    klare Meldung als ein toter ACE auf einem Profilshare, den der Explorer
    als rohe SID anzeigt und der dem eigentlich Berechtigten den Zugriff auf
    sein eigenes Profil entzieht. Ein bewusstes Uebergehen durch den Bediener
    gehoert, wenn ueberhaupt, in die Dialogschicht (Phase 7) und nicht hierher.

    Die Funktion druckt nicht und fragt nicht: weder Write-Host noch Read-Host
    (C-10). Sie gibt ein Objekt zurueck oder wirft.
#>

function Resolve-TrusteeSid {
    <#
    .SYNOPSIS
        Loest eine Trustee-Angabe zu einem SecurityIdentifier auf.

    .DESCRIPTION
        Vier Zweige in fester Reihenfolge: bereinigen und leere Eingabe
        abweisen, WellKnown-Token an Get-WellKnownSid delegieren, SID-String
        konstruieren und rueckwaerts proben, alles uebrige als Kontoname
        aufloesen.

        Es gibt im gesamten Werkzeug genau EINE Wahrheit ueber die sechs
        vordefinierten Prinzipale, und die steht als Literal-SID-Map in
        WellKnownSid.ps1. Hier wird deshalb delegiert und keine zweite
        Zuordnung angelegt: zwei Wahrheiten ueber dieselben sechs Prinzipale
        driften auseinander, und die Verifikation prueft dann gegen die
        falsche (IDENT-01, C-03).

        Zwei Fehlerarten, zwei Ausnahmetypen -- das ist keine Formalie,
        sondern der Traeger zweier verschiedener Auskuenfte an den Bediener:
        System.ArgumentException heisst "SID-Syntax ungueltig" oder "Angabe
        leer", System.Security.Principal.IdentityNotMappedException heisst
        "existiert nicht oder ist nicht aufloesbar" (IDENT-07).

        Geprueft wird im Testcode grundsaetzlich der Ausnahmetyp und nicht
        der Ausnahmetext -- die Meldungen der .NET-Laufzeit kommen auf einem
        deutschen Server deutsch zurueck.

    .EXAMPLE
        Resolve-TrusteeSid -InputValue 'WellKnown:BuiltinAdmins'

    .EXAMPLE
        Resolve-TrusteeSid -InputValue 'DOMAENE\VDI-Admins'
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Principal.SecurityIdentifier])]
    param(
        # AllowEmptyString ist Absicht: die leere Angabe soll an der eigenen
        # Pruefung unten scheitern und nicht an der Parameterbindung. Nur so
        # ist der Fehlerfall vom Aufrufer wie vom Testcode als
        # ArgumentException zu fassen statt als ParameterBindingException.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $InputValue
    )

    # --- 1. Bereinigen, bevor irgendetwas konstruiert wird ------------------
    # Aus der Zwischenablage kopierte Gruppennamen tragen regelmaessig
    # umschliessende Anfuehrungszeichen; das zweite Trim faengt den Fall
    # '  "Name"  ' vollstaendig ab.
    $wert = $InputValue.Trim().Trim('"').Trim()

    if ([string]::IsNullOrWhiteSpace($wert)) {
        throw [System.ArgumentException]::new(
            'Die Trustee-Angabe ist leer. Erwartet wird ein WellKnown-Token, eine SID oder ein Kontoname.')
    }

    # --- 2. Token-Zweig: an die einzige SID-Map des Werkzeugs delegieren ----
    if ($wert.StartsWith('WellKnown:', [System.StringComparison]::Ordinal)) {
        return Get-WellKnownSid -Token $wert
    }

    # --- 3. SID-Zweig -------------------------------------------------------
    if ($wert -match '^S-1-') {

        try {
            $sid = [System.Security.Principal.SecurityIdentifier]::new($wert)
        }
        catch [System.ArgumentException] {
            # Der typisierte catch greift, obwohl PowerShell den Fehler eines
            # ::new()-Aufrufs in eine MethodInvocationException verpackt.
            throw [System.ArgumentException]::new(
                ('"{0}" ist keine syntaktisch gültige SID.' -f $wert))
        }

        # RUECKWAERTSPROBE -- der eigentliche Inhalt von IDENT-07.
        #
        # SecurityIdentifier prueft nur die Syntax, nicht die Existenz: ein
        # wohlgeformter, aber nirgends existierender SID-String konstruiert
        # klaglos. Ohne diese Probe reicht das Werkzeug genau die
        # "unaufloesbare SID" weiter, die IDENT-07 verbietet, und der Fehler
        # faellt erst auf dem Fileserver auf, als toter ACE.
        #
        # WARUM DAS IDENT-02 NICHT VERLETZT: IDENT-02 verbietet, dass ein
        # NAME in den Schreibpfad gelangt. Hier wird der Name erzeugt,
        # geprueft und sofort verworfen -- er wird keiner Variablen
        # zugewiesen und verlaesst diese Funktion nie. Weitergereicht wird
        # ausschliesslich das SecurityIdentifier.
        #
        # Diese Zeile ist deshalb KEIN Regelverstoss und darf nicht als
        # solcher wegkorrigiert werden. Ohne sie ist die Luecke wieder offen.
        try {
            $null = $sid.Translate([System.Security.Principal.NTAccount])
        }
        catch [System.Security.Principal.IdentityNotMappedException] {
            throw [System.Security.Principal.IdentityNotMappedException]::new(
                ('Die SID "{0}" ist syntaktisch gültig, aber nicht auflösbar. Abbruch statt totem ACE (IDENT-07).' -f $wert))
        }

        return $sid
    }

    # --- 4. Namenszweig -----------------------------------------------------
    try {
        return ([System.Security.Principal.NTAccount]::new($wert)).Translate(
            [System.Security.Principal.SecurityIdentifier])
    }
    catch [System.Security.Principal.IdentityNotMappedException] {
        throw [System.Security.Principal.IdentityNotMappedException]::new(
            ('"{0}" konnte nicht Aufgelöst werden. Schreibweise und Domänenpräfix prüfen.' -f $wert))
    }
}
