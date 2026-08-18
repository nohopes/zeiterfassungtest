import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Verwaltet den Login-Status für die Web/PWA-Variante.
///
/// Nur relevant, wenn die App im Browser läuft und gegen den Backend-Server
/// spricht (siehe `database_helper_web.dart`) - auf iOS/Windows gibt es kein
/// Login, dort wird diese Klasse gar nicht erst benutzt.
///
/// Der Token wird nach erfolgreichem Login lokal (SharedPreferences, im
/// Browser landet das im LocalStorage) gespeichert, damit man nach einem
/// Neuladen der Seite nicht jedes Mal neu einloggen muss.
class AuthService extends ChangeNotifier {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  static const _tokenPrefKey = 'auth_token';

  final _prefs = SharedPreferencesAsync();

  String? _token;
  int? _userId;
  String? _username;
  bool _isAdmin = false;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _token != null && _username != null;
  bool get isAdmin => _isAdmin;
  String? get username => _username;
  int? get userId => _userId;

  /// Für authentifizierte REST-Aufrufe: einfach an die vorhandenen Header
  /// mergen (siehe database_helper_web.dart).
  Map<String, String> get authHeaders =>
      _token == null ? {} : {'authorization': 'Bearer $_token'};

  Uri _apiUri(String pathAndQuery) => Uri.base.resolve(pathAndQuery);

  /// Muss einmal beim App-Start aufgerufen werden (z. B. in AuthGate),
  /// bevor isLoggedIn ausgewertet wird. Lädt einen evtl. gespeicherten Token
  /// und prüft, ob er noch gültig ist.
  Future<void> init() async {
    if (_isInitialized) return;
    final storedToken = await _prefs.getString(_tokenPrefKey);
    if (storedToken != null && storedToken.isNotEmpty) {
      _token = storedToken;
      final ok = await _fetchMe();
      if (!ok) {
        await _clearToken();
      }
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// Gibt bei Erfolg null zurück, sonst eine anzeigbare Fehlermeldung.
  Future<String?> login(String username, String password) async {
    try {
      final response = await http.post(
        _apiUri('/api/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      if (response.statusCode == 401) {
        return 'Benutzername oder Passwort falsch';
      }
      if (response.statusCode != 200) {
        return 'Serverfehler (${response.statusCode})';
      }
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      _token = map['token'] as String;
      final user = map['user'] as Map<String, dynamic>;
      _userId = user['id'] as int;
      _username = user['username'] as String;
      _isAdmin = user['isAdmin'] == true;
      await _prefs.setString(_tokenPrefKey, _token!);
      notifyListeners();
      return null;
    } catch (_) {
      return 'Server nicht erreichbar';
    }
  }

  Future<void> logout() async {
    final token = _token;
    if (token != null) {
      try {
        await http.post(
          _apiUri('/api/auth/logout'),
          headers: {'authorization': 'Bearer $token'},
        );
      } catch (_) {
        // Egal ob das klappt - lokal loggen wir in jedem Fall aus.
      }
    }
    await _clearToken();
  }

  /// Lädt die eigenen Nutzerdaten mit dem aktuell gesetzten Token.
  /// Gibt zurück, ob der Token (noch) gültig ist.
  Future<bool> _fetchMe() async {
    try {
      final response = await http.get(
        _apiUri('/api/auth/me'),
        headers: {'authorization': 'Bearer $_token'},
      );
      if (response.statusCode != 200) return false;
      final user = jsonDecode(response.body) as Map<String, dynamic>;
      _userId = user['id'] as int;
      _username = user['username'] as String;
      _isAdmin = user['isAdmin'] == true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearToken() async {
    _token = null;
    _userId = null;
    _username = null;
    _isAdmin = false;
    await _prefs.remove(_tokenPrefKey);
    notifyListeners();
  }
}
