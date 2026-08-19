import 'dart:typed_data';

/// Persönliche Angaben für den Werkstatt-Wochenbericht: Name (wird auf dem
/// PDF ausgegeben) und eine optional hinterlegte Unterschrift (PNG-Bild),
/// die dann automatisch mit ausgegeben wird, statt jedes Mal von Hand
/// unterschreiben zu müssen.
class ProfileData {
  final String? displayName;
  final Uint8List? signature;

  const ProfileData({this.displayName, this.signature});
}
