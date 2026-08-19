import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../services/pdf_export_service.dart';
import '../widgets/stamp_badge.dart';
import 'customer_month_detail_screen.dart';
import 'day_detail_screen.dart';
import 'werkstatt_week_report_screen.dart';

class MonthOverviewScreen extends StatefulWidget {
  const MonthOverviewScreen({super.key});

  @override
  State<MonthOverviewScreen> createState() => MonthOverviewScreenState();
}

/// Nicht mehr privat, damit RootShell (via GlobalKey) [reload] aufrufen
/// kann, wenn der Monats-Tab angetippt wird - siehe Kommentar dort.
class MonthOverviewScreenState extends State<MonthOverviewScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<TimeEntry> _entries = [];
  bool _loading = true;
  bool _exportingFull = false;

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

  /// Öffentlich aufrufbar, damit RootShell den Monat neu laden kann, wenn
  /// der Nutzer auf den "Monat"-Tab wechselt - der Screen bleibt dank
  /// IndexedStack sonst dauerhaft im Speicher und würde neue Einträge aus
  /// anderen Tabs (z. B. Werkstatt-Eintrag über "Tag" angelegt) nicht von
  /// selbst mitbekommen.
  Future<void> reload() => _load();

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

  Set<int> get _werkstattDays =>
      _entries.where((e) => e.isWerkstatt).map((e) => e.date.day).toSet();

  Set<int> get _kundeDays =>
      _entries.where((e) => !e.isWerkstatt).map((e) => e.date.day).toSet();

  /// Montag der Woche, in der [day] liegt - gleiche Logik wie in
  /// database_helper's entriesForWeek()/home_screen's _openWeekList().
  DateTime _weekStartFor(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return dateOnly.subtract(Duration(days: dateOnly.weekday - 1));
  }

  /// Öffnet den Werkstatt-Wochenbericht - Ausgangspunkt ist die aktuelle
  /// Woche, falls gerade der laufende Monat angezeigt wird, sonst die erste
  /// Woche des angezeigten Monats. Von dort lässt sich mit den Pfeilen im
  /// Wochenbericht zu jeder anderen Woche navigieren.
  void _openWeekReport() {
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;
    final weekStart = _weekStartFor(isCurrentMonth ? now : DateTime(_month.year, _month.month, 1));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WerkstattWeekReportScreen(initialWeekStart: weekStart),
      ),
    );
  }

  Future<void> _exportFullPdf() async {
    setState(() => _exportingFull = true);
    try {
      await PdfExportService.exportAndShareFullMonth(
        year: _month.year,
        month: _month.month,
        entries: _entries,
      );
    } finally {
      if (mounted) setState(() => _exportingFull = false);
    }
  }

  Future<void> _openDay(DateTime day) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DayDetailScreen(day: day)),
    );
    if (result == true) _load();
  }

  Future<void> _openCustomer(String name) async {
    final entriesForCustomer =
        _entries.where((e) => e.name == name && !e.isWerkstatt).toList();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerMonthDetailScreen(
          customerName: name,
          month: _month,
          initialEntries: entriesForCustomer,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(_month);
    final customerTotals = _customerTotals;

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
                        child: Text(
                          monthLabel,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _MonthCalendar(
                  month: _month,
                  werkstattDays: _werkstattDays,
                  kundeDays: _kundeDays,
                  onDayTap: _openDay,
                ),
                const SizedBox(height: 20),
                _SummaryRow(
                  icon: Icons.build_rounded,
                  color: AppColors.amber,
                  title: 'Werkstatt (gesamt)',
                  subtitle: 'Export im Werkstatt-Wochenbericht',
                  hours: _werkstattTotal,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _openWeekReport,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Werkstatt-Wochenbericht öffnen'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (_entries.isEmpty || _exportingFull) ? null : _exportFullPdf,
                  icon: _exportingFull
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.summarize_outlined),
                  label: Text(_exportingFull ? 'Erstelle PDF …' : 'Gesamtbericht exportieren'),
                ),
                const SizedBox(height: 28),
                Text(
                  'KUNDEN (ZUR EIGENEN KONTROLLE)',
                  style: AppTextStyles.eyebrow(AppColors.inkMuted),
                ),
                const SizedBox(height: 10),
                if (customerTotals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Keine Kundeneinträge in diesem Monat',
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      children: [
                        for (final entry in customerTotals.entries)
                          _CustomerRow(
                            name: entry.key,
                            hours: entry.value,
                            isLast: entry.key == customerTotals.keys.last,
                            onTap: () => _openCustomer(entry.key),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Zusammenfassungszeile mit farbigem Rand links, wie eine hervorgehobene
/// Buchzeile - konsistent mit LedgerRow, aber ohne festen TimeEntry-Bezug.
class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double hours;

  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.hours,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          StampBadge(hours: hours, color: color),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  final String name;
  final double hours;
  final bool isLast;
  final VoidCallback onTap;

  const _CustomerRow({
    required this.name,
    required this.hours,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.person_outline, size: 18, color: AppColors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            StampBadge(hours: hours, color: AppColors.teal, fontSize: 12),
          ],
        ),
      ),
    );
  }
}

/// Kleiner Monatskalender mit Punkt-Markierung an Tagen mit Einträgen -
/// getrennt nach Werkstatt (Amber) und Kunde (Petrol), damit auf einen
/// Blick erkennbar ist, welche Art von Eintrag an einem Tag existiert.
/// Tippen auf einen Tag öffnet die Tagesdetailansicht.
class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final Set<int> werkstattDays;
  final Set<int> kundeDays;
  final ValueChanged<DateTime> onDayTap;

  const _MonthCalendar({
    required this.month,
    required this.werkstattDays,
    required this.kundeDays,
    required this.onDayTap,
  });

  static const _weekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leadingEmptyCells = firstOfMonth.weekday - 1; // Montag = 1
    final now = DateTime.now();

    final cells = <Widget>[];
    for (var i = 0; i < leadingEmptyCells; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      final isToday =
          date.year == now.year && date.month == now.month && date.day == now.day;
      final hasWerkstatt = werkstattDays.contains(day);
      final hasKunde = kundeDays.contains(day);

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => onDayTap(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isToday ? AppColors.amberDim : null,
              border: isToday ? Border.all(color: AppColors.amber, width: 1) : null,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: AppTextStyles.mono.copyWith(
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isToday ? AppColors.amber : AppColors.ink,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 5,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasWerkstatt)
                        Container(
                          width: 5,
                          height: 5,
                          margin: EdgeInsets.only(right: hasKunde ? 3 : 0),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.amber,
                          ),
                        ),
                      if (hasKunde)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.teal,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Row(
            children: _weekdayLabels
                .map(
                  (label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: AppTextStyles.eyebrow(AppColors.inkMuted),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            children: cells,
          ),
        ],
      ),
    );
  }
}
