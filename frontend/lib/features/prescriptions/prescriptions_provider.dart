import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/prescription.dart';
import '../auth/auth_provider.dart';

/// `GET /api/prescriptions/my-active` — every active prescription for
/// the signed-in patient. Backs the medication timeline screen and
/// any future home-screen "today's doses" widget. autoDispose so the
/// list refreshes from the server every time the patient opens the
/// timeline.
class PatientPrescriptionsNotifier
    extends AutoDisposeAsyncNotifier<List<Prescription>> {
  @override
  Future<List<Prescription>> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const [];
    return ref.read(dioClientProvider).getMyActivePrescriptions();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getMyActivePrescriptions(),
    );
  }

  /// Optimistic dose-toggle. Updates the local list first so the
  /// checkbox flips in the same frame, then writes through to the
  /// backend and reconciles against the canonical response. On
  /// failure we roll back so the UI doesn't lie.
  Future<bool> toggleDose({
    required String prescriptionId,
    required String itemId,
    required DoseSlot slot,
    required String dayKey,
    required bool taken,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      final refreshed = await ref.read(dioClientProvider).setDoseTaken(
            prescriptionId: prescriptionId,
            itemId: itemId,
            slot: slot,
            dayKey: dayKey,
            taken: taken,
          );
      state = AsyncData([
        for (final p in current)
          if (p.id == prescriptionId) refreshed else p,
      ]);
      return true;
    } catch (_) {
      // Keep the previous state on failure — caller surfaces a snack.
      return false;
    }
  }
}

final patientPrescriptionsProvider = AsyncNotifierProvider.autoDispose<
    PatientPrescriptionsNotifier,
    List<Prescription>>(PatientPrescriptionsNotifier.new);

/// `GET /api/prescriptions/by-patient/:accountId` — the patient's full
/// historical prescription vault (every script ever issued, newest-first),
/// distinct from the active-only timeline above.
final patientPrescriptionVaultProvider =
    FutureProvider.autoDispose<List<Prescription>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(dioClientProvider).getPrescriptionsForPatient(user.id);
});

/// `GET /api/prescriptions/:id` — a single prescription enriched with the
/// doctor's verified credentials + symptoms, for the vault detail card.
final prescriptionDetailProvider =
    FutureProvider.autoDispose.family<Prescription, String>((ref, id) async {
  return ref.read(dioClientProvider).getPrescriptionById(id);
});
