import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/signature_pad.dart';

/// Vollbild-Unterschriftenfeld für kleine Bildschirme (Handy statt iPad):
/// das komplette Feld inkl. Bedienknöpfe wird um 90° gedreht dargestellt,
/// sodass durch Drehen des Handys quer eine große, bequem nutzbare
/// Zeichenfläche entsteht - ohne dass eine Bildschirm-Rotation vom
/// Betriebssystem/Browser erzwungen werden muss (das funktioniert auf
/// iOS-Safari als installierte PWA nämlich nicht zuverlässig).
///
/// Gibt bei "Fertig" die PNG-Bytes der Unterschrift über
/// `Navigator.pop(bytes)` zurück, oder `null` bei "Abbrechen".
class SignatureCaptureScreen extends StatefulWidget {
  const SignatureCaptureScreen({super.key});

  @override
  State<SignatureCaptureScreen> createState() => _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<SignatureCaptureScreen> {
  final _padKey = GlobalKey<SignaturePadState>();

  Future<void> _done() async {
    final bytes = await _padKey.currentState?.exportPng();
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte erst unterschreiben.')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop<Uint8List>(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RotatedBox(
          // Ein Viertel im Uhrzeigersinn gedreht: Handy quer halten (im
          // Uhrzeigersinn drehen), damit Zeichenfläche + Knöpfe unten
          // korrekt herum erscheinen.
          quarterTurns: 1,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Abbrechen',
                    ),
                    const Expanded(
                      child: Text(
                        'Handy quer halten und unterschreiben',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _padKey.currentState?.clear(),
                      child: const Text('Löschen'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: _done,
                      child: const Text('Fertig'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                    child: SignaturePad(key: _padKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
