import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/preset_activity.dart';
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

  /// Pause in Minuten (0 = keine, 15 = Frühstück, 30 = Mittag) - nur bei
  /// Kunden-Einträgen relevant, siehe [TimeEntry.breakMinutes].
  int _breakMinutes = 0;

  List<String> _knownCustomers = [];
  List<String> _topActivities = [];
  List<PresetActivity> _presets = [];
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
      _breakMinutes = source.breakMinutes;
    }
    _loadKnownCustomers();
    _loadTopActivities();
    _loadPresets();
  }

  Future<void> _loadKnownCustomers() async {
    final names = await DatabaseHelper.instance.distinctCustomerNames();
    if (!mounted) return;
    setState(() => _knownCustomers = names);
  }

  Future<void> _loadTopActivities() async {
    final activities = await DatabaseHelper.instance.topActivities();
    if (!mounted) return;
    setState(() => _topActivities = activities);
  }

  Future<void> _loadPresets() async {
    final presets = await DatabaseHelper.instance.presetActivities();
    if (!mounted) return;
    setState(() => _presets = presets);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _activityController.dispose();
    super.dispose();
  }

  Duration get _rawDuration => calculateDuration(_startTime, _endTime);

  Duration get _netDuration {
    final breakToSubtract = _isWerkstatt ? 0 : _breakMinutes;
    final net = _rawDuration - Duration(minutes: breakToSubtract);
    return net.isNegative ? Duration.zero : net;
  }

  double get _roundedHours => roundDurationToQuarterHours(_netDuration);

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
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startTime = picked;
        // Zielzeit springt automatisch auf mindestens Start + 15 Min. mit -
        // verhindert eine ungültige/zu knappe Endzeit, ohne eine bewusst
        // länger gewählte Endzeit zu überschreiben. Gleiche
        // Über-Mitternacht-Logik wie calculateDuration().
        final startMinutes = picked.hour * 60 + picked.minute;
        var currentEndMinutes = _endTime.hour * 60 + _endTime.minute;
        if (currentEndMinutes < startMinutes) currentEndMinutes += 24 * 60;
        final minEndMinutes = startMinutes + 15;
        if (currentEndMinutes < minEndMinutes) {
          _endTime = addMinutesToTimeOfDay(picked, 15);
        }
      } else {
        _endTime = picked;
      }
    });
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
    if (!_isWerkstatt && _breakMinutes >= _rawDuration.inMinutes) {
      _showMessage('Die Pause ist länger als die Arbeitszeit');
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
      breakMinutes: _isWerkstatt ? 0 : _breakMinutes,
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

  Future<void> _addPreset() async {
    final text = await _promptForActivityText(title: 'Neue Vorlage');
    if (text == null || text.isEmpty) return;
    final newId = await DatabaseHelper.instance.addPresetActivity(text);
    if (!mounted) return;
    setState(() => _presets = [..._presets, PresetActivity(id: newId, text: text)]);
  }

  Future<void> _editPreset(PresetActivity preset) async {
    final text = await _promptForActivityText(title: 'Vorlage bearbeiten', initial: preset.text);
    if (text == null || text.isEmpty || text == preset.text) return;
    await DatabaseHelper.instance.updatePresetActivity(preset.id, text);
    if (!mounted) return;
    setState(() {
      _presets = _presets
          .map((p) => p.id == preset.id ? PresetActivity(id: p.id, text: text) : p)
          .toList();
    });
  }

  Future<void> _deletePreset(PresetActivity preset) async {
    await DatabaseHelper.instance.deletePresetActivity(preset.id);
    if (!mounted) return;
    setState(() => _presets = _presets.where((p) => p.id != preset.id).toList());
  }

  Future<String?> _promptForActivityText({required String title, String? initial}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Tätigkeit'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickCustomers =
        _knownCustomers.where((n) => n != _nameController.text).take(8).toList();
    final quickTopActivities = _topActivities
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
            if (!_isWerkstatt) ...[
              const SizedBox(height: 12),
              Text('PAUSE', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Keine'), icon: Icon(Icons.block)),
                  ButtonSegment(
                    value: 15,
                    label: Text('Frühstück · 15 Min.'),
                    icon: Icon(Icons.free_breakfast_outlined),
                  ),
                  ButtonSegment(
                    value: 30,
                    label: Text('Mittag · 30 Min.'),
                    icon: Icon(Icons.lunch_dining_outlined),
                  ),
                ],
                selected: {_breakMinutes},
                onSelectionChanged: (s) => setState(() => _breakMinutes = s.first),
              ),
            ],
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
            if (_isWerkstatt) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('DEINE VORLAGEN', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
                  InkWell(
                    onTap: _addPreset,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 15, color: AppColors.amber),
                          const SizedBox(width: 2),
                          Text(
                            'Neu',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_presets.isEmpty)
                Text(
                  'Noch keine Vorlagen - über "Neu" anlegen.',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _presets
                      .map(
                        (preset) => GestureDetector(
                          onLongPress: () => _editPreset(preset),
                          child: InputChip(
                            label: Text(preset.text),
                            onPressed: () {
                              _activityController.text = preset.text;
                              setState(() {});
                            },
                            onDeleted: () => _deletePreset(preset),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
            if (quickTopActivities.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('HÄUFIG VERWENDET', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: quickTopActivities
                    .map(
                      (activity) => ActionChip(
                        avatar: const Icon(Icons.trending_up, size: 16),
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
