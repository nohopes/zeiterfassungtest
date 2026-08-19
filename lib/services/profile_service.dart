/// Öffentliche Fassade: welche Implementierung tatsächlich verwendet wird,
/// entscheidet sich rein anhand der Plattform, auf der der Code läuft -
/// genau wie bei database_helper.dart.
///
/// - Auf iOS/Windows/macOS/Linux/Android: Name/Unterschrift liegen lokal
///   auf dem Gerät (profile_service_io.dart).
/// - Im Browser/PWA: Name/Unterschrift liegen am eingeloggten Nutzerkonto
///   auf dem Server (profile_service_web.dart).
export 'profile_service_stub.dart'
    if (dart.library.io) 'profile_service_io.dart'
    if (dart.library.html) 'profile_service_web.dart';
