import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medi_treat/features/patient/screens/widgets/fluid_nav_bar.dart';

/// Regression tests for the trimmed 3-tab [FluidNavBar]. These cover the two
/// behaviours the home/shell redesign depends on:
///   1. The tray renders exactly the three primary destinations (Account was
///      moved to the header avatar).
///   2. It survives a `currentIndex` that points *past* the visible items —
///      i.e. the Account screen (IndexedStack index 3) is showing while the
///      tray only has 3 slots. Before the fix this threw a RangeError.
void main() {
  const items = [
    FluidNavItem(icon: Icons.home_rounded, label: 'Home'),
    FluidNavItem(icon: Icons.add_circle_outline_rounded, label: 'New Request'),
    FluidNavItem(icon: Icons.analytics_outlined, label: 'Activities'),
  ];

  Widget harness({required int currentIndex, required ValueChanged<int> onTap}) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: FluidNavBar(
          currentIndex: currentIndex,
          onTap: onTap,
          items: items,
        ),
      ),
    );
  }

  testWidgets('renders exactly the three primary tabs, no Account', (
    tester,
  ) async {
    await tester.pumpWidget(harness(currentIndex: 0, onTap: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('New Request'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Account'), findsNothing);
  });

  testWidgets('tapping a tab reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      harness(currentIndex: 0, onTap: (i) => tapped = i),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activities'));
    expect(tapped, 2);

    await tester.tap(find.text('New Request'));
    expect(tapped, 1);
  });

  testWidgets(
    'currentIndex past the visible items (Account open) does not throw',
    (tester) async {
      // Index 3 = the Account destination, which has no bottom-nav slot.
      await tester.pumpWidget(harness(currentIndex: 3, onTap: (_) {}));
      await tester.pumpAndSettle();

      // Built cleanly (no RangeError) and no tab is marked active.
      expect(tester.takeException(), isNull);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Activities'), findsOneWidget);
    },
  );
}
