import '../models/profile_data.dart';

/// Fallback, falls weder dart:io noch dart:html verfügbar sind.
class ProfileService {
  ProfileService._internal();
  static final ProfileService instance = ProfileService._internal();

  static Never _unsupported() => throw UnsupportedError(
        'Keine passende Profil-Implementierung für diese Plattform gefunden.',
      );

  Future<ProfileData> loadProfile() async => _unsupported();
  Future<void> saveDisplayName(String name) async => _unsupported();
  Future<void> saveSignature(List<int> pngBytes) async => _unsupported();
  Future<void> clearSignature() async => _unsupported();
}
