import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../utils/time_rounding.dart';
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

  @override
  void initState() {
    super.initState();
    _loadEntries();
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
    }
  }

  Future<void> _deleteEntry(TimeEntry entry) async {
    if (entry.id == null) return;
    await DatabaseHelper.instance.deleteEntry(entry.id!);
    _loadEntries();
  }

  double get _dayTotal => _entries.fold(0.0, (sum, e) => sum + e.durationHours);

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zeiterfassung'),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeDay(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text(dateLabel, style: Theme.of(context).textTheme.titleMedium),
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
                        child: Text(
                          'Noch keine Einträge für diesen Tag',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
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
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Icon(
                                Icons.delete,
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                            onDismissed: (_) => _deleteEntry(e),
                            child: Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      e.isWerkstatt ? Colors.orange : Colors.blueGrey,
                                  child: Icon(
                                    e.isWerkstatt ? Icons.build : Icons.person,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                title: Text(e.name),
                                subtitle: Text(
                                  '${formatTimeOfDay(e.startTime)} - ${formatTimeOfDay(e.endTime)} · ${e.activity}',
                                ),
                                trailing: Text(
                                  '${formatHours(e.durationHours)} Std.',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                onTap: () => _openAddEntry(existing: e),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (!_loading && _entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Tagessumme: ${formatHours(_dayTotal)} Std.',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
