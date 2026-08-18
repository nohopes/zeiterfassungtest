/// Öffentliche Fassade: welche Implementierung tatsächlich verwendet wird,
/// entscheidet sich rein anhand der Plattform, auf der der Code läuft -
/// alle Screens importieren weiterhin nur diese Datei und nutzen
/// `DatabaseHelper.instance...` ganz normal.
///
/// - Auf iOS/Windows/macOS/Linux/Android (dart:io verfügbar):
///   [database_helper_io.dart] - Daten liegen lokal auf dem Gerät (sembast).
/// - Im Browser/PWA (dart:html verfügbar):
///   [database_helper_web.dart] - Daten liegen NICHT im Browser, sondern
///   werden über eine REST-API vom Backend-Server geholt/gespeichert (siehe
///   `server/`), der sie dauerhaft in einem Docker-Volume ablegt.
export 'database_helper_stub.dart'
    if (dart.library.io) 'database_helper_io.dart'
    if (dart.library.html) 'database_helper_web.dart';
