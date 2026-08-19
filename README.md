# Zeiterfassung (Handwerk)

Stunden- und Zeiterfassung fürs Handwerk als reine Web/PWA-App ("Stunden
Logbuch"), inkl. eigenem Backend-Server. Läuft komplett bei dir selbst per
Docker (z. B. auf einem unRAID-Server) - kein Cloud-Dienst, keine
Drittanbieter-Abhängigkeit für die eigentlichen Daten.

Zwei Arten von Einträgen:

- **Kunde** (z. B. "Gerhard"): Startzeit, Endzeit, Tätigkeit, optionale
  Pause (Frühstückspause 15 min / Mittagspause 30 min, wird von der Dauer
  abgezogen). Dient nur der eigenen Kontrolle, taucht **nicht** im
  Werkstatt-PDF-Export auf.
- **Werkstatt**: gleiche Eingabe, Name ist immer "Werkstatt". Diese
  Einträge sind die offizielle Grundlage und werden als PDF exportiert
  (Datum, Uhrzeit, Dauer, Tätigkeit, Kontrollspalte, Unterschrift).

Die Dauer wird aus Start-/Endzeit automatisch berechnet und auf
15-Minuten-Schritte gerundet.

## Funktionen

- **Mehrbenutzer-Login**: jeder Kollege hat einen eigenen Account und sieht
  nur seine eigenen Einträge. Ein Admin-Konto kann weitere Nutzer anlegen/
  löschen (unter "Konto").
- **Vorgefertigte Tätigkeiten**: pro Nutzer selbst anlegbare/änderbare/
  löschbare Vorlagen für Werkstatt-Tätigkeiten, dazu automatisch die 5
  häufigsten Tätigkeiten als Schnellauswahl.
- **Profil mit Name & Unterschrift**: unter "Konto" hinterlegt jeder Nutzer
  einmalig seinen Namen und eine gezeichnete Unterschrift - beides wird
  automatisch dem Werkstatt-PDF beigefügt. Auf kleinen Bildschirmen (Handy)
  öffnet sich dafür automatisch ein gedrehtes Vollbild-Zeichenfeld, auf
  größeren (Tablet) direkt inline.
- **Startseite**: Tagesansicht mit Vor-/Zurück-Navigation, Wochen-/
  Monatssumme als Kacheln (antippbar für eine vollständige, chronologisch
  sortierte Liste aller Einträge des Zeitraums), Name aus dem Profil oben
  rechts im Header.
- **Monatsübersicht**: Kalender mit Punkt-Markierung pro Tag (Amber =
  Werkstatt, Petrol = Kunde), Kundenliste mit Zwischensummen, PDF-Exporte.
- **Werkstatt-PDF-Export**: ein Knopf "PDF Export Werkstattstunden" pro
  Monat - Datum, Uhrzeit, Dauer, Tätigkeit, eine Spalte "Eingetragen Büro"
  zum manuellen Abhaken durch das Büro, sowie Name/Unterschrift aus dem
  Profil (sofern hinterlegt, sonst bleibt die Zeile leer).
- **Gesamtbericht-Export**: separater, monatlicher PDF-Export mit ALLEN
  Einträgen (Kunde + Werkstatt), zur eigenen Sicherung - kein offizielles
  Werkstatt-Dokument.
- **Push-Erinnerungen**: optionale Browser-Benachrichtigung werktags um
  16:30 Uhr, falls für den Tag noch kein Eintrag existiert.
- **PWA**: auf dem Handy/Tablet zum Homescreen hinzufügbar, läuft dann wie
  eine native App (eigenes Icon, ohne Browser-Adressleiste).

## Aufbau

```
zeiterfassung/
  lib/                     # Flutter-Web-App
    models/                # Datenmodelle
    services/               # REST-Zugriff, Auth, PDF-Export, Push
    screens/                # Bildschirme
    widgets/                # wiederverwendbare UI-Bausteine
    theme/                  # Design-Tokens ("Werkstattbuch"-Optik)
  web/                      # PWA-Manifest, index.html, Service-Worker
  server/                   # Dart-Backend (REST-API + sembast-Datenbank)
  Dockerfile                # Multi-Stage-Build: Flutter-Web + Dart-Server
  docker-compose.yml        # Beispiel-Konfiguration für den eigenen Server
  .github/workflows/        # baut & pusht das Docker-Image nach GitHub
                             # Container Registry (ghcr.io) bei jedem Push
```

## Betrieb per Docker

1. `docker-compose.yml` anpassen: `ADMIN_USERNAME`/`ADMIN_PASSWORD` setzen
   (nur beim allerersten Start wirksam, legt das erste Admin-Konto an),
   optional `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY`/`VAPID_SUBJECT` für
   Push-Erinnerungen (ohne diese drei bleibt Push einfach deaktiviert).
2. `docker compose up -d --build` (oder das fertige Image von
   `ghcr.io/<dein-repo>:latest` verwenden, das GitHub Actions bei jedem
   Push automatisch baut).
3. Die App ist danach unter `http://<server>:8080` erreichbar. Mit dem
   Admin-Konto einloggen, weitere Kollegen unter "Konto" anlegen.

## Daten & Backup

Alle Daten - Zeiteinträge, Nutzerkonten/Logins (als bcrypt-Hash, nie im
Klartext), Vorlagen, Profil-Namen und -Unterschriften, Push-Abos - liegen
in **einer einzigen Datei**: `zeiterfassung.db` im gemounteten Datenordner
(Standard: `./data/zeiterfassung.db`, bzw. wo auch immer das Volume in
`docker-compose.yml` hinzeigt). Ein regelmäßiges (z. B. tägliches)
inkrementelles Backup genau dieser einen Datei sichert die komplette App
inklusive aller Unterschriften.

## Entwicklung

Änderungen an `lib/` werden bei jedem `docker compose up --build`
automatisch neu für's Web kompiliert (`flutter build web --release` im
Dockerfile). Für schnellere Iteration lokal auch direkt mit
`flutter run -d chrome` möglich (Backend-Server dafür separat mit
`dart run server/bin/server.dart` starten).
