import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/time_entry.dart';

/// Kapselt den Zugriff auf die Daten - für die Web/PWA-Variante.
///
/// Anders als auf iOS/Windows/etc. werden Daten hier NICHT lokal im Browser
/// gespeichert, sondern per REST-API vom mitgelieferten Backend-Server
/// geholt/gespeichert (siehe `server/`). Der Server legt sie dauerhaft in
/// einem Docker-Volume ab - so bleiben die Daten erhalten, egal welches
/// Gerät/Browser die Seite öffnet, und sie überleben einen Container-Neustart.
///
/// Achtung: Es gibt (bisher) kein Nutzerkonzept/Login - alle Einträge landen
/// in einem gemeinsamen Topf.
///
/// `Uri.base` liefert im Browser zuverlässig die aktuelle Seiten-URL (Origin
/// + Pfad) - darüber werden alle API-Aufrufe absolut und funktionieren egal
/// unter welcher Adresse/Port die App gehostet wird.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Uri _apiUri(String pathAndQuery) => Uri.base.resolve(pathAndQuery);

  Future<int> insertEntry(TimeEntry entry) async {
    final response = await http.post(
      _apiUri('/api/entries'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(entry.toInsertMap()),
    );
    _checkOk(response);
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return map['id'] as int;
  }

  Future<int> updateEntry(TimeEntry entry) async {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError('updateEntry benötigt eine vorhandene id');
    }
    final response = await http.put(
      _apiUri('/api/entries/$id'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(entry.toInsertMap()),
    );
    _checkOk(response);
    return id;
  }

  Future<void> deleteEntry(int id) async {
    final response = await http.delete(_apiUri('/api/entries/$id'));
    _checkOk(response);
  }

  Future<List<TimeEntry>> entriesForDay(DateTime day) async {
    final dateOnly = DateTime(day.year, day.month, day.day);
    final response = await http.get(
      _apiUri('/api/entries/day?date=${dateOnly.toIso8601String()}'),
    );
    return _decodeList(response);
  }

  Future<List<TimeEntry>> entriesForMonth(int year, int month) async {
    final response = await http.get(
      _apiUri('/api/entries/month?year=$year&month=$month'),
    );
    return _decodeList(response);
  }

  /// Alle Einträge in einem Datumsbereich [startInclusive, endExclusive).
  Future<List<TimeEntry>> entriesForDateRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    final response = await http.get(
      _apiUri(
        '/api/entries/range?start=${startInclusive.toIso8601String()}'
        '&end=${endExclusive.toIso8601String()}',
      ),
    );
    return _decodeList(response);
  }

  /// Alle Einträge der Kalenderwoche (Montag-Sonntag), in der [anyDayInWeek] liegt.
  Future<List<TimeEntry>> entriesForWeek(DateTime anyDayInWeek) async {
    final dateOnly = DateTime(anyDayInWeek.year, anyDayInWeek.month, anyDayInWeek.day);
    final monday = dateOnly.subtract(Duration(days: dateOnly.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    return entriesForDateRange(monday, nextMonday);
  }

  /// Die zuletzt verwendeten, unterschiedlichen Tätigkeitstexte (für
  /// Schnellauswahl beim Anlegen eines neuen Eintrags).
  Future<List<String>> recentActivities({int limit = 8}) async {
    final response = await http.get(_apiUri('/api/recent-activities?limit=$limit'));
    _checkOk(response);
    return (jsonDecode(response.body) as List).cast<String>();
  }

  /// Sucht Einträge, deren Kunde/Werkstatt-Name oder Tätigkeit den
  /// Suchbegriff enthält (Groß-/Kleinschreibung wird ignoriert, das
  /// übernimmt der Server). Neueste Einträge zuerst.
  Future<List<TimeEntry>> searchEntries(String query) async {
    final needle = query.trim();
    if (needle.isEmpty) return [];
    final response = await http.get(
      _apiUri('/api/search?q=${Uri.encodeQueryComponent(needle)}'),
    );
    return _decodeList(response);
  }

  /// Alle bisher verwendeten Kundennamen (für Schnellauswahl), sortiert.
  Future<List<String>> distinctCustomerNames() async {
    final response = await http.get(_apiUri('/api/customers'));
    _checkOk(response);
    return (jsonDecode(response.body) as List).cast<String>();
  }

  List<TimeEntry> _decodeList(http.Response response) {
    _checkOk(response);
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => TimeEntry.fromMap((e as Map).cast<String, Object?>()))
        .toList();
  }

  void _checkOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server-Fehler (${response.statusCode}): ${response.body}');
    }
  }
}
