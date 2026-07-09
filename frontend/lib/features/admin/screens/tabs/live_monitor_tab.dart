import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/admin_models.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_empty_state.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../../core/widgets/mt_skeleton.dart';
import '../../admin_providers.dart';

/// Real-time monitor showing every visit that's currently dispatched, in
/// transit, or in service. The right sidebar is bound to [liveServicesProvider];
/// a [Timer.periodic] silently re-fetches every 30s and a manual Refresh
/// button lets the admin pull immediately when they need an authoritative
/// snapshot.
class LiveMonitorTab extends ConsumerStatefulWidget {
  const LiveMonitorTab({super.key});

  @override
  ConsumerState<LiveMonitorTab> createState() => _LiveMonitorTabState();
}

class _LiveMonitorTabState extends ConsumerState<LiveMonitorTab> {
  Timer? _refreshTimer;
  DateTime _lastRefreshed = DateTime.now();
  // Ticks every 15s just to update the "refreshed Xs ago" label between real
  // refreshes; keeps the time display honest without re-fetching.
  Timer? _displayTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      ref.invalidate(liveServicesProvider);
      setState(() => _lastRefreshed = DateTime.now());
    });
    _displayTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {}); // re-render the "refreshed ago" label
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _displayTimer?.cancel();
    super.dispose();
  }

  void _manualRefresh() {
    ref.invalidate(liveServicesProvider);
    setState(() => _lastRefreshed = DateTime.now());
  }

  String _refreshedAgoLabel() {
    final secs = DateTime.now().difference(_lastRefreshed).inSeconds;
    if (secs < 5) return 'refreshed just now';
    if (secs < 60) return 'refreshed ${secs}s ago';
    final mins = secs ~/ 60;
    return 'refreshed ${mins}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(liveServicesProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left: map ────────────────────────────────────────────────────
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: MtColors.rejected,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Live map · Dhaka',
                            style: MtTextStyles.labelLg),
                        const SizedBox(width: 12),
                        Builder(
                          builder: (_) {
                            final count = liveAsync.maybeWhen(
                              data: (v) => v.length,
                              orElse: () => null,
                            );
                            final label = count == null
                                ? _refreshedAgoLabel()
                                : '$count services in progress · ${_refreshedAgoLabel()}';
                            return Text(
                              label,
                              style: MtTextStyles.bodySm
                                  .copyWith(color: MtColors.ink3),
                            );
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _LegendDot(
                            color: const Color(0xFF2563EB),
                            label: 'En route'),
                        const SizedBox(width: 12),
                        _LegendDot(
                            color: MtColors.brand, label: 'Arrived'),
                        const SizedBox(width: 12),
                        _LegendDot(
                            color: const Color(0xFF8B5CF6),
                            label: 'In service'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MtColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: liveAsync.when(
                      loading: () => Container(
                        color: MtColors.bg,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, _) => Container(
                        color: MtColors.bg,
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: MtErrorState(
                          message: e.toString(),
                          onRetry: _manualRefresh,
                        ),
                      ),
                      data: (services) => CustomPaint(
                        painter: _LiveMonitorMapPainter(services: services),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Right: sidebar list ─────────────────────────────────────────
        Container(
          width: 340,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: MtColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Active services',
                              style: MtTextStyles.labelLg),
                          Text(
                            'Auto-refreshes every 10s',
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink3),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      color: MtColors.ink2,
                      tooltip: 'Refresh now',
                      onPressed: _manualRefresh,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: MtColors.line),
              Expanded(
                child: liveAsync.when(
                  loading: () => ListView.separated(
                    itemCount: 4,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: MtColors.line),
                    itemBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MtSkeleton.line(width: 80, height: 10),
                          const SizedBox(height: 10),
                          MtSkeleton.line(width: 160),
                          const SizedBox(height: 6),
                          MtSkeleton.line(width: 200, height: 10),
                          const SizedBox(height: 14),
                          MtSkeleton.box(height: 4, radius: 2),
                        ],
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: MtErrorState(
                      message: e.toString(),
                      onRetry: _manualRefresh,
                    ),
                  ),
                  data: (services) {
                    if (services.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: MtEmptyState(
                          icon: Icons.medical_services_outlined,
                          title: 'No active services',
                          subtitle:
                              'Once a visit is dispatched, it will appear here in real time.',
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: services.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: MtColors.line),
                      itemBuilder: (_, i) =>
                          _ActiveServiceItem(service: services[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

({Color color, Color bg, String label}) _statusVisuals(LiveServiceStatus s) {
  switch (s) {
    case LiveServiceStatus.onTheWay:
      return (
        color: const Color(0xFF2563EB),
        bg: const Color(0xFFEFF6FF),
        label: 'ON THE WAY',
      );
    case LiveServiceStatus.arrived:
      return (
        color: MtColors.brand,
        bg: MtColors.brandSoft,
        label: 'ARRIVED',
      );
    case LiveServiceStatus.inService:
      return (
        color: const Color(0xFF8B5CF6),
        bg: const Color(0xFFF5F3FF),
        label: 'IN SERVICE',
      );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: MtTextStyles.labelSm.copyWith(color: MtColors.ink2)),
      ],
    );
  }
}

class _ActiveServiceItem extends StatelessWidget {
  final LiveServiceUpdate service;

  const _ActiveServiceItem({required this.service});

  @override
  Widget build(BuildContext context) {
    final visuals = _statusVisuals(service.status);
    final progressColor = service.status == LiveServiceStatus.arrived
        ? MtColors.line
        : visuals.color;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(service.id,
                  style: MtTextStyles.labelSm
                      .copyWith(color: MtColors.ink3)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: visuals.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: visuals.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      visuals.label,
                      style: MtTextStyles.labelSm.copyWith(
                        color: visuals.color,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(service.patientName, style: MtTextStyles.labelLg),
          Text(
            service.doctorWithArea,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: MtColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: service.progressPercent.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: progressColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                service.timeLabel,
                style: MtTextStyles.labelSm.copyWith(
                  color: MtColors.ink3,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom-paints a stylized Dhaka grid + a pin per live service. Reads pins
/// directly from the provider's data so an empty list paints an empty map.
class _LiveMonitorMapPainter extends CustomPainter {
  final List<LiveServiceUpdate> services;

  _LiveMonitorMapPainter({required this.services});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      bgPaint,
    );

    final blockPaint = Paint()..color = const Color(0xFFE2E8F0);
    final double blockW = (size.width - (6 * 16)) / 5;
    final double blockH = (size.height - (5 * 16)) / 4;

    for (int col = 0; col < 5; col++) {
      for (int row = 0; row < 4; row++) {
        if ((col == 1 && row == 2) || (col == 3 && row == 0)) continue;
        final double x = 16.0 + (col * (blockW + 16));
        final double y = 16.0 + (row * (blockH + 16));
        final w = blockW * (row % 2 == 0 && col % 2 == 1 ? 0.9 : 1.0);
        final h = blockH * (col % 2 == 0 ? 0.95 : 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            const Radius.circular(8),
          ),
          blockPaint,
        );
      }
    }

    if (services.isEmpty) return;

    // Deterministic, evenly distributed pin positions — the live services
    // payload doesn't currently carry projected screen-space coordinates,
    // so we tile pin slots across the canvas instead of mapping lat/lng.
    final slots = <Offset>[
      Offset(size.width * 0.25, size.height * 0.35),
      Offset(size.width * 0.55, size.height * 0.25),
      Offset(size.width * 0.80, size.height * 0.55),
      Offset(size.width * 0.35, size.height * 0.65),
      Offset(size.width * 0.65, size.height * 0.70),
      Offset(size.width * 0.20, size.height * 0.75),
    ];

    for (var i = 0; i < services.length && i < slots.length; i++) {
      final svc = services[i];
      final visuals = _statusVisuals(svc.status);
      _drawPin(canvas, slots[i], svc.id, visuals.color);
    }
  }

  void _drawPin(Canvas canvas, Offset center, String id, Color color) {
    // Dark tooltip with the request id.
    final tooltipPaint = Paint()..color = const Color(0xFF111827);
    const tooltipW = 64.0;
    const tooltipH = 20.0;
    final tooltipRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 32),
      width: tooltipW,
      height: tooltipH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tooltipRect, const Radius.circular(4)),
      tooltipPaint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: id,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - 32 - (textPainter.height / 2),
      ),
    );

    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, 18, shadowPaint);

    final pinBorderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 18, pinBorderPaint);

    final pinInnerPaint = Paint()..color = color;
    canvas.drawCircle(center, 14, pinInnerPaint);

    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final iconPath = Path()
      ..moveTo(center.dx - 4, center.dy - 6)
      ..quadraticBezierTo(
          center.dx - 4, center.dy + 4, center.dx, center.dy + 4)
      ..quadraticBezierTo(
          center.dx + 4, center.dy + 4, center.dx + 4, center.dy - 6)
      ..moveTo(center.dx, center.dy + 4)
      ..lineTo(center.dx, center.dy + 8)
      ..addOval(
          Rect.fromCircle(center: Offset(center.dx, center.dy + 10), radius: 2));

    canvas.drawPath(iconPath, iconPaint);
  }

  @override
  bool shouldRepaint(covariant _LiveMonitorMapPainter old) =>
      old.services != services;
}
