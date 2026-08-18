import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Fallback für Plattformen ohne Login-Konzept (iOS/Windows/macOS/Linux/
/// Android) - hier gibt es keine Konten, also nur ein kurzer Hinweis.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konto')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smartphone_outlined, size: 40, color: AppColors.inkMuted),
              const SizedBox(height: 12),
              Text(
                'Auf diesem Gerät gibt es kein Nutzerkonto - alle Daten '
                'liegen lokal und nur für dich.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
