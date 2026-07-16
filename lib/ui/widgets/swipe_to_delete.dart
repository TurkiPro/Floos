import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Swipe an entry left-to-right to delete it (the natural direction in an RTL
/// layout). The row does NOT slide aside: a solid red panel wipes across it
/// *on top*, growing from the leading (left) edge to cover the whole entry,
/// with a trash icon that pops in at that edge. The entry and the panel share
/// one rounded clip, so the red lines up with the row exactly — no gaps at the
/// corners. Release past the threshold to delete; an optional [confirm] gate
/// (e.g. a confirmation sheet) runs first. Below the threshold it springs back.
class SwipeToDelete extends StatefulWidget {
  final Widget child;

  /// Runs once the swipe completes (and [confirm], if any, returns true).
  final VoidCallback onDelete;

  /// Optional gate shown after the swipe passes the threshold; the delete
  /// proceeds only if it resolves true.
  final Future<bool> Function()? confirm;

  /// The rounded shape shared by the entry and the red panel.
  final BorderRadius borderRadius;

  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.confirm,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadii.tile)),
  });

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFE53935); // solid Material red 600
  // Past this fraction, releasing commits the delete; below it, springs back.
  static const _threshold = 0.4;

  // 0..1 = how much of the row the red panel currently covers.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _deleting = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _end() async {
    if (_deleting) return;
    if (_c.value < _threshold) {
      _c.animateTo(0, curve: Curves.easeOut);
      return;
    }
    if (widget.confirm != null) {
      final ok = await widget.confirm!();
      if (!ok) {
        if (mounted) _c.animateTo(0, curve: Curves.easeOut);
        return;
      }
    }
    _deleting = true;
    await _c.animateTo(1, curve: Curves.easeOut);
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            if (_deleting || width == 0) return;
            // Left-to-right (a positive delta) grows the red panel.
            _c.value = (_c.value + d.primaryDelta! / width).clamp(0.0, 1.0);
          },
          onHorizontalDragEnd: (_) => _end(),
          child: AnimatedBuilder(
            animation: _c,
            child: widget.child,
            builder: (context, child) {
              final f = _c.value;
              return ClipRRect(
                borderRadius: widget.borderRadius,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    child!,
                    if (f > 0) ...[
                      // Solid red wiping in from the leading (left) edge, over
                      // the row. Sharing the parent clip means its corners line
                      // up with the row's — nothing peeks through.
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: width * f,
                        child: const ColoredBox(color: _red),
                      ),
                      // Trash pinned at the leading edge — fades in fast, then
                      // scales up with a slight overshoot so it "pops" in rather
                      // than appearing from nowhere.
                      Positioned(
                        left: AppSpacing.lg,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Opacity(
                            opacity: (f / 0.15).clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: 0.4 +
                                  0.6 *
                                      Curves.easeOutBack.transform(
                                          (f / 0.35).clamp(0.0, 1.0)),
                              child: const Icon(Icons.delete_outline,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
