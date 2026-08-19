import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/profile_data.dart';

/// Lokale Variante (iOS/Windows/macOS/Linux/Android): Name und
/// Unterschrift liegen als kleine Dateien im App-Dokumentenordner - genau
/// dort, wo auch die sembast-Datenbank liegt (siehe database_helper_io.dart).
class ProfileService {
  ProfileService._internal();
  static final ProfileService instance = ProfileService._internal();

  Future<File> get _profileFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, 'profile.json'));
  }

  Future<File> get _signatureFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, 'signature.png'));
  }

  Future<ProfileData> loadProfile() async {
    String? displayName;
    final profileFile = await _profileFile;
    if (await profileFile.exists()) {
      try {
        final map = jsonDecode(await profileFile.readAsString()) as Map<String, dynamic>;
        displayName = map['displayName'] as String?;
      } catch (_) {
        // Beschädigte/leere Datei - einfach ohne Namen weitermachen.
      }
    }

    Uint8List? signature;
    final signatureFile = await _signatureFile;
    if (await signatureFile.exists()) {
      signature = await signatureFile.readAsBytes();
    }

    return ProfileData(displayName: displayName, signature: signature);
  }

  Future<void> saveDisplayName(String name) async {
    final file = await _profileFile;
    await file.writeAsString(jsonEncode({'displayName': name}));
  }

  Future<void> saveSignature(List<int> pngBytes) async {
    final file = await _signatureFile;
    await file.writeAsBytes(pngBytes, flush: true);
  }

  Future<void> clearSignature() async {
    final file = await _signatureFile;
    if (await file.exists()) await file.delete();
  }
}
