# Zeiterfassung (Handwerk)

Lokale Zeiterfassungs-App für iOs (Flutter). Zwei Arten von Einträgen:

- **Kunde** (z. B. "Gerhard"): Startzeit, Endzeit, Tätigkeit. Dient nur der
  eigenen Kontrolle, taucht **nicht** im PDF-Export auf. Die Uhrzeit wird
  nur zur Berechnung der Dauer genutzt.
- **Werkstatt**: gleiche Eingabe, aber Name ist immer "Werkstatt". Diese
  Einträge sind die offizielle Grundlage und werden monatlich als PDF
  exportiert (Datum, Uhrzeit, Dauer, Tätigkeit, Monatssumme).

Die Dauer wird aus Start-/Endzeit automatisch berechnet und kaufmännisch auf
0,25-Stunden-Schritte gerundet (0,25 / 0,5 / 0,75 / 1,0 …), genau wie in
deinem Beispiel (7:00–7:30 → 0,5 Std.).

Alle Daten werden **lokal** auf dem Gerät in einer SQLite-Datenbank
gespeichert (kein Server, keine Internetverbindung nötig). iCloud-Sync ist
als nächster Ausbauschritt vorgesehen (siehe unten).

## Wichtiger Hinweis zu diesem Projektstand

Ich konnte den Code in meiner Cloud-Umgebung **nicht selbst kompilieren**,
da dort kein Flutter/Xcode zur Verfügung steht (das Netzwerk dort blockiert
den Download des Flutter-Engine-Pakets). Der komplette App-Code (`lib/`)
ist fertig und von mir sorgfältig manuell geprüft, aber der **erste echte
Kompiliertest** passiert bei dir bzw. automatisch über Codemagic.

Außerdem fehlen bewusst die nativen `ios/`- und `android/`-Ordner
(Xcode-Projektdateien) – die lassen sich nicht von Hand zuverlässig
schreiben, sondern werden von Flutter selbst generiert. Das ist der
**erste Schritt**, den du (oder Codemagic automatisch) einmalig ausführen
musst:

```bash
cd zeiterfassung
flutter create --platforms=ios --org de.dennis .
flutter pub get
```

Das ergänzt nur die fehlenden Plattform-Ordner, ohne deinen `lib/`-Code
anzufassen. Die Codemagic-Konfiguration (`codemagic.yaml`) macht das
automatisch bei jedem Cloud-Build – dort musst du gar nichts tun.

## Schnell-Vorschau auf deinem Windows-PC (ganz ohne Mac/VM)

Flutter kann die App auch direkt als Windows-Programm bauen. Da Flutter die
komplette Oberfläche selbst zeichnet (nicht auf native Windows-Steuerelemente
zurückgreift), sieht sie dabei optisch praktisch genauso aus wie später auf
dem iPhone. Perfekt, um sich die App schon mal anzusehen, während die VM
noch beschäftigt ist.

1. Flutter für Windows installieren: https://docs.flutter.dev/get-started/install/windows
   (offizieller Installer, danach `flutter doctor` ausführen, um zu prüfen
   ob alles passt)
2. Dieses Zip entpacken, dann im Terminal/PowerShell in den `zeiterfassung`-
   Ordner wechseln
3. Windows-Unterstützung + Abhängigkeiten einrichten:
   ```powershell
   flutter create --platforms=windows .
   flutter pub get
   ```
4. App starten:
   ```powershell
   flutter run -d windows
   ```

Das öffnet ein echtes Windows-Fenster mit der App. Die Datenbank läuft dabei
über eine Windows-kompatible SQLite-Anbindung (`sqflite_common_ffi`), die
ich dafür bereits eingebaut habe – Speichern/Laden von Einträgen funktioniert
also genauso wie später auf dem iPhone.

**Eine Einschränkung:** Der PDF-Export-Button nutzt zum Teilen des PDFs eine
Funktion, die auf dem iPhone (Teilen-Menü) optimiert ist. Unter Windows
öffnet sich stattdessen wahrscheinlich ein Speichern- oder Druckdialog statt
eines "Teilen"-Fensters – das ist normal und kein Fehler, richtig getestet
wird dieser Teil dann final auf dem iPhone.

## Nächste Schritte (wie in unserem Gespräch besprochen)

1. **Projekt zu GitHub hochladen** (privates Repo reicht):
   ```bash
   cd zeiterfassung
   git init
   git add .
   git commit -m "Erste Version Zeiterfassung"
   # dann bei GitHub ein neues Repo anlegen und pushen
   ```

2. **Kostenloser erster Test auf deinem iPhone** (ohne Abo, mit dem Mac
   deines Bekannten):
   - `flutter create --platforms=ios --org de.dennis .` und `flutter pub get`
     ausführen
   - Projekt in Xcode öffnen (`open ios/Runner.xcworkspace`)
   - Dein Apple-ID unter Xcode → Settings → Accounts hinzufügen
   - iPhone per Kabel anschließen, als "Personal Team" signieren, "Run"
     drücken. Läuft 7 Tage, danach ggf. erneut signieren.

3. **Sobald du das Apple Developer Program hast (99 $/Jahr) und die App
   auch an Kollegen verteilen willst**: Codemagic-Konto anlegen, Repo
   verbinden, App-Store-Connect-API-Key hinterlegen (siehe Kommentare in
   `codemagic.yaml`). Danach baut Codemagic die App bei jedem Push
   automatisch und lädt sie zu TestFlight hoch – ganz ohne dass du selbst
   Xcode bedienen musst.

## Neue Funktionen (aktuelle Version)

- **Angemeldeter Nutzer im Header**: In der Web/PWA-Variante steht rechts
  oben neben "Stunden Logbuch" jetzt der Name des eingeloggten Nutzers.
- **Komplette Liste für Woche/Monat**: Tippen auf die Kachel "Diese Woche"
  bzw. "Dieser Monat" auf der Startseite öffnet eine vollständige,
  chronologisch sortierte Liste aller Einträge des Zeitraums (neuste oben,
  älteste unten) inkl. Gesamtsumme.
- **Kalender mit zwei Punkten**: In der Monatsübersicht zeigt jeder Tag mit
  Einträgen bis zu zwei kleine Punkte - Amber für Werkstatt, Petrol für
  Kunde - damit auf einen Blick erkennbar ist, welche Art von Eintrag an
  diesem Tag existiert.
- **Profil mit Name & Unterschrift**: Unter "Konto" kann jeder Nutzer (auf
  allen Plattformen) seinen Namen hinterlegen sowie einmalig eine
  Unterschrift zeichnen (z. B. mit dem Finger/Stift auf einem iPad). Beides
  wird auf dem Werkstatt-Wochenbericht automatisch mit ausgegeben, sofern
  hinterlegt - ansonsten bleiben Name/Unterschriftszeile einfach leer. Auf
  iOS/Windows liegen diese Angaben lokal auf dem Gerät, in der Web/PWA-
  Variante am eingeloggten Nutzerkonto auf dem Server.
- **Werkstatt-Wochenbericht (einziger Werkstatt-PDF-Export)**: Der frühere
  monatliche Werkstatt-PDF-Export wurde entfernt - es gibt jetzt bewusst nur
  noch EIN Werkstatt-PDF-Format, den Wochenbericht. Erreichbar über die
  Kachel "Diese Woche" auf der Startseite oder über den Button
  "Werkstatt-Wochenbericht öffnen" in der Monatsübersicht. Die Ansicht hat
  eine eigene Wochen-Navigation (Pfeile), man ist also nicht auf die
  aktuelle Woche beschränkt, sondern kann auch für vergangene (oder
  zukünftige) Wochen einen Bericht exportieren. Enthält:
  - Kalenderwoche (KW) inkl. Datumsbereich neben dem Monat im Titel, z. B.
    "August 2026 (KW 34: 17.08.–23.08.)"
  - einer "Kontrolle"-Spalte neben der Tätigkeit zum manuellen Abhaken durch
    das Büro, sobald eine Zeile erfasst wurde
  - einem Unterschriften-/Namensfeld unten, automatisch befüllt aus dem
    Profil (siehe oben)

  Der "Gesamtbericht" (alle Einträge inkl. Kunde, zur eigenen Sicherung)
  bleibt weiterhin als separater, monatlicher Export in der
  Monatsübersicht bestehen - das ist kein offizielles Werkstatt-Dokument.

## Noch offen / nächste Ausbaustufe

- **iCloud-Backup**: aktuell nur lokale Speicherung. Für echten
  iCloud-Sync braucht es die "iCloud"-Capability in Xcode (App-ID im
  Apple Developer Portal, CloudKit-Container) – das richten wir ein,
  sobald du Zugriff auf einen Mac/Developer-Account hast. Bis dahin ließe
  sich als Zwischenlösung ein manueller "Exportieren/Sichern"-Button
  ergänzen (z. B. Datenbank-Datei in die Dateien-App/iCloud Drive
  kopieren).
- **Bearbeiten mehrerer Tage rückwirkend**: aktuell über die
  Tages-Navigation (Pfeile) möglich, kein Kalender-Picker – kann bei
  Bedarf ergänzt werden.

## Projektstruktur

```
zeiterfassung/
  lib/
    models/time_entry.dart        # Datenmodell + Umrechnung Map<->Objekt
    utils/time_rounding.dart      # Dauer-Berechnung & 0,25h-Rundung
    db/database_helper.dart       # lokale SQLite-Datenbank
    services/pdf_export_service.dart  # Werkstatt-PDF-Export
    screens/home_screen.dart      # Tagesansicht
    screens/add_entry_screen.dart # Eintrag anlegen/bearbeiten
    screens/month_overview_screen.dart # Monatsübersicht + PDF-Export
    main.dart
  pubspec.yaml
  codemagic.yaml                  # Cloud-Build-Konfiguration
```
