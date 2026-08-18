/// Öffentliche Fassade: entscheidet rein anhand der Plattform, ob ein Login
/// nötig ist.
///
/// - Auf iOS/Windows/macOS/Linux/Android (dart:io verfügbar): kein Login,
///   [child] wird direkt angezeigt (siehe auth_gate_passthrough.dart).
/// - Im Browser/PWA (dart:html verfügbar): [child] wird erst angezeigt,
///   nachdem sich der Nutzer eingeloggt hat (siehe auth_gate_web.dart).
export 'auth_gate_passthrough.dart'
    if (dart.library.io) 'auth_gate_passthrough.dart'
    if (dart.library.html) 'auth_gate_web.dart';
