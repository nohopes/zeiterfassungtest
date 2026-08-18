import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../widgets/ledger_row.dart';
import 'add_entry_screen.dart';

/// Volltextsuche über Kundennamen/"Werkstatt" und Tätigkeit, über alle
/// gespeicherten Einträge hinweg (nicht auf einen Monat beschränkt).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<TimeEntry> _results = [];
  bool _loading = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    setState(() => _loading = true);
    final results = await DatabaseHelper.instance.searchEntries(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      _hasSearched = true;
    });
  }

  void _clear() {
    _controller.clear();
    _search('');
  }

  Future<void> _openEntry(TimeEntry entry) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEntryScreen(initialDate: entry.date, existing: entry),
      ),
    );
    if (result == true) {
      _search(_controller.text);
    }
  }

  /// Übernimmt Name/Tätigkeit/Uhrzeiten eines vergangenen Eintrags als
  /// Ausgangspunkt für einen neuen Eintrag - z. B. um eine wiederkehrende
  /// Tätigkeit für heute schnell zu erfassen, ohne alles neu einzutippen.
  Future<void> _duplicateForToday(TimeEntry entry) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEntryScreen(
          initialDate: DateTime.now(),
          template: entry,
        ),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Für heute übernommen')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suche')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Kunde oder Tätigkeit suchen …',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clear,
                      ),
              ),
              onChanged: (value) {
                setState(() {}); // für das Clear-Icon
                _search(value);
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? Center(
                        child: Text(
                          'Suche nach Kunde oder Tätigkeit',
                          style: TextStyle(color: AppColors.inkMuted),
                        ),
                      )
                    : _results.isEmpty
                        ? const Center(child: Text('Keine Treffer'))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final e = _results[index];
                              return LedgerRow(
                                entry: e,
                                showDate: true,
                                onTap: () => _openEntry(e),
                                trailingAction: IconButton(
                                  icon: const Icon(Icons.today_outlined, size: 20),
                                  tooltip: 'Für heute übernehmen',
                                  onPressed: () => _duplicateForToday(e),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
