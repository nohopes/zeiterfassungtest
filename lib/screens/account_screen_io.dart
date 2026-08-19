import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../widgets/profile_section.dart';

/// Fallback für Plattformen ohne Login-Konzept (iOS/Windows/macOS/Linux/
/// Android) - hier gibt es keine Konten, nur die persönlichen Angaben für
/// den Werkstatt-Wochenbericht (Name/Unterschrift).
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.smartphone_outlined, color: AppColors.inkMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Auf diesem Gerät gibt es kein Nutzerkonto - alle Daten '
                    'liegen lokal und nur für dich.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const ProfileSection(),
        ],
      ),
    );
  }
}
