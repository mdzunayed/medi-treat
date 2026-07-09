import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index ↔ label canonical mapping for the bottom nav. Exposed as
/// constants so the wrapper file's `BottomNavigationBar.items` order
/// and the deep-link helpers below can never drift out of sync.
class PatientNavIndex {
  PatientNavIndex._();

  static const int home = 0;
  static const int newRequest = 1;
  static const int activities = 2;
  static const int account = 3;

  /// Clamp incoming values so a stale int from a future build (or a
  /// bad write) can never push the IndexedStack out of bounds.
  static int clamp(int i) {
    if (i < 0) return 0;
    if (i > 3) return 3;
    return i;
  }
}

/// Sub-tabs inside the Activities surface (Index 2). Kept as an enum
/// for clarity at the call sites — the names are load-bearing.
enum PatientActivitiesTab {
  /// Still pending admin approval — old "Under Review".
  underReview,

  /// Live tracking + on-the-way map.
  tracking,

  /// Completed visits + ratings (old "Rating" tab).
  history,

  /// Active prescriptions + daily Mark-as-Taken adherence timeline.
  medications,
}

extension PatientActivitiesTabX on PatientActivitiesTab {
  int get index {
    switch (this) {
      case PatientActivitiesTab.underReview:
        return 0;
      case PatientActivitiesTab.tracking:
        return 1;
      case PatientActivitiesTab.history:
        return 2;
      case PatientActivitiesTab.medications:
        return 3;
    }
  }
}

/// Bottom-nav state controller. Exposes the active index as an `int`
/// (canonical for `BottomNavigationBar.currentIndex`) so the shell can
/// drop the value straight into the widget without an enum conversion.
class PatientNavController extends Notifier<int> {
  @override
  int build() => PatientNavIndex.home;

  /// Single mutation entry point — guards the clamp and the no-op
  /// short-circuit so widgets can call this freely on every tap
  /// without triggering an extra rebuild for an unchanged index.
  void changeTab(int index) {
    final next = PatientNavIndex.clamp(index);
    if (state != next) {
      HapticFeedback.lightImpact();
      state = next;
    }
  }
}

/// Inner Activities sub-tab state.
class PatientActivitiesController extends Notifier<PatientActivitiesTab> {
  @override
  PatientActivitiesTab build() => PatientActivitiesTab.underReview;

  void setTab(PatientActivitiesTab tab) {
    if (state != tab) {
      HapticFeedback.lightImpact();
      state = tab;
    }
  }
}

/// Source of truth for the bottom-nav active index. Watched by the
/// shell ([PatientMainNavigationWrapper]) and written by every
/// deep-link helper below via `.notifier.changeTab(...)`.
final patientNavProvider =
    NotifierProvider<PatientNavController, int>(PatientNavController.new);

final patientActivitiesTabProvider =
    NotifierProvider<PatientActivitiesController, PatientActivitiesTab>(
  PatientActivitiesController.new,
);

/// One-stop deep-link helper. Lets unrelated widgets (the orange "Start
/// new request" banner on Home, a notification card, the tracking
/// screen's back button) hop into the right bottom-nav destination —
/// AND, when relevant, into the right Activities sub-tab — through a
/// single call site, without each one having to coordinate two
/// providers manually.
extension PatientShellNavExt on WidgetRef {
  void goToHome() =>
      read(patientNavProvider.notifier).changeTab(PatientNavIndex.home);

  void goToNewRequest() =>
      read(patientNavProvider.notifier).changeTab(PatientNavIndex.newRequest);

  void goToAccount() =>
      read(patientNavProvider.notifier).changeTab(PatientNavIndex.account);

  /// Jumps into Activities, optionally pre-selecting the sub-tab.
  /// Defaults to "Under Review" — same landing the old chip nav had.
  void goToActivities({
    PatientActivitiesTab sub = PatientActivitiesTab.underReview,
  }) {
    read(patientActivitiesTabProvider.notifier).setTab(sub);
    read(patientNavProvider.notifier).changeTab(PatientNavIndex.activities);
  }
}
