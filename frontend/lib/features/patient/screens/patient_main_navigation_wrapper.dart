import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/mt_colors.dart';
import '../navigation/patient_nav_provider.dart';
import 'new_request_tab.dart';
import 'patient_account_screen.dart';
import 'patient_activities_screen.dart';
import 'patient_home_screen.dart';
import 'widgets/fluid_nav_bar.dart';
import 'widgets/patient_home_palette.dart';

/// Root navigation shell for the patient app. The router mounts this
/// widget at `/patient/:name`; it owns the [Scaffold], the
/// [IndexedStack] body, and the [BottomNavigationBar].
///
/// Critical layout rules baked in:
///
/// 1. `IndexedStack` is the `body` — every tab destination is mounted
///    once, so jumping between Home and Activities preserves scroll
///    state and avoids re-fetching the API.
/// 2. The [BottomNavigationBar] is wired into the Scaffold's real
///    `bottomNavigationBar` slot (NOT inside the body), so the
///    framework anchors it at the absolute bottom edge of the
///    viewport — no floating, no centring inside the body column.
/// 3. The bar itself is wrapped in `SafeArea → Center → maxWidth: 600`
///    so on desktop / web the bar stays a sensible pill width while
///    its background colour still extends edge-to-edge. Mobile
///    sizes are unaffected (the Center collapses around the bar).
///
/// State lives in [patientNavProvider] (a `Notifier<int>`) so deep
/// link helpers across the app — the orange "Start new request"
/// banner, notification cards, the tracking screen's back button —
/// can flip destinations atomically without touching this widget.
class PatientMainNavigationWrapper extends ConsumerWidget {
  const PatientMainNavigationWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(patientNavProvider);

    return Scaffold(
      backgroundColor: MtColors.bg,
      // 1. Maintain screen state and render the actual complete sub-screens.
      body: IndexedStack(
        index: currentIndex,
        children: const [
          PatientHomeScreen(),       // Index 0: Restored complete dashboard view
          NewRequestTab(),           // Index 1: Intake workflow view
          PatientActivitiesScreen(), // Index 2: Consolidated Activities (tabs)
          PatientAccountScreen(),    // Index 3: Profile / account settings
        ],
      ),
      // 2. Custom fluid notched tray with the floating orange pill. It
      //    sits in the real `bottomNavigationBar` slot (not the body), so
      //    it anchors to the absolute bottom edge and every tab's own
      //    layout — including the New Request screen's bottom submit bar —
      //    stays intact. The transparent band above the painted bar (where
      //    the pill rides) shows the cream Scaffold canvas, matching the
      //    design language. Width is capped on wide viewports.
      // A deep-canvas backdrop fills the whole bottom region (the nav bar's
      // transparent top inset + the bottom safe-area inset) so the dark tray
      // meets the dark Home body seamlessly — no light Scaffold line showing
      // through. Scoped here rather than on `Scaffold.backgroundColor`, which
      // would darken the still-light New Request tab (it has no Scaffold).
      bottomNavigationBar: ColoredBox(
        color: HomeDark.canvas,
        child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double cap = 600;
            final double sidePad = constraints.maxWidth > cap
                ? (constraints.maxWidth - cap) / 2
                : 0;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: sidePad),
              // Only the three primary destinations live in the tray. The
              // Account destination is still mounted in the [IndexedStack]
              // (index 3) and is reached from the Home header avatar via
              // `ref.goToAccount()` — so its lifecycle is identical, it just
              // no longer occupies a bottom-nav slot. The bar renders with no
              // active pill while the account screen is showing.
              child: FluidNavBar(
                currentIndex: currentIndex,
                onTap: (index) =>
                    ref.read(patientNavProvider.notifier).changeTab(index),
                items: const [
                  FluidNavItem(icon: Icons.home_rounded, label: 'Home'),
                  FluidNavItem(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'New Request',
                  ),
                  FluidNavItem(
                    icon: Icons.analytics_outlined,
                    label: 'Activities',
                  ),
                ],
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}
