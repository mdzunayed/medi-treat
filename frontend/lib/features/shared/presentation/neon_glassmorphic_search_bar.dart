import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

// --- Local, self-contained palette (keeps this a truly shared widget with no
// dependency on any feature's theme). Deep-indigo / electric-violet, no orange.
const Color _kFill = Color(0x0AFFFFFF); // white @ ~4% over the frosted blur
const Color _kNeon = Color(0xFF7C3AED); // deep neon violet (~#673AB7 family)
const Color _kNeonBright = Color(0xFFB794F6); // electric lavender (focus/glow)
const Color _kIcon = Color(0xFFAAB2C5); // soft lavender-grey icons
const Color _kText = Color(0xFFF4F5FA); // crisp near-white input text
const Color _kHint = Color(0xFF8891A5); // muted hint

/// A premium dark-mode, frosted-glass search capsule with a continuously
/// "breathing" neon-violet glow that locks into a crisp bright stroke on focus.
///
/// Fully decoupled: it owns its breathing [AnimationController] and (optionally)
/// its own [TextEditingController], and reports input via [onChanged] /
/// [onSubmitted] so a parent can drive filtering without this widget importing
/// any feature-specific state.
class NeonGlassmorphicSearchBar extends StatefulWidget {
  /// Optional external controller; when omitted an internal one is created and
  /// disposed automatically.
  final TextEditingController? controller;

  /// Placeholder shown when the field is empty.
  final String hintText;

  /// Fired on every keystroke — wire this to your query state for live search.
  final ValueChanged<String>? onChanged;

  /// Fired when the user submits from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Optional trailing filter/settings button tap.
  final VoidCallback? onFilterTap;

  const NeonGlassmorphicSearchBar({
    super.key,
    this.controller,
    this.hintText = 'Search "Vaccination", "Physio", "Wound care"...',
    this.onChanged,
    this.onSubmitted,
    this.onFilterTap,
  });

  @override
  State<NeonGlassmorphicSearchBar> createState() =>
      _NeonGlassmorphicSearchBarState();
}

class _NeonGlassmorphicSearchBarState extends State<NeonGlassmorphicSearchBar>
    with SingleTickerProviderStateMixin {
  static const double _radius = 30;

  late final AnimationController _breathe;
  late final Animation<double> _pulse;
  final FocusNode _focusNode = FocusNode();
  TextEditingController? _internalController;
  bool _focused = false;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    // One controller + one tween: a single soft BoxShadow is modulated, so no
    // stacks of overlapping shadows and no per-frame allocation churn.
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _pulse = CurvedAnimation(parent: _breathe, curve: Curves.easeInOutSine);
    _breathe.addStatusListener(_loopBreath);
    _breathe.forward();

    _focusNode.addListener(_onFocusChange);
  }

  // Seamless ping-pong: completed -> reverse, dismissed -> forward.
  void _loopBreath(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _breathe.reverse();
    } else if (status == AnimationStatus.dismissed) {
      _breathe.forward();
    }
  }

  void _onFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused == _focused) return;
    setState(() => _focused = focused);
    // Freeze the breathing while focused (crisp static stroke); resume after.
    if (focused) {
      _breathe.stop();
    } else if (!_breathe.isAnimating) {
      _breathe.forward();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _breathe.removeStatusListener(_loopBreath);
    _breathe.dispose();
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The interior (icon + field + filter) is built once and passed as the
    // AnimatedBuilder `child`, so only the decoration repaints each frame.
    final interior = Row(
      children: [
        const Icon(Icons.search_rounded, color: _kIcon, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            textInputAction: TextInputAction.search,
            cursorColor: _kNeonBright,
            style: const TextStyle(
              color: _kText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.hintText,
              hintStyle: const TextStyle(
                color: _kHint,
                fontSize: 13,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _FilterButton(onTap: widget.onFilterTap),
      ],
    );

    return AnimatedScale(
      // Sharp-but-smooth micro-interaction on focus.
      scale: _focused ? 1.015 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _focused ? 1.0 : _pulse.value;
          final glowOpacity = _focused ? 0.55 : (0.16 + 0.20 * t);
          final glowBlur = _focused ? 20.0 : (10.0 + 8.0 * t);
          final borderColor = _focused
              ? _kNeonBright
              : Color.lerp(
                  _kNeon.withValues(alpha: 0.35),
                  _kNeonBright.withValues(alpha: 0.70),
                  t,
                )!;

          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: _kNeon.withValues(alpha: glowOpacity),
                  blurRadius: glowBlur,
                  spreadRadius: _focused ? 1.0 : 0.5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _kFill,
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(
                      color: borderColor,
                      width: _focused ? 1.6 : 1.0,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: interior,
      ),
    );
  }
}

/// Trailing circular filter/settings affordance, tinted electric lavender.
class _FilterButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _FilterButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kNeon.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.tune_rounded, color: _kNeonBright, size: 19),
        ),
      ),
    );
  }
}
