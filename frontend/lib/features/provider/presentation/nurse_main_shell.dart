import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../../doctor/doctor_providers.dart';
import '../../doctor/services/location_tracking_service.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../chat/presentation/conversation_inbox_button.dart';
import 'nurse_dashboard_tabs.dart';
import 'nurse_profile_screen.dart';

/// Nurse Operations Hub shell — the single `/nurse/:name` destination.
///
/// A persistent 3-tab bottom navigation (Dispatches · Task History ·
/// Earnings Tracker) under a profile banner whose trailing switch flips
/// the nurse's Duty (Online/Offline) visibility for the matching system.
/// All content is centred at `maxWidth: 600` for wide web viewports.
class NurseMainShell extends ConsumerStatefulWidget {
  const NurseMainShell({super.key});

  @override
  ConsumerState<NurseMainShell> createState() => _NurseMainShellState();
}

class _NurseMainShellState extends ConsumerState<NurseMainShell> {
  int _index = 0;

  static const _tabs = [
    DispatchesTab(),
    TaskHistoryTab(),
    EarningsTab(),
    NurseProfileScreen(),
  ];

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: MtTextStyles.h3),
        content: Text(
          'সাইন আউট করবেন?',
          style: MtTextStyles.bodyMd.copyWith(
              color: ctx.appColors.body, fontFamily: 'Kalpurush'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                TextButton.styleFrom(foregroundColor: ctx.appColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(locationTrackingServiceProvider).stop();
    if (!mounted) return;
    await ref.read(authTokenProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _NurseBanner(onSignOut: _confirmSignOut),
                Expanded(
                  child: IndexedStack(index: _index, children: _tabs),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: c.surface,
          indicatorColor: c.accent.withValues(alpha: 0.15),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => MtTextStyles.labelSm.copyWith(
              color: states.contains(WidgetState.selected)
                  ? c.accent
                  : c.muted,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? c.accent
                  : c.muted,
            ),
          ),
        ),
        child: NavigationBar(
          height: 66,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.emergency_outlined),
              selectedIcon: Icon(Icons.emergency),
              label: 'Dispatches',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: 'Task History',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Earnings',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile banner with the nurse's metrics + the Duty (Online/Offline)
/// visibility switch.
class _NurseBanner extends ConsumerWidget {
  final VoidCallback onSignOut;
  const _NurseBanner({required this.onSignOut});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final user = ref.watch(currentUserProvider);
    final availability = ref.watch(doctorAvailabilityProvider);
    final online = availability.valueOrNull ?? true;
    final isBusy = availability.isLoading;

    final name = user?.name ?? 'Nurse';
    final credentials = (user?.specialization ?? '').trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: name,
                size: 46,
                backgroundColor: c.accent.withValues(alpha: 0.12),
                textColor: c.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: MtTextStyles.h3.copyWith(color: c.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      credentials.isEmpty ? 'Home care nurse' : credentials,
                      style: MtTextStyles.bodySm.copyWith(color: c.body),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const ConversationInboxButton(),
              const SizedBox(width: 8),
              const NotificationBell(),
              IconButton(
                tooltip: 'Sign out',
                icon: Icon(Icons.logout, color: c.muted, size: 20),
                onPressed: onSignOut,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: online ? c.positiveBg : c.surfaceHi,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  online ? Icons.bolt : Icons.bolt_outlined,
                  size: 16,
                  color: online ? c.positive : c.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    online
                        ? 'On duty · discoverable for dispatches'
                        : 'Off duty · not receiving dispatches',
                    style: MtTextStyles.labelMd.copyWith(
                      color: online ? c.positive : c.muted,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: online,
                  activeThumbColor: c.positive,
                  onChanged: isBusy
                      ? null
                      : (_) => ref
                          .read(doctorAvailabilityProvider.notifier)
                          .toggle(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
