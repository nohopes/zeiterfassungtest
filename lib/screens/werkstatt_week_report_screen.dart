import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../services/pdf_export_service.dart';
import '../services/profile_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/stamp_badge.dart';

/// Eigenständiger, schlanker Screen nur für den Werkstatt-Wochenbericht:
/// Wochen-Navigation + Vorschau der Werkstatt-Stundensumme + Export-Button.
/// Bewusst OHNE Auflistung der einzelnen Einträge - die gehört auf die
/// "Diese Woche"-Übersicht (siehe [EntriesListScreen]), nicht hierher.
class WerkstattWeekReportScreen extends StatefulWidget {
  /// Muss ein Montag sein.
  final DateTime initialWeekStart;

  const WerkstattWeekReportScreen({super.key, required this.initialWeekStart});

  @override
  State<WerkstattWeekReportScreen> createState() => _WerkstattWeekReportScreenState();
}

class _WerkstattWeekReportScreenState extends State<WerkstattWeekReportScreen> {
  late DateTime _weekStart;
  List<TimeEntry> _werkstattEntries = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _weekStart = widget.initialWeekStart;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await DatabaseHelper.instance.entriesForDateRange(
      _weekStart,
      _weekStart.add(const Duration(days: 7)),
    );
    if (!mounted) return;
    setState(() {
      _werkstattEntries = entries.where((e) => e.isWerkstatt).toList();
      _loading = false;
    });
  }

  static DateTime _mondayOf(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return dateOnly.subtract(Duration(days: dateOnly.weekday - 1));
  }

  bool get _isCurrentWeek => _weekStart.isAtSameMomentAs(_mondayOf(DateTime.now()));

  void _changeWeek(int deltaWeeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks)));
    _load();
  }

  void _goToCurrentWeek() {
    setState(() => _weekStart = _mondayOf(DateTime.now()));
    _load();
  }

  double get _totalHours =>
      _werkstattEntries.fold(0.0, (sum, e) => sum + e.durationHours);

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final profile = await ProfileService.instance.loadProfile();
      await PdfExportService.exportAndShareWerkstattWeek(
        weekStart: _weekStart,
        entries: _werkstattEntries,
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
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final weekLabel = 'KW ${PdfExportService.isoWeekNumber(_weekStart)} · '
        '${DateFormat('dd.MM.').format(_weekStart)}–'
        '${DateFormat('dd.MM.yyyy').format(weekEnd)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Werkstatt-Wochenbericht'),
        actions: [
          if (!_isCurrentWeek)
            TextButton(
              onPressed: _goToCurrentWeek,
              child: const Text('Diese Woche'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
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
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(4),
                      border: Border(left: BorderSide(color: AppColors.amber, width: 4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.build_rounded, color: AppColors.amber, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Werkstatt (diese KW)',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_werkstattEntries.length} '
                                '${_werkstattEntries.length == 1 ? "Eintrag" : "Einträge"}',
                                style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        StampBadge(hours: _totalHours, color: AppColors.amber),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          (_werkstattEntries.isEmpty || _exporting) ? null : _export,
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf),
                      label: Text(
                        _exporting ? 'Erstelle PDF …' : 'Werkstatt-Wochenbericht exportieren',
                      ),
                    ),
                  ),
                  if (_werkstattEntries.isEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Keine Werkstatt-Einträge in dieser Woche.',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
