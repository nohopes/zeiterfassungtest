import '../models/preset_activity.dart';
import '../models/time_entry.dart';

/// Fallback, falls weder dart:io noch dart:html verfügbar sind. Sollte in
/// der Praxis nie erreicht werden - existiert nur, damit der conditional
/// export in database_helper.dart eine gültige Default-Datei hat.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Never _unsupported() => throw UnsupportedError(
        'Keine passende Datenbank-Implementierung für diese Plattform gefunden.',
      );

  Future<int> insertEntry(TimeEntry entry) async => _unsupported();
  Future<int> updateEntry(TimeEntry entry) async => _unsupported();
  Future<void> deleteEntry(int id) async => _unsupported();
  Future<List<TimeEntry>> entriesForDay(DateTime day) async => _unsupported();
  Future<List<TimeEntry>> entriesForMonth(int year, int month) async => _unsupported();
  Future<List<TimeEntry>> entriesForDateRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async =>
      _unsupported();
  Future<List<TimeEntry>> entriesForWeek(DateTime anyDayInWeek) async => _unsupported();
  Future<List<String>> recentActivities({int limit = 8}) async => _unsupported();
  Future<List<String>> topActivities({int limit = 5}) async => _unsupported();
  Future<List<PresetActivity>> presetActivities() async => _unsupported();
  Future<int> addPresetActivity(String text) async => _unsupported();
  Future<void> updatePresetActivity(int id, String text) async => _unsupported();
  Future<void> deletePresetActivity(int id) async => _unsupported();
  Future<List<TimeEntry>> searchEntries(String query) async => _unsupported();
  Future<List<String>> distinctCustomerNames() async => _unsupported();
}
