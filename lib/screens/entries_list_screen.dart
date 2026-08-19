import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../services/pdf_export_service.dart';
import '../services/profile_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/ledger_row.dart';
import '../widgets/stamp_badge.dart';

/// Vollständige, chronologisch sortierte Auflistung aller Einträge in einem
/// Zeitraum (Woche oder Monat) - neuste zuerst. Wird von den "Diese
/// Woche"/"Dieser Monat"-Kacheln auf der Startseite geöffnet.
///
/// Im Wochen-Modus ([isWeek]) ist dies zugleich der einzige Ort für den
/// offiziellen Werkstatt-PDF-Export: mit den Pfeilen lässt sich zu jeder
/// beliebigen (auch vergangenen) Woche navigieren, nicht nur zur aktuellen.
class EntriesListScreen extends StatefulWidget {
  final String title;
  final DateTime startInclusive;
  final DateTime endExclusive;

  /// Aktiviert die Wochen-Navigation (Pfeile) sowie den
  /// "Werkstatt-Wochenbericht exportieren"-Button. [startInclusive] muss in
  /// diesem Fall ein Montag sein (siehe
  /// [PdfExportService.exportAndShareWerkstattWeek]).
  final bool isWeek;

  const EntriesListScreen({
    super.key,
    required this.title,
    required this.startInclusive,
    required this.endExclusive,
    this.isWeek = false,
  });

  @override
  State<EntriesListScreen> createState() => _EntriesListScreenState();
}

class _EntriesListScreenState extends State<EntriesListScreen> {
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  List<TimeEntry> _entries = [];
  bool _loading = true;
  bool _exportingWeek = false;

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.startInclusive;
    _rangeEnd = widget.endExclusive;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await DatabaseHelper.instance.entriesForDateRange(
      _rangeStart,
      _rangeEnd,
    );
    entries.sort(_byDateAndStartDesc);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  static int _byDateAndStartDesc(TimeEntry a, TimeEntry b) {
    final dateCompare = b.date.compareTo(a.date);
    if (dateCompare != 0) return dateCompare;
    return (b.startTime.hour * 60 + b.startTime.minute)
        .compareTo(a.startTime.hour * 60 + a.startTime.minute);
  }

  double get _totalHours => _entries.fold(0.0, (sum, e) => sum + e.durationHours);

  static DateTime _mondayOf(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return dateOnly.subtract(Duration(days: dateOnly.weekday - 1));
  }

  bool get _isCurrentWeek => _rangeStart.isAtSameMomentAs(_mondayOf(DateTime.now()));

  void _changeWeek(int deltaWeeks) {
    setState(() {
      _rangeStart = _rangeStart.add(Duration(days: 7 * deltaWeeks));
      _rangeEnd = _rangeEnd.add(Duration(days: 7 * deltaWeeks));
    });
    _load();
  }

  void _goToCurrentWeek() {
    final monday = _mondayOf(DateTime.now());
    setState(() {
      _rangeStart = monday;
      _rangeEnd = monday.add(const Duration(days: 7));
    });
    _load();
  }

  Future<void> _exportWeekReport() async {
    setState(() => _exportingWeek = true);
    try {
      final profile = await ProfileService.instance.loadProfile();
      await PdfExportService.exportAndShareWerkstattWeek(
        weekStart: _rangeStart,
        entries: _entries,
        authorName: profile.displayName,
        signatureBytes: profile.signature,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wochenbericht konnte nicht erstellt werden.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingWeek = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitle = widget.isWeek ? 'Werkstatt-Wochenbericht' : widget.title;
    final weekEnd = _rangeEnd.subtract(const Duration(days: 1));
    final weekLabel = widget.isWeek
        ? 'KW ${PdfExportService.isoWeekNumber(_rangeStart)} · '
            '${DateFormat('dd.MM.').format(_rangeStart)}–'
            '${DateFormat('dd.MM.yyyy').format(weekEnd)}'
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          if (widget.isWeek && !_isCurrentWeek)
            TextButton(
              onPressed: _goToCurrentWeek,
              child: const Text('Diese Woche'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (widget.isWeek) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => _changeWeek(-1),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              weekLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => _changeWeek(1),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (_entries.isEmpty || _exportingWeek)
                            ? null
                            : _exportWeekReport,
                        icon: _exportingWeek
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(
                          _exportingWeek
                              ? 'Erstelle PDF …'
                              : 'Werkstatt-Wochenbericht exportieren',
                        ),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: _entries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.event_available_outlined,
                                size: 40,
                                color: AppColors.inkMuted,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Einträge in diesem Zeitraum',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppColors.inkMuted),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 4, bottom: 12),
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            return LedgerRow(entry: _entries[index], showDate: true);
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: (!_loading && _entries.isNotEmpty)
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('GESAMT', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
                  StampBadge(hours: _totalHours),
                ],
              ),
            )
          : null,
    );
  }
}
