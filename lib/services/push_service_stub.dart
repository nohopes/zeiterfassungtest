/// Fallback für Plattformen ohne Push-Konzept (iOS/Windows/macOS/Linux/
/// Android) - dort gibt es keinen Server, der Erinnerungen verschicken
/// könnte.
class PushService {
  PushService._internal();
  static final PushService instance = PushService._internal();

  Future<String?> subscribe() async => 'Auf diesem Gerät nicht verfügbar';

  Future<bool> sendTestNotification() async => false;
}
