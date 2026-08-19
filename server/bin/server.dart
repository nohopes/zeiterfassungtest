import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcrypt/bcrypt.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:zeiterfassung_server/web_push.dart' as web_push;

/// Backend-Server für die Zeiterfassung-PWA.
///
/// Speichert alle Einträge server-seitig in einer sembast-Datenbank auf
/// einem gemounteten Docker-Volume (Standard: /data), statt lokal im
/// Browser. Jeder Nutzer sieht ausschließlich seine eigenen Einträge - dafür
/// braucht jede Anfrage (außer Login) einen gültigen Bearer-Token im
/// Authorization-Header.
///
/// Die Datenlogik (Filter/Sortierung) ist bewusst identisch zu der im
/// Client (`lib/db/database_helper.dart`) gehalten, nur zusätzlich immer
/// auf die eingeloggte userId gefiltert.
final _store = intMapStoreFactory.store('time_entries');
final _usersStore = intMapStoreFactory.store('users');
final _sessionsStore = stringMapStoreFactory.store('sessions');
final _presetActivitiesStore = intMapStoreFactory.store('preset_activities');
final _pushSubscriptionsStore = intMapStoreFactory.store('push_subscriptions');

late Database _db;
late String _webDir;

// --- Brute-Force-Schutz für den Login ------------------------------------
//
// Rein im Arbeitsspeicher (kein Problem, ein Server-Neustart löscht die
// Sperren einfach wieder - für eine kleine, selbstgehostete Handwerker-App
// reicht das völlig, ohne Komplexität einer externen Rate-Limit-Lösung).
// Nach [_maxLoginFailures] Fehlversuchen innerhalb von [_loginFailureWindow]
// wird der jeweilige Benutzername für [_loginLockoutDuration] gesperrt.
class _LoginAttempts {
  int failures = 0;
  DateTime firstFailureAt = DateTime.now();
  DateTime? lockedUntil;
}

final _loginAttempts = <String, _LoginAttempts>{};
const _maxLoginFailures = 5;
const _loginFailureWindow = Duration(minutes: 15);
const _loginLockoutDuration = Duration(minutes: 15);

bool _isLoginLocked(String username) {
  final state = _loginAttempts[username.toLowerCase()];
  final lockedUntil = state?.lockedUntil;
  if (lockedUntil == null) return false;
  if (DateTime.now().isAfter(lockedUntil)) {
    _loginAttempts.remove(username.toLowerCase());
    return false;
  }
  return true;
}

void _recordLoginFailure(String username) {
  final key = username.toLowerCase();
  final now = DateTime.now();
  final state = _loginAttempts.putIfAbsent(key, () => _LoginAttempts());
  if (now.difference(state.firstFailureAt) > _loginFailureWindow) {
    state.failures = 0;
    state.firstFailureAt = now;
  }
  state.failures++;
  if (state.failures >= _maxLoginFailures) {
    state.lockedUntil = now.add(_loginLockoutDuration);
  }
}

void _recordLoginSuccess(String username) => _loginAttempts.remove(username.toLowerCase());

// --- Session-Ablauf --------------------------------------------------------
//
// Ein Bearer-Token ist ab Ausstellung [_sessionMaxAge] lang gültig - danach
// muss man sich neu einloggen. Verhindert, dass ein einmal ausgestellter
// Token (z. B. bei einem verlorenen/verkauften Gerät) für immer gültig
// bleibt, ohne dass man sich bei jedem App-Start neu anmelden müsste.
const _sessionMaxAge = Duration(days: 180);

// --- Push-Benachrichtigungen (siehe lib/web_push.dart) --------------------
//
// Erinnert Mo-Fr um 16:30 (Europe/Berlin) jeden Nutzer ohne heutigen
// Eintrag. Ohne VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY bleibt die Funktion
// komplett deaktiviert (kein Fehler, nur eine Warnung im Log) - der Server
// läuft dann ganz normal ohne Push weiter.
web_push.ECPrivateKey? _vapidPrivateKey;
String? _vapidPublicKeyRaw;
String _vapidSubject = 'mailto:kontakt@example.com';
DateTime? _lastReminderRunDate;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final dataDir = Platform.environment['DATA_DIR'] ?? '/data';
  _webDir = Platform.environment['WEB_DIR'] ?? '/app/web';

  final dir = Directory(dataDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _db = await databaseFactoryIo.openDatabase('$dataDir/zeiterfassung.db');
  await _ensureAdminBootstrap();
  tz_data.initializeTimeZones();
  _initPush();
  _startReminderScheduler();

  final router = Router()
    ..post('/api/auth/login', _login)
    ..post('/api/auth/logout', _logout)
    ..get('/api/auth/me', _me)
    ..get('/api/profile', _getProfile)
    ..put('/api/profile', _updateProfile)
    ..get('/api/admin/users', _adminListUsers)
    ..post('/api/admin/users', _adminCreateUser)
    ..delete('/api/admin/users/<id>', _adminDeleteUser)
    ..get('/api/entries/day', _entriesForDay)
    ..get('/api/entries/month', _entriesForMonth)
    ..get('/api/entries/range', _entriesForRange)
    ..get('/api/recent-activities', _recentActivities)
    ..get('/api/top-activities', _topActivities)
    ..get('/api/preset-activities', _listPresetActivities)
    ..post('/api/preset-activities', _createPresetActivity)
    ..put('/api/preset-activities/<id>', _updatePresetActivity)
    ..delete('/api/preset-activities/<id>', _deletePresetActivity)
    ..get('/api/push/public-key', _pushPublicKey)
    ..post('/api/push/subscribe', _pushSubscribe)
    ..post('/api/push/unsubscribe', _pushUnsubscribe)
    ..post('/api/push/test', _pushTest)
    ..get('/api/search', _search)
    ..get('/api/customers', _customers)
    ..post('/api/entries', _insertEntry)
    ..put('/api/entries/<id>', _updateEntry)
    ..delete('/api/entries/<id>', _deleteEntry);

  final staticHandler = createStaticHandler(_webDir, defaultDocument: 'index.html');

  final cascade = Cascade().add(router.call).add(staticHandler).add(_spaFallback);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_securityHeaders())
      .addHandler(cascade.handler);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('Zeiterfassung-Server läuft auf Port ${server.port} (Daten: $dataDir, Web: $_webDir)');
}

/// Ein paar einfache, risikofreie Sicherheits-Header auf jede Antwort -
/// Defense-in-Depth, kein Ersatz für die eigentliche Auth-Logik oben.
Middleware _securityHeaders() {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      return response.change(headers: {
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'Referrer-Policy': 'no-referrer',
      });
    };
  };
}

// --- Login-Bootstrap ---------------------------------------------------

/// Legt beim allerersten Start (noch kein Nutzer vorhanden) automatisch
/// einen Admin-Account aus den Umgebungsvariablen ADMIN_USERNAME/
/// ADMIN_PASSWORD an. Ohne diese Variablen kann sich niemand einloggen -
/// das wird dann klar im Log ausgegeben.
Future<void> _ensureAdminBootstrap() async {
  final anyUser = await _usersStore.find(_db, finder: Finder(limit: 1));
  if (anyUser.isNotEmpty) return;

  final username = Platform.environment['ADMIN_USERNAME'];
  final password = Platform.environment['ADMIN_PASSWORD'];
  if (username == null || password == null || username.trim().isEmpty || password.isEmpty) {
    // ignore: avoid_print
    print(
      'WARNUNG: Noch kein Nutzer vorhanden und ADMIN_USERNAME/ADMIN_PASSWORD '
      'sind nicht gesetzt - es kann sich aktuell niemand anmelden! Bitte '
      'beide Umgebungsvariablen setzen und den Container neu starten.',
    );
    return;
  }

  final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());
  await _usersStore.add(_db, {
    'username': username.trim(),
    'passwordHash': passwordHash,
    'isAdmin': true,
  });
  // ignore: avoid_print
  print('Admin-Konto "${username.trim()}" wurde angelegt.');
}

/// Fängt alle Anfragen ab, die weder von der API noch von einer echten
/// statischen Datei bedient wurden, und liefert index.html aus (einfaches
/// SPA-Fallback - hier praktisch nur relevant für "/").
Future<Response> _spaFallback(Request request) async {
  final indexFile = File('$_webDir/index.html');
  if (await indexFile.exists()) {
    return Response.ok(
      await indexFile.readAsBytes(),
      headers: {'content-type': 'text/html'},
    );
  }
  return Response.notFound('Not found');
}

// --- Auth-Hilfsfunktionen ------------------------------------------------

String _generateToken() {
  final rand = Random.secure();
  final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
  return base64Url.encode(bytes);
}

/// Liest den Bearer-Token aus dem Authorization-Header und gibt die
/// zugehörige userId zurück, oder null falls kein gültiger Token vorliegt.
Future<int?> _authenticate(Request request) async {
  final authHeader = request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;
  final token = authHeader.substring('Bearer '.length);
  final session = await _sessionsStore.record(token).get(_db);
  if (session == null) return null;

  final createdAtRaw = session['createdAt'] as String?;
  final createdAt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;
  if (createdAt != null && DateTime.now().difference(createdAt) > _sessionMaxAge) {
    await _sessionsStore.record(token).delete(_db);
    return null;
  }

  return session['userId'] as int;
}

Response _unauthorized() => Response(
      401,
      body: jsonEncode({'error': 'Nicht angemeldet'}),
      headers: {'content-type': 'application/json'},
    );

Response _forbidden() => Response(
      403,
      body: jsonEncode({'error': 'Keine Berechtigung'}),
      headers: {'content-type': 'application/json'},
    );

Response _badRequest(String message) => Response(
      400,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );

Response _jsonList(List<RecordSnapshot<int, Map<String, Object?>>> records) {
  final list = records.map((r) => {...r.value, 'id': r.key}).toList();
  return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
}

Map<String, Object?> _publicUser(int id, Map<String, Object?> value) => {
      'id': id,
      'username': value['username'],
      'isAdmin': value['isAdmin'] == true,
    };

// --- Auth-Endpunkte --------------------------------------------------------

Future<Response> _login(Request request) async {
  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final username = (map['username'] as String? ?? '').trim();
  final password = map['password'] as String? ?? '';
  if (username.isEmpty || password.isEmpty) {
    return _badRequest('Benutzername und Passwort erforderlich');
  }

  if (_isLoginLocked(username)) {
    return Response(
      429,
      body: jsonEncode({
        'error': 'Zu viele Fehlversuche - bitte in ein paar Minuten erneut versuchen',
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  final records = await _usersStore.find(
    _db,
    finder: Finder(filter: Filter.equals('username', username)),
  );
  if (records.isEmpty) {
    _recordLoginFailure(username);
    return _unauthorized();
  }
  final userRecord = records.first;
  final passwordHash = userRecord.value['passwordHash'] as String;
  if (!BCrypt.checkpw(password, passwordHash)) {
    _recordLoginFailure(username);
    return _unauthorized();
  }
  _recordLoginSuccess(username);

  final token = _generateToken();
  await _sessionsStore.record(token).put(_db, {
    'userId': userRecord.key,
    'createdAt': DateTime.now().toIso8601String(),
  });

  return Response.ok(
    jsonEncode({
      'token': token,
      'user': _publicUser(userRecord.key, userRecord.value),
    }),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _logout(Request request) async {
  final authHeader = request.headers['authorization'];
  if (authHeader != null && authHeader.startsWith('Bearer ')) {
    final token = authHeader.substring('Bearer '.length);
    await _sessionsStore.record(token).delete(_db);
  }
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

Future<Response> _me(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();
  final userRecord = await _usersStore.record(userId).get(_db);
  if (userRecord == null) return _unauthorized();
  return Response.ok(
    jsonEncode(_publicUser(userId, userRecord)),
    headers: {'content-type': 'application/json'},
  );
}

/// Persönliche Angaben für den Werkstatt-Wochenbericht (Name/Unterschrift) -
/// getrennt von [_me]/[_publicUser], da diese Felder rein privat sind
/// (die Unterschrift landet nie in der Admin-Nutzerliste).
Future<Response> _getProfile(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();
  final userRecord = await _usersStore.record(userId).get(_db);
  if (userRecord == null) return _unauthorized();
  return Response.ok(
    jsonEncode({
      'displayName': userRecord['displayName'],
      'signature': userRecord['signature'],
    }),
    headers: {'content-type': 'application/json'},
  );
}

/// Aktualisiert nur die Felder, die im Body tatsächlich mitgeschickt
/// wurden (partielles Update) - so kann z. B. nur der Name gespeichert
/// werden, ohne die Unterschrift zu berühren, und umgekehrt.
Future<Response> _updateProfile(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final updates = <String, Object?>{};
  if (map.containsKey('displayName')) {
    updates['displayName'] = (map['displayName'] as String?)?.trim();
  }
  if (map.containsKey('signature')) {
    updates['signature'] = map['signature'] as String?;
  }
  if (updates.isNotEmpty) {
    await _usersStore.record(userId).update(_db, updates);
  }
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

// --- Admin-Endpunkte (Nutzerverwaltung) -------------------------------

/// Prüft Login + Admin-Recht. Gibt bei Erfolg die userId des Anfragenden
/// zurück, sonst null (die passende Fehlerantwort wird dann direkt vom
/// Aufrufer über [_unauthorized]/[_forbidden] erzeugt).
Future<int?> _requireAdmin(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return null;
  final requester = await _usersStore.record(userId).get(_db);
  if (requester == null || requester['isAdmin'] != true) return null;
  return userId;
}

Future<Response> _adminListUsers(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();
  if (await _requireAdmin(request) == null) return _forbidden();

  final records = await _usersStore.find(_db);
  final list = records.map((r) => _publicUser(r.key, r.value)).toList();
  return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
}

Future<Response> _adminCreateUser(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();
  if (await _requireAdmin(request) == null) return _forbidden();

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final username = (map['username'] as String? ?? '').trim();
  final password = map['password'] as String? ?? '';
  final isAdmin = map['isAdmin'] == true;
  if (username.isEmpty || password.length < 8) {
    return _badRequest('Benutzername und ein Passwort (mind. 8 Zeichen) erforderlich');
  }

  final existing = await _usersStore.find(
    _db,
    finder: Finder(filter: Filter.equals('username', username)),
  );
  if (existing.isNotEmpty) return _badRequest('Benutzername bereits vergeben');

  final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());
  final newId = await _usersStore.add(_db, {
    'username': username,
    'passwordHash': passwordHash,
    'isAdmin': isAdmin,
  });
  return Response.ok(jsonEncode({'id': newId}), headers: {'content-type': 'application/json'});
}

Future<Response> _adminDeleteUser(Request request, String id) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();
  if (await _requireAdmin(request) == null) return _forbidden();

  final parsedId = int.tryParse(id);
  if (parsedId == null) return _badRequest('ungültige id');
  if (parsedId == userId) {
    return _badRequest('Du kannst dich nicht selbst löschen');
  }

  await _usersStore.record(parsedId).delete(_db);

  // Alle Sessions dieses Nutzers ungültig machen, damit er nicht mit einem
  // bereits ausgestellten Token weiterarbeiten kann.
  final sessions = await _sessionsStore.find(
    _db,
    finder: Finder(filter: Filter.equals('userId', parsedId)),
  );
  for (final s in sessions) {
    await _sessionsStore.record(s.key).delete(_db);
  }

  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

// --- Eintrags-Endpunkte (immer auf die eingeloggte userId gefiltert) ---

Future<Response> _entriesForDay(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final dateParam = request.url.queryParameters['date'];
  if (dateParam == null) return _badRequest('date fehlt');
  final d = DateTime.parse(dateParam);
  final dateOnly = DateTime(d.year, d.month, d.day).toIso8601String();
  final finder = Finder(
    filter: Filter.and([
      Filter.equals('date', dateOnly),
      Filter.equals('userId', userId),
    ]),
    sortOrders: [SortOrder('startHour'), SortOrder('startMinute')],
  );
  final records = await _store.find(_db, finder: finder);
  return _jsonList(records);
}

Future<Response> _entriesForMonth(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final year = int.tryParse(request.url.queryParameters['year'] ?? '');
  final month = int.tryParse(request.url.queryParameters['month'] ?? '');
  if (year == null || month == null) return _badRequest('year/month fehlt');
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 1);
  final finder = Finder(
    filter: Filter.and([
      Filter.greaterThanOrEquals('date', start.toIso8601String()),
      Filter.lessThan('date', end.toIso8601String()),
      Filter.equals('userId', userId),
    ]),
    sortOrders: [
      SortOrder('date'),
      SortOrder('startHour'),
      SortOrder('startMinute'),
    ],
  );
  final records = await _store.find(_db, finder: finder);
  return _jsonList(records);
}

/// Bedient sowohl entriesForDateRange als auch entriesForWeek (die Woche
/// wird auf Client-Seite in Montag/nächster-Montag umgerechnet und dann
/// hierüber abgefragt).
Future<Response> _entriesForRange(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final startParam = request.url.queryParameters['start'];
  final endParam = request.url.queryParameters['end'];
  if (startParam == null || endParam == null) return _badRequest('start/end fehlt');
  final start = DateTime.parse(startParam);
  final end = DateTime.parse(endParam);
  final finder = Finder(
    filter: Filter.and([
      Filter.greaterThanOrEquals('date', start.toIso8601String()),
      Filter.lessThan('date', end.toIso8601String()),
      Filter.equals('userId', userId),
    ]),
    sortOrders: [
      SortOrder('date'),
      SortOrder('startHour'),
      SortOrder('startMinute'),
    ],
  );
  final records = await _store.find(_db, finder: finder);
  return _jsonList(records);
}

Future<Response> _recentActivities(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 8;
  final finder = Finder(
    filter: Filter.equals('userId', userId),
    sortOrders: [SortOrder('date', false), SortOrder('startHour', false)],
  );
  final records = await _store.find(_db, finder: finder);
  final seen = <String>{};
  final result = <String>[];
  for (final r in records) {
    final activity = (r.value['activity'] as String? ?? '').trim();
    if (activity.isEmpty) continue;
    if (seen.add(activity)) {
      result.add(activity);
      if (result.length >= limit) break;
    }
  }
  return Response.ok(jsonEncode(result), headers: {'content-type': 'application/json'});
}

/// Die häufigsten Tätigkeitstexte über alle Einträge des Nutzers hinweg
/// (im Gegensatz zu [_recentActivities], die nach Zeitpunkt sortiert).
Future<Response> _topActivities(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 5;
  final records = await _store.find(_db, finder: Finder(filter: Filter.equals('userId', userId)));
  final counts = <String, int>{};
  for (final r in records) {
    final activity = (r.value['activity'] as String? ?? '').trim();
    if (activity.isEmpty) continue;
    counts[activity] = (counts[activity] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final result = sorted.take(limit).map((e) => e.key).toList();
  return Response.ok(jsonEncode(result), headers: {'content-type': 'application/json'});
}

// --- Tätigkeits-Vorlagen (jeder Nutzer verwaltet seine eigenen) -------

Future<Response> _listPresetActivities(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final records = await _presetActivitiesStore.find(
    _db,
    finder: Finder(filter: Filter.equals('userId', userId)),
  );
  final list = records.map((r) => {'id': r.key, 'text': r.value['text']}).toList();
  return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
}

Future<Response> _createPresetActivity(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final text = (map['text'] as String? ?? '').trim();
  if (text.isEmpty) return _badRequest('Text darf nicht leer sein');

  final id = await _presetActivitiesStore.add(_db, {'userId': userId, 'text': text});
  return Response.ok(jsonEncode({'id': id, 'text': text}), headers: {'content-type': 'application/json'});
}

Future<Response> _updatePresetActivity(Request request, String id) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final parsedId = int.tryParse(id);
  if (parsedId == null) return _badRequest('ungültige id');

  final existing = await _presetActivitiesStore.record(parsedId).get(_db);
  if (existing == null || existing['userId'] != userId) {
    return Response.notFound(
      jsonEncode({'error': 'Vorlage nicht gefunden'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final text = (map['text'] as String? ?? '').trim();
  if (text.isEmpty) return _badRequest('Text darf nicht leer sein');

  await _presetActivitiesStore.record(parsedId).update(_db, {'userId': userId, 'text': text});
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

Future<Response> _deletePresetActivity(Request request, String id) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final parsedId = int.tryParse(id);
  if (parsedId == null) return _badRequest('ungültige id');

  final existing = await _presetActivitiesStore.record(parsedId).get(_db);
  if (existing == null || existing['userId'] != userId) {
    return Response.notFound(
      jsonEncode({'error': 'Vorlage nicht gefunden'}),
      headers: {'content-type': 'application/json'},
    );
  }

  await _presetActivitiesStore.record(parsedId).delete(_db);
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

// --- Push-Benachrichtigungen --------------------------------------------

/// Lädt die VAPID-Schlüssel aus den Umgebungsvariablen. Ohne gültige
/// Schlüssel bleiben Push-Benachrichtigungen komplett deaktiviert - der
/// Server läuft trotzdem ganz normal weiter (nur eine Warnung im Log).
void _initPush() {
  final publicKey = Platform.environment['VAPID_PUBLIC_KEY'];
  final privateKey = Platform.environment['VAPID_PRIVATE_KEY'];
  final subject = Platform.environment['VAPID_SUBJECT'];
  if (publicKey == null ||
      privateKey == null ||
      publicKey.trim().isEmpty ||
      privateKey.trim().isEmpty) {
    // ignore: avoid_print
    print(
      'Hinweis: VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY nicht gesetzt - '
      'Push-Benachrichtigungen sind deaktiviert.',
    );
    return;
  }
  try {
    _vapidPrivateKey = web_push.vapidPrivateKeyFromBase64Url(privateKey.trim());
    _vapidPublicKeyRaw = publicKey.trim();
    if (subject != null && subject.trim().isNotEmpty) _vapidSubject = subject.trim();
    // ignore: avoid_print
    print('Push-Benachrichtigungen aktiviert.');
  } catch (e) {
    // ignore: avoid_print
    print('WARNUNG: VAPID-Schlüssel ungültig ($e) - Push-Benachrichtigungen sind deaktiviert.');
  }
}

/// Prüft jede Minute, ob gerade Mo-Fr 16:30 Uhr (Europe/Berlin) ist, und
/// verschickt dann höchstens einmal pro Tag die Erinnerungen.
void _startReminderScheduler() {
  if (_vapidPrivateKey == null) return;
  Timer.periodic(const Duration(minutes: 1), (_) async {
    final berlin = tz.getLocation('Europe/Berlin');
    final now = tz.TZDateTime.now(berlin);
    final isWeekday = now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
    final isReminderTime = now.hour == 16 && now.minute == 30;
    final today = DateTime(now.year, now.month, now.day);
    if (isWeekday && isReminderTime && _lastReminderRunDate != today) {
      _lastReminderRunDate = today;
      try {
        await _sendMissingEntryReminders();
      } catch (e) {
        // ignore: avoid_print
        print('Fehler beim Versand der Tages-Erinnerungen: $e');
      }
    }
  });
}

/// Schickt jedem Nutzer ohne heutigen Eintrag (Europe/Berlin-Datum) eine
/// Erinnerung an alle seine registrierten Geräte/Browser.
Future<void> _sendMissingEntryReminders() async {
  final berlin = tz.getLocation('Europe/Berlin');
  final now = tz.TZDateTime.now(berlin);
  final todayIso = DateTime(now.year, now.month, now.day).toIso8601String();

  final allUsers = await _usersStore.find(_db);
  for (final userRecord in allUsers) {
    final userId = userRecord.key;
    final todaysEntries = await _store.find(
      _db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('userId', userId),
          Filter.equals('date', todayIso),
        ]),
      ),
    );
    if (todaysEntries.isNotEmpty) continue;

    await _sendPushToUser(
      userId,
      title: 'Stunden Logbuch',
      body: 'Für heute fehlt noch ein Eintrag im Logbuch.',
    );
  }
}

/// Verschickt eine Push-Benachrichtigung an alle Geräte/Browser eines
/// Nutzers. Abgelaufene/ungültige Abos (410/404 vom Push-Dienst) werden
/// automatisch entfernt.
Future<void> _sendPushToUser(int userId, {required String title, required String body}) async {
  if (_vapidPrivateKey == null || _vapidPublicKeyRaw == null) return;

  final subs = await _pushSubscriptionsStore.find(
    _db,
    finder: Finder(filter: Filter.equals('userId', userId)),
  );
  if (subs.isEmpty) return;

  final payload = utf8.encode(jsonEncode({'title': title, 'body': body}));

  for (final subRecord in subs) {
    final statusCode = await _sendPushToSubscription(subRecord.value, payload);
    if (statusCode == 404 || statusCode == 410) {
      await _pushSubscriptionsStore.record(subRecord.key).delete(_db);
    }
  }
}

/// Sendet eine einzelne verschlüsselte Push-Nachricht an einen
/// Push-Endpunkt. Gibt den HTTP-Statuscode der Antwort zurück (oder -1 bei
/// einem Netzwerkfehler).
Future<int> _sendPushToSubscription(Map<String, Object?> sub, List<int> payload) async {
  final endpoint = sub['endpoint'] as String;
  final p256dh = sub['p256dh'] as String;
  final auth = sub['auth'] as String;

  try {
    final encryptedBody = web_push.encryptWebPush(
      subscriberPublicKeyBytes: web_push.decodeBase64UrlField(p256dh),
      subscriberAuthSecret: web_push.decodeBase64UrlField(auth),
      plaintext: Uint8List.fromList(payload),
    );

    final endpointUri = Uri.parse(endpoint);
    final audience = '${endpointUri.scheme}://${endpointUri.host}'
        '${endpointUri.hasPort ? ':${endpointUri.port}' : ''}';
    final jwt = web_push.buildVapidJwt(
      privateKey: _vapidPrivateKey!,
      audience: audience,
      subject: _vapidSubject,
    );

    final client = HttpClient();
    try {
      final request = await client.postUrl(endpointUri);
      request.headers.set('Authorization', 'vapid t=$jwt, k=$_vapidPublicKeyRaw');
      request.headers.set('Content-Encoding', 'aes128gcm');
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.headers.set('TTL', '86400');
      request.contentLength = encryptedBody.length;
      request.add(encryptedBody);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close();
    }
  } catch (e) {
    // ignore: avoid_print
    print('Push-Versand fehlgeschlagen: $e');
    return -1;
  }
}

Future<Response> _pushPublicKey(Request request) async {
  return Response.ok(
    jsonEncode({'publicKey': _vapidPublicKeyRaw}),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _pushSubscribe(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();
  if (_vapidPublicKeyRaw == null) return _badRequest('Push ist auf diesem Server nicht aktiviert');

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final endpoint = map['endpoint'] as String?;
  final keys = map['keys'] as Map<String, dynamic>?;
  final p256dh = keys?['p256dh'] as String?;
  final auth = keys?['auth'] as String?;
  if (endpoint == null || p256dh == null || auth == null) {
    return _badRequest('endpoint/keys fehlen');
  }

  // Ein evtl. schon vorhandenes Abo mit demselben Endpoint ersetzen statt
  // zu duplizieren (z. B. wenn der Browser die Schlüssel rotiert hat).
  await _deleteSubscriptionsForEndpoint(userId, endpoint);
  await _pushSubscriptionsStore.add(_db, {
    'userId': userId,
    'endpoint': endpoint,
    'p256dh': p256dh,
    'auth': auth,
  });
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

Future<Response> _pushUnsubscribe(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final endpoint = map['endpoint'] as String?;
  if (endpoint == null) return _badRequest('endpoint fehlt');

  await _deleteSubscriptionsForEndpoint(userId, endpoint);
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

Future<void> _deleteSubscriptionsForEndpoint(int userId, String endpoint) async {
  final existing = await _pushSubscriptionsStore.find(
    _db,
    finder: Finder(
      filter: Filter.and([
        Filter.equals('userId', userId),
        Filter.equals('endpoint', endpoint),
      ]),
    ),
  );
  for (final e in existing) {
    await _pushSubscriptionsStore.record(e.key).delete(_db);
  }
}

/// Verschickt sofort eine Test-Benachrichtigung an den eingeloggten Nutzer -
/// so lässt sich der komplette Weg (Abo -> Verschlüsselung -> Versand ->
/// Service-Worker) direkt nach dem Aktivieren prüfen, ohne bis 16:30 zu
/// warten.
Future<Response> _pushTest(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();
  if (_vapidPrivateKey == null) return _badRequest('Push ist auf diesem Server nicht aktiviert');

  await _sendPushToUser(
    userId,
    title: 'Stunden Logbuch',
    body: 'Test-Benachrichtigung - wenn du das hier siehst, funktioniert alles!',
  );
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}

Future<Response> _search(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final needle = (request.url.queryParameters['q'] ?? '').trim().toLowerCase();
  if (needle.isEmpty) {
    return Response.ok(jsonEncode(const []), headers: {'content-type': 'application/json'});
  }
  final finder = Finder(
    filter: Filter.equals('userId', userId),
    sortOrders: [SortOrder('date', false), SortOrder('startHour', false)],
  );
  final records = await _store.find(_db, finder: finder);
  final filtered = records.where((r) {
    final name = (r.value['name'] as String? ?? '').toLowerCase();
    final activity = (r.value['activity'] as String? ?? '').toLowerCase();
    return name.contains(needle) || activity.contains(needle);
  }).toList();
  return _jsonList(filtered);
}

Future<Response> _customers(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final finder = Finder(
    filter: Filter.and([
      Filter.equals('isWerkstatt', 0),
      Filter.equals('userId', userId),
      // Urlaub/Krankheit sind keine echten Kundennamen - nicht mit
      // aufführen.
      Filter.isNull('absenceType'),
    ]),
  );
  final records = await _store.find(_db, finder: finder);
  final names = records.map((r) => r.value['name'] as String).toSet().toList();
  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return Response.ok(jsonEncode(names), headers: {'content-type': 'application/json'});
}

Future<Response> _insertEntry(Request request) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final record = Map<String, Object?>.from(map)..['userId'] = userId;
  final id = await _store.add(_db, record);
  return Response.ok(jsonEncode({'id': id}), headers: {'content-type': 'application/json'});
}

Future<Response> _updateEntry(Request request, String id) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final parsedId = int.tryParse(id);
  if (parsedId == null) return _badRequest('ungültige id');

  final existing = await _store.record(parsedId).get(_db);
  if (existing == null || existing['userId'] != userId) {
    return Response.notFound(
      jsonEncode({'error': 'Eintrag nicht gefunden'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final record = Map<String, Object?>.from(map)..['userId'] = userId;
  await _store.record(parsedId).update(_db, record);
  return Response.ok(jsonEncode({'id': parsedId}), headers: {'content-type': 'application/json'});
}

Future<Response> _deleteEntry(Request request, String id) async {
  final userId = await _authenticate(request);
  if (userId == null) return _unauthorized();

  final parsedId = int.tryParse(id);
  if (parsedId == null) return _badRequest('ungültige id');

  final existing = await _store.record(parsedId).get(_db);
  if (existing == null || existing['userId'] != userId) {
    return Response.notFound(
      jsonEncode({'error': 'Eintrag nicht gefunden'}),
      headers: {'content-type': 'application/json'},
    );
  }

  await _store.record(parsedId).delete(_db);
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}
