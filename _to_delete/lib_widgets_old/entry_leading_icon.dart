import 'package:flutter/material.dart';

/// Einheitliches "App-Icon"-Symbol für einen Zeiteintrag (abgerundetes
/// Quadrat statt Kreis - modernerer, klarerer Look als Kreis-Avatare).
class EntryLeadingIcon extends StatelessWidget {
  final bool isWerkstatt;
  final double size;

  const EntryLeadingIcon({super.key, required this.isWerkstatt, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final color = isWerkstatt ? Colors.orange : Colors.blueGrey;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        isWerkstatt ? Icons.build_rounded : Icons.person_rounded,
        color: Colors.white,
        size: size * 0.52,
      ),
    );
  }
}
