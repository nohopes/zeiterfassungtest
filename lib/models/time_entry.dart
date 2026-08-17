import 'package:flutter/material.dart';

import '../utils/time_rounding.dart';

/// Ein einzelner Zeiteintrag.
///
/// Zwei Arten von Einträgen:
/// - Werkstatt-Einträge (isWerkstatt = true): Name ist immer "Werkstatt",
///   die genaue Uhrzeit ist wichtig, da sie monatlich als PDF ausgedruckt
///   werden. Diese Zeiten sind die offizielle Grundlage.
/// - Kunden-Einträge (isWerkstatt = false): Name ist der Kundenname, dient
///   nur der eigenen Kontrolle. Die Uhrzeit wird nur zur Berechnung der
///   Dauer benötigt, ist aber selbst nicht weiter relevant.
class TimeEntry {
  final int? id;
  final DateTime date;
  final String name;
  final bool isWerkstatt;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String activity;

  TimeEntry({
    this.id,
    required DateTime date,
    required this.name,
    required this.isWerkstatt,
    required this.startTime,
    required this.endTime,
    required this.activity,
  }) : date = DateTime(date.year, date.month, date.day);

  /// Gerundete Dauer in Dezimalstunden (0,25-Schritte).
  double get durationHours =>
      roundDurationToQuarterHours(calculateDuration(startTime, endTime));

  TimeEntry copyWith({
    int? id,
    DateTime? date,
    String? name,
    bool? isWerkstatt,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? activity,
  }) {
    return TimeEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      name: name ?? this.name,
      isWerkstatt: isWerkstatt ?? this.isWerkstatt,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      activity: activity ?? this.activity,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'name': name,
      'isWerkstatt': isWerkstatt ? 1 : 0,
      'startHour': startTime.hour,
      'startMinute': startTime.minute,
      'endHour': endTime.hour,
      'endMinute': endTime.minute,
      'activity': activity,
    };
  }

  /// Map fürs Einfügen (ohne id, die wird von SQLite automatisch vergeben).
  Map<String, Object?> toInsertMap() {
    final map = toMap();
    map.remove('id');
    return map;
  }

  factory TimeEntry.fromMap(Map<String, Object?> map) {
    return TimeEntry(
      id: map['id'] as int?,
      date: DateTime.parse(map['date'] as String),
      name: map['name'] as String,
      isWerkstatt: (map['isWerkstatt'] as int) == 1,
      startTime: TimeOfDay(
        hour: map['startHour'] as int,
        minute: map['startMinute'] as int,
      ),
      endTime: TimeOfDay(
        hour: map['endHour'] as int,
        minute: map['endMinute'] as int,
      ),
      activity: map['activity'] as String,
    );
  }
}
