import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../utils/time_rounding.dart';

/// Gestempelte Stundenanzeige - erinnert an einen Kontrollstempel auf einem
/// Stundenzettel. Wird für jede Stundensumme verwendet (Tag/Woche/Monat/
/// Kunde), damit "das ist eine belastbare Zahl" durchgängig lesbar bleibt.
class StampBadge extends StatelessWidget {
  final double hours;
  final Color color;
  final double fontSize;

  const StampBadge({
    super.key,
    required this.hours,
    this.color = AppColors.amber,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.035, // ~-2°: dezenter "von Hand gestempelt"-Effekt
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.4),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          '${formatHours(hours)} Std.',
          style: AppTextStyles.monoStrong.copyWith(
            color: color,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}
