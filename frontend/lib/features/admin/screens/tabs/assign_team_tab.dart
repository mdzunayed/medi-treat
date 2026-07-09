import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/admin_models.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/mt_empty_state.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../doctor/doctor_providers.dart';
import '../../admin_providers.dart';

/// Admin "Assign team" surface. Built around two distinct provider
/// rosters — doctors and nurses — that the admin can select from
/// independently or jointly before dispatching the visit.
///
/// Layout switches between two presentations based on viewport width:
///
///   - Wide (≥ 1100 px): a **side-by-side split view** — request
///     details column on the left, then two equal columns "Available
///     Doctors" and "Available Nurses" side-by-side, with a sticky
///     finalize bar at the bottom of the column pair.
///   - Narrow (< 1100 px): a **nested TabBar** — same request column
///     on the left, then a tabbed pane that flips between the two
///     rosters with the sticky finalize bar pinned below.
class AssignTeamTab extends ConsumerWidget {
  final ValueChanged<int>? onNavigateTab;

  const AssignTeamTab({super.key, this.onNavigateTab});

  static const double _wideBreakpoint = 1100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(selectedRequestProvider);

    if (request == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: MtEmptyState(
              icon: Icons.person_add_disabled,
              title: 'No request selected',
              subtitle:
                  'Pick a pending request from the Review Queue to start matching a doctor and nurse.',
              actionLabel: 'Go to Review Queue',
              onAction: () => onNavigateTab?.call(1),
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Left: Request Details ──────────────────────────────────────────
        Expanded(
          flex: 4,
          child: _RequestDetailsColumn(request: request),
        ),

        // ── Right: Dual-list match-maker + finalize bar ────────────────────
        Expanded(
          flex: 7,
          child: Container(
            color: MtColors.bg,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // The 7-flex right column is just over half the
                      // workspace width on a 1440-monitor; threshold the
                      // split on the *parent* width here so the layout
                      // flips when the admin window narrows.
                      final wide = constraints.maxWidth >= _wideBreakpoint;
                      if (wide) {
                        return _SideBySidePool(requestId: request.id);
                      }
                      return _TabbedPool(requestId: request.id);
                    },
                  ),
                ),
                _FinalizeAssignmentBar(request: request),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Request details column (left)
// ============================================================================

class _RequestDetailsColumn extends StatelessWidget {
  final AdminCareRequest request;
  const _RequestDetailsColumn({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assign Team', style: MtTextStyles.h1),
            const SizedBox(height: 8),
            Text('Match providers for request ${request.id}',
                style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3)),
            const SizedBox(height: 32),
            _DetailSection(
              title: 'PATIENT',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${request.patientName} (${request.patientAge}${request.patientGender ?? ''})',
                    style: MtTextStyles.labelLg,
                  ),
                  const SizedBox(height: 4),
                  Text(request.phone ?? 'No phone provided',
                      style: MtTextStyles.bodyMd),
                  if (request.patientHistory != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      request.patientHistory!,
                      style: MtTextStyles.bodySm
                          .copyWith(color: MtColors.ink2),
                    ),
                  ],
                ],
              ),
            ),
            _DetailSection(
              title: 'SERVICE REQUIRED',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(request.serviceName,
                          style: MtTextStyles.labelLg),
                      if (request.isUrgent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'URGENT',
                            style: MtTextStyles.labelSm.copyWith(
                              color: MtColors.rejected,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (request.surgeryDetails != null) ...[
                    const SizedBox(height: 4),
                    Text(request.surgeryDetails!,
                        style: MtTextStyles.bodyMd
                            .copyWith(color: MtColors.brand)),
                  ],
                  const SizedBox(height: 8),
                  Text('Duration: ${request.durationHours} hours',
                      style: MtTextStyles.bodyMd),
                  Text('Location: ${request.location}',
                      style: MtTextStyles.bodyMd),
                  Text(
                    'Expected pay: ৳${request.patientOffer.toStringAsFixed(0)}',
                    style: MtTextStyles.bodyMd,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _DetailSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: MtTextStyles.sectionLabel),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ============================================================================
// Right column — dual-list pool
// ============================================================================

class _SideBySidePool extends StatelessWidget {
  final String requestId;
  const _SideBySidePool({required this.requestId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _DoctorsColumn(requestId: requestId)),
          const SizedBox(width: 20),
          Expanded(child: _NursesColumn(requestId: requestId)),
        ],
      ),
    );
  }
}

class _TabbedPool extends StatefulWidget {
  final String requestId;
  const _TabbedPool({required this.requestId});

  @override
  State<_TabbedPool> createState() => _TabbedPoolState();
}

class _TabbedPoolState extends State<_TabbedPool>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MtColors.line),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: MtColors.brand,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: MtColors.ink2,
              labelStyle:
                  MtTextStyles.labelMd.copyWith(fontWeight: FontWeight.w700),
              unselectedLabelStyle: MtTextStyles.labelMd,
              splashBorderRadius: BorderRadius.circular(10),
              tabs: const [
                Tab(height: 36, text: 'Available Doctors'),
                Tab(height: 36, text: 'Available Nurses'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(
                  child: _DoctorsColumn(requestId: widget.requestId),
                ),
                SingleChildScrollView(
                  child: _NursesColumn(requestId: widget.requestId),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Doctors column
// ============================================================================

class _DoctorsColumn extends ConsumerWidget {
  final String requestId;
  const _DoctorsColumn({required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(availableDoctorsProvider(requestId));
    final selectedId = ref.watch(assignedDoctorIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColumnHeader(
          title: 'Available Doctors',
          subtitle: 'Verified · online · sorted by rating',
          onClear: selectedId == null
              ? null
              : () => ref
                  .read(assignedDoctorIdProvider.notifier)
                  .state = null,
        ),
        const SizedBox(height: 14),
        async.when(
          loading: () => const _ListLoading(),
          error: (e, _) => MtErrorState(
            message: e.toString(),
            onRetry: () => ref
                .invalidate(availableDoctorsProvider(requestId)),
          ),
          data: (docs) {
            if (docs.isEmpty) {
              return const _ListEmpty(
                copy: 'No doctors are online right now.',
              );
            }
            return Column(
              children: [
                for (final d in docs)
                  _ProviderTile(
                    initials: d.initials,
                    name: d.name,
                    subtitle: d.specialization,
                    fee: d.fee,
                    rating: d.rating,
                    reviewCount: d.reviewCount,
                    online: d.isAvailable,
                    isSelected: selectedId == d.id,
                    onSelect: () => ref
                        .read(assignedDoctorIdProvider.notifier)
                        .state = d.id,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ============================================================================
// Nurses column
// ============================================================================

class _NursesColumn extends ConsumerWidget {
  final String requestId;
  const _NursesColumn({required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(availableNursesProvider(requestId));
    final selectedId = ref.watch(assignedNurseIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColumnHeader(
          title: 'Available Nurses',
          subtitle: 'Verified · online · sorted by rating',
          onClear: selectedId == null
              ? null
              : () => ref
                  .read(assignedNurseIdProvider.notifier)
                  .state = null,
        ),
        const SizedBox(height: 14),
        async.when(
          loading: () => const _ListLoading(),
          error: (e, _) => MtErrorState(
            message: e.toString(),
            onRetry: () =>
                ref.invalidate(availableNursesProvider(requestId)),
          ),
          data: (nurses) {
            if (nurses.isEmpty) {
              return const _ListEmpty(
                copy: 'No nurses are online right now.',
              );
            }
            return Column(
              children: [
                for (final n in nurses)
                  _ProviderTile(
                    initials: n.initials,
                    name: n.name,
                    subtitle: n.nursingSpecialty,
                    fee: n.fee,
                    rating: n.rating,
                    reviewCount: n.reviewCount,
                    online: n.isAvailable,
                    isSelected: selectedId == n.id,
                    onSelect: () => ref
                        .read(assignedNurseIdProvider.notifier)
                        .state = n.id,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ============================================================================
// Shared atoms
// ============================================================================

class _ColumnHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onClear;

  const _ColumnHeader({
    required this.title,
    required this.subtitle,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: MtTextStyles.h2),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            ],
          ),
        ),
        if (onClear != null)
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(foregroundColor: MtColors.ink2),
            child: Text('Clear', style: MtTextStyles.labelMd),
          ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final String initials;
  final String name;
  final String subtitle;
  final double fee;
  final double rating;
  final int reviewCount;
  final bool online;
  final bool isSelected;
  final VoidCallback onSelect;

  const _ProviderTile({
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.fee,
    required this.rating,
    required this.reviewCount,
    required this.online,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? MtColors.brand : MtColors.line,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: MtColors.brand.withValues(alpha: 0.18),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                InitialsAvatar(
                  name: name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), ''),
                  size: 44,
                  backgroundColor: const Color(0xFFFFF4E5),
                  textColor: const Color(0xFF92400E),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name.isEmpty ? 'Provider' : name,
                              style: MtTextStyles.labelLg.copyWith(
                                color: MtColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (online) ...[
                            const SizedBox(width: 8),
                            const _OnlineChip(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle.isEmpty ? '—' : subtitle,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (rating > 0) ...[
                            const Icon(Icons.star_rounded,
                                size: 14, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1) +
                                  (reviewCount > 0 ? ' ($reviewCount)' : ''),
                              style: MtTextStyles.bodySm
                                  .copyWith(color: MtColors.ink),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            '৳${fee.toStringAsFixed(0)}',
                            style: MtTextStyles.labelMd.copyWith(
                              color: MtColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _SelectChevron(isSelected: isSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlineChip extends StatelessWidget {
  const _OnlineChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: MtColors.completedBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: MtColors.completed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'ONLINE',
            style: MtTextStyles.labelSm.copyWith(
              color: MtColors.completed,
              fontWeight: FontWeight.w700,
              fontSize: 9.5,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectChevron extends StatelessWidget {
  final bool isSelected;
  const _SelectChevron({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isSelected ? MtColors.brand : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? MtColors.brand : MtColors.line,
          width: 1.5,
        ),
      ),
      child: Icon(
        isSelected ? Icons.check : Icons.add,
        size: 18,
        color: isSelected ? Colors.white : MtColors.ink3,
      ),
    );
  }
}

class _ListLoading extends StatelessWidget {
  const _ListLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: CircularProgressIndicator(color: MtColors.brand),
      ),
    );
  }
}

class _ListEmpty extends StatelessWidget {
  final String copy;
  const _ListEmpty({required this.copy});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.line),
      ),
      child: Text(
        copy,
        style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
      ),
    );
  }
}

// ============================================================================
// Sticky finalize bar — assembles both selections into a single payload
// ============================================================================

/// Admin-entered final service fee for the request being assigned. Pricing
/// authority lives entirely here now — the patient no longer offers a budget,
/// so this value is mandatory before a dispatch can fire. `null` = not yet
/// entered. Reset to `null` after each successful assignment.
final assignFinalPriceProvider = StateProvider<double?>((ref) => null);

class _FinalizeAssignmentBar extends ConsumerWidget {
  final AdminCareRequest request;
  const _FinalizeAssignmentBar({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignState = ref.watch(assignTeamStateProvider);
    final selectedDoctorId = ref.watch(assignedDoctorIdProvider);
    final selectedNurseId = ref.watch(assignedNurseIdProvider);
    final finalPrice = ref.watch(assignFinalPriceProvider);

    final doctorsAsync = ref.watch(availableDoctorsProvider(request.id));
    final nursesAsync = ref.watch(availableNursesProvider(request.id));

    String? nameById<T>(
      AsyncValue<List<T>> async,
      String? id,
      String Function(T) idOf,
      String Function(T) nameOf,
    ) {
      if (id == null) return null;
      final list = async.valueOrNull;
      if (list == null) return null;
      for (final p in list) {
        if (idOf(p) == id) return nameOf(p);
      }
      return null;
    }

    final doctorName = nameById<AvailableDoctor>(
      doctorsAsync,
      selectedDoctorId,
      (d) => d.id,
      (d) => d.name,
    );
    final nurseName = nameById<AvailableNurse>(
      nursesAsync,
      selectedNurseId,
      (n) => n.id,
      (n) => n.name,
    );

    final summary = _composeSummary(doctorName, nurseName);
    // Pricing is now mandatory: a provider must be picked AND a positive fee
    // entered before the dispatch button enables.
    final hasValidPrice = finalPrice != null && finalPrice > 0;
    final canDispatch = (selectedDoctorId != null || selectedNurseId != null) &&
        hasValidPrice &&
        !assignState.isLoading;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Manual billing console — the admin types the final service fee.
          _PriceField(key: ValueKey('price_${request.id}')),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _StatusLine(
                  assignState: assignState,
                  summary: summary,
                ),
              ),
              const SizedBox(width: 12),
          if (assignState.isDone || assignState.isError)
            OutlinedButton(
              onPressed: () {
                ref.read(assignTeamStateProvider.notifier).reset();
                if (assignState.isDone) {
                  ref.read(selectedRequestProvider.notifier).state = null;
                  ref.read(assignedDoctorIdProvider.notifier).state = null;
                  ref.read(assignedNurseIdProvider.notifier).state = null;
                  ref.read(assignedHelperIdProvider.notifier).state = null;
                }
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 14),
              ),
              child: Text(
                assignState.isDone ? 'Next request' : 'Retry',
                style: MtTextStyles.labelLg,
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: canDispatch
                  ? () => _dispatch(
                        ref,
                        doctorName: doctorName,
                        nurseName: nurseName,
                      )
                  : null,
              icon: assignState.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(
                assignState.isLoading
                    ? 'Processing…'
                    : 'Confirm Team Dispatch',
                style: MtTextStyles.labelLg.copyWith(color: Colors.white),
              ),
            ),
            ],
          ),
        ],
      ),
    );
  }

  String _composeSummary(String? doctorName, String? nurseName) {
    final parts = <String>[];
    if ((doctorName ?? '').trim().isNotEmpty) parts.add(doctorName!);
    if ((nurseName ?? '').trim().isNotEmpty) parts.add('Nurse $nurseName');
    if (parts.isEmpty) return 'Select a doctor or nurse to continue';
    return 'Assigning ${parts.join(' & ')} to this request';
  }

  void _dispatch(
    WidgetRef ref, {
    String? doctorName,
    String? nurseName,
  }) {
    final selectedDoctorId = ref.read(assignedDoctorIdProvider);
    final selectedNurseId = ref.read(assignedNurseIdProvider);
    final selectedHelperId = ref.read(assignedHelperIdProvider);
    final helpersAsync = ref.read(availableHelpersProvider(request.id));
    String? lookupHelperName(String? id) {
      if (id == null) return null;
      final list = helpersAsync.valueOrNull;
      if (list == null) return null;
      for (final h in list) {
        if (h.id == id) return h.name;
      }
      return null;
    }

    ref
        .read(assignTeamStateProvider.notifier)
        .assignTeam(
          requestId: request.id,
          doctorId: selectedDoctorId,
          doctorName: doctorName,
          nurseId: selectedNurseId,
          nurseName: nurseName,
          helperId: selectedHelperId,
          helperName: lookupHelperName(selectedHelperId),
          // Admin-entered fee is the single source of pricing truth now.
          finalPrice: ref.read(assignFinalPriceProvider),
        )
        .then((success) {
      if (success) {
        ref.invalidate(adminRequestsProvider);
        ref.invalidate(doctorDashboardProvider);
        ref.read(selectedRequestIdsProvider.notifier).state = {};
        // Clear the fee so the next request starts from a blank field.
        ref.read(assignFinalPriceProvider.notifier).state = null;
        // Surface a quick success banner — the OutlinedButton in the
        // bar flips to "Next request" once the notifier transitions
        // to `done`, so no extra navigation is required here.
      }
    });
  }
}

/// Manual billing console — a numeric field for the admin to enter the final
/// service fee. Writes the parsed value into [assignFinalPriceProvider]; the
/// finalize bar reads it to gate + send the dispatch. Decimal digits only;
/// empty / zero leaves the provider `null` so the dispatch button stays off.
class _PriceField extends ConsumerStatefulWidget {
  const _PriceField({super.key});

  @override
  ConsumerState<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends ConsumerState<_PriceField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final current = ref.read(assignFinalPriceProvider);
    _controller = TextEditingController(
      text: current == null ? '' : _trim(current),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the field in sync when the provider is cleared elsewhere (e.g.
    // after a successful dispatch resets it to null).
    ref.listen<double?>(assignFinalPriceProvider, (prev, next) {
      if (next == null && _controller.text.isNotEmpty) {
        _controller.clear();
      }
    });

    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        // Digits + at most one decimal point.
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        TextInputFormatter.withFunction((oldV, newV) =>
            newV.text.split('.').length > 2 ? oldV : newV),
      ],
      onChanged: (raw) {
        final parsed = double.tryParse(raw.trim());
        ref.read(assignFinalPriceProvider.notifier).state =
            (parsed == null || parsed <= 0) ? null : parsed;
      },
      decoration: InputDecoration(
        labelText: 'Set Final Service Fee / Amount (৳)',
        prefixText: '৳ ',
        isDense: true,
        filled: true,
        fillColor: MtColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final AssignTeamState assignState;
  final String summary;

  const _StatusLine({
    required this.assignState,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    if (assignState.stage != AssignTeamStage.idle) {
      Widget leading;
      Color color;
      if (assignState.isLoading) {
        leading = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        color = MtColors.ink;
      } else if (assignState.isDone) {
        leading = const Icon(Icons.check_circle,
            color: MtColors.completed, size: 20);
        color = MtColors.completed;
      } else if (assignState.isError) {
        leading = const Icon(Icons.error,
            color: MtColors.rejected, size: 20);
        color = MtColors.rejected;
      } else {
        leading = const SizedBox(width: 16, height: 16);
        color = MtColors.ink;
      }
      return Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              assignState.stageLabel,
              style: MtTextStyles.labelMd.copyWith(color: color),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Text(
      summary,
      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
