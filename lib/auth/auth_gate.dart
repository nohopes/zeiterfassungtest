import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/auth_service.dart';

/// Zeigt einen Ladeindikator, bis geprüft wurde, ob ein gespeicherter
/// Login-Token noch gültig ist, danach entweder den [LoginScreen] oder
/// [child] - reaktiv, damit ein Logout (z. B. im Konto-Screen) sofort
/// zurück zum Login springt.
class AuthGate extends StatefulWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    AuthService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        if (!auth.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!auth.isLoggedIn) {
          return const LoginScreen();
        }
        return widget.child;
      },
    );
  }
}
