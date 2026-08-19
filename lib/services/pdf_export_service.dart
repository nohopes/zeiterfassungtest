import 'dart:typed_data';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/time_entry.dart';
import '../utils/time_rounding.dart';

/// Erstellt und teilt PDF-Berichte. Der offizielle Werkstatt-Bericht ist
/// bewusst nur noch EIN einziges PDF-Format - ein einzelner Knopf pro
/// Monat, keine Wochen-Navigation, keine separate Vorschau-Seite.
class PdfExportService {
  /// Erstellt und teilt den monatlichen Werkstatt-Bericht - Datum, Uhrzeit,
  /// Dauer, Tätigkeit, dazu eine Spalte "Eingetragen Büro" zum manuellen
  /// Abhaken sowie Name und (falls im Profil hinterlegt) Unterschrift.
  /// Kunden-Einträge fließen bewusst NICHT mit ein, da sie nur zur eigenen
  /// Kontrolle dienen.
  static Future<void> exportAndShareWerkstattMonth({
    required int year,
    required int month,
    required List<TimeEntry> entries,
    String? authorName,
    Uint8List? signatureBytes,
  }) async {
    final bytes = await _buildPdf(
      year: year,
      month: month,
      entries: entries,
      authorName: authorName,
      signatureBytes: signatureBytes,
    );
    final fileLabel = DateFormat('yyyy-MM').format(DateTime(year, month));
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Werkstattstunden_$fileLabel.pdf',
    );
  }

  /// Erstellt und teilt einen vollständigen Monatsbericht - ALLE Einträge
  /// (Werkstatt UND Kunden), gruppiert nach Kunde/Werkstatt mit
  /// Zwischensummen. Gedacht als persönliche Sicherung/Übersicht, nicht als
  /// offizielles Werkstatt-Dokument (dafür [exportAndShareWerkstattMonth]
  /// verwenden).
  static Future<void> exportAndShareFullMonth({
    required int year,
    required int month,
    required List<TimeEntry> entries,
  }) async {
    final bytes = await _buildFullReportPdf(year: year, month: month, entries: entries);
    final fileLabel = DateFormat('yyyy-MM').format(DateTime(year, month));
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Gesamtbericht_$fileLabel.pdf',
    );
  }

  static Future<Uint8List> _buildFullReportPdf({
    required int year,
    required int month,
    required List<TimeEntry> entries,
  }) async {
    final sorted = [...entries]..sort(_byDateAndStart);
    final doc = pw.Document();
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(DateTime(year, month));
    final totalHours = sorted.fold<double>(0, (sum, e) => sum + e.durationHours);

    // Gruppierung für die Zusammenfassung oben (pro Kunde/Werkstatt).
    final totalsByName = <String, double>{};
    for (final e in sorted) {
      totalsByName[e.name] = (totalsByName[e.name] ?? 0) + e.durationHours;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Gesamtbericht',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(monthLabel, style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 12),
          ],
        ),
        build: (context) => [
          if (totalsByName.isNotEmpty) ...[
            pw.Text(
              'Zusammenfassung',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            for (final entry in totalsByName.entries)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(entry.key, style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(
                      '${formatHours(entry.value)} Std.',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            pw.SizedBox(height: 16),
          ],
          pw.Text(
            'Alle Einträge',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (sorted.isEmpty)
            pw.Text('Keine Einträge in diesem Monat.')
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(1.8),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(3.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _headerCell('Datum'),
                    _headerCell('Kunde/Werkstatt'),
                    _headerCell('Uhrzeit'),
                    _headerCell('Dauer'),
                    _headerCell('Tätigkeit'),
                  ],
                ),
                for (final e in sorted)
                  pw.TableRow(
                    children: [
                      _cell(DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(e.date)),
                      _cell(e.name),
                      _cell('${_fmtTime(e.startTime)} - ${_fmtTime(e.endTime)}'),
                      _cell('${formatHours(e.durationHours)} Std.'),
                      _cell(e.activity),
                    ],
                  ),
              ],
            ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Gesamt: ${formatHours(totalHours)} Std.',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> _buildPdf({
    required int year,
    required int month,
    required List<TimeEntry> entries,
    String? authorName,
    Uint8List? signatureBytes,
  }) async {
    final werkstattEntries = entries.where((e) => e.isWerkstatt).toList()
      ..sort(_byDateAndStart);

    final doc = pw.Document();
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(DateTime(year, month));
    final totalHours =
        werkstattEntries.fold<double>(0, (sum, e) => sum + e.durationHours);
    final signatureImage =
        signatureBytes != null ? pw.MemoryImage(signatureBytes) : null;
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
          if (werkstattEntries.isEmpty)
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
                for (final e in werkstattEntries)
                  pw.TableRow(
                    children: [
                      _cell(DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(e.date)),
                      _cell('${_fmtTime(e.startTime)} - ${_fmtTime(e.endTime)}'),
                      _cell('${formatHours(e.durationHours)} Std.'),
                      _cell(e.activity),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Center(
                          child: pw.Container(
                            width: 12,
                            height: 12,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                width: 0.8,
                                color: PdfColors.grey700,
                              ),
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
              'Gesamt: ${formatHours(totalHours)} Std.',
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
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static int _byDateAndStart(TimeEntry a, TimeEntry b) {
    final dateCompare = a.date.compareTo(b.date);
    if (dateCompare != 0) return dateCompare;
    return (a.startTime.hour * 60 + a.startTime.minute)
        .compareTo(b.startTime.hour * 60 + b.startTime.minute);
  }

  static pw.Widget _headerCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _cell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
      );

  static String _fmtTime(TimeOfDay t) => formatTimeOfDay(t);
}
