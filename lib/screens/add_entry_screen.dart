import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../utils/time_rounding.dart';

class AddEntryScreen extends StatefulWidget {
  final DateTime initialDate;

  /// Vorhandener Eintrag zum Bearbeiten (hat eine id, kann gelöscht werden).
  final TimeEntry? existing;

  /// Werte eines vergangenen Eintrags, die als Ausgangspunkt für einen NEUEN
  /// Eintrag übernommen werden sollen (z. B. "Für heute übernehmen" aus der
  /// Suche). Wird als neuer Eintrag gespeichert, nicht als Bearbeitung.
  final TimeEntry? template;

  const AddEntryScreen({
    super.key,
    required this.initialDate,
    this.existing,
    this.template,
  });

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  late bool _isWerkstatt;
  late TextEditingController _nameController;
  late TextEditingController _activityController;
  TimeOfDay _startTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 7, minute: 30);
  List<String> _knownCustomers = [];
  List<String> _recentActivities = [];
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // Werte kommen entweder von einem zu bearbeitenden Eintrag, einer
    // Vorlage (Duplizieren), oder es sind die Standardwerte für einen
    // komplett neuen Eintrag.
    final source = widget.existing ?? widget.template;
    _isWerkstatt = source?.isWerkstatt ?? false;
    _nameController = TextEditingController(
      text: (source != null && !source.isWerkstatt) ? source.name : '',
    );
    _activityController = TextEditingController(text: source?.activity ?? '');
    if (source != null) {
      _startTime = source.startTime;
      _endTime = source.endTime;
    }
    _loadKnownCustomers();
    _loadRecentActivities();
  }

  Future<void> _loadKnownCustomers() async {
    final names = await DatabaseHelper.instance.distinctCustomerNames();
    if (!mounted) return;
    setState(() => _knownCustomers = names);
  }

  Future<void> _loadRecentActivities() async {
    final activities = await DatabaseHelper.instance.recentActivities();
    if (!mounted) return;
    setState(() => _recentActivities = activities);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _activityController.dispose();
    super.dispose();
  }

  Duration get _rawDuration => calculateDuration(_startTime, _endTime);
  double get _roundedHours => roundDurationToQuarterHours(_rawDuration);

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_isWerkstatt && _nameController.text.trim().isEmpty) {
      _showMessage('Bitte einen Kundennamen eingeben');
      return;
    }
    if (_activityController.text.trim().isEmpty) {
      _showMessage('Bitte eine Tätigkeit eingeben');
      return;
    }
    if (_rawDuration.inMinutes <= 0) {
      _showMessage('Endzeit muss nach der Startzeit liegen');
      return;
    }

    setState(() => _saving = true);

    final entry = TimeEntry(
      id: widget.existing?.id,
      date: widget.initialDate,
      name: _isWerkstatt ? 'Werkstatt' : _nameController.text.trim(),
      isWerkstatt: _isWerkstatt,
      startTime: _startTime,
      endTime: _endTime,
      activity: _activityController.text.trim(),
    );

    if (_isEditing) {
      await DatabaseHelper.instance.updateEntry(entry);
    } else {
      await DatabaseHelper.instance.insertEntry(entry);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    await DatabaseHelper.instance.deleteEntry(id);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final quickCustomers =
        _knownCustomers.where((n) => n != _nameController.text).take(8).toList();
    final quickActivities = _recentActivities
        .where((a) => a != _activityController.text)
        .take(6)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Eintrag bearbeiten' : 'Neuer Eintrag'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Löschen',
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Kunde'), icon: Icon(Icons.person)),
                ButtonSegment(value: true, label: Text('Werkstatt'), icon: Icon(Icons.build)),
              ],
              selected: {_isWerkstatt},
              onSelectionChanged: (selection) {
                setState(() => _isWerkstatt = selection.first);
              },
            ),
            const SizedBox(height: 16),
            if (!_isWerkstatt) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Kunde'),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              if (quickCustomers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: quickCustomers
                      .map(
                        (name) => ActionChip(
                          label: Text(name),
                          onPressed: () {
                            _nameController.text = name;
                            setState(() {});
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: true),
                    child: Text('Von: ${formatTimeOfDay(_startTime)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isStart: false),
                    child: Text('Bis: ${formatTimeOfDay(_endTime)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  formatHours(_roundedHours),
                  style: AppTextStyles.monoStrong.copyWith(
                    fontSize: 16,
                    color: _isWerkstatt ? AppColors.amber : AppColors.teal,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Std. (gerundet auf 0,25-Schritte)',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _activityController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Tätigkeit',
                hintText: 'z. B. UP Arbeiten',
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            if (quickActivities.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: quickActivities
                    .map(
                      (activity) => ActionChip(
                        avatar: const Icon(Icons.history, size: 16),
                        label: Text(activity),
                        onPressed: () {
                          _activityController.text = activity;
                          setState(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
