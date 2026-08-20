import 'package:flutter/material.dart';

/// Design-Sprache "Werkstattbuch": Die App liest sich wie ein geführtes
/// Logbuch aus der Werkstatt - warmes, fast schwarzes Papier, zwei klare
/// Stempelfarben für die zwei Eintragsarten (Amber = Werkstatt, Petrol =
/// Kunde) und Monospace-Ziffern für alles, was gezählt/gestempelt wird
/// (Uhrzeiten, Stunden), damit Zahlen wie in einem echten Stundenzettel
/// exakt untereinanderstehen.
class AppColors {
  AppColors._();

  static const bg = Color(0xFF15130E); // Werkstattwand, warmes Schwarz
  static const surface = Color(0xFF1C1911); // Zeilen/Karten
  static const surfaceHigh = Color(0xFF262119); // Kennzahlen-Kacheln
  static const line = Color(0xFF3B3527); // Linierung, wie Ledger-Papier

  static const ink = Color(0xFFF4EEDF); // warmes Off-White (Text)
  static const inkMuted = Color(0xFFAE9F84); // gedämpfter Text

  static const amber = Color(0xFFF2A93B); // Werkstatt-Stempel
  static const amberDim = Color(0xFF7A5A22);
  static const teal = Color(0xFF4FA093); // Kunden-Stempel
  static const tealDim = Color(0xFF285850);
  static const rust = Color(0xFFC1553B); // Löschen/Warnung
  static const slate = Color(0xFF7C93B0); // Urlaub-Stempel
  static const clay = Color(0xFFB5654A); // Krankheit-Stempel (bewusst anders als "rust"/Fehler)
  static const violet = Color(0xFFA98CD1); // "Diese Woche"-Kachel auf der Startseite
}

/// Zentrale Textstile für Zahlen, die "gezählt" werden - bewusst mit der
/// generischen `monospace`-Systemschrift (keine Zusatz-Fonts nötig), damit
/// Uhrzeiten/Stundenwerte wie auf einem gestempelten Stundenzettel exakt
/// untereinander ausgerichtet sind.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const TextStyle monoStrong = TextStyle(
    fontFamily: 'monospace',
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );

  /// Kleine, breit gesperrte Großbuchstaben-Labels ("WERKSTATT",
  /// "DIESE WOCHE") - wirken wie Beschriftungen auf Karteikarten/Regalen.
  static TextStyle eyebrow(Color color) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: color,
      );
}
