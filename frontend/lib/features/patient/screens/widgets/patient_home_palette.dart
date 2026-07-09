import 'package:flutter/material.dart';

/// Screen-scoped **dark midnight / violet** palette for the patient Home
/// surface and its shared fluid nav bar. Kept separate from the global
/// [MtColors] (which is a light, orange-branded system) so the dark retheme
/// stays contained to the patient dashboard + tray and never bleeds into the
/// doctor / nurse / admin shells or the other patient tabs.
///
/// Both [PatientHomeScreen] and the `FluidNavBar` import these tokens so their
/// violets and dark surfaces can never drift apart.
class HomeDark {
  HomeDark._();

  /// Deep near-black canvas that sits behind the whole scroll body.
  static const Color canvas = Color(0xFF0D151C);

  /// Card surface + a slightly raised variant for nested chrome (avatars,
  /// inner chips, the peach-band replacement, etc.).
  static const Color surface = Color(0xFF161C28);
  static const Color surfaceHi = Color(0xFF1E2536);

  /// Core violet accent + its bright (neon) and deep (gradient-end) siblings.
  /// [violet2] is a lighter, glossier top used for the vivid card gradients
  /// (promo slides, hero, service headers) so they pop like the mockups.
  static const Color violet = Color(0xFF7C3AED);
  static const Color violet2 = Color(0xFF8B5CF6);
  static const Color violetBright = Color(0xFFA78BFA);
  static const Color violetDeep = Color(0xFF4C1D95);

  /// Indigo used for the "ON THE WAY" live capsule so it reads distinct from
  /// the violet brand accents.
  static const Color indigo = Color(0xFF6366F1);

  /// Emerald-teal accent — used for the service-card "+" quick-add button so
  /// it pops against the violet/obsidian card.
  static const Color teal = Color(0xFF2DD4BF);

  /// Hairline border for cards / chips, plus a translucent violet "glow" for
  /// neon outlines and the provider avatar rings.
  static const Color border = Color(0xFF283040);
  static Color glow = const Color(0xFF7C3AED).withValues(alpha: 0.28);

  /// Typography: crisp white titles, lavender-grey body/subtitles, dim muted
  /// captions.
  static const Color title = Color(0xFFF4F5FA);
  static const Color body = Color(0xFFAAB2C5);
  static const Color muted = Color(0xFF6B7488);

  /// Status tints tuned for the dark canvas (used by the ongoing-care pill).
  static const Color positive = Color(0xFF34D399);
  static const Color positiveBg = Color(0xFF10291F);
  static const Color danger = Color(0xFFF87171);
  static const Color dangerBg = Color(0xFF2A1416);
}
