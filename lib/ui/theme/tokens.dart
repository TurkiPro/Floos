import 'package:flutter/material.dart';

/// Spacing scale (logical pixels).
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

/// Corner radii.
class AppRadii {
  static const card = 16.0;
  static const tile = 12.0;
  static const tileLg = 14.0;
  static const button = 14.0;
  static const chip = 10.0;
}

/// Type scale.
class AppTextSizes {
  static const heroMin = 32.0;
  static const heroMax = 40.0;
  static const label = 12.5;
  static const row = 15.0;
}

/// Raw palette. Screens should read colors via Theme.of(context).colorScheme
/// where a ColorScheme slot exists (primary, surface, onSurface, ...) and
/// fall back to these constants only for values with no natural slot
/// (brandProgress, income, the muted text tier).
class AppColors {
  static const brand = Color(0xFF0F6E56);
  static const brandProgress = Color(0xFF1D9E75);
  static const income = Color(0xFF2FA363);
  // Expense amounts use ColorScheme.onSurface (primary ink) rather than a
  // fixed hex here, since ink differs light (#1A1815) vs dark.

  static const pageLight = Color(0xFFF7F5F0);
  static const cardLight = Color(0xFFFFFFFF);
  static const textPrimaryLight = Color(0xFF1A1815);
  static const textSecondaryLight = Color(0xFF8A857C);
  static const textMutedLight = Color(0xFFA8A39A);

  static const pageDark = Color(0xFF0E0E10);
  static const cardDark = Color(0xFF1A1A1C);
  // Dark text triplet wasn't specified by the design brief (only page/card
  // hex were given for dark mode) -- proposed to mirror the light triplet's
  // contrast relationship against its own background.
  static const textPrimaryDark = Color(0xFFF2F0EC);
  static const textSecondaryDark = Color(0xFFA8A39A);
  static const textMutedDark = Color(0xFF6E6A62);
}

/// Card shadow (0 4px 16px rgba(0,0,0,0.05)) -- Material elevation can't
/// reproduce this soft diffuse CSS-style shadow, so it's applied directly
/// via BoxDecoration on the widgets that need it (hero/goal cards) rather
/// than routed through CardTheme elevation.
class AppShadows {
  static const card = BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 16,
    offset: Offset(0, 4),
  );
}

/// User-selectable accent colors, chosen on a color-wheel spread (green →
/// teal → blue → purple → pink → warm) so they read as a deliberate,
/// harmonious set rather than random hues. Each carries its own [onPrimary]
/// so a light accent (baby pink) still gets legible text on filled surfaces,
/// and a brighter [progress] shade for progress bars. [green] is the default.
enum AppAccent {
  green('أخضر', Color(0xFF0F6E56), Colors.white, Color(0xFF1D9E75)),
  teal('فيروزي', Color(0xFF0E7C6E), Colors.white, Color(0xFF17A594)),
  blue('أزرق', Color(0xFF2F6DB5), Colors.white, Color(0xFF4A90D9)),
  purple('بنفسجي', Color(0xFF6B4EA8), Colors.white, Color(0xFF8B6DD1)),
  pink('وردي', Color(0xFFE68CAF), Color(0xFF3E1528), Color(0xFFF2AECB)),
  amber('كهرماني', Color(0xFFC77D2E), Colors.white, Color(0xFFE8A13A));

  const AppAccent(this.label, this.primary, this.onPrimary, this.progress);

  final String label;
  final Color primary;
  final Color onPrimary;
  final Color progress;
}

/// Carries the accent's brighter progress shade through the theme so progress
/// bars follow the selected accent without every call site hardcoding a hex.
/// (Buttons/FAB already follow the accent via ColorScheme.primary.)
class AccentPalette extends ThemeExtension<AccentPalette> {
  final Color progress;
  const AccentPalette({required this.progress});

  @override
  AccentPalette copyWith({Color? progress}) =>
      AccentPalette(progress: progress ?? this.progress);

  @override
  AccentPalette lerp(ThemeExtension<AccentPalette>? other, double t) {
    if (other is! AccentPalette) return this;
    return AccentPalette(progress: Color.lerp(progress, other.progress, t)!);
  }
}

/// Light/dark ColorScheme pairs, built explicitly (not .fromSeed) since the
/// design brief gives exact hex values for text/surface roles that
/// fromSeed's derivation algorithm wouldn't reliably reproduce. Only the
/// accent-driven [primary]/[onPrimary] slots vary with the chosen accent.
class AppColorSchemes {
  static ColorScheme light(AppAccent accent) => ColorScheme.light(
        primary: accent.primary,
        onPrimary: accent.onPrimary,
        surface: AppColors.cardLight,
        onSurface: AppColors.textPrimaryLight,
        onSurfaceVariant: AppColors.textSecondaryLight,
      );

  static ColorScheme dark(AppAccent accent) => ColorScheme.dark(
        primary: accent.primary,
        onPrimary: accent.onPrimary,
        surface: AppColors.cardDark,
        onSurface: AppColors.textPrimaryDark,
        onSurfaceVariant: AppColors.textSecondaryDark,
      );
}

/// Per-category-icon-key tile colors (pale tint background + deep
/// saturated icon color), theme-mode-aware via ThemeExtension so it's
/// reachable the idiomatic way and can grow real dark-mode variants later
/// without touching call sites.
class CategoryTileColors extends ThemeExtension<CategoryTileColors> {
  final Map<String, (Color bg, Color fg)> byIconKey;
  const CategoryTileColors(this.byIconKey);

  @override
  CategoryTileColors copyWith() => this;

  @override
  CategoryTileColors lerp(ThemeExtension<CategoryTileColors>? other, double t) {
    return this; // discrete swap, no lerp needed
  }
}

/// The 8 expense-leaning pairs are from the design brief verbatim. The 3
/// income-leaning keys (salary, extra_income, investment) weren't covered
/// by the brief -- proposed here following the same pale-tint/deep-fg
/// pattern, each hue-distinct from the other 10: salary = forest green,
/// extra_income = teal-green (echoes the brand teal), investment =
/// blue-teal (echoes its existing Icons.trending_up glyph). Reused
/// unchanged in dark mode -- no dark variants were specified and these
/// stay saturated enough to read on the #1A1A1C dark card.
const categoryTileColors = CategoryTileColors({
  'food': (Color(0xFFFAECE7), Color(0xFF712B13)),
  'transport': (Color(0xFFE6F1FB), Color(0xFF0C447C)),
  'shopping': (Color(0xFFEEEDFE), Color(0xFF3C3489)),
  'bills': (Color(0xFFFAEEDA), Color(0xFF633806)),
  'health': (Color(0xFFE1F5EE), Color(0xFF085041)),
  'entertainment': (Color(0xFFFBEAF0), Color(0xFF72243E)),
  'home': (Color(0xFFEAF3DE), Color(0xFF27500A)),
  'other': (Color(0xFFF1EFE8), Color(0xFF2C2C2A)),
  'salary': (Color(0xFFE8F2EA), Color(0xFF1B5E3A)),
  'extra_income': (Color(0xFFEAF4F0), Color(0xFF0E6E52)),
  'investment': (Color(0xFFE3F0F5), Color(0xFF105B73)),
});

/// Tile colors for a category: the curated design-brief pair when the icon key
/// is one of the 11 seeded ones, otherwise a pair derived from the category's
/// own [colorValue] — pale tint background, readable foreground — so
/// user-created categories and sub-categories carry the color the user picked
/// instead of all falling back to the neutral "other" pair.
(Color bg, Color fg) categoryTilePair({
  required String iconKey,
  required int? colorValue,
  required Brightness brightness,
}) {
  final curated = categoryTileColors.byIconKey[iconKey];
  if (curated != null) return curated;
  if (colorValue == null) return categoryTileColors.byIconKey['other']!;
  final hsl = HSLColor.fromColor(Color(colorValue));
  if (brightness == Brightness.light) {
    // Pale tint like the curated pairs (~93% lightness), deep saturated fg.
    final bg = hsl
        .withLightness(0.93)
        .withSaturation(hsl.saturation.clamp(0.35, 0.75))
        .toColor();
    final fg = hsl.withLightness(0.28).toColor();
    return (bg, fg);
  }
  // Dark mode: dim tint that reads on the dark card, brighter fg.
  final bg = hsl.withLightness(0.16).toColor();
  final fg = hsl.withLightness(0.72).toColor();
  return (bg, fg);
}
