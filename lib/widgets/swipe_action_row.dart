import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Wischbare Zeile im Stil von Mail-Apps: leichtes Wischen nach links
/// deckt "Bearbeiten" + "Löschen" nebeneinander auf (bleiben stehen, bis
/// man wieder antippt oder zurückwischt statt sofort zu löschen), ein
/// komplettes Durchziehen nach links löscht dagegen sofort, ohne dass man
/// extra auf den Löschen-Button tippen muss.
class SwipeActionRow extends StatefulWidget {
  /// Der eigentliche Zeileninhalt (z. B. [LedgerRow]) - bekommt bewusst
  /// KEIN eigenes onTap mehr übergeben, das übernimmt [onTap] hier, damit
  /// sich Wisch- und Tipp-Geste nicht gegenseitig stören.
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const SwipeActionRow({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.onTap,
  });

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow>
    with SingleTickerProviderStateMixin {
  static const double _actionWidth = 72;
  static const double _actionsWidth = _actionWidth * 2;

  late final AnimationController _controller;
  Animation<double>? _animation;

  /// Aktuelle horizontale Verschiebung (immer <= 0 - nur nach links).
  double _dragX = 0;
  double _rowWidth = 300;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, {VoidCallback? onDone, Duration? duration}) {
    final begin = _dragX;
    _animation = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dragX = _animation!.value));
    _controller
      ..duration = duration ?? const Duration(milliseconds: 200)
      ..forward(from: 0).whenComplete(() {
        onDone?.call();
      });
  }

  void _close() => _animateTo(0);

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(-_rowWidth, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final fullThreshold = -(_rowWidth * 0.62);
    if (_dragX < fullThreshold || velocity < -1200) {
      _animateTo(
        -_rowWidth,
        duration: const Duration(milliseconds: 180),
        onDone: widget.onDelete,
      );
      return;
    }
    final revealThreshold = -(_actionsWidth * 0.35);
    if (_dragX < revealThreshold) {
      _animateTo(-_actionsWidth);
    } else {
      _close();
    }
  }

  void _delete() {
    _animateTo(
      -_rowWidth,
      duration: const Duration(milliseconds: 180),
      onDone: widget.onDelete,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _rowWidth = constraints.maxWidth;
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    const Spacer(),
                    _ActionButton(
                      width: _actionWidth,
                      color: AppColors.teal,
                      icon: Icons.edit_outlined,
                      label: 'Bearbeiten',
                      onTap: () {
                        _close();
                        widget.onEdit();
                      },
                    ),
                    _ActionButton(
                      width: _actionWidth,
                      color: AppColors.rust,
                      icon: Icons.delete_outline,
                      label: 'Löschen',
                      onTap: _delete,
                    ),
                  ],
                ),
              ),
              // WICHTIG: Transform.translate als NICHT in Positioned
              // gewrapptes Stack-Kind - nur so behält die Zeile ihre
              // natürliche Höhe. Ein Stack, dessen Kinder ALLE positioniert
              // sind (wie in einer vorherigen Version dieser Datei, die
              // hier stattdessen Positioned(left: _dragX, ...) nutzte),
              // kollabiert innerhalb einer ListView auf Höhe 0 - ListView
              // gibt seinen Kindern eine unbeschränkte Höhe, und ohne
              // mindestens ein NICHT positioniertes Kind hat der Stack
              // dann keine Grundlage, seine eigene Höhe zu bestimmen. Genau
              // das ließ zuletzt ganze Einträge unsichtbar werden, obwohl
              // sie noch in der Tagessumme mitzählten.
              //
              // WICHTIG 2: GestureDetector als KIND von Transform.translate
              // (nicht als Elternteil, wie ursprünglich vor dem
              // Positioned-Zwischenstand) - Flutter rechnet eingehende
              // Tap-Positionen dann korrekt anhand der Inversen des
              // Transforms in Kind-Koordinaten um. Ein Tap im aufgedeckten
              // Bereich landet dadurch außerhalb der Bounds dieses Kindes
              // und fällt automatisch durch zum darunterliegenden
              // Stack-Kind (den Bearbeiten/Löschen-Buttons), statt (wie
              // beim ursprünglichen Bug, als der GestureDetector der
              // Elternteil des Transforms war) von einer immer an der
              // vollen, unverschobenen Zeilenbreite stehenden Hit-Test-Box
              // abgefangen zu werden.
              Transform.translate(
                offset: Offset(_dragX, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_dragX != 0) {
                      _close();
                      return;
                    }
                    widget.onTap?.call();
                  },
                  onHorizontalDragStart: (_) => _controller.stop(),
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: ColoredBox(color: AppColors.bg, child: widget.child),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final double width;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.width,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        color: color,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
