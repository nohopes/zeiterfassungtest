import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Server-seitiger Nachbau des Werkstatt-PDF-Exports aus
/// `lib/services/pdf_export_service.dart` (dort `_buildPdf`) - inhaltlich
/// und optisch bewusst identisch gehalten, aber ohne jede Flutter-
/// Abhängigkeit (der Server bindet kein Flutter ein, siehe Kommentar in
/// server/pubspec.yaml). Arbeitet direkt auf den rohen sembast-Record-Maps
/// (int-Felder statt TimeOfDay) statt auf dem Flutter-`TimeEntry`-Modell.
///
/// Wird für den automatischen Monats-E-Mail-Versand verwendet (siehe
/// `_sendMonthlyReports` in server/bin/server.dart) - der Nutzer bekommt
/// also exakt das gleiche PDF wie beim manuellen Export in der App.
class _ReportEntry {
  final DateTime date;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final String activity;
  final int breakMinutes;
  final bool isAbsence;

  _ReportEntry({
    required this.date,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.activity,
    required this.breakMinutes,
    required this.isAbsence,
  });

  /// Gerundete Dauer in Dezimalstunden - identische Rundungslogik wie
  /// `roundDurationToQuarterHours` im Client (lib/utils/time_rounding.dart).
  /// Urlaub/Krankheit zählen pauschal mit 8 Std. (siehe
  /// `TimeEntry.absenceDayHours` im Client), tauchen aber ohnehin nicht im
  /// Werkstatt-Bericht auf (siehe [buildWerkstattReportPdf] - nur
  /// Werkstatt-Einträge werden berücksichtigt).
  double get durationHours {
    if (isAbsence) return 8.0;
    final startMinutes = startHour * 60 + startMinute;
    var endMinutes = endHour * 60 + endMinute;
    if (endMinutes < startMinutes) endMinutes += 24 * 60;
    final netMinutes = (endMinutes - startMinutes) - breakMinutes;
    if (netMinutes <= 0) return 0.0;
    const stepMinutes = 15;
    final roundedMinutes = ((netMinutes + stepMinutes / 2) ~/ stepMinutes) * stepMinutes;
    return roundedMinutes / 60.0;
  }

  String get timeLabel =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')} - '
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
}

String _formatHours(double hours) => hours.toStringAsFixed(2).replaceAll('.', ',');

/// Erstellt den monatlichen Werkstatt-Bericht als PDF-Bytes.
///
/// [rawEntries] sind die rohen sembast-Record-Maps eines einzelnen Nutzers
/// für den gewünschten Monat (wie in `_store` gespeichert, siehe
/// server/bin/server.dart) - es werden automatisch nur Werkstatt-Einträge
/// (`isWerkstatt == 1`) berücksichtigt, alles andere (Kunde, Urlaub,
/// Krankheit) wird - wie beim manuellen Export in der App - ignoriert.
Future<Uint8List> buildWerkstattReportPdf({
  required int year,
  required int month,
  required List<Map<String, Object?>> rawEntries,
  String? authorName,
  Uint8List? signatureBytes,
}) async {
  final entries = rawEntries
      .where((m) => (m['isWerkstatt'] as int? ?? 0) == 1)
      .map((m) => _ReportEntry(
            date: DateTime.parse(m['date'] as String),
            startHour: m['startHour'] as int? ?? 0,
            startMinute: m['startMinute'] as int? ?? 0,
            endHour: m['endHour'] as int? ?? 0,
            endMinute: m['endMinute'] as int? ?? 0,
            activity: m['activity'] as String? ?? '',
            breakMinutes: m['breakMinutes'] as int? ?? 0,
            isAbsence: m['absenceType'] != null,
          ))
      .toList()
    ..sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return (a.startHour * 60 + a.startMinute).compareTo(b.startHour * 60 + b.startMinute);
    });

  final doc = pw.Document();
  final monthLabel = _monthLabelWithWeeks(year, month);
  final totalHours = entries.fold<double>(0, (sum, e) => sum + e.durationHours);
  final signatureImage = signatureBytes != null ? pw.MemoryImage(signatureBytes) : null;
  final hasName = authorName != null && authorName.trim().isNotEmpty;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Werkstattstunden',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(monthLabel, style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 12),
        ],
      ),
      build: (context) => [
        if (entries.isEmpty)
          pw.Text('Keine Werkstatt-Einträge in diesem Monat.')
        else
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1.7),
              2: pw.FlexColumnWidth(1.1),
              3: pw.FlexColumnWidth(3.2),
              4: pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _headerCell('Datum'),
                  _headerCell('Uhrzeit'),
                  _headerCell('Dauer'),
                  _headerCell('Tätigkeit'),
                  _headerCell('Eingetragen Büro'),
                ],
              ),
              for (final e in entries)
                pw.TableRow(
                  children: [
                    _cell(DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(e.date)),
                    _cell(e.timeLabel),
                    _cell('${_formatHours(e.durationHours)} Std.'),
                    _cell(e.activity),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Center(
                        child: pw.Container(
                          width: 12,
                          height: 12,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Gesamt: ${_formatHours(totalHours)} Std.',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 36),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (signatureImage != null)
                  pw.SizedBox(
                    height: 60,
                    width: 180,
                    child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                  )
                else
                  pw.SizedBox(height: 60),
                pw.Container(
                  width: 200,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(width: 0.8, color: PdfColors.grey700),
                    ),
                  ),
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(
                    hasName ? authorName!.trim() : 'Unterschrift',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Erstellt am ${DateFormat('dd.MM.yyyy', 'de_DE').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

/// Monatsname + Jahr, dahinter in Klammern die ISO-Kalenderwoche(n), die
/// der Monat abdeckt - z. B. "August 2026 (KW32-35)" (siehe Pendant im
/// Client, `PdfExportService._monthLabelWithWeeks`).
String _monthLabelWithWeeks(int year, int month) {
  final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(DateTime(year, month));
  final firstOfMonth = DateTime(year, month, 1);
  final lastOfMonth = DateTime(year, month + 1, 0);
  final startWeek = _isoWeekNumber(firstOfMonth);
  final endWeek = _isoWeekNumber(lastOfMonth);
  final weekLabel = startWeek == endWeek ? 'KW$startWeek' : 'KW$startWeek-$endWeek';
  return '$monthLabel ($weekLabel)';
}

/// ISO-8601-Kalenderwoche (Montag als Wochenstart, Woche 1 enthält den
/// ersten Donnerstag des Jahres).
int _isoWeekNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final firstDayOfYear = DateTime.utc(thursday.year, 1, 1);
  return ((thursday.difference(firstDayOfYear).inDays) / 7).floor() + 1;
}

pw.Widget _headerCell(String text) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    );

pw.Widget _cell(String text) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
    );
