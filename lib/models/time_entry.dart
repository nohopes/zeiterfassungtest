import 'package:flutter/material.dart';

import '../utils/time_rounding.dart';

/// Urlaub/Krankheit sind Tages-Markierungen statt Zeit-Einträgen: keine
/// Uhrzeit, zählen aber pauschal mit [TimeEntry.absenceDayHours] Std. in
/// der Wochen-/Monatssumme und tauchen nicht im Werkstatt-PDF-Export auf.
enum AbsenceType {
  urlaub,
  krankheit;

  String get label => switch (this) {
        AbsenceType.urlaub => 'Urlaub',
        AbsenceType.krankheit => 'Krankheit',
      };

  static AbsenceType? fromName(String? name) {
    if (name == null) return null;
    for (final v in AbsenceType.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// Ein einzelner Zeiteintrag.
///
/// Drei Arten von Einträgen:
/// - Werkstatt-Einträge (isWerkstatt = true): Name ist immer "Werkstatt",
///   die genaue Uhrzeit ist wichtig, da sie monatlich als PDF ausgedruckt
///   werden. Diese Zeiten sind die offizielle Grundlage.
/// - Kunden-Einträge (isWerkstatt = false, absenceType = null): Name ist
///   der Kundenname, dient nur der eigenen Kontrolle. Die Uhrzeit wird nur
///   zur Berechnung der Dauer benötigt, ist aber selbst nicht weiter
///   relevant.
/// - Urlaub/Krankheit-Einträge (absenceType != null): reine
///   Tages-Markierung ohne Uhrzeit/Dauer, siehe [AbsenceType].
class TimeEntry {
  /// Pauschale Stundenzahl, mit der ein Urlaubs-/Krankheitstag in der
  /// Wochen-/Monatssumme mitgezählt wird (kein echter Zeit-Eintrag, daher
  /// fest statt berechnet).
  static const double absenceDayHours = 8.0;

  final int? id;
  final DateTime date;
  final String name;
  final bool isWerkstatt;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String activity;

  /// Pausenzeit in Minuten, die von der Arbeitszeit abgezogen wird (z. B.
  /// 15 = Frühstückspause, 30 = Mittagspause, 45 = beide kombiniert,
  /// 0 = keine Pause). Nur bei Kunden-Einträgen relevant - bei
  /// Werkstatt- und Urlaub/Krankheit-Einträgen immer 0.
  final int breakMinutes;

  /// Gesetzt, wenn dieser Eintrag statt einer Zeit einen Urlaubs- oder
  /// Krankheitstag markiert (siehe [AbsenceType]). Ist das der Fall, sind
  /// [startTime]/[endTime]/[breakMinutes] irrelevant.
  final AbsenceType? absenceType;

  TimeEntry({
    this.id,
    required DateTime date,
    required this.name,
    required this.isWerkstatt,
    required this.startTime,
    required this.endTime,
    required this.activity,
    this.breakMinutes = 0,
    this.absenceType,
  }) : date = DateTime(date.year, date.month, date.day);

  bool get isAbsence => absenceType != null;

  /// Gerundete Dauer in Dezimalstunden (0,25-Schritte), abzüglich einer
  /// evtl. gewählten Pause. Wird nie negativ. Urlaub/Krankheit zählen
  /// pauschal mit [absenceDayHours] (kein echter Zeit-Eintrag).
  double get durationHours {
    if (isAbsence) return absenceDayHours;
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
    AbsenceType? absenceType,
    bool clearAbsenceType = false,
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
      absenceType: clearAbsenceType ? null : (absenceType ?? this.absenceType),
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
      'absenceType': absenceType?.name,
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
      // Ältere Einträge kennen "absenceType" noch nicht - fehlt es, ist es
      // ein ganz normaler Zeit-Eintrag.
      absenceType: AbsenceType.fromName(map['absenceType'] as String?),
    );
  }
}
