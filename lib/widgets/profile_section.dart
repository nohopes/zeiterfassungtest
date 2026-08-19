import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/profile_data.dart';
import '../services/profile_service.dart';
import '../theme/design_tokens.dart';
import 'signature_pad.dart';

/// Name + Unterschrift für den Werkstatt-Wochenbericht - auf jeder
/// Plattform gleich aufgebaut (siehe profile_service.dart für die
/// jeweilige Speicherung). Wird sowohl in der io- als auch der
/// web-Variante des Konto-Screens eingebettet.
class ProfileSection extends StatefulWidget {
  const ProfileSection({super.key});

  @override
  State<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<ProfileSection> {
  final _nameController = TextEditingController();
  final _signaturePadKey = GlobalKey<SignaturePadState>();

  bool _loading = true;
  Uint8List? _savedSignature;
  bool _editingSignature = false;
  bool _savingName = false;
  bool _savingSignature = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ProfileData profile;
    try {
      profile = await ProfileService.instance.loadProfile();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _nameController.text = profile.displayName ?? '';
      _savedSignature = profile.signature;
      _editingSignature = profile.signature == null;
      _loading = false;
    });
  }

  Future<void> _saveName() async {
    setState(() => _savingName = true);
    await ProfileService.instance.saveDisplayName(_nameController.text.trim());
    if (!mounted) return;
    setState(() => _savingName = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name gespeichert.')),
    );
  }

  Future<void> _saveSignature() async {
    final bytes = await _signaturePadKey.currentState?.exportPng();
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte erst unterschreiben.')),
      );
      return;
    }
    setState(() => _savingSignature = true);
    await ProfileService.instance.saveSignature(bytes);
    if (!mounted) return;
    setState(() {
      _savedSignature = bytes;
      _editingSignature = false;
      _savingSignature = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unterschrift gespeichert.')),
    );
  }

  Future<void> _removeSignature() async {
    await ProfileService.instance.clearSignature();
    if (!mounted) return;
    setState(() {
      _savedSignature = null;
      _editingSignature = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PROFIL', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
        const SizedBox(height: 4),
        Text(
          'Dein Name erscheint auf dem Werkstatt-Wochenbericht.',
          style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Dein Name'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _savingName ? null : _saveName,
              child: _savingName
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Speichern'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('UNTERSCHRIFT', style: AppTextStyles.eyebrow(AppColors.inkMuted)),
        const SizedBox(height: 4),
        Text(
          'Wird automatisch dem Werkstatt-Wochenbericht beigefügt, sofern '
          'hinterlegt - ansonsten bleibt die Zeile leer zum Unterschreiben.',
          style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (!_editingSignature && _savedSignature != null) ...[
          Container(
            height: 90,
            decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
            alignment: Alignment.center,
            child: Image.memory(_savedSignature!, height: 80),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _editingSignature = true),
                child: const Text('Ändern'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _removeSignature,
                child: const Text('Entfernen'),
              ),
            ],
          ),
        ] else ...[
          Container(
            height: 140,
            decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
            child: SignaturePad(key: _signaturePadKey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => _signaturePadKey.currentState?.clear(),
                child: const Text('Löschen'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _savingSignature ? null : _saveSignature,
                child: _savingSignature
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unterschrift speichern'),
              ),
              if (_savedSignature != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _editingSignature = false),
                  child: const Text('Abbrechen'),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
