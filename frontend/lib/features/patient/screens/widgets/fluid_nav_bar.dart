import 'package:flutter/material.dart';

import '../../../../core/theme/mt_text_styles.dart';
import 'patient_home_palette.dart';

/// Core patient-shell accent — the neon violet used for the floating active
/// pill in the dark midnight tray. Scoped to this file (patient role only) so
/// it never bleeds into the doctor / nurse / admin shells.
const Color kPatientAccent = HomeDark.violet;

/// One navigation destination — icon + label. Kept as a tiny value type so
/// [FluidNavBar] can lay the row out generically without hard-coding four
/// items.
@immutable
class FluidNavItem {
  final IconData icon;
  final String label;
  const FluidNavItem({required this.icon, required this.label});
}

/// A custom, fully hand-painted bottom navigation tray.
///
/// Visual anatomy (bottom-up):
///   • A crisp white bar with rounded top corners.
///   • A smooth, concave cubic-Bézier "wave" notch carved into the top
///     lip directly beneath the active destination.
///   • A circular, elevated **orange pill** seated in that notch — its
///     lower half inside the bar, upper half lifted above the top lip
///     ("bisecting the upper curved lip"). The pill — and the notch it
///     sits in — glide horizontally to the tapped index via a single
///     [AnimationController], so the geometry and the pill never desync.
///   • Inactive destinations render as slate icon + label stacks.
///
/// The widget reports its own intrinsic height back to the Scaffold, so it
/// drops straight into the `bottomNavigationBar` slot with no `extendBody`
/// gymnastics — every other tab's layout (including the New Request submit
/// bar) is left untouched.
class FluidNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FluidNavItem> items;

  const FluidNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  /// Height of the painted white bar (the active bubble nests INSIDE this
  /// band — it no longer breaks out above the top lip).
  static const double barHeight = 80;

  /// A small transparent headroom above the painted bar, just enough for the
  /// drop shadow + rounded top corners to render cleanly. The bubble does NOT
  /// live up here — it sits down inside the bar.
  static const double topInset = 8;

  /// Diameter of the active bubble. Sized so it seats fully within the bar's
  /// vertical band with comfortable margin on both edges.
  static const double pillDiameter = 48;

  /// Y of the bubble's top edge, measured from the top of the widget. Places
  /// the bubble nested in the notch dip, wholly inside the bar bounds
  /// (`topInset .. topInset + barHeight`).
  static const double pillTop = topInset + 8;

  /// Total widget height. No pill overshoot to account for any more, so this
  /// is simply the headroom + the bar.
  static const double totalHeight = topInset + barHeight;

  @override
  State<FluidNavBar> createState() => _FluidNavBarState();
}

class _FluidNavBarState extends State<FluidNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _slide;

  /// Clamp the incoming index into the *visible* slot range so the notch +
  /// pill always target a real tab. When [FluidNavBar.currentIndex] points at
  /// a destination that isn't in the tray (e.g. the Account screen, which is
  /// mounted in the shell's IndexedStack but has no bottom-nav slot), the
  /// index can exceed `items.length - 1`; this keeps the geometry in bounds
  /// while [_hasActiveVisible] hides the pill for that case.
  double get _targetFrac {
    final maxIndex = (widget.items.length - 1).toDouble();
    return widget.currentIndex.toDouble().clamp(0.0, maxIndex);
  }

  /// Whether the active destination is one of the visible tray slots. False
  /// while an off-tray destination (Account) is showing — the tray then
  /// renders with every slot inactive and no floating pill.
  bool get _hasActiveVisible =>
      widget.currentIndex >= 0 && widget.currentIndex < widget.items.length;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    // The animated value is a *fractional index* — it interpolates between
    // integer tab positions so the notch + pill sweep smoothly rather than
    // jumping. Seed it at the initial index with no animation.
    _slide = AlwaysStoppedAnimation(_targetFrac);
  }

  @override
  void didUpdateWidget(covariant FluidNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _slide = Tween<double>(
        begin: _slide.value,
        end: _targetFrac,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;

    return SizedBox(
      height: FluidNavBar.totalHeight,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final frac = _slide.value; // 0..count-1, fractional during slide
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final slot = width / count;
              final rawCenterX = slot * (frac + 0.5);
              // Keep the notch mouth (and the rounded top corners) inside the
              // bar even when an edge tab is active on a narrow screen. The
              // pill and the notch share this ONE clamped value so they can
              // never drift apart; the clamp only nudges by a few px at the
              // extremes, which reads as the pill sitting snug to the corner.
              final double margin =
                  _FluidBarPainter.notchHalfWidth + _FluidBarPainter.corner;
              final centerX = rawCenterX.clamp(margin, width - margin);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. The painted bar + notch. The painted body starts a
                  //    small `topInset` down from the widget top, leaving just
                  //    enough headroom for the shadow + rounded corners.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FluidBarPainter(
                        notchCenterX: centerX,
                        topInset: FluidNavBar.topInset,
                        // Flatten the lip while no visible tab is active
                        // (Account is open) so there's no empty dip without a
                        // pill sitting in it.
                        drawNotch: _hasActiveVisible,
                      ),
                    ),
                  ),

                  // 2. The active bubble — nested INSIDE the bar, seated in
                  //    the notch dip. Shares the notch centre so the two never
                  //    desync as they slide. Only drawn when the active
                  //    destination is one of the visible tray slots; while an
                  //    off-tray screen (Account) is showing, the pill is
                  //    omitted and the tray reads as fully inactive.
                  if (_hasActiveVisible)
                    Positioned(
                      left: centerX - FluidNavBar.pillDiameter / 2,
                      top: FluidNavBar.pillTop,
                      child: _ActivePill(
                        icon: widget.items[widget.currentIndex].icon,
                      ),
                    ),

                  // 3. Tap targets + inactive icon/label stacks. The active
                  //    slot renders only its label (the icon lives in the
                  //    pill above it).
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: FluidNavBar.barHeight,
                    child: Row(
                      children: [
                        for (int i = 0; i < count; i++)
                          Expanded(
                            child: _NavSlot(
                              item: widget.items[i],
                              active: i == widget.currentIndex,
                              onTap: () => widget.onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// The elevated circular active pill.
class _ActivePill extends StatelessWidget {
  final IconData icon;
  const _ActivePill({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: FluidNavBar.pillDiameter,
      height: FluidNavBar.pillDiameter,
      decoration: BoxDecoration(
        color: kPatientAccent,
        shape: BoxShape.circle,
        border: Border.all(color: HomeDark.surface, width: 4),
        boxShadow: [
          BoxShadow(
            color: kPatientAccent.withValues(alpha: 0.55),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

/// A single tappable slot. Inactive slots show icon + label; the active
/// slot shows only its label (its icon is rendered inside the pill).
class _NavSlot extends StatelessWidget {
  final FluidNavItem item;
  final bool active;
  final VoidCallback onTap;

  const _NavSlot({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        // Nudge the icon + label cluster a touch lower inside the tray so
        // they sit with even breathing room below the curved top lip rather
        // than crowding it.
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          // Reserve the icon's vertical space on the active slot so the
          // label sits at the same baseline as its neighbours.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: active ? 0 : 1,
            child: Icon(
              item.icon,
              size: 24,
              color: active ? HomeDark.violetBright : HomeDark.body,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.labelSm.copyWith(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? HomeDark.violetBright : HomeDark.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the white tray with a smooth concave notch under [notchCenterX].
///
/// The path is a single continuous outline:
///   top-left rounded corner → top lip up to the notch → a symmetric pair
///   of cubic Béziers diving down and back up (the wave) → remaining top
///   lip → top-right rounded corner → down/around the solid body → close.
class _FluidBarPainter extends CustomPainter {
  /// Horizontal centre of the notch (and the pill above it). Pre-clamped by
  /// the caller so it always shares the pill's centre.
  final double notchCenterX;

  /// Transparent band above the bar (where the pill floats). The painted
  /// body starts at `topInset` from the top of the canvas.
  final double topInset;

  /// When false the top lip is drawn perfectly flat (no notch) — used while
  /// no visible tab is active so there's never an empty dip.
  final bool drawNotch;

  _FluidBarPainter({
    required this.notchCenterX,
    required this.topInset,
    this.drawNotch = true,
  });

  /// Rounded top-corner radius of the tray.
  static const double corner = 22;

  /// Half the notch mouth width along the top lip. Slightly narrower than
  /// the pill so the pill overhangs the dip for a snug seated look.
  static const double notchHalfWidth = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final top = topInset; // y of the bar's top lip
    final w = size.width;
    final h = size.height;

    // Notch geometry. `depth` is how far the wave dips below the lip.
    const half = notchHalfWidth;
    const depth = 30.0;
    final cx = notchCenterX;
    final left = cx - half;
    final right = cx + half;

    final path = Path()
      ..moveTo(0, top + corner)
      ..quadraticBezierTo(0, top, corner, top);
    if (drawNotch) {
      path
        ..lineTo(left, top)
        // Down-slope into the notch. Control points pulled inward + downward
        // give the smooth sweeping wave rather than a sharp 'V'.
        ..cubicTo(
          left + half * 0.45, top,
          cx - half * 0.55, top + depth,
          cx, top + depth,
        )
        // Up-slope back to the lip, mirror image of the down-slope.
        ..cubicTo(
          cx + half * 0.55, top + depth,
          right - half * 0.45, top,
          right, top,
        );
    }
    path
      ..lineTo(w - corner, top)
      ..quadraticBezierTo(w, top, w, top + corner)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    // Soft top shadow so the dark bar still reads as a raised surface lifted
    // above the content behind it.
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.55), 14, false);
    canvas.drawPath(path, Paint()..color = HomeDark.surface);
  }

  @override
  bool shouldRepaint(covariant _FluidBarPainter old) =>
      old.notchCenterX != notchCenterX ||
      old.topInset != topInset ||
      old.drawNotch != drawNotch;
}
