import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../auth/auth_provider.dart';
import 'admin_table_chrome.dart';

// SharedPreferences keys for the local-only toggles. Once a settings
// backend ships these can move behind a /admin/settings endpoint
// without changing any UI.
const _kAutoAssign = 'admin.allow_auto_assignment';
const _kMaintenance = 'admin.maintenance_mode';
const _kRequireVerified = 'admin.require_verified_doctors';
const _kBetaCharts = 'admin.beta_charts';

class _SettingsValue {
  final bool autoAssign;
  final bool maintenance;
  final bool requireVerified;
  final bool betaCharts;
  const _SettingsValue({
    required this.autoAssign,
    required this.maintenance,
    required this.requireVerified,
    required this.betaCharts,
  });

  static const empty = _SettingsValue(
    autoAssign: false,
    maintenance: false,
    requireVerified: true,
    betaCharts: false,
  );
}

class _SettingsNotifier extends AsyncNotifier<_SettingsValue> {
  SharedPreferences? _prefs;

  @override
  Future<_SettingsValue> build() async {
    _prefs = await SharedPreferences.getInstance();
    return _SettingsValue(
      autoAssign: _prefs?.getBool(_kAutoAssign) ?? false,
      maintenance: _prefs?.getBool(_kMaintenance) ?? false,
      requireVerified: _prefs?.getBool(_kRequireVerified) ?? true,
      betaCharts: _prefs?.getBool(_kBetaCharts) ?? false,
    );
  }

  Future<void> _set(String key, bool value) async {
    await _prefs?.setBool(key, value);
    // Re-read from prefs so the in-memory snapshot stays the canonical
    // source of truth even if multiple toggles fire concurrently.
    state = AsyncData(_SettingsValue(
      autoAssign: _prefs?.getBool(_kAutoAssign) ?? false,
      maintenance: _prefs?.getBool(_kMaintenance) ?? false,
      requireVerified: _prefs?.getBool(_kRequireVerified) ?? true,
      betaCharts: _prefs?.getBool(_kBetaCharts) ?? false,
    ));
  }

  Future<void> setAutoAssign(bool v) => _set(_kAutoAssign, v);
  Future<void> setMaintenance(bool v) => _set(_kMaintenance, v);
  Future<void> setRequireVerified(bool v) => _set(_kRequireVerified, v);
  Future<void> setBetaCharts(bool v) => _set(_kBetaCharts, v);
}

final _settingsProvider =
    AsyncNotifierProvider<_SettingsNotifier, _SettingsValue>(
        _SettingsNotifier.new);

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_settingsProvider);
    final v = async.valueOrNull ?? _SettingsValue.empty;
    final notifier = ref.read(_settingsProvider.notifier);

    return AdminListScaffold(
      title: 'Settings',
      subtitle: 'Operational toggles for the Taafi console',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: 'Dispatch',
            tiles: [
              _ToggleTile(
                icon: Icons.bolt_outlined,
                title: 'Allow auto-assignment',
                subtitle:
                    'When ON, the matcher picks a doctor for low-urgency requests automatically.',
                value: v.autoAssign,
                onChanged: notifier.setAutoAssign,
              ),
              _ToggleTile(
                icon: Icons.verified_user_outlined,
                title: 'Require verified doctors only',
                subtitle:
                    'Pending-verification providers are hidden from the assign team picker.',
                value: v.requireVerified,
                onChanged: notifier.setRequireVerified,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'System',
            tiles: [
              _ToggleTile(
                icon: Icons.construction_outlined,
                title: 'Maintenance mode',
                subtitle:
                    'Suspends patient-facing request submission with a notice banner.',
                value: v.maintenance,
                onChanged: notifier.setMaintenance,
                danger: true,
              ),
              _ToggleTile(
                icon: Icons.insights_outlined,
                title: 'Beta charts',
                subtitle:
                    'Enables experimental visualizations on the Overview tab.',
                value: v.betaCharts,
                onChanged: notifier.setBetaCharts,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _AdminAccessSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-admin onboarding
// ---------------------------------------------------------------------------

class _AdminAccessSection extends StatelessWidget {
  const _AdminAccessSection();

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'ADMINISTRATION',
              style: MtTextStyles.labelSm
                  .copyWith(color: MtColors.ink3, letterSpacing: 0.9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 16, 18),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MtColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings_outlined,
                      color: MtColors.brand, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Onboard new admin',
                          style: MtTextStyles.labelLg
                              .copyWith(color: MtColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        'Securely grant a colleague secondary admin access. Requires your verified admin session.',
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const _OnboardAdminDialog(),
                  ),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text('Onboard New Admin',
                      style:
                          MtTextStyles.labelLg.copyWith(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MtColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Secure onboarding modal — captures the new admin's identity and a
/// password that must be typed twice. Submit is gated on a matching
/// double-confirmation to prevent spoofing/typos before the account is
/// minted with `role: 'admin'`.
class _OnboardAdminDialog extends ConsumerStatefulWidget {
  const _OnboardAdminDialog();

  @override
  ConsumerState<_OnboardAdminDialog> createState() =>
      _OnboardAdminDialogState();
}

class _OnboardAdminDialogState extends ConsumerState<_OnboardAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(dioClientProvider).registerSubAdmin(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            phone: _phone.text.trim(),
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Admin "${_name.text.trim()}" onboarded.'),
        backgroundColor: MtColors.completed,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Could not onboard admin: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MtColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: MtColors.brandSofter,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.admin_panel_settings_outlined,
                            color: MtColors.brand, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Onboard New Admin',
                            style: MtTextStyles.h3.copyWith(
                                color: MtColors.ink,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _OnboardField(
                    controller: _name,
                    label: 'Full name',
                    hint: 'Tania Akter',
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _email,
                    label: 'Email',
                    hint: 'admin@taafi.app',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Email is required';
                      if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(s)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _phone,
                    label: 'Phone (optional)',
                    hint: '+8801…',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _password,
                    label: 'Password',
                    hint: 'At least 8 characters',
                    obscure: _obscure,
                    trailing: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: MtColors.ink3,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (v) => (v ?? '').length < 8
                        ? 'Use at least 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _confirm,
                    label: 'Confirm password',
                    hint: 'Re-enter the password',
                    obscure: _obscure,
                    validator: (v) => v != _password.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                            foregroundColor: MtColors.ink2),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MtColors.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(_busy ? 'Creating…' : 'Create admin',
                            style: MtTextStyles.labelLg
                                .copyWith(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _OnboardField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
    this.trailing,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: MtTextStyles.labelMd.copyWith(
                color: MtColors.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          validator: validator,
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
            suffixIcon: trailing,
            filled: true,
            fillColor: MtColors.surface2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              borderSide: const BorderSide(color: MtColors.brand, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const _Section({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              title.toUpperCase(),
              style: MtTextStyles.labelSm.copyWith(
                color: MtColors.ink3,
                letterSpacing: 0.9,
              ),
            ),
          ),
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: MtColors.line),
            tiles[i],
          ],
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool danger;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? MtColors.rejected : MtColors.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: MtTextStyles.labelLg
                        .copyWith(color: MtColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: accent,
          ),
        ],
      ),
    );
  }
}
