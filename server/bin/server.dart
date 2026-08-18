import 'dart:convert';
import 'dart:io';

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
/// Browser. Dadurch sehen alle Geräte/Browser, die diese Web-App öffnen,
/// dieselben Daten.
///
/// Achtung: Es gibt (bisher) kein Nutzerkonzept/Login. Alle Einträge landen
/// in einem gemeinsamen Topf - für eine einzelne Person genau richtig,
/// falls mehrere Kollegen dieselbe Instanz nutzen, sehen/bearbeiten sie
/// dieselben Einträge.
///
/// Die Datenlogik (Filter/Sortierung) ist bewusst identisch zur
/// lokalen iOS/Windows-Implementierung (`lib/db/database_helper_io.dart`)
/// gehalten, damit sich beide Varianten exakt gleich verhalten.
final _store = intMapStoreFactory.store('time_entries');

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

  final router = Router()
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

Response _badRequest(String message) => Response(
      400,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );

Response _jsonList(List<RecordSnapshot<int, Map<String, Object?>>> records) {
  final list = records.map((r) => {...r.value, 'id': r.key}).toList();
  return Response.ok(jsonEncode(list), headers: {'content-type': 'application/json'});
}

Future<Response> _entriesForDay(Request request) async {
  final dateParam = request.url.queryParameters['date'];
  if (dateParam == null) return _badRequest('date fehlt');
  final d = DateTime.parse(dateParam);
  final dateOnly = DateTime(d.year, d.month, d.day).toIso8601String();
  final finder = Finder(
    filter: Filter.equals('date', dateOnly),
    sortOrders: [SortOrder('startHour'), SortOrder('startMinute')],
  );
  final records = await _store.find(_db, finder: finder);
  return _jsonList(records);
}

Future<Response> _entriesForMonth(Request request) async {
  final year = int.tryParse(request.url.queryParameters['year'] ?? '');
  final month = int.tryParse(request.url.queryParameters['month'] ?? '');
  if (year == null || month == null) return _badRequest('year/month fehlt');
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 1);
  final finder = Finder(
    filter: Filter.and([
      Filter.greaterThanOrEquals('date', start.toIso8601String()),
      Filter.lessThan('date', end.toIso8601String()),
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
  final startParam = request.url.queryParameters['start'];
  final endParam = request.url.queryParameters['end'];
  if (startParam == null || endParam == null) return _badRequest('start/end fehlt');
  final start = DateTime.parse(startParam);
  final end = DateTime.parse(endParam);
  final finder = Finder(
    filter: Filter.and([
      Filter.greaterThanOrEquals('date', start.toIso8601String()),
      Filter.lessThan('date', end.toIso8601String()),
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
  final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 8;
  final finder = Finder(
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
  final needle = (request.url.queryParameters['q'] ?? '').trim().toLowerCase();
  if (needle.isEmpty) {
    return Response.ok(jsonEncode(const []), headers: {'content-type': 'application/json'});
  }
  final finder = Finder(
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
  final finder = Finder(filter: Filter.equals('isWerkstatt', 0));
  final records = await _store.find(_db, finder: finder);
  final names = records.map((r) => r.value['name'] as String).toSet().toList();
  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return Response.ok(jsonEncode(names), headers: {'content-type': 'application/json'});
}

Future<Response> _insertEntry(Request request) async {
  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final id = await _store.add(_db, Map<String, Object?>.from(map));
  return Response.ok(jsonEncode({'id': id}), headers: {'content-type': 'application/json'});
}

Future<Response> _updateEntry(Request request, String id) async {
  final parsedId = int.tryParse(id);
  if (parsedId == null) return _badRequest('ungültige id');
  final body = await request.readAsString();
  final map = jsonDecode(body) as Map<String, dynamic>;
  await _store.record(parsedId).update(_db, Map<String, Object?>.from(map));
  return Response.ok(jsonEncode({'id': parsedId}), headers: {'content-type': 'application/json'});
}

Future<Response> _deleteEntry(Request request, String id) async {
  final parsedId = int.tryParse(id);
  if (parsedId == null) return _badRequest('ungültige id');
  await _store.record(parsedId).delete(_db);
  return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json'});
}
