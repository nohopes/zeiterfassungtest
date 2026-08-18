/// Öffentliche Fassade: welche Implementierung tatsächlich verwendet wird,
/// entscheidet sich rein anhand der Plattform, auf der der Code läuft.
///
/// - Auf iOS/Windows/macOS/Linux/Android (dart:io verfügbar): kein
///   Login-Konzept, einfacher Hinweistext (account_screen_io.dart).
/// - Im Browser/PWA (dart:html verfügbar): zeigt den eingeloggten Nutzer,
///   einen Logout-Button, und für Admins eine Nutzerverwaltung
///   (account_screen_web.dart).
export 'account_screen_io.dart'
    if (dart.library.io) 'account_screen_io.dart'
    if (dart.library.html) 'account_screen_web.dart';
