import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/admin_models.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../admin_providers.dart';

/// Right-aligned 500-wide slide-over showing the full triage view for a
/// single [AdminCareRequest]. Used by both the Review Queue and Overview tabs
/// so the experience stays identical regardless of entry point.
///
/// Call via [showTriageSlideOver] — that helper wires up [showModalBottomSheet]
/// with the correct `isScrollControlled` and transparent backdrop so the
/// slide-over animates in from the right edge.
class TriageSlideOver extends ConsumerWidget {
  final AdminCareRequest request;
  final VoidCallback onAssignTeam;

  const TriageSlideOver({
    super.key,
    required this.request,
    required this.onAssignTeam,
  });

  Future<void> _confirmReject(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject request ${request.id}?', style: MtTextStyles.h3),
        content: Text(
          'The patient will be notified. Any escrowed payment will be refunded within 24 hours.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep request', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: Text('Reject', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref
          .read(adminRequestsProvider.notifier)
          .bulkUpdateStatus({request.id}, 'rejected');
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Request ${request.id} rejected'),
          backgroundColor: MtColors.completed,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not reject: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel booking ${request.id}?', style: MtTextStyles.h3),
        content: Text(
          'The booking will be cancelled, any assigned team released, and the '
          'patient notified. This cannot be undone.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep booking', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: Text('Cancel booking', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref
          .read(adminRequestsProvider.notifier)
          .cancelBooking(request.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Booking ${request.id} cancelled'),
          backgroundColor: MtColors.completed,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not cancel: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = request.status == 'pending';
    // Terminal bookings can't be cancelled; pending ones use "Reject" (their
    // pre-processing equivalent), so the admin Cancel action targets bookings
    // that are actively being processed.
    const terminal = {'completed', 'cancelled', 'rejected'};
    final canCancel = !isPending && !terminal.contains(request.status);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 500,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(-4, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: MtColors.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Triage request', style: MtTextStyles.h2),
                        Text(request.id,
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink3)),
                      ],
                    ),
                  ),
                  _StatusBadge(status: request.status),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PATIENT', style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 8),
                    Text(
                      '${request.patientName} (${request.patientAge}${request.patientGender ?? ''})',
                      style: MtTextStyles.labelLg,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.phone ?? 'No phone provided',
                      style: MtTextStyles.bodyMd,
                    ),
                    const SizedBox(height: 16),

                    if (request.patientHistory != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: MtColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: MtColors.line),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.history,
                                color: MtColors.ink3, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('Medical history',
                                      style: MtTextStyles.labelMd),
                                  const SizedBox(height: 4),
                                  Text(
                                    request.patientHistory ?? '',
                                    style: MtTextStyles.bodySm,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    Text('SERVICE DETAILS',
                        style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 8),
                    Text(request.serviceName, style: MtTextStyles.labelLg),
                    if (request.surgeryDetails != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Surgery: ${request.surgeryDetails}',
                        style: MtTextStyles.bodyMd
                            .copyWith(color: MtColors.brand),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text('Duration: ${request.durationHours} hours',
                        style: MtTextStyles.bodyMd),
                    const SizedBox(height: 4),
                    Text(
                      'Scheduled: ${request.scheduledTime != null ? request.scheduledTime!.toLocal().toString().split('.')[0] : 'ASAP'}',
                      style: MtTextStyles.bodyMd,
                    ),
                    const SizedBox(height: 24),

                    Text('LOCATION', style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 8),
                    Text(request.location, style: MtTextStyles.labelLg),
                    const SizedBox(height: 12),
                    Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: MtColors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MtColors.line),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.map,
                            size: 48,
                            color: MtColors.ink3.withValues(alpha: 0.5),
                          ),
                          if (request.latitude != null)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${request.latitude?.toStringAsFixed(4)}, ${request.longitude?.toStringAsFixed(4)}',
                                  style: MtTextStyles.labelSm
                                      .copyWith(fontSize: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (request.notes != null && request.notes!.isNotEmpty) ...[
                      Text('NOTES', style: MtTextStyles.sectionLabel),
                      const SizedBox(height: 8),
                      Text(request.notes ?? '', style: MtTextStyles.bodyMd),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),

            // Footer / Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: MtColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  if (isPending) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _confirmReject(context, ref),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MtColors.rejected,
                          side: const BorderSide(color: MtColors.rejected),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                  if (canCancel) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _confirmCancel(context, ref),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MtColors.rejected,
                          side: const BorderSide(color: MtColors.rejected),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancel booking'),
                      ),
                    ),
                  ],
                  if (isPending) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: onAssignTeam,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Assign team'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience helper so callers don't have to remember the right
/// `showModalBottomSheet` config to make the slide-over render as a
/// right-edge drawer.
Future<void> showTriageSlideOver(
  BuildContext context, {
  required AdminCareRequest request,
  required VoidCallback onAssignTeam,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TriageSlideOver(
      request: request,
      onAssignTeam: onAssignTeam,
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color sColor;
    Color sBgColor;
    final label = status.toUpperCase();
    switch (status) {
      case 'pending':
        sColor = MtColors.brand;
        sBgColor = MtColors.brandSoft;
        break;
      case 'approved':
        sColor = const Color(0xFF059669);
        sBgColor = const Color(0xFFDCF3E7);
        break;
      case 'rejected':
        sColor = MtColors.rejected;
        sBgColor = const Color(0xFFFEE2E2);
        break;
      case 'cancelled':
        sColor = MtColors.rejected;
        sBgColor = const Color(0xFFFEE2E2);
        break;
      default:
        sColor = MtColors.ink3;
        sBgColor = MtColors.line;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: sBgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: sColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: MtTextStyles.labelSm
                .copyWith(color: sColor, fontSize: 9, height: 1.1),
          ),
        ],
      ),
    );
  }
}
