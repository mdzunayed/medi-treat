import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/models/care_request_status.dart';
import '../../../core/models/doctor_stats.dart';
import '../../../core/models/nurse_profile.dart';
import '../../../core/models/patient_history_item.dart';
import '../../../core/models/provider_earnings.dart';
import '../../admin/admin_providers.dart';
import '../../auth/auth_provider.dart';
import '../../doctor/services/location_tracking_service.dart';
import '../../nurse/nurse_providers.dart';

/// Re-exported so the nurse hub's UI imports a single workflow file.
export '../../nurse/nurse_providers.dart' show nurseDashboardProvider;

/// State + actions controller for the Nurse Operations Hub. Mirrors the
/// doctor workflow controller but targets the nurse's procedural paradigm:
/// the Dispatches feed rides the shared [nurseDashboardProvider], while
/// Task History + Earnings get their own nurse-scoped surfaces here so the
/// nurse hub stays self-contained and its invalidation lifecycle never
/// tangles with the doctor's.

// ─── Earnings Tracker tab ────────────────────────────────────────────────────

/// Earnings + completed-session rollup for the signed-in nurse. The
/// `/doctor/:id/stats` aggregation already unions doctor + nurse
/// assignments, so the nurse session reads the same shape via their
/// account id.
final nurseStatsProvider =
    FutureProvider.autoDispose<DoctorStats>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return DoctorStats.empty;
  return ref.read(dioClientProvider).getDoctorStats(user.id);
});

// ─── Task History tab ────────────────────────────────────────────────────────

/// Completed/terminal nursing sessions this nurse has delivered, newest
/// first. The tab buckets them by service tier (care_type) client-side.
final nurseHistoryProvider =
    FutureProvider.autoDispose<List<PatientHistoryItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(dioClientProvider).getProviderHistory(user.id);
});

// ─── Profile tab ─────────────────────────────────────────────────────────────

/// The signed-in nurse's professional registry (BNMC reg, specialization,
/// experience, affiliation, bio). Backs the Profile tab's form.
final nurseProfileProvider =
    FutureProvider.autoDispose<NurseProfile>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return NurseProfile.empty;
  return ref.read(dioClientProvider).getNurseProfile(user.id);
});

// ─── Duty / availability ─────────────────────────────────────────────────────

/// Nurse on/off-duty flag. Mirrors `doctorAvailabilityProvider` but seeds
/// from the nurse profile's `availability_status` (instead of the doctor
/// dashboard) and flips through the session-resolved
/// `PATCH /api/provider/availability`, so the toggle no longer 400s for
/// lacking a provider id. Optimistic with rollback; starts/stops GPS so
/// coordinates flow only while ON duty.
final nurseAvailabilityProvider =
    AsyncNotifierProvider.autoDispose<NurseAvailabilityNotifier, bool>(
        NurseAvailabilityNotifier.new);

class NurseAvailabilityNotifier extends AutoDisposeAsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final profile = await ref.watch(nurseProfileProvider.future);
    if (profile.isOnline) {
      Future.microtask(() {
        ref.read(locationTrackingServiceProvider).start();
      });
    }
    return profile.isOnline;
  }

  Future<void> toggle() async {
    final current = state.valueOrNull ?? false;
    final next = !current;
    state = AsyncData(next);
    final tracker = ref.read(locationTrackingServiceProvider);
    try {
      await ref.read(dioClientProvider).setProviderAvailability(next);
      if (next) {
        await tracker.start();
      } else {
        await tracker.stop();
      }
    } catch (e, st) {
      // Roll back so the switch never lies about dispatch discoverability.
      state = AsyncData(current);
      state = AsyncError(e, st);
    }
  }
}

// ─── Earnings ledger (settled vs pending payouts) ────────────────────────────

/// Settled-vs-pending payout ledger for the signed-in nurse, backing the
/// itemized history on the Earnings tab. Fed by `GET /api/provider/earnings`.
final nurseEarningsProvider =
    FutureProvider.autoDispose<ProviderEarnings>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return ProviderEarnings.empty;
  return ref.read(dioClientProvider).getProviderEarnings();
});

// ─── Visit lifecycle actions ─────────────────────────────────────────────────

/// Single mutation surface for the nurse visit lifecycle. Centralises the
/// cross-role fan-out so the Dispatches card and the Nursing Console never
/// drift in which caches they refresh.
final nurseWorkflowProvider =
    Provider<NurseWorkflowController>((ref) => NurseWorkflowController(ref));

class NurseWorkflowController {
  NurseWorkflowController(this._ref);
  final Ref _ref;

  /// Transit pipeline step (assigned → enroute → arrived → in_service).
  Future<void> advance(String requestId, String nextStatus) async {
    await _ref.read(dioClientProvider).updateVisitStatus(requestId, nextStatus);
    _fanOut(completed: false);
  }

  /// Accept an incoming dispatch — shifts the visit straight to transit
  /// mode (`enroute`, "On the Way") via PATCH /api/appointments/:id/accept.
  Future<void> acceptDispatch(String requestId) async {
    await _ref.read(dioClientProvider).acceptDispatch(requestId);
    _fanOut(completed: false);
  }

  /// Decline an incoming dispatch — unassigns the nurse and clears the
  /// board via PATCH /api/appointments/:id/reject.
  Future<void> rejectDispatch(String requestId) async {
    await _ref.read(dioClientProvider).rejectDispatch(requestId);
    _fanOut(completed: false);
  }

  /// Mid-visit vitals save — visible to admin immediately, no status change.
  Future<void> saveVitals(
    String appointmentId, {
    String? bloodPressure,
    String? pulse,
    String? spo2,
    String? temperature,
  }) {
    return _ref.read(dioClientProvider).saveAppointmentVitals(
          appointmentId,
          bloodPressure: bloodPressure,
          pulse: pulse,
          spo2: spo2,
          temperature: temperature,
        );
  }

  /// Complete Care Session — posts the final vitals matrix + summary to
  /// `/api/appointments/:id/complete`, which flips the visit to completed
  /// and (server-side) locks the chat room. Then refresh every surface.
  Future<void> completeSession(
    String appointmentId, {
    String? bloodPressure,
    String? pulse,
    String? spo2,
    String? temperature,
    String? summary,
  }) async {
    await _ref.read(dioClientProvider).completeAppointment(
          appointmentId,
          bloodPressure: bloodPressure,
          pulse: pulse,
          spo2: spo2,
          temperature: temperature,
          summary: summary,
        );
    _fanOut(completed: true);
  }

  void _fanOut({required bool completed}) {
    _ref.invalidate(nurseDashboardProvider);
    _ref.invalidate(adminRequestsProvider);
    if (completed) {
      // Completion unlocks new earnings + adds a Task History row.
      _ref.invalidate(nurseStatsProvider);
      _ref.invalidate(nurseHistoryProvider);
    }
    // Patient's tracking card flips to the new status.
    // ignore: unused_result
    _ref.read(patientHomeFeedProvider.notifier).refresh();
  }
}

/// Convenience constants for the nurse transit pipeline, kept here so the
/// Dispatches card and console agree on the sequence.
class NurseTransit {
  NurseTransit._();
  static const String startTransit = CareRequestStatus.onTheWay;
  static const String arrived = CareRequestStatus.arrived;
  static const String inService = CareRequestStatus.inService;
}
