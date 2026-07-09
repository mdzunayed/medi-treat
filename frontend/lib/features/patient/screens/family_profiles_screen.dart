import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/dependent.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../auth/auth_provider.dart';
import '../profile/patient_lifecycle_providers.dart';

const List<String> _kRelationships = [
  'parent',
  'child',
  'spouse',
  'sibling',
  'other',
];
const List<String> _kGenders = ['male', 'female', 'other', 'unspecified'];

/// The patient's family / dependents medical-profile matrix. Saved members
/// can be booked on behalf of from the New Request screen.
class FamilyProfilesScreen extends ConsumerWidget {
  const FamilyProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dependentsProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Family Profiles',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MtColors.brand,
        foregroundColor: Colors.white,
        onPressed: () {
          HapticFeedback.lightImpact();
          _openEditor(context, null);
        },
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add member'),
      ),
      body: RefreshIndicator(
        color: MtColors.brand,
        onRefresh: () async => ref.invalidate(dependentsProvider),
        child: async.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: MtColors.brand)),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MtErrorState(
                title: "Couldn't load family profiles",
                message: e.toString(),
                onRetry: () => ref.invalidate(dependentsProvider),
              ),
            ],
          ),
          data: (members) {
            if (members.isEmpty) return const _EmptyFamily();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _MemberCard(member: members[i]),
            );
          },
        ),
      ),
    );
  }

  static void _openEditor(BuildContext context, Dependent? existing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MtColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MemberEditorSheet(existing: existing),
    );
  }
}

class _MemberCard extends ConsumerWidget {
  final Dependent member;
  const _MemberCard({required this.member});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${member.fullName} from your family profiles?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(dioClientProvider).deleteDependent(member.id);
      ref.invalidate(dependentsProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: MtColors.rejected,
        content: Text("Couldn't remove: $e"),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNotes = member.criticalAllergiesMedicalHistory.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline,
                    color: MtColors.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.fullName,
                        style: MtTextStyles.labelLg.copyWith(
                            color: MtColors.ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        member.relationshipLabel,
                        if (member.dateOfBirth.isNotEmpty)
                          'DOB ${member.dateOfBirth}',
                      ].join(' · '),
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: MtColors.ink3),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  FamilyProfilesScreen._openEditor(context, member);
                },
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: MtColors.rejected),
                onPressed: () => _delete(context, ref),
              ),
            ],
          ),
          if (hasNotes) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(member.criticalAllergiesMedicalHistory,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink2)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Editor sheet ────────────────────────────────────────────────────────────

class _MemberEditorSheet extends ConsumerStatefulWidget {
  final Dependent? existing;
  const _MemberEditorSheet({this.existing});

  @override
  ConsumerState<_MemberEditorSheet> createState() => _MemberEditorSheetState();
}

class _MemberEditorSheetState extends ConsumerState<_MemberEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.fullName ?? '');
  late final TextEditingController _dob =
      TextEditingController(text: widget.existing?.dateOfBirth ?? '');
  late final TextEditingController _history = TextEditingController(
      text: widget.existing?.criticalAllergiesMedicalHistory ?? '');
  late String _gender = widget.existing?.gender ?? 'unspecified';
  late String _relationship = widget.existing?.relationshipTag ?? 'other';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _dob.dispose();
    _history.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.vibrate();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      await ref.read(dioClientProvider).saveDependent(
            id: widget.existing?.id,
            fullName: _name.text.trim(),
            dateOfBirth: _dob.text.trim(),
            gender: _gender,
            relationshipTag: _relationship,
            criticalAllergiesMedicalHistory: _history.text.trim(),
          );
      ref.invalidate(dependentsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: MtColors.completed,
        content: Text('Family member saved.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: MtColors.rejected,
        content: Text("Couldn't save: $e"),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
              Text(widget.existing == null ? 'Add member' : 'Edit member',
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
              const SizedBox(height: 16),
              _field(_name, 'Full name', validator: true),
              const SizedBox(height: 12),
              _field(_dob, 'Date of birth (e.g. 2015-04-12)'),
              const SizedBox(height: 14),
              _label('Relationship'),
              _chips(_kRelationships, _relationship,
                  (v) => setState(() => _relationship = v)),
              const SizedBox(height: 12),
              _label('Gender'),
              _chips(
                  _kGenders, _gender, (v) => setState(() => _gender = v)),
              const SizedBox(height: 12),
              _field(_history,
                  'Critical allergies / medical history (visible to the clinician)',
                  maxLines: 3),
              const SizedBox(height: 16),
              MtButton(
                label: 'Save member',
                leadingIcon: Icons.check_circle_outline,
                isLoading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
      );

  Widget _chips(
      List<String> options, String selected, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o[0].toUpperCase() + o.substring(1)),
            selected: selected == o,
            selectedColor: MtColors.brandSoft,
            labelStyle: MtTextStyles.labelMd.copyWith(
              color: selected == o ? MtColors.brand : MtColors.ink2,
              fontWeight: FontWeight.w700,
            ),
            side: BorderSide(
                color: selected == o ? MtColors.brand : MtColors.line),
            backgroundColor: MtColors.surface,
            onSelected: (_) {
              HapticFeedback.lightImpact();
              onPick(o);
            },
          ),
      ],
    );
  }

  Widget _field(TextEditingController c, String hint,
      {bool validator = false, int maxLines = 1}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: MtColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
      ),
      validator: validator
          ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
          : null,
    );
  }
}

class _EmptyFamily extends StatelessWidget {
  const _EmptyFamily();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.family_restroom,
            size: 46, color: MtColors.ink3.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text('No family members yet',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 4),
        Text('Add a dependent to book care on their behalf.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
      ],
    );
  }
}
