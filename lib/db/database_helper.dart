import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

import '../models/time_entry.dart';

/// Kapselt den Zugriff auf die lokale Datenbank.
///
/// Nutzt sembast (reine Dart-Implementierung, dateibasiert) statt sqflite -
/// dadurch ist keinerlei native Kompilierung oder plattformspezifische
/// FFI-Anbindung nötig. Läuft dadurch identisch auf iOS, Android, Windows,
/// macOS und Linux. Alle Daten bleiben ausschließlich auf dem Gerät.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const _dbFileName = 'zeiterfassung.db';
  final _store = intMapStoreFactory.store('time_entries');

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final path = join(directory.path, _dbFileName);
    return databaseFactoryIo.openDatabase(path);
  }

  Future<int> insertEntry(TimeEntry entry) async {
    final db = await database;
    return _store.add(db, entry.toInsertMap());
  }

  Future<int> updateEntry(TimeEntry entry) async {
    final db = await database;
    final id = entry.id;
    if (id == null) {
      throw ArgumentError('updateEntry benötigt eine vorhandene id');
    }
    await _store.record(id).update(db, entry.toInsertMap());
    return id;
  }

  Future<void> deleteEntry(int id) async {
    final db = await database;
    await _store.record(id).delete(db);
  }

  Future<List<TimeEntry>> entriesForDay(DateTime day) async {
    final db = await database;
    final dateOnly = DateTime(day.year, day.month, day.day).toIso8601String();
    final finder = Finder(
      filter: Filter.equals('date', dateOnly),
      sortOrders: [
        SortOrder('startHour'),
        SortOrder('startMinute'),
      ],
    );
    final records = await _store.find(db, finder: finder);
    return records.map(_fromRecord).toList();
  }

  Future<List<TimeEntry>> entriesForMonth(int year, int month) async {
    final db = await database;
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
    final records = await _store.find(db, finder: finder);
    return records.map(_fromRecord).toList();
  }

  /// Sucht Einträge, deren Kunde/Werkstatt-Name oder Tätigkeit den
  /// Suchbegriff enthält (Groß-/Kleinschreibung wird ignoriert).
  /// Neueste Einträge zuerst.
  Future<List<TimeEntry>> searchEntries(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return [];
    final db = await database;
    // Bewusst ohne Filter.matches() (deren genaue API ich hier nicht
    // gegenprüfen konnte) - stattdessen alle Einträge laden und in Dart
    // filtern. Bei den Datenmengen einer privaten Zeiterfassung völlig
    // unproblematisch und dafür garantiert korrekt.
    final finder = Finder(
      sortOrders: [
        SortOrder('date', false),
        SortOrder('startHour', false),
      ],
    );
    final records = await _store.find(db, finder: finder);
    return records
        .where((r) {
          final name = (r.value['name'] as String? ?? '').toLowerCase();
          final activity = (r.value['activity'] as String? ?? '').toLowerCase();
          return name.contains(needle) || activity.contains(needle);
        })
        .map(_fromRecord)
        .toList();
  }

  /// Alle bisher verwendeten Kundennamen (für Schnellauswahl), sortiert.
  Future<List<String>> distinctCustomerNames() async {
    final db = await database;
    final finder = Finder(filter: Filter.equals('isWerkstatt', 0));
    final records = await _store.find(db, finder: finder);
    final names = records.map((r) => r.value['name'] as String).toSet().toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  TimeEntry _fromRecord(RecordSnapshot<int, Map<String, Object?>> record) {
    return TimeEntry.fromMap({...record.value, 'id': record.key});
  }
}
