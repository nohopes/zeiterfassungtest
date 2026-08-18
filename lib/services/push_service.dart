/// Öffentliche Fassade: Push-Erinnerungen gibt es nur in der Web/PWA-
/// Variante (dort läuft auch der Server, der die Erinnerungen verschickt).
/// Auf iOS/Windows/etc. ist [subscribe] ein No-Op mit erklärender
/// Fehlermeldung.
export 'push_service_stub.dart'
    if (dart.library.io) 'push_service_stub.dart'
    if (dart.library.html) 'push_service_web.dart';
