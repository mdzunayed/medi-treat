import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/care_request_status.dart';
import '../../../core/models/doctor_dashboard.dart';
import '../../../core/models/doctor_stats.dart';
import '../../../core/models/patient_history_item.dart';
import '../../../core/models/provider_earnings.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/shimmer_loading_placeholder.dart';
import '../../doctor/doctor_providers.dart';
import '../providers/nurse_workflow_provider.dart';
import 'active_nurse_console_screen.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 · Dispatches — active callouts + the procedural transit pipeline
// ═══════════════════════════════════════════════════════════════════════════

class DispatchesTab extends ConsumerWidget {
  const DispatchesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nurseDashboardProvider);
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () async => ref.invalidate(nurseDashboardProvider),
      child: async.when(
        // Skeleton dispatch cards hold the job-log layout steady while the
        // board fetches, replacing the centred spinner.
        loading: () => const ShimmerCareCardList(),
        error: (e, _) => _TabError(
          message: e.toString(),
          onRetry: () => ref.invalidate(nurseDashboardProvider),
        ),
        data: (dashboard) {
          // Incoming = freshly assigned (needs Accept/Decline).
          // Active = already accepted and in transit / on-site.
          final incoming = dashboard.upcomingToday
              .where((a) => a.awaitingAcceptance)
              .toList();
          final active =
              dashboard.upcomingToday.where((a) => a.isActive).toList();
          final hasPending = dashboard.pendingAssignment != null;

          if (!hasPending && incoming.isEmpty && active.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: const [_NoDispatchesState()],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (dashboard.pendingAssignment case final pending?) ...[
                _OfferCard(assignment: pending),
                const SizedBox(height: 16),
              ],
              if (incoming.isNotEmpty) ...[
                Text('INCOMING DISPATCH',
                    style: MtTextStyles.sectionLabel
                        .copyWith(color: MtColors.brand, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                for (final appt in incoming) ...[
                  _IncomingDispatchCard(appt: appt),
                  const SizedBox(height: 12),
                ],
              ],
              if (active.isNotEmpty) ...[
                if (incoming.isNotEmpty) const SizedBox(height: 8),
                Text('ACTIVE DISPATCHES',
                    style: MtTextStyles.sectionLabel
                        .copyWith(color: MtColors.ink3, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                for (final appt in active) ...[
                  _DispatchCard(appt: appt),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OfferCard extends ConsumerStatefulWidget {
  final PendingAssignment assignment;
  const _OfferCard({required this.assignment});

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _acceptBusy = false;
  bool _declineBusy = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.assignment.remainingFrom(DateTime.now());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final r = widget.assignment.remainingFrom(DateTime.now());
      setState(() => _remaining = r);
      if (r == Duration.zero) {
        _ticker?.cancel();
        ref.invalidate(nurseDashboardProvider);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _countdown {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ));
  }

  Future<void> _accept() async {
    if (_acceptBusy || _declineBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _acceptBusy = true);
    try {
      await ref.read(acceptAssignmentProvider(widget.assignment.id).future);
      _toast('Dispatch accepted');
    } catch (e) {
      HapticFeedback.vibrate();
      _toast('Could not accept: $e', error: true);
    } finally {
      // Re-sync the board on BOTH outcomes. On success the card moves to
      // "active"; on a 409 conflict (someone else won the atomic claim)
      // this clears the now-unavailable card instead of leaving a stale
      // tap target behind.
      ref.invalidate(nurseDashboardProvider);
      if (mounted) setState(() => _acceptBusy = false);
    }
  }

  Future<void> _decline() async {
    if (_acceptBusy || _declineBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _declineBusy = true);
    try {
      await ref.read(declineAssignmentProvider(widget.assignment.id).future);
      ref.invalidate(nurseDashboardProvider);
      _toast('Dispatch declined');
    } catch (e) {
      HapticFeedback.vibrate();
      _toast('Could not decline: $e', error: true);
    } finally {
      if (mounted) setState(() => _declineBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final canTap = !_acceptBusy && !_declineBusy;
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.brand, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: MtColors.brand,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.5),
                topRight: Radius.circular(12.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_hospital, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('NEW DISPATCH',
                    style: MtTextStyles.labelMd
                        .copyWith(color: Colors.white, letterSpacing: 0.8)),
                const Spacer(),
                Text('Expires in $_countdown',
                    style: MtTextStyles.labelMd.copyWith(color: Colors.white)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(a.serviceNameEn,
                          style:
                              MtTextStyles.h3.copyWith(color: MtColors.ink)),
                    ),
                    Text(_money(a.fee),
                        style: MtTextStyles.h2.copyWith(color: MtColors.brand)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  a.patientAgeSex.isEmpty
                      ? a.patientName
                      : '${a.patientName}, ${a.patientAgeSex}',
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
                if (a.address.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LocationRow(address: a.address),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: canTap ? _decline : null,
                          icon: _declineBusy
                              ? const _MiniSpinner()
                              : const Icon(Icons.close, size: 18),
                          label:
                              Text('Decline', style: MtTextStyles.labelLg),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MtColors.ink,
                            side: const BorderSide(color: MtColors.line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: canTap ? _accept : null,
                          icon: _acceptBusy
                              ? const _MiniSpinner(light: true)
                              : const Icon(Icons.check, size: 18),
                          label: Text('Accept dispatch',
                              style: MtTextStyles.labelLg
                                  .copyWith(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MtColors.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Active dispatch tracker — the Phase 2 procedural transit pipeline.
class _DispatchCard extends ConsumerStatefulWidget {
  final UpcomingAppointment appt;
  const _DispatchCard({required this.appt});

  @override
  ConsumerState<_DispatchCard> createState() => _DispatchCardState();
}

class _DispatchCardState extends ConsumerState<_DispatchCard> {
  bool _busy = false;

  UpcomingAppointment get _appt => widget.appt;

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ));
  }

  Future<void> _runStage(_Stage stage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final workflow = ref.read(nurseWorkflowProvider);
      switch (stage.kind) {
        case _StageKind.confirmArrival:
          await workflow.advance(_appt.id, NurseTransit.arrived);
          _toast('Arrival confirmed.');
        case _StageKind.openTerminal:
          if (_appt.status != CareRequestStatus.inService) {
            await workflow.advance(_appt.id, NurseTransit.inService);
          }
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ActiveNurseConsoleScreen(appointment: _appt),
            ),
          );
      }
    } catch (e) {
      _toast('Could not update status: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = _Stage.forStatus(_appt.status);
    final distance = _appt.distanceKm != null
        ? '${(_appt.distanceKm ?? 0).toStringAsFixed(1)} km away'
        : '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: _appt.patientName,
                size: 48,
                backgroundColor: const Color(0xFFDBEAFE),
                textColor: const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_appt.patientName,
                        style: MtTextStyles.labelLg.copyWith(
                            color: MtColors.ink,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_appt.serviceName,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink2)),
                  ],
                ),
              ),
              _StatusChip(status: _appt.status),
            ],
          ),
          if (_appt.address != null && _appt.address!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _LocationRow(address: _appt.address!),
          ],
          if (distance.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.near_me_outlined,
                    size: 14, color: MtColors.ink3),
                const SizedBox(width: 6),
                Text(distance,
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _runStage(stage),
              icon: _busy
                  ? const _MiniSpinner(light: true)
                  : Icon(stage.icon, size: 20),
              label: Text(stage.label,
                  style: MtTextStyles.labelLg.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: stage.kind == _StageKind.openTerminal
                    ? MtColors.completed
                    : MtColors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StageKind { confirmArrival, openTerminal }

class _Stage {
  final _StageKind kind;
  final String label;
  final IconData icon;
  const _Stage(this.kind, this.label, this.icon);

  static _Stage forStatus(String status) {
    switch (status) {
      case CareRequestStatus.arrived:
      case CareRequestStatus.inService:
        return const _Stage(_StageKind.openTerminal,
            '🩺  OPEN NURSING PROCEDURAL TERMINAL',
            Icons.medical_services_outlined);
      // enroute / on-the-way (and any active fallback) → confirm arrival.
      default:
        return const _Stage(_StageKind.confirmArrival,
            '📍  CONFIRM ARRIVAL AT RESIDENCE', Icons.location_on);
    }
  }
}

/// Phase 1 — the interactive incoming callout. Shown for a freshly
/// `assigned` dispatch: patient, procedure, address, guaranteed payout,
/// and the Accept / Decline action engine.
class _IncomingDispatchCard extends ConsumerStatefulWidget {
  final UpcomingAppointment appt;
  const _IncomingDispatchCard({required this.appt});

  @override
  ConsumerState<_IncomingDispatchCard> createState() =>
      _IncomingDispatchCardState();
}

class _IncomingDispatchCardState
    extends ConsumerState<_IncomingDispatchCard> {
  bool _accepting = false;
  bool _declining = false;

  UpcomingAppointment get _appt => widget.appt;

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ));
  }

  Future<void> _accept() async {
    if (_accepting || _declining) return;
    setState(() => _accepting = true);
    try {
      await ref.read(nurseWorkflowProvider).acceptDispatch(_appt.id);
      _toast('Dispatch accepted — you are on the way.');
    } catch (e) {
      _toast('Could not accept: $e', error: true);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _decline() async {
    if (_accepting || _declining) return;
    setState(() => _declining = true);
    try {
      await ref.read(nurseWorkflowProvider).rejectDispatch(_appt.id);
      _toast('Dispatch declined.');
    } catch (e) {
      _toast('Could not decline: $e', error: true);
    } finally {
      if (mounted) setState(() => _declining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canTap = !_accepting && !_declining;
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.brand, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: MtColors.brand.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header strip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: MtColors.brand,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14.5),
                topRight: Radius.circular(14.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('NEW VISIT ASSIGNED',
                    style: MtTextStyles.labelMd
                        .copyWith(color: Colors.white, letterSpacing: 0.8)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_money(_appt.fee),
                      style: MtTextStyles.labelMd
                          .copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InitialsAvatar(
                      name: _appt.patientName,
                      size: 48,
                      backgroundColor: const Color(0xFFDBEAFE),
                      textColor: const Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_appt.patientName,
                              style: MtTextStyles.h3
                                  .copyWith(color: MtColors.ink)),
                          const SizedBox(height: 2),
                          Text(_appt.serviceName,
                              style: MtTextStyles.bodySm
                                  .copyWith(color: MtColors.ink2)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_appt.address != null && _appt.address!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _LocationRow(address: _appt.address!),
                ],
                const SizedBox(height: 8),
                _PayoutRow(fee: _appt.fee),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: canTap ? _decline : null,
                          icon: _declining
                              ? const _MiniSpinner()
                              : const Icon(Icons.close, size: 18),
                          label: Text('Decline',
                              style: MtTextStyles.labelLg
                                  .copyWith(color: MtColors.rejected)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MtColors.rejected,
                            side: const BorderSide(color: MtColors.line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: canTap ? _accept : null,
                          icon: _accepting
                              ? const _MiniSpinner(light: true)
                              : const Icon(Icons.rocket_launch, size: 18),
                          label: Text('Accept Dispatch',
                              style: MtTextStyles.labelLg.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MtColors.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  final num fee;
  const _PayoutRow({required this.fee});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: MtColors.brand, size: 18),
          const SizedBox(width: 8),
          Text('Guaranteed payout',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
          const Spacer(),
          Text(_money(fee),
              style: MtTextStyles.labelLg.copyWith(
                  color: MtColors.brand700, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 · Task History — past sessions bucketed by service tier
// ═══════════════════════════════════════════════════════════════════════════

class TaskHistoryTab extends ConsumerWidget {
  const TaskHistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nurseHistoryProvider);
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () async => ref.invalidate(nurseHistoryProvider),
      child: async.when(
        loading: () => const _CenteredLoader(),
        error: (e, _) => _TabError(
          message: e.toString(),
          onRetry: () => ref.invalidate(nurseHistoryProvider),
        ),
        data: (items) {
          if (items.isEmpty) return const _EmptyHistoryState();
          // Bucket by service tier (care_type), preserving recency order.
          final tiers = <String, List<PatientHistoryItem>>{};
          for (final it in items) {
            final key = it.serviceName.isEmpty ? 'Other' : it.serviceName;
            (tiers[key] ??= []).add(it);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              for (final entry in tiers.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Row(
                    children: [
                      Text(entry.key.toUpperCase(),
                          style: MtTextStyles.sectionLabel.copyWith(
                              color: MtColors.ink3, letterSpacing: 1.0)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: MtColors.brandSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${entry.value.length}',
                            style: MtTextStyles.labelSm
                                .copyWith(color: MtColors.brand700)),
                      ),
                    ],
                  ),
                ),
                for (final it in entry.value) _HistoryRow(item: it),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PatientHistoryItem item;
  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, yyyy').format(item.updatedAt.toLocal());
    final (statusFg, statusBg) = switch (item.status) {
      'completed' => (MtColors.completed, MtColors.completedBg),
      'cancelled' => (MtColors.ink3, MtColors.bg),
      'rejected' => (MtColors.rejected, const Color(0xFFFEE2E2)),
      _ => (MtColors.ink3, MtColors.bg),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(date,
                        style: MtTextStyles.labelMd.copyWith(
                            color: MtColors.ink, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(item.status.toUpperCase(),
                          style: MtTextStyles.labelSm
                              .copyWith(color: statusFg, fontSize: 9)),
                    ),
                  ],
                ),
                if (item.locationText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.locationText,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Text(_money(item.effectivePrice),
              style: MtTextStyles.labelLg.copyWith(color: MtColors.brand)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 · Earnings Tracker — historical statements + performance stars
// ═══════════════════════════════════════════════════════════════════════════

class EarningsTab extends ConsumerWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(nurseStatsProvider).valueOrNull ?? DoctorStats.empty;
    final earnings = ref.watch(nurseEarningsProvider);
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () async {
        ref.invalidate(nurseStatsProvider);
        ref.invalidate(nurseEarningsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _EarningsHero(stats: stats),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'TODAY',
                  value: _money(stats.todayEarnings),
                  caption: stats.todayVisits == 1
                      ? '1 service'
                      : '${stats.todayVisits} services',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: 'THIS WEEK',
                  value: _money(stats.weekEarnings),
                  caption: stats.weekVisits == 1
                      ? '1 service'
                      : '${stats.weekVisits} services',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RatingCard(rating: stats.rating, reviewCount: stats.reviewCount),
          const SizedBox(height: 20),
          // Settled-vs-pending payout ledger — itemized history of completed
          // dispatch tickets (GET /api/provider/earnings).
          Text('PAYOUT LEDGER',
              style: MtTextStyles.sectionLabel
                  .copyWith(color: MtColors.ink3, letterSpacing: 1.0)),
          const SizedBox(height: 10),
          earnings.when(
            loading: () => ShimmerLoadingPlaceholder(
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            error: (e, _) => _LedgerError(
              message: e.toString(),
              onRetry: () => ref.invalidate(nurseEarningsProvider),
            ),
            data: (ledger) => _PayoutLedger(ledger: ledger),
          ),
        ],
      ),
    );
  }
}

// ── Payout ledger — settled/pending totals + itemized payout history ─────────

class _PayoutLedger extends StatelessWidget {
  final ProviderEarnings ledger;
  const _PayoutLedger({required this.ledger});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _LedgerTotalCard(
                label: 'TOTAL SETTLED',
                value: _money(ledger.totalSettled),
                accent: const Color(0xFF059669),
                icon: Icons.verified_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LedgerTotalCard(
                label: 'PENDING',
                value: _money(ledger.totalPending),
                accent: const Color(0xFFD97706),
                icon: Icons.hourglass_bottom_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (ledger.items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: MtColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MtColors.line),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 34, color: MtColors.ink3.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text('No payouts yet',
                    style: MtTextStyles.labelLg.copyWith(color: MtColors.ink3)),
                const SizedBox(height: 2),
                Text(
                  'Completed visits will show up here once billed.',
                  textAlign: TextAlign.center,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: MtColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MtColors.line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < ledger.items.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: MtColors.line),
                  _LedgerPayoutRow(item: ledger.items[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _LedgerTotalCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final IconData icon;
  const _LedgerTotalCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.labelSm.copyWith(
                        color: MtColors.ink3, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MtTextStyles.h2.copyWith(color: MtColors.ink)),
        ],
      ),
    );
  }
}

class _LedgerPayoutRow extends StatelessWidget {
  final ProviderPayoutItem item;
  const _LedgerPayoutRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final date = item.completedAt;
    final dateLabel = date == null ? '—' : DateFormat('d MMM y').format(date);
    final settled = item.settled;
    final badgeColor =
        settled ? const Color(0xFF059669) : const Color(0xFFD97706);
    final badgeBg =
        settled ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.patientName.isEmpty ? 'Patient' : item.patientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelMd.copyWith(
                      color: MtColors.ink, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  item.careType.isEmpty
                      ? dateLabel
                      : '${item.careType} · $dateLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(item.amount),
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  settled ? 'Settled' : 'Pending',
                  style: MtTextStyles.labelSm
                      .copyWith(color: badgeColor, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LedgerError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: MtColors.rejected, size: 28),
          const SizedBox(height: 8),
          Text("Couldn't load the payout ledger",
              style: MtTextStyles.labelLg.copyWith(color: MtColors.ink)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onRetry,
            child: Text('Retry', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );
  }
}

class _EarningsHero extends StatelessWidget {
  final DoctorStats stats;
  const _EarningsHero({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MtColors.brand, MtColors.brand700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THIS WEEK\'S EARNINGS',
              style: MtTextStyles.labelSm.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 1.0)),
          const SizedBox(height: 8),
          Text(_money(stats.weekEarnings),
              style: MtTextStyles.displayLg
                  .copyWith(color: Colors.white, fontSize: 38)),
          const SizedBox(height: 4),
          Text('${stats.weekVisits} care services completed',
              style: MtTextStyles.bodyMd
                  .copyWith(color: Colors.white.withValues(alpha: 0.9))),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  final double rating;
  final int reviewCount;
  const _RatingCard({required this.rating, required this.reviewCount});

  @override
  Widget build(BuildContext context) {
    final full = rating.floor();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PERFORMANCE RATING',
                    style: MtTextStyles.sectionLabel.copyWith(
                        color: MtColors.ink3, letterSpacing: 1.0)),
                const SizedBox(height: 6),
                Text(rating.toStringAsFixed(2),
                    style: MtTextStyles.h2
                        .copyWith(color: MtColors.ink, fontSize: 24)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Icon(
                        i < full ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 18,
                        color: const Color(0xFFF59E0B),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  reviewCount == 1 ? 'from 1 review' : 'from $reviewCount reviews',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: MtTextStyles.sectionLabel
                  .copyWith(color: MtColors.ink3, letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  MtTextStyles.h2.copyWith(color: MtColors.ink, fontSize: 24)),
          const SizedBox(height: 2),
          Text(caption, style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared small widgets
// ═══════════════════════════════════════════════════════════════════════════

class _LocationRow extends StatelessWidget {
  final String address;
  const _LocationRow({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: MtColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, color: MtColors.brand, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(address,
                style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      CareRequestStatus.assigned => ('ASSIGNED', MtColors.brand700, MtColors.brandSoft),
      CareRequestStatus.enroute ||
      CareRequestStatus.onTheWay =>
        ('ON THE WAY', const Color(0xFF1D4ED8), const Color(0xFFEFF6FF)),
      CareRequestStatus.arrived => ('ARRIVED', MtColors.brand, MtColors.brandSoft),
      CareRequestStatus.inService =>
        ('IN SERVICE', const Color(0xFF6B21A8), const Color(0xFFF3E8FF)),
      _ => (status.toUpperCase(), MtColors.ink3, MtColors.bg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: MtTextStyles.labelSm.copyWith(color: fg, fontSize: 10)),
    );
  }
}

class _MiniSpinner extends StatelessWidget {
  final bool light;
  const _MiniSpinner({this.light = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: light
            ? const AlwaysStoppedAnimation<Color>(Colors.white)
            : const AlwaysStoppedAnimation<Color>(MtColors.brand),
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: MtColors.brand)),
      ],
    );
  }
}

class _TabError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _TabError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        const Icon(Icons.error_outline, color: MtColors.rejected, size: 40),
        const SizedBox(height: 12),
        Text('Something went wrong',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 6),
        Text(message,
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoDispatchesState extends StatelessWidget {
  const _NoDispatchesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline,
              color: MtColors.completed, size: 40),
          const SizedBox(height: 10),
          Text('No active dispatches',
              style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
          const SizedBox(height: 4),
          Text('Stay on duty — new dispatches will appear here.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        const Icon(Icons.history, color: MtColors.ink3, size: 40),
        const SizedBox(height: 12),
        Text('No past sessions yet',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 6),
        Text('Completed nursing sessions will be logged here.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
      ],
    );
  }
}
