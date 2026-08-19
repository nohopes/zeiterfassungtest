import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../widgets/ledger_row.dart';
import '../widgets/stamp_badge.dart';
import '../widgets/swipe_action_row.dart';
import 'add_entry_screen.dart';

/// Detailansicht eines einzelnen (auch vergangenen) Tages - erreichbar z. B.
/// über einen Tipp im Mini-Kalender der Monatsübersicht. Praktisch auch, um
/// rückwirkend Einträge für einen vergangenen Tag nachzutragen.
class DayDetailScreen extends StatefulWidget {
  final DateTime day;

  const DayDetailScreen({super.key, required this.day});

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  List<TimeEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await DatabaseHelper.instance.entriesForDay(widget.day);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _openAddEntry({TimeEntry? existing}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEntryScreen(initialDate: widget.day, existing: existing),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _deleteEntry(TimeEntry entry) async {
    if (entry.id == null) return;
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    await DatabaseHelper.instance.deleteEntry(entry.id!);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${entry.activity}" gelöscht'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () async {
            await DatabaseHelper.instance.insertEntry(entry);
            _load();
          },
        ),
      ),
    );
  }

  double get _dayTotal => _entries.fold(0.0, (sum, e) => sum + e.durationHours);

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(widget.day);

    return Scaffold(
      appBar: AppBar(title: Text(dateLabel)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Text(
                              'Noch keine Einträge für diesen Tag',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.inkMuted),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final e = _entries[index];
                        return SwipeActionRow(
                          key: ValueKey(e.id),
                          onTap: () => _openAddEntry(existing: e),
                          onEdit: () => _openAddEntry(existing: e),
                          onDelete: () => _deleteEntry(e),
                          child: LedgerRow(entry: e),
                        );
                      },
                    ),
            ),
      bottomNavigationBar: _entries.isEmpty
          ? null
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TAGESSUMME', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
                  StampBadge(hours: _dayTotal),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddEntry(),
        tooltip: 'Eintrag nachtragen',
        child: const Icon(Icons.add),
      ),
    );
  }
}
