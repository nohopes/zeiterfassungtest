import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/design_tokens.dart';

/// Login-Formular für die Web/PWA-Variante. Wird von AuthGate angezeigt,
/// solange noch kein gültiger Token vorliegt.
///
/// Design bewusst als "Deckblatt des Logbuchs": liniertes Papier im
/// Hintergrund (wie die Web/PWA-App selbst als geführtes Werkstattbuch
/// verstanden wird), ein großer gestempelter Werkstatt-Stempel oben - genau
/// die Bildsprache, die StampBadge/LedgerRow im Rest der App schon etabliert
/// haben, hier nur einmal groß auf der ersten Seite.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Bitte Benutzername und Passwort eingeben');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await AuthService.instance.login(username, password);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Liniertes Papier über die volle Fläche - dieselbe Assoziation
          // ("Logbuch"), die die Werkzeugleiste/Ledger-Zeilen im Rest der
          // App tragen, hier als ruhiger Hintergrund statt als Deko-Element.
          Positioned.fill(
            child: CustomPaint(painter: _LedgerPaperPainter()),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _StampMark()),
                      const SizedBox(height: 20),
                      Text(
                        'Stunden Logbuch',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: AppColors.ink,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Melde dich an, um dein Logbuch zu öffnen.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Benutzername',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'Passwort',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _LedgerNotice(text: _error!),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : const Text('Anmelden'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Großer Werkstatt-Stempel als Titelbild - dieselbe Bildsprache wie
/// [StampBadge] (Rand statt Füllung, leicht schräg wie von Hand gestempelt),
/// hier einmalig groß für den Wiedererkennungswert auf der Anmeldeseite.
class _StampMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.05,
      child: Container(
        width: 76,
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.amber, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.construction, color: AppColors.amber, size: 34),
      ),
    );
  }
}

/// Statusmeldung im "Ledger-Zeilen"-Stil - farbiger Rand links, so wie
/// jede Zeile im Logbuch (siehe LedgerRow), nur hier für eine Warnung statt
/// eines Eintrags. Dieselbe Struktur, andere Bedeutung: die Farbe des
/// Randstrichs zeigt in der ganzen App den Status/die Art einer Zeile an.
class _LedgerNotice extends StatelessWidget {
  final String text;

  const _LedgerNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.rust, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.rust),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zeichnet feine horizontale Linien über die ganze Fläche - liniertes
/// Papier wie in einem echten Werkstattbuch. Bewusst sehr dezent (gleiche
/// gedämpfte Linienfarbe wie die Trennlinien in den Listen), damit es
/// Textur bleibt und nicht mit dem Formular konkurriert.
class _LedgerPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line.withOpacity(0.55)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LedgerPaperPainter oldDelegate) => false;
}
