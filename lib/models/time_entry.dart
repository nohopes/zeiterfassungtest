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

  /// Pausenzeit in Minuten, die von der Arbeitszeit abgezogen wird (z. B.
  /// 15 = Frühstückspause, 30 = Mittagspause, 0 = keine Pause). Nur bei
  /// Kunden-Einträgen relevant - bei Werkstatt-Einträgen immer 0.
  final int breakMinutes;

  TimeEntry({
    this.id,
    required DateTime date,
    required this.name,
    required this.isWerkstatt,
    required this.startTime,
    required this.endTime,
    required this.activity,
    this.breakMinutes = 0,
  }) : date = DateTime(date.year, date.month, date.day);

  /// Gerundete Dauer in Dezimalstunden (0,25-Schritte), abzüglich einer
  /// evtl. gewählten Pause. Wird nie negativ.
  double get durationHours {
    final raw = calculateDuration(startTime, endTime);
    final net = raw - Duration(minutes: breakMinutes);
    return roundDurationToQuarterHours(net.isNegative ? Duration.zero : net);
  }

  TimeEntry copyWith({
    int? id,
    DateTime? date,
    String? name,
    bool? isWerkstatt,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? activity,
    int? breakMinutes,
  }) {
    return TimeEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      name: name ?? this.name,
      isWerkstatt: isWerkstatt ?? this.isWerkstatt,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      activity: activity ?? this.activity,
      breakMinutes: breakMinutes ?? this.breakMinutes,
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
      'breakMinutes': breakMinutes,
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
      // ?? 0 - ältere, schon gespeicherte Einträge kennen dieses Feld noch
      // nicht (Feld wurde nachträglich ergänzt).
      breakMinutes: (map['breakMinutes'] as int?) ?? 0,
    );
  }
}
