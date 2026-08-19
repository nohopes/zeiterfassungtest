import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../widgets/ledger_row.dart';
import '../widgets/stamp_badge.dart';

/// Vollständige, chronologisch sortierte Auflistung aller Einträge in einem
/// Zeitraum (Woche oder Monat) - neuste zuerst, alle Arten gemischt (Kunde
/// UND Werkstatt). Wird von den "Diese Woche"/"Dieser Monat"-Kacheln auf
/// der Startseite geöffnet - reine Übersicht, kein PDF-Export (den PDF-
/// Export der Werkstatt-Stunden gibt es als eigenen Knopf in der
/// Monatsübersicht).
class EntriesListScreen extends StatefulWidget {
  final String title;
  final DateTime startInclusive;
  final DateTime endExclusive;

  const EntriesListScreen({
    super.key,
    required this.title,
    required this.startInclusive,
    required this.endExclusive,
  });

  @override
  State<EntriesListScreen> createState() => _EntriesListScreenState();
}

class _EntriesListScreenState extends State<EntriesListScreen> {
  List<TimeEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await DatabaseHelper.instance.entriesForDateRange(
      widget.startInclusive,
      widget.endExclusive,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
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
