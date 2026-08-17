import 'package:flutter/material.dart';

/// Berechnet die Rohdauer zwischen Start- und Endzeit.
///
/// Falls die Endzeit "vor" der Startzeit liegt (z. B. Schicht über
/// Mitternacht), wird angenommen, dass sich die Endzeit auf den
/// Folgetag bezieht.
Duration calculateDuration(TimeOfDay start, TimeOfDay end) {
  final startMinutes = start.hour * 60 + start.minute;
  var endMinutes = end.hour * 60 + end.minute;
  if (endMinutes < startMinutes) {
    endMinutes += 24 * 60;
  }
  return Duration(minutes: endMinutes - startMinutes);
}

/// Rundet eine Dauer kaufmännisch auf 15-Minuten-Schritte (= 0,25 Std.)
/// und gibt das Ergebnis als Dezimalstunden zurück.
///
/// Beispiele:
///   7:00 - 7:30  -> 0.5
///   7:00 - 7:10  -> 0.25 (10 Min. werden auf 15 Min. aufgerundet)
///   7:00 - 7:37  -> 0.5  (37 Min. werden auf 30 Min. abgerundet)
double roundDurationToQuarterHours(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes <= 0) return 0.0;
  const stepMinutes = 15;
  final roundedMinutes =
      ((totalMinutes + stepMinutes / 2) ~/ stepMinutes) * stepMinutes;
  return roundedMinutes / 60.0;
}

/// Formatiert Dezimalstunden im deutschen Format, z. B. 0.5 -> "0,50".
String formatHours(double hours) {
  return hours.toStringAsFixed(2).replaceAll('.', ',');
}

/// Formatiert eine TimeOfDay als "HH:mm".
String formatTimeOfDay(TimeOfDay t) {
  final hour = t.hour.toString().padLeft(2, '0');
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
