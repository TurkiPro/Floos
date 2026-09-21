import 'package:flutter/material.dart';

/// Gives a tappable icon a small press-and-spring so a tap feels answered.
///
/// It listens to raw pointer events rather than recognising a gesture, which
/// matters: the things this wraps already have their own [InkWell] or
/// [GestureDetector]. Entering the gesture arena would mean competing with
/// them — swallowing taps, or killing the ink ripple. A [Listener] only
/// watches, so the child's tap handling and ripple are untouched and this
/// stays purely decorative.
///
/// The child shrinks on press and eases back on release. It deliberately does
/// not overshoot: the pop would be bounded by the press depth (a few percent),
/// so it lands under the threshold of being visible while still costing a
/// frame budget — and on controls tapped as often as these, a bouncier
/// animation stops reading as polish and starts reading as noise.
class TapBounce extends StatefulWidget {
  final Widget child;

  /// How far to shrink while held. Subtle on purpose — this should register
  /// as responsiveness, not as an effect.
  final double scale;

  const TapBounce({super.key, required this.child, this.scale = 0.92});

  @override
  State<TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<TapBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Down fast so the press feels immediate; back slower so the spring is
    // visible rather than a flicker.
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 260),
  );

  late final Animation<double> _press = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    // Decelerating on the way back, so the icon settles rather than snapping.
    reverseCurve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "reduce motion" setting: no wrapper at all, so there is
    // nothing to animate and nothing extra in the tree.
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    return Listener(
      onPointerDown: (_) => _controller.forward(),
      onPointerUp: (_) => _controller.reverse(),
      // Fires when a scroll takes the pointer over, so starting a drag on an
      // icon springs it back instead of leaving it stuck small.
      onPointerCancel: (_) => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) => Transform.scale(
          scale: 1 - (1 - widget.scale) * _press.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
