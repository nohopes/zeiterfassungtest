import 'dart:typed_data';

/// Persönliche Angaben für den Werkstatt-Wochenbericht: Name (wird auf dem
/// PDF ausgegeben) und eine optional hinterlegte Unterschrift (PNG-Bild),
/// die dann automatisch mit ausgegeben wird, statt jedes Mal von Hand
/// unterschreiben zu müssen. Zusätzlich optional eine E-Mail-Adresse, an
/// die der Server automatisch jeden Monat den Werkstatt-Bericht schickt
/// (siehe `_sendMonthlyReports` in server/bin/server.dart) - leer/nicht
/// gesetzt bedeutet, dass dieser Nutzer keine automatischen Berichte
/// erhalten möchte.
class ProfileData {
  final String? displayName;
  final Uint8List? signature;
  final String? notificationEmail;

  const ProfileData({this.displayName, this.signature, this.notificationEmail});
}
