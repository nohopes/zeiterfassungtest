import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/profile_data.dart';
import 'auth_service.dart';

/// Web/PWA-Variante: Name und Unterschrift liegen am eingeloggten
/// Nutzerkonto auf dem Server (siehe server/bin/server.dart, `/api/profile`).
class ProfileService {
  ProfileService._internal();
  static final ProfileService instance = ProfileService._internal();

  Uri _apiUri(String pathAndQuery) => Uri.base.resolve(pathAndQuery);

  Map<String, String> _headers([Map<String, String>? extra]) => {
        ...AuthService.instance.authHeaders,
        ...?extra,
      };

  Future<ProfileData> loadProfile() async {
    final response = await http.get(_apiUri('/api/profile'), headers: _headers());
    if (response.statusCode != 200) return const ProfileData();
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final displayName = map['displayName'] as String?;
    final signatureB64 = map['signature'] as String?;
    return ProfileData(
      displayName: displayName,
      signature: signatureB64 == null ? null : base64Decode(signatureB64),
    );
  }

  Future<void> saveDisplayName(String name) async {
    await http.put(
      _apiUri('/api/profile'),
      headers: _headers({'content-type': 'application/json'}),
      body: jsonEncode({'displayName': name}),
    );
  }

  Future<void> saveSignature(List<int> pngBytes) async {
    await http.put(
      _apiUri('/api/profile'),
      headers: _headers({'content-type': 'application/json'}),
      body: jsonEncode({'signature': base64Encode(pngBytes)}),
    );
  }

  Future<void> clearSignature() async {
    await http.put(
      _apiUri('/api/profile'),
      headers: _headers({'content-type': 'application/json'}),
      body: jsonEncode({'signature': null}),
    );
  }
}
