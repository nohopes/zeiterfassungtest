import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../services/pdf_export_service.dart';
import '../utils/time_rounding.dart';

class MonthOverviewScreen extends StatefulWidget {
  const MonthOverviewScreen({super.key});

  @override
  State<MonthOverviewScreen> createState() => _MonthOverviewScreenState();
}

class _MonthOverviewScreenState extends State<MonthOverviewScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<TimeEntry> _entries = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries =
        await DatabaseHelper.instance.entriesForMonth(_month.year, _month.month);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  Map<String, double> get _customerTotals {
    final map = <String, double>{};
    for (final e in _entries.where((e) => !e.isWerkstatt)) {
      map[e.name] = (map[e.name] ?? 0) + e.durationHours;
    }
    return map;
  }

  double get _werkstattTotal => _entries
      .where((e) => e.isWerkstatt)
      .fold(0.0, (sum, e) => sum + e.durationHours);

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      await PdfExportService.exportAndShareWerkstattMonth(
        year: _month.year,
        month: _month.month,
        entries: _entries,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(_month);
    final customerTotals = _customerTotals;
    final hasWerkstattEntries = _entries.any((e) => e.isWerkstatt);

    return Scaffold(
      appBar: AppBar(title: const Text('Monatsübersicht')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeMonth(-1),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(monthLabel, style: Theme.of(context).textTheme.titleLarge),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  color: Colors.orange.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.build, color: Colors.orange),
                    title: const Text('Werkstatt (gesamt)'),
                    subtitle: const Text('Wird im PDF-Export ausgegeben'),
                    trailing: Text(
                      '${formatHours(_werkstattTotal)} Std.',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (!hasWerkstattEntries || _exporting) ? null : _exportPdf,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(_exporting ? 'Erstelle PDF …' : 'Werkstatt-PDF exportieren'),
                ),
                const SizedBox(height: 24),
                Text('Kunden (zur eigenen Kontrolle)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (customerTotals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Keine Kundeneinträge in diesem Monat'),
                  )
                else
                  ...customerTotals.entries.map(
                    (entry) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(entry.key),
                      trailing: Text(
                        '${formatHours(entry.value)} Std.',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
