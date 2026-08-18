import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

/// Backend-Server für die Zeiterfassung-PWA.
///
/// Speichert alle Einträge server-seitig in einer sembast-Datenbank auf
/// einem gemounteten Docker-Volume (Standard: /data), statt lokal im
/// Browser. Jeder Nutzer sieht ausschließlich seine eigenen Einträge - dafür
/// braucht jede Anfrage (außer Login) einen gültigen Bearer-Token im
/// Authorization-Header.
///
/// Die Datenlogik (Filter/Sortierung) ist bewusst identisch zur lokalen
/// iOS/Windows-Implementierung (`lib/db/database_helper_io.dart`) gehalten,
/// nur zusätzlich immer auf die eingeloggte userId gefiltert.
final _store = intMapStoreFactory.store('time_entries');
final _usersStore = intMapStoreFactory.store('users');
final _sessionsStore = stringMapStoreFactory.store('sessions');

late Database _db;
late String _webDir;

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

  final router = Router()
    ..post('/api/auth/login', _login)
    ..post('/api/auth/logout', _logout)
    ..get('/api/auth/me', _me)
    ..get('/api/admin/users', _adminListUsers)
    ..post('/api/admin/users', _adminCreateUser)
    ..delete('/api/admin/users/<id>', _adminDeleteUser)
    ..get('/api/entries/day', _entriesForDay)
    ..get('/api/entries/month', _entriesForMonth)
    ..get('/api/entries/range', _entriesForRange)
    ..get('/api/recent-activities', _recentActivities)
    ..get('/api/search', _search)
    ..get('/api/customers', _customers)
    ..post('/api/entries', _insertEntry)
    ..put('/api/entries/<id>', _updateEntry)
    ..delete('/api/entries/<id>', _deleteEntry);

  final staticHandler = createStaticHandler(_webDir, defaultDocument: 'index.html');

  final cascade = Cascade().add(router.call).add(staticHandler).add(_spaFallback);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(cascade.handler);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('Zeiterfassung-Server läuft auf Port ${server.port} (Daten: $dataDir, Web: $_webDir)');
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

  final records = await _usersStore.find(
    _db,
    finder: Finder(filter: Filter.equals('username', username)),
  );
  if (records.isEmpty) return _unauthorized();
  final userRecord = records.first;
  final passwordHash = userRecord.value['passwordHash'] as String;
  if (!BCrypt.checkpw(password, passwordHash)) return _unauthorized();

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
  if (username.isEmpty || password.length < 4) {
    return _badRequest('Benutzername und ein Passwort (mind. 4 Zeichen) erforderlich');
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
