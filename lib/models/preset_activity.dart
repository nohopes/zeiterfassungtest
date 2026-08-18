/// Eine vom Nutzer selbst angelegte Vorlage für eine Tätigkeit (z. B. "UP
/// Arbeiten"), damit sie beim Anlegen eines Eintrags nicht jedes Mal neu
/// eingetippt werden muss. Jeder Nutzer verwaltet seine eigenen Vorlagen
/// (anlegen/bearbeiten/löschen) - unabhängig von den automatisch aus der
/// Historie ermittelten "häufig verwendet"-Vorschlägen.
class PresetActivity {
  final int id;
  final String text;

  const PresetActivity({required this.id, required this.text});

  factory PresetActivity.fromMap(Map<String, Object?> map) {
    return PresetActivity(
      id: map['id'] as int,
      text: map['text'] as String,
    );
  }

  Map<String, Object?> toMap() => {'id': id, 'text': text};
}
