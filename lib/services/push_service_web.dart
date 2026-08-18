import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// Die eigentliche Browser-Logik (Berechtigung anfragen, Service-Worker
/// registrieren, `PushManager.subscribe()` aufrufen) steckt bewusst in
/// EINER einzigen JS-Funktion in `web/index.html`
/// (`zeiterfassungSubscribePush`) statt in mehreren einzelnen dart:js_interop-
/// Aufrufen - das hält die Interop-Fläche hier klein und leicht
/// nachvollziehbar. Rückgabewert: leerer String bei Erfolg, sonst eine
/// anzeigbare Fehlermeldung.
@JS('zeiterfassungSubscribePush')
external JSPromise<JSString> _subscribePushJs(JSString vapidPublicKey, JSString bearerToken);

/// Web/PWA-Variante: meldet den Browser für Push-Erinnerungen beim Server
/// an. Siehe `server/bin/server.dart` (`_sendMissingEntryReminders`) für
/// die serverseitige Logik.
class PushService {
  PushService._internal();
  static final PushService instance = PushService._internal();

  Uri _apiUri(String pathAndQuery) => Uri.base.resolve(pathAndQuery);

  /// Fragt Benachrichtigungs-Berechtigung an, registriert den
  /// Push-Service-Worker, abonniert beim Browser und meldet das Abo beim
  /// Server an. Gibt bei Erfolg null zurück, sonst eine anzeigbare
  /// Fehlermeldung.
  Future<String?> subscribe() async {
    final authHeader = AuthService.instance.authHeaders['authorization'];
    if (authHeader == null) return 'Nicht angemeldet';
    final bearerToken = authHeader.replaceFirst('Bearer ', '');

    final keyResponse = await http.get(_apiUri('/api/push/public-key'));
    if (keyResponse.statusCode != 200) return 'Server nicht erreichbar';
    final keyMap = jsonDecode(keyResponse.body) as Map<String, dynamic>;
    final publicKey = keyMap['publicKey'] as String?;
    if (publicKey == null) {
      return 'Push ist auf diesem Server nicht aktiviert (VAPID-Schlüssel fehlen)';
    }

    final result = await _subscribePushJs(publicKey.toJS, bearerToken.toJS).toDart;
    final message = result.toDart;
    return message.isEmpty ? null : message;
  }

  /// Löst sofort eine Test-Benachrichtigung über den Server aus - so lässt
  /// sich der komplette Weg direkt prüfen, ohne bis 16:30 Uhr zu warten.
  Future<bool> sendTestNotification() async {
    final response = await http.post(
      _apiUri('/api/push/test'),
      headers: AuthService.instance.authHeaders,
    );
    return response.statusCode == 200;
  }
}
