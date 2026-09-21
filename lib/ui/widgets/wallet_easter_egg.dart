import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_settings.dart';
import '../../data/enums.dart';
import '../../services/sound_service.dart';

/// The wallet glyph beside the فلوس wordmark, with a small reward for tapping
/// it: the wallet gives a decaying wobble and spills a handful of coins that
/// arc out and fade, over the same chime a saved transaction plays.
///
/// Purely decorative and entirely self-contained — it changes no data and
/// nothing else depends on it, so it can be removed by deleting the widget.
class WalletEasterEgg extends StatefulWidget {
  final Color color;
  final double size;

  const WalletEasterEgg({super.key, required this.color, this.size = 28});

  @override
  State<WalletEasterEgg> createState() => _WalletEasterEggState();
}

/// One coin's flight, fixed rather than random so the burst looks composed
/// every time instead of occasionally clumping.
typedef _Coin = ({double angle, double distance, double delay, double size});

/// Angles are in radians with -pi/2 straight up, so this fans the coins from
/// upper-left to upper-right. Distances stay short enough that they finish
/// inside the header rather than being clipped at its edge.
const List<_Coin> _coins = [
  (angle: -2.45, distance: 34, delay: 0.00, size: 14),
  (angle: -1.95, distance: 46, delay: 0.06, size: 16),
  (angle: -1.55, distance: 52, delay: 0.02, size: 13),
  (angle: -1.15, distance: 44, delay: 0.10, size: 15),
  (angle: -0.70, distance: 36, delay: 0.05, size: 13),
  (angle: -0.30, distance: 28, delay: 0.13, size: 15),
];

const _coinGold = Color(0xFFFFC94D);
const _coinEdge = Color(0xFF8A5A00);

/// A coin struck with the riyal mark rather than a Material money icon —
/// every one of those carries a dollar sign, which has no business in an
/// Arabic-first Saudi app. U+20C1 is the same glyph every amount in the app
/// is suffixed with, and falls back to the bundled Saudi Riyal font.
Widget _coinFace(double size) {
  return Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: _coinGold, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text(
      '⃁',
      style: TextStyle(
        fontSize: size * 0.66,
        height: 1,
        color: _coinEdge,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _WalletEasterEggState extends State<WalletEasterEgg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tap() {
    // Income's chime rather than expense's: coins leaving the wallet is the
    // picture, but this is a reward, and that is the happier of the two.
    SoundService.playSaved(
      enabled: context.read<AppSettings>().soundEnabled,
      type: TxnType.income,
    );
    // from: 0 so an impatient second tap restarts the burst instead of being
    // swallowed while the first is still running.
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = Icon(
      Icons.account_balance_wallet_rounded,
      color: widget.color,
      size: widget.size,
    );

    return GestureDetector(
      onTap: _tap,
      // The glyph does not fill its box; opaque keeps the whole area tappable
      // so this doesn't become a game of hitting the exact pixels.
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          return Stack(
            // Coins travel beyond the glyph's box; without this they would be
            // cut off at its edge.
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Coins paint BEFORE the wallet, so they emerge from behind it
              // and read as coming from inside.
              for (final coin in _coins) _buildCoin(coin, t),
              Transform.rotate(angle: _wobble(t), child: child),
            ],
          );
        },
        child: wallet,
      ),
    );
  }

  /// A decaying wobble: three swings that shrink to nothing, so the wallet
  /// settles rather than stopping dead.
  double _wobble(double t) {
    if (t == 0 || t == 1) return 0;
    return math.sin(t * math.pi * 6) * 0.20 * (1 - t);
  }

  Widget _buildCoin(_Coin coin, double t) {
    if (t == 0 || t == 1) return const SizedBox.shrink();

    // Each coin runs its own clock, staggered, so they spill rather than
    // leaving in formation.
    final local = ((t - coin.delay) / (1 - coin.delay)).clamp(0.0, 1.0);
    if (local == 0) return const SizedBox.shrink();

    final travel = Curves.easeOutCubic.transform(local);
    final dx = math.cos(coin.angle) * coin.distance * travel;
    // A little gravity pulling the arc back down as it slows.
    final dy =
        math.sin(coin.angle) * coin.distance * travel + 18 * travel * travel;

    // Not Positioned: the stack centres it on the wallet and Transform.translate
    // moves it at paint time, so a coin in flight never affects layout.
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        // Solid until the coin has cleared the wallet, then fading away. A
        // fade that starts at once makes the burst read as a faint smudge,
        // because the coins are dimmest exactly where they overlap the glyph.
        opacity:
            local < 0.35 ? 1.0 : (1 - (local - 0.35) / 0.65).clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: travel * math.pi * 1.5,
          child: _coinFace(coin.size),
        ),
      ),
    );
  }
}
