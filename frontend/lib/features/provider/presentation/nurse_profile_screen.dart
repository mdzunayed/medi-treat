import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/nurse_profile.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../providers/nurse_workflow_provider.dart';

/// Phase 3 — the professional nurse profile & credentials registry. A
/// form-driven page (rendered as the 4th bottom-nav tab) that captures the
/// nurse's clinical qualifications and pushes them to the Provider record.
///
/// Layout cap: `Center → ConstrainedBox(maxWidth: 600)` for wide web.
class NurseProfileScreen extends ConsumerWidget {
  const NurseProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nurseProfileProvider);
    return async.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: MtColors.brand),
      ),
      error: (e, _) => _ProfileError(
        message: e.toString(),
        onRetry: () => ref.invalidate(nurseProfileProvider),
      ),
      data: (profile) => _ProfileForm(profile: profile),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  final NurseProfile profile;
  const _ProfileForm({required this.profile});

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  static const _specializations = [
    'General Nursing',
    'ICU Care Specialist',
    'Pediatric Phlebotomy',
    'Post-Surgical Dressing Expert',
  ];

  late final TextEditingController _license =
      TextEditingController(text: widget.profile.nursingLicense);
  late final TextEditingController _experience = TextEditingController(
      text: widget.profile.yearsExperience > 0
          ? '${widget.profile.yearsExperience}'
          : '');
  late final TextEditingController _affiliation =
      TextEditingController(text: widget.profile.hospitalAffiliation);
  late final TextEditingController _bio =
      TextEditingController(text: widget.profile.bio);
  late String? _specialization = _specializations.contains(
          widget.profile.specialization)
      ? widget.profile.specialization
      : (widget.profile.specialization.isEmpty
          ? null
          : widget.profile.specialization);
  bool _saving = false;

  @override
  void dispose() {
    _license.dispose();
    _experience.dispose();
    _affiliation.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.completed,
    ));
  }

  Future<void> _save() async {
    final license = _license.text.trim();
    if (license.isEmpty) {
      _toast('BNMC registration number is required', error: true);
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(dioClientProvider).updateNurseProfile(
            user.id,
            nursingLicense: license,
            specialization: _specialization,
            yearsExperience: int.tryParse(_experience.text.trim()),
            hospitalAffiliation: _affiliation.text.trim(),
            bio: _bio.text.trim(),
          );
      ref.invalidate(nurseProfileProvider);
      _toast('Professional credentials saved.');
    } catch (e) {
      _toast('Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              _IdentityCard(profile: p),
              const SizedBox(height: 18),
              _SectionLabel('Professional medical details'),
              const SizedBox(height: 8),
              _FieldLabel(
                'Bangladesh Nursing & Midwifery Council Reg No.',
                required: true,
              ),
              const SizedBox(height: 6),
              _Field(
                controller: _license,
                hint: 'e.g. BNMC-123456',
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 14),
              _FieldLabel('Nursing specialization'),
              const SizedBox(height: 6),
              _SpecializationDropdown(
                value: _specialization,
                options: _specializations,
                onChanged: (v) => setState(() => _specialization = v),
              ),
              const SizedBox(height: 14),
              _FieldLabel('Years of clinical experience'),
              const SizedBox(height: 6),
              _Field(
                controller: _experience,
                hint: 'e.g. 5',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                suffix: 'years',
              ),
              const SizedBox(height: 14),
              _FieldLabel('Current institutional affiliation'),
              const SizedBox(height: 6),
              _Field(
                controller: _affiliation,
                hint: 'e.g. Dhaka Medical College Hospital',
              ),
              const SizedBox(height: 14),
              _FieldLabel('Professional summary bio'),
              const SizedBox(height: 6),
              _Field(
                controller: _bio,
                hint: 'A short introductory sentence about your practice.',
                maxLines: 3,
              ),
            ],
          ),
        ),
        _SaveBar(busy: _saving, onTap: _save),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Identity card
// ---------------------------------------------------------------------------

class _IdentityCard extends StatelessWidget {
  final NurseProfile profile;
  const _IdentityCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final name = profile.fullName.isEmpty ? 'Nurse' : profile.fullName;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          InitialsAvatar(
            name: name,
            size: 80,
            backgroundColor: MtColors.brandSoft,
            textColor: MtColors.brand,
          ),
          const SizedBox(height: 12),
          Text(name,
              style: MtTextStyles.h2.copyWith(color: MtColors.ink),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          _VerifiedBadge(verified: profile.isVerified),
          if (profile.phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(profile.phone,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
          ],
        ],
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  final bool verified;
  const _VerifiedBadge({required this.verified});

  @override
  Widget build(BuildContext context) {
    final fg = verified ? MtColors.completed : MtColors.ink3;
    final bg = verified ? MtColors.completedBg : MtColors.bg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verified ? Icons.verified : Icons.pending_outlined,
              size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            verified ? 'Verified nurse' : 'Verification pending',
            style: MtTextStyles.labelMd.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form fields
// ---------------------------------------------------------------------------

class _SpecializationDropdown extends StatelessWidget {
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  const _SpecializationDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Tolerate a stored value that's outside the canonical option set by
    // surfacing it as an extra item, so a legacy record doesn't crash the
    // dropdown's single-value assertion.
    final items = <String>{...options, ?value}.toList();
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _decoration(hint: 'Select specialization'),
      items: [
        for (final o in items) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: onChanged,
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final String? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
      decoration: _decoration(hint: hint, suffix: suffix),
    );
  }
}

InputDecoration _decoration({required String hint, String? suffix}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
    suffixText: suffix,
    suffixStyle: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
    filled: true,
    fillColor: MtColors.surface2,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: text,
        style: MtTextStyles.labelMd.copyWith(
            color: MtColors.ink, fontWeight: FontWeight.w700),
        children: required
            ? [
                TextSpan(
                  text: '  *',
                  style: MtTextStyles.labelMd.copyWith(color: MtColors.rejected),
                ),
              ]
            : null,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: MtTextStyles.sectionLabel
          .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _SaveBar({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: MtColors.brand,
            foregroundColor: Colors.white,
            disabledBackgroundColor: MtColors.brandSofter,
            disabledForegroundColor: MtColors.brand,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.save_alt, size: 20),
          label: Text(
            busy ? 'Saving…' : 'Save Professional Credentials',
            style: MtTextStyles.labelLg
                .copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ProfileError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: MtColors.rejected, size: 40),
            const SizedBox(height: 12),
            Text("Couldn't load your profile",
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
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
          ],
        ),
      ),
    );
  }
}
