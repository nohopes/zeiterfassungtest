import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../widgets/ledger_row.dart';
import '../widgets/stamp_badge.dart';
import 'add_entry_screen.dart';

/// Zeigt alle Einträge eines Kunden in einem bestimmten Monat - erreichbar
/// durch Antippen eines Kunden in der Monatsübersicht.
class CustomerMonthDetailScreen extends StatefulWidget {
  final String customerName;
  final DateTime month;
  final List<TimeEntry> initialEntries;

  const CustomerMonthDetailScreen({
    super.key,
    required this.customerName,
    required this.month,
    required this.initialEntries,
  });

  @override
  State<CustomerMonthDetailScreen> createState() => _CustomerMonthDetailScreenState();
}

class _CustomerMonthDetailScreenState extends State<CustomerMonthDetailScreen> {
  late List<TimeEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.initialEntries;
  }

  Future<void> _reload() async {
    final monthEntries = await DatabaseHelper.instance
        .entriesForMonth(widget.month.year, widget.month.month);
    if (!mounted) return;
    setState(() {
      _entries = monthEntries.where((e) => e.name == widget.customerName).toList();
    });
  }

  double get _total => _entries.fold(0.0, (sum, e) => sum + e.durationHours);

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(widget.month);
    final sorted = [..._entries]..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(title: Text(widget.customerName)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    monthLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StampBadge(hours: _total, color: AppColors.teal),
              ],
            ),
          ),
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Text(
                      'Keine Einträge in diesem Monat',
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final e = sorted[index];
                      return LedgerRow(
                        entry: e,
                        onTap: () async {
                          final result = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => AddEntryScreen(
                                initialDate: e.date,
                                existing: e,
                              ),
                            ),
                          );
                          if (result == true) _reload();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
