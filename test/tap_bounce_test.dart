import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/ui/widgets/tap_bounce.dart';

void main() {
  /// The scale the bounce is currently applying, read off the Transform it
  /// builds. 1.0 means "at rest".
  ///
  /// Reads the x scale (m00) directly rather than `getMaxScaleOnAxis()`:
  /// Transform.scale leaves the z axis at 1.0, and that helper takes the
  /// maximum across all three, so every shrink would read back as 1.0.
  double currentScale(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.ancestor(
        of: find.byKey(const ValueKey('target')),
        matching: find.byType(Transform),
      ),
    );
    return transform.transform.storage[0];
  }

  Future<void> pump(WidgetTester tester, {bool reduceMotion = false}) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: TapBounce(
                child: IconButton(
                  key: const ValueKey('target'),
                  icon: const Icon(Icons.settings),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shrinks while held and springs back on release', (tester) async {
    await pump(tester);
    expect(currentScale(tester), 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    // The first pump only lets the ticker take its baseline; the second is
    // what actually advances the animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(currentScale(tester), lessThan(1.0),
        reason: 'the press should be visible while the finger is down');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(currentScale(tester), moreOrLessEquals(1.0, epsilon: 0.001),
        reason: 'it must return to its real size, not stay shrunk');
  });

  testWidgets('returns smoothly, never past its own size', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump();

    // The return grows monotonically back to exactly 1.0. An overshoot here
    // would be invisible anyway (it is bounded by the press depth), so the
    // absence of one is the intended behaviour, not a missing feature.
    var previous = currentScale(tester);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      final now = currentScale(tester);
      expect(now, greaterThanOrEqualTo(previous - 0.0001));
      expect(now, lessThanOrEqualTo(1.0 + 0.0001));
      previous = now;
    }
    await tester.pumpAndSettle();
    expect(currentScale(tester), moreOrLessEquals(1.0, epsilon: 0.001));
  });

  testWidgets('a cancelled pointer springs back too', (tester) async {
    // Starting a scroll on top of an icon must not leave it stuck small.
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(currentScale(tester), lessThan(1.0));

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(currentScale(tester), moreOrLessEquals(1.0, epsilon: 0.001));
  });

  testWidgets('the wrapped button still receives its tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TapBounce(
              child: IconButton(
                key: const ValueKey('target'),
                icon: const Icon(Icons.settings),
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('target')));
    await tester.pumpAndSettle();
    // The Listener must stay out of the gesture arena, or it would swallow
    // taps from the widget it is decorating.
    expect(taps, 1);
  });

  testWidgets('reduce-motion removes the animation entirely', (tester) async {
    await pump(tester, reduceMotion: true);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('target')),
        matching: find.byType(Listener),
      ),
      findsWidgets,
      reason: 'IconButton has Listeners of its own; the check below is the one '
          'that matters',
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump(const Duration(milliseconds: 120));
    // No Transform is inserted at all when animations are disabled.
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('target')),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
