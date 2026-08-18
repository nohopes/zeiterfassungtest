import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Kompakte Kennzahlen-Kachel (z. B. "DIESE WOCHE · 12,50 Std."). Label als
/// gesperrte Großbuchstaben-Beschriftung wie auf einer Karteikarte, Wert in
/// Monospace wie ein gestempelter Stundenwert.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border(top: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppTextStyles.eyebrow(AppColors.inkMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.monoStrong.copyWith(
              fontSize: 20,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
