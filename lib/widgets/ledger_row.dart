import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/time_entry.dart';
import '../theme/design_tokens.dart';
import '../utils/time_rounding.dart';
import 'stamp_badge.dart';

/// Eine Zeile im Werkstattbuch: farbiger Rand links (Amber = Werkstatt,
/// Petrol = Kunde), Uhrzeit in Monospace, Name/Tätigkeit, gestempelte
/// Stundenzahl rechts, dünne Linie unten. Ersetzt Card+ListTile durch
/// linierte Buchzeilen statt schwebender Karten - passend zu einem
/// "Logbuch"-Layout.
class LedgerRow extends StatelessWidget {
  final TimeEntry entry;
  final VoidCallback? onTap;

  /// Zeigt zusätzlich das Datum an (z. B. in der Suche/Kunden-Übersicht,
  /// wo Einträge aus verschiedenen Tagen gemischt auftauchen).
  final bool showDate;

  /// Optionales zusätzliches Aktions-Icon rechts neben dem Stempel (z. B.
  /// "Für heute übernehmen" in der Suche).
  final Widget? trailingAction;

  const LedgerRow({
    super.key,
    required this.entry,
    this.onTap,
    this.showDate = false,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    final accent = entry.isWerkstatt ? AppColors.amber : AppColors.teal;
    final timeLabel =
        '${formatTimeOfDay(entry.startTime)}–${formatTimeOfDay(entry.endTime)}';
    final datePrefix =
        showDate ? '${DateFormat('EEE, dd.MM.', 'de_DE').format(entry.date)} · ' : '';

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  timeLabel,
                                  style: AppTextStyles.mono.copyWith(
                                    color: accent,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$datePrefix${entry.name}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              entry.activity,
                              style: const TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      StampBadge(hours: entry.durationHours, color: accent),
                      if (trailingAction != null) ...[
                        const SizedBox(width: 4),
                        trailingAction!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
