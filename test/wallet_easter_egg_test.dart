import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/ui/widgets/wallet_easter_egg.dart';

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  Future<void> pump(WidgetTester tester, {bool reduceMotion = false}) {
    return tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: const Scaffold(
              body: Center(
                child: WalletEasterEgg(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Each coin is struck with the riyal mark, so counting those counts coins.
  int coinCount(WidgetTester tester) => find.text('⃁').evaluate().length;

  testWidgets('at rest it is just the wallet, no coins', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsOneWidget);
    expect(coinCount(tester), 0);
  });

  testWidgets('tapping spills coins that then disappear', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(WalletEasterEgg));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(coinCount(tester), greaterThan(0),
        reason: 'the burst should be in flight mid-animation');

    await tester.pumpAndSettle();
    expect(coinCount(tester), 0,
        reason: 'coins must clean themselves up, not linger in the header');
  });

  testWidgets('the wallet wobbles and returns to square', (tester) async {
    await pump(tester);

    double walletAngle() {
      final rotations = tester.widgetList<Transform>(
        find.ancestor(
          of: find.byIcon(Icons.account_balance_wallet_rounded),
          matching: find.byType(Transform),
        ),
      );
      // The wallet's own rotation is the innermost Transform above it.
      return rotations.first.transform.storage[1];
    }

    expect(walletAngle(), 0.0);
    await tester.tap(find.byType(WalletEasterEgg));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(walletAngle(), isNot(0.0), reason: 'it should be mid-wobble');

    await tester.pumpAndSettle();
    expect(walletAngle(), 0.0, reason: 'it must settle square, not askew');
  });

  testWidgets('a second tap restarts the burst rather than being swallowed',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byType(WalletEasterEgg));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(WalletEasterEgg));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(coinCount(tester), greaterThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('reduce-motion skips the animation entirely', (tester) async {
    await pump(tester, reduceMotion: true);
    await tester.tap(find.byType(WalletEasterEgg));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    // Still tappable (the chime and haptic are the feedback), but nothing moves.
    expect(coinCount(tester), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('it never changes the layout around it', (tester) async {
    await pump(tester);
    final before = tester.getSize(find.byType(WalletEasterEgg));

    await tester.tap(find.byType(WalletEasterEgg));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Coins in flight must not grow the header or nudge the wordmark.
    expect(tester.getSize(find.byType(WalletEasterEgg)), before);
    await tester.pumpAndSettle();
  });
}
