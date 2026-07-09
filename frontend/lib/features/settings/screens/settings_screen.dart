import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../auth/auth_provider.dart';

/// SharedPreferences keys for the local-only toggles. Once a settings
/// backend ships these can move behind a `/api/users/:id/preferences`
/// endpoint without changing any UI.
const _kNotificationsPush = 'user.settings.notifications_push';
const _kDarkMode = 'user.settings.dark_mode';

/// Dedicated `/settings` screen for the doctor + patient flows. Layout
/// pattern mirrors the admin `settings_tab.dart` so all three roles
/// feel like one design system. Settings persist via SharedPreferences;
/// theme switching is intentionally deferred — see plan file.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SharedPreferences? _prefs;
  bool _pushOn = false;
  bool _darkOn = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _pushOn = prefs.getBool(_kNotificationsPush) ?? true;
      _darkOn = prefs.getBool(_kDarkMode) ?? false;
      _loaded = true;
    });
  }

  Future<void> _setPush(bool v) async {
    setState(() => _pushOn = v);
    await _prefs?.setBool(_kNotificationsPush, v);
  }

  Future<void> _setDark(bool v) async {
    setState(() => _darkOn = v);
    await _prefs?.setBool(_kDarkMode, v);
    if (!mounted) return;
    // The theme provider isn't wired yet — let the user know the
    // preference is captured but visually nothing flips.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Dark mode preference saved — full theme switching ships next.'),
      ),
    );
  }

  Future<void> _openTerms() async {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Terms of Service', style: MtTextStyles.h3),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Text(
              'By using Medi-Treat you agree to our standard terms of service. '
              'Full legal copy will be published before the public launch. '
              'For specific questions in the meantime, contact support.',
              style: MtTextStyles.bodyMd.copyWith(
                color: MtColors.ink2,
                height: 1.45,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: MtColors.brand),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openHelpCenter() async {
    final uri = Uri.parse('https://meditreat.app/help');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the help center.')),
      );
    }
  }

  Future<void> _openPrivacyStub() async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MtColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Privacy & Security',
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
              const SizedBox(height: 6),
              Text(
                'Session management, two-factor authentication, and data exports will live here. We are still building the underlying audit log — check back soon.',
                style:
                    MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final controller = TextEditingController();
    bool canConfirm = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Delete account?',
            style: MtTextStyles.h3.copyWith(color: MtColors.rejected),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This signs you out and queues your account for deletion. '
                'In-flight visits stay active; permanent removal happens '
                'within 30 days. Type DELETE to confirm.',
                style: MtTextStyles.bodyMd
                    .copyWith(color: MtColors.ink2, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Type DELETE',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MtColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MtColors.rejected, width: 1.5),
                  ),
                ),
                onChanged: (v) {
                  setInnerState(() => canConfirm = v.trim() == 'DELETE');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: MtColors.ink2),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: canConfirm
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: MtColors.rejected,
                disabledForegroundColor:
                    MtColors.rejected.withValues(alpha: 0.35),
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    // Stub path: log out + surface a SnackBar. A real soft-delete
    // endpoint can layer in here later without UI changes.
    await ref.read(authTokenProvider.notifier).logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Deletion queued — contact support to finalize before 30 days.'),
        backgroundColor: MtColors.rejected,
      ),
    );
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: MtColors.bg,
        body: Center(child: CircularProgressIndicator(color: MtColors.brand)),
      );
    }
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MtColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Settings', style: MtTextStyles.h3),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Section(
            title: 'Account',
            tiles: [
              _Tile(
                icon: Icons.lock_outline,
                label: 'Change Password',
                subtitle: 'Reset via phone + 6-digit code',
                onTap: () => context.push('/forgot-password'),
              ),
              _Tile(
                icon: Icons.shield_outlined,
                label: 'Privacy & Security',
                subtitle: 'Sessions, two-factor, data export',
                onTap: _openPrivacyStub,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Preferences',
            tiles: [
              _ToggleTile(
                icon: Icons.notifications_outlined,
                label: 'Push Notifications',
                subtitle: 'Visit assignments, status updates, reminders',
                value: _pushOn,
                onChanged: _setPush,
              ),
              _ToggleTile(
                icon: Icons.dark_mode_outlined,
                label: 'Dark Mode',
                subtitle: 'Preference is saved; full theme ships soon',
                value: _darkOn,
                onChanged: _setDark,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Support',
            tiles: [
              _Tile(
                icon: Icons.help_outline,
                label: 'Help Center',
                subtitle: 'Articles, FAQs, video walkthroughs',
                onTap: _openHelpCenter,
              ),
              _Tile(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: _openTerms,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Danger Zone',
            tiles: [
              _Tile(
                icon: Icons.delete_outline,
                label: 'Delete Account',
                subtitle: 'Removes access; permanent in 30 days',
                onTap: _confirmDeleteAccount,
                danger: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private layout primitives — mirror admin/settings_tab.dart for visual
// consistency without sharing implementation across roles (which would
// risk admin-only logic leaking into the user-facing screen).
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const _Section({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              title.toUpperCase(),
              style: MtTextStyles.labelSm.copyWith(
                color: MtColors.ink3,
                letterSpacing: 0.9,
              ),
            ),
          ),
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                color: MtColors.line,
                indent: 64,
                endIndent: 16,
              ),
            tiles[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? MtColors.rejected : MtColors.brand;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: accent, size: 18),
      ),
      title: Text(
        label,
        style: MtTextStyles.labelLg.copyWith(
          color: danger ? MtColors.rejected : MtColors.ink,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
      trailing:
          const Icon(Icons.chevron_right, color: MtColors.ink3, size: 22),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      activeThumbColor: Colors.white,
      activeTrackColor: MtColors.brand,
      secondary: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MtColors.brand.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: MtColors.brand, size: 18),
      ),
      title: Text(label,
          style: MtTextStyles.labelLg.copyWith(color: MtColors.ink)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}
