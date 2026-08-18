import 'package:flutter/widgets.dart';

/// Fallback für Plattformen ohne Login-Konzept (iOS/Windows/macOS/Linux/
/// Android) - zeigt [child] immer direkt an, ganz ohne Anmeldung.
class AuthGate extends StatelessWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
