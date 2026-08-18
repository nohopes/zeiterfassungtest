import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../utils/time_rounding.dart';
import '../widgets/ledger_row.dart';
import '../widgets/stamp_badge.dart';
import '../widgets/stat_tile.dart';
import 'add_entry_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDay = DateTime.now();
  List<TimeEntry> _entries = [];
  bool _loading = true;

  double _weekTotal = 0;
  double _monthTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _loadStats();
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    final entries = await DatabaseHelper.instance.entriesForDay(_selectedDay);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// Wochen-/Monatssumme bezogen auf HEUTE (unabhängig davon, welcher Tag
  /// gerade in der Liste angeschaut wird) - für den schnellen Überblick.
  Future<void> _loadStats() async {
    final now = DateTime.now();
    final weekEntries = await DatabaseHelper.instance.entriesForWeek(now);
    final monthEntries = await DatabaseHelper.instance.entriesForMonth(now.year, now.month);
    if (!mounted) return;
    setState(() {
      _weekTotal = weekEntries.fold(0.0, (sum, e) => sum + e.durationHours);
      _monthTotal = monthEntries.fold(0.0, (sum, e) => sum + e.durationHours);
    });
  }

  void _changeDay(int deltaDays) {
    setState(() {
      _selectedDay = _selectedDay.add(Duration(days: deltaDays));
    });
    _loadEntries();
  }

  void _goToToday() {
    setState(() => _selectedDay = DateTime.now());
    _loadEntries();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDay.year == now.year &&
        _selectedDay.month == now.month &&
        _selectedDay.day == now.day;
  }

  Future<void> _openAddEntry({TimeEntry? existing}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEntryScreen(initialDate: _selectedDay, existing: existing),
      ),
    );
    if (result == true) {
      _loadEntries();
      _loadStats();
    }
  }

  Future<void> _deleteEntry(TimeEntry entry) async {
    if (entry.id == null) return;
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await DatabaseHelper.instance.deleteEntry(entry.id!);
    _loadStats();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${entry.activity}" gelöscht'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () async {
            // insertEntry() ignoriert ein evtl. gesetztes entry.id ohnehin
            // (siehe toInsertMap()) und vergibt automatisch eine neue id.
            await DatabaseHelper.instance.insertEntry(entry);
            _loadEntries();
            _loadStats();
          },
        ),
      ),
    );
  }

  double get _dayTotal => _entries.fold(0.0, (sum, e) => sum + e.durationHours);

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stunden Logbuch'),
        actions: [
          if (!_isToday)
            TextButton(
              onPressed: _goToToday,
              child: const Text('Heute'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Diese Woche',
                    value: '${formatHours(_weekTotal)} Std.',
                    icon: Icons.date_range_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Dieser Monat',
                    value: '${formatHours(_monthTotal)} Std.',
                    icon: Icons.calendar_month_rounded,
                    accentColor: AppColors.teal,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeDay(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      dateLabel,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeDay(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
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
                              'Noch keine Einträge für diesen Tag',
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
                          final e = _entries[index];
                          return Dismissible(
                            key: ValueKey(e.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: AppColors.rust,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => _deleteEntry(e),
                            child: LedgerRow(
                              entry: e,
                              onTap: () => _openAddEntry(existing: e),
                            ),
                          );
                        },
                      ),
          ),
          if (!_loading && _entries.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TAGESSUMME',
                    style: AppTextStyles.eyebrow(AppColors.inkMuted),
                  ),
                  StampBadge(hours: _dayTotal),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddEntry(),
        tooltip: 'Neuer Eintrag',
        child: const Icon(Icons.add),
      ),
    );
  }
}
