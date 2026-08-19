import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/design_tokens.dart';
import '../utils/time_rounding.dart';
import '../widgets/ledger_row.dart';
import '../widgets/stamp_badge.dart';
import '../widgets/stat_tile.dart';
import '../widgets/swipe_action_row.dart';
import 'add_entry_screen.dart';
import 'entries_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

/// Nicht mehr privat, damit RootShell (via GlobalKey) [reloadProfileName]
/// aufrufen kann, wenn der "Tag"-Tab wieder angetippt wird - so zeigt der
/// Header sofort den aktuellen Profil-Namen, falls er zuvor unter "Konto"
/// geändert wurde (siehe Kommentar zu MonthOverviewScreenState).
class HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDay = DateTime.now();
  List<TimeEntry> _entries = [];
  bool _loading = true;
  String? _profileName;

  double _weekTotal = 0;
  double _monthTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _loadStats();
    reloadProfileName();
  }

  /// Lädt den im Profil hinterlegten Namen (siehe ProfileService) für die
  /// Anzeige rechts im Header - bewusst NICHT der Login-Benutzername.
  Future<void> reloadProfileName() async {
    try {
      final profile = await ProfileService.instance.loadProfile();
      if (!mounted) return;
      setState(() => _profileName = profile.displayName);
    } catch (_) {
      // Kein Profil-Backend auf dieser Plattform verfügbar o. Ä. - dann
      // bleibt der Header einfach ohne Namen.
    }
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

  /// Für Pull-to-refresh: Tag-Einträge UND die Wochen-/Monatssumme neu
  /// laden, damit ein Runterziehen wirklich alles Sichtbare aktualisiert.
  Future<void> _refresh() async {
    await Future.wait([_loadEntries(), _loadStats()]);
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

  void _openWeekList() {
    final now = DateTime.now();
    final dateOnly = DateTime(now.year, now.month, now.day);
    final monday = dateOnly.subtract(Duration(days: dateOnly.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntriesListScreen(
          title: 'Diese Woche',
          startInclusive: monday,
          endExclusive: nextMonday,
        ),
      ),
    );
  }

  void _openMonthList() {
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final firstOfNextMonth = DateTime(now.year, now.month + 1, 1);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntriesListScreen(
          title: 'Dieser Monat',
          startInclusive: firstOfMonth,
          endExclusive: firstOfNextMonth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(_selectedDay);
    // Zeigt bevorzugt den im Profil hinterlegten Namen, sonst als Fallback
    // den Login-Benutzernamen (Web/PWA) - so steht auf jeden Fall etwas da,
    // solange noch kein Profilname eingetragen wurde.
    final trimmedProfileName = _profileName?.trim();
    final headerName = (trimmedProfileName != null && trimmedProfileName.isNotEmpty)
        ? trimmedProfileName
        : AuthService.instance.username;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stunden Logbuch'),
        actions: [
          if (headerName != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  headerName,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
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
                    onTap: _openWeekList,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Dieser Monat',
                    value: '${formatHours(_monthTotal)} Std.',
                    icon: Icons.calendar_month_rounded,
                    accentColor: AppColors.teal,
                    onTap: _openMonthList,
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
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: _entries.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: Center(
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
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
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
          ),
        ],
      ),
      // Bewusst als bottomNavigationBar statt als letztes Listenelement:
      // so schiebt Flutter den FloatingActionButton automatisch darüber,
      // statt dass er die Tagessumme überdeckt.
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
                  Text(
                    'TAGESSUMME',
                    style: AppTextStyles.eyebrow(AppColors.inkMuted),
                  ),
                  StampBadge(hours: _dayTotal),
                ],
              ),
            )
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddEntry(),
        tooltip: 'Neuer Eintrag',
        child: const Icon(Icons.add),
      ),
    );
  }
}
