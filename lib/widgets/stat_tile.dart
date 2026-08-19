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
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.amber;

    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
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
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 16, color: AppColors.inkMuted),
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
        ),
      ),
    );
  }
}
