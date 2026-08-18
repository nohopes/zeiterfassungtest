# Stunden Logbuch (Handwerk)

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

Auf iPhone/Windows/macOS/Linux werden alle Daten **lokal** auf dem Gerät
gespeichert (kein Server, keine Internetverbindung nötig) - über `sembast`,
eine reine Dart-Datenbank ohne native Kompilierung. iCloud-Sync ist als
nächster Ausbauschritt vorgesehen (siehe unten).

Für die Web/PWA-Variante (siehe unten, per Docker/unRAID gehostet) gilt das
NICHT: dort speichert ein kleiner Backend-Server die Daten dauerhaft auf dem
Server selbst (in einem Docker-Volume), damit alle Geräte/Browser dieselben
Einträge sehen.

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

## Web-Variante (PWA) auf unRAID per Docker hosten

Neben iPhone/Windows lässt sich dieselbe App auch als Web-App (PWA) bauen
und auf deinem unRAID-Server per Docker laufen lassen.

**Architektur:** Der Container enthält zwei Teile, die zusammen ausgeliefert
werden: die gebaute Flutter-Web-App (HTML/JS) und einen kleinen
Backend-Server (reines Dart, kein Flutter nötig). Anders als bei einer
"nur Browser"-PWA speichert dieser Server die Einträge dauerhaft in einer
Datei auf einem Docker-Volume - dadurch sehen alle Geräte/Browser, die die
Seite öffnen, dieselben Daten, und die Daten überleben einen
Container-Neustart oder -Update. **Wichtig:** Es gibt (noch) kein
Nutzerkonto/Login - alle Einträge landen in einem gemeinsamen Topf. Für
dich allein (z. B. Handy- und Desktop-Browser gleichzeitig) ist das genau
richtig; falls später mehrere Kollegen dieselbe Instanz nutzen sollen,
sehen/bearbeiten die aktuell alle dieselben Einträge (eine echte
Benutzertrennung wäre ein separater Ausbauschritt).

Das Bauen (Flutter-SDK + Dart-Compiler) passiert komplett in
GitHub Actions - kostenlos, genau wie beim iOS-Build. unRAID muss dadurch
selbst nichts kompilieren, sondern lädt nur das fertige Image.

### 1. Fertiges Image bauen lassen (GitHub Actions)

Die Workflow-Datei `.github/workflows/docker-build.yml` ist schon
enthalten. Bei jedem Push auf `main` (oder manuell über den Button
"Run workflow" im Tab "Actions" auf GitHub) baut GitHub automatisch ein
Docker-Image und veröffentlicht es in der GitHub Container Registry (GHCR) -
für ein öffentliches Repo kostenlos, genau wie die iOS-Action.

Nach dem **ersten** erfolgreichen Lauf einmalig:
1. Auf GitHub im Repo rechts auf "Packages" klicken (oder
   `github.com/<dein-name>?tab=packages`) - dort taucht das neue Paket
   (Image) auf.
2. Paket öffnen → "Package settings" → "Change visibility" → **Public**
   stellen. Sonst kann unRAID das Image später nicht ohne Login herunterladen.

### 2. Auf unRAID einrichten

Im unRAID-Webinterface, Tab **Docker** → unten **"Add Container"**:

- **Name:** `zeiterfassung`
- **Repository:** `ghcr.io/<dein-github-name>/<dein-repo-name>:latest`
  (z. B. `ghcr.io/nohopes/zeiterfassungtest:latest`)
- **Port-Zuordnung:** Container-Port `8080` → Host-Port z. B. `8080`
  (frei wählbar, falls belegt)
- **Pfad-Zuordnung (Volume):** Container-Pfad `/data` → Host-Pfad z. B.
  `/mnt/user/appdata/zeiterfassung` (hier landen die Zeiterfassungsdaten
  dauerhaft)
- Übernehmen/Apply klicken - unRAID lädt das Image herunter und startet
  den Container.

Danach ist die App unter `http://<ip-deines-unraid-servers>:8080`
erreichbar - im Handy-Browser öffnen und über "Zum Startbildschirm
hinzufügen" installieren, dann verhält sie sich wie eine echte App.

Falls du stattdessen die "Docker Compose Manager"-Plugin von unRAID nutzt,
kannst du auch einfach den Inhalt von `docker-compose.yml` als neuen Stack
einfügen (Pfad `./data` dann auf `/mnt/user/appdata/zeiterfassung` ändern).

### 3. Nach Code-Änderungen aktualisieren

1. Änderungen nach GitHub pushen (oder Workflow manuell auslaufen lassen) -
   GitHub Actions baut automatisch ein neues `:latest`-Image.
2. Auf unRAID im Docker-Tab auf das Container-Icon klicken → **"Force
   Update"** (oder Container entfernen und mit denselben Einstellungen neu
   hinzufügen). Die gespeicherten Daten im Volume bleiben davon unberührt.

### Hinweis zum PDF-Export in der Browser-Variante

Der "Teilen"-Dialog ist wie unter Windows aufs iPhone optimiert - im
Browser läuft das wahrscheinlich auf einen Download/Speichern-Dialog
hinaus. Funktional (PDF wird korrekt erzeugt) macht das keinen Unterschied.

### Lokal testen (ohne unRAID)

```bash
cd zeiterfassung
docker compose up -d --build
```

Danach unter `http://localhost:8080` erreichbar, Daten landen im Ordner
`./data`.

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
    db/database_helper.dart       # Fassade: wählt io- oder web-Implementierung
    db/database_helper_io.dart    # lokale sembast-Datenbank (iOS/Windows/macOS/Linux)
    db/database_helper_web.dart   # REST-Client fürs Backend (Web/PWA)
    services/pdf_export_service.dart  # PDF-Export (Werkstatt + Gesamtbericht)
    screens/home_screen.dart      # Tagesansicht
    screens/add_entry_screen.dart # Eintrag anlegen/bearbeiten
    screens/month_overview_screen.dart # Monatsübersicht + PDF-Export
    main.dart
  server/                          # Backend für die PWA (reines Dart, kein Flutter)
    bin/server.dart                 # REST-API + Ausliefern der Web-App + sembast-Speicherung
    pubspec.yaml
  pubspec.yaml
  codemagic.yaml                  # Cloud-Build-Konfiguration (Apple Developer Program)
  Dockerfile, docker-compose.yml  # PWA per Docker/unRAID hosten
  .github/workflows/docker-build.yml # baut & veröffentlicht das Docker-Image (GHCR)
  .github/workflows/ios-unsigned-build.yml # baut die unsignierte iOS-IPA
```
