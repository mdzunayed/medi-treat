import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/service_catalog_providers.dart';
import '../../../core/models/dependent.dart';
import '../../../core/models/saved_address.dart';
import '../../../core/models/service_catalog_item.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/mt_empty_state.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../navigation/patient_nav_provider.dart';
import '../new_request/new_request_notifier.dart';
import '../new_request/new_request_state.dart';
import '../profile/patient_lifecycle_providers.dart';
import 'select_address_sheet.dart';

/// New care-request flow. Pure ConsumerWidget — all form state lives in
/// [newRequestProvider], all dependency data flows through Riverpod providers.
class NewRequestTab extends ConsumerStatefulWidget {
  const NewRequestTab({super.key});

  @override
  ConsumerState<NewRequestTab> createState() => _NewRequestTabState();
}

class _NewRequestTabState extends ConsumerState<NewRequestTab> {
  late final TextEditingController _notesController;
  bool _showLandmarkField = false;
  late final TextEditingController _landmarkController;
  // Tracks whether the form has been hydrated from the notifier on first
  // build, so we don't fight the user every time they type.
  String? _lastNotesSnapshot;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _landmarkController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  void _syncControllers(NewRequestState s) {
    // Only push notifier changes into the controller when they originate from
    // outside (e.g. prefill). Typing back through the controller already
    // updates the notifier via onChanged.
    if (_lastNotesSnapshot != s.notes && s.notes != _notesController.text) {
      _notesController.text = s.notes;
      _notesController.selection = TextSelection.collapsed(
        offset: s.notes.length,
      );
    }
    _lastNotesSnapshot = s.notes;

    final landmark = s.address.landmark ?? '';
    if (landmark != _landmarkController.text) {
      _landmarkController.text = landmark;
      _landmarkController.selection = TextSelection.collapsed(
        offset: landmark.length,
      );
    }
    if (landmark.isNotEmpty && !_showLandmarkField) {
      _showLandmarkField = true;
    }
  }

  Future<void> _handleSubmit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = await ref.read(newRequestProvider.notifier).submit();
    if (!mounted) return;

    if (id == null) {
      // Failure path. `cachedLocally` distinguishes a network outage
      // (preserved form, retry possible) from a validation / unexpected
      // error. The icon hints the user that nothing was lost.
      final postState = ref.read(newRequestProvider);
      final isOffline = postState.cachedLocally;
      final err = postState.validationError;
      if (err != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isOffline ? Icons.cloud_off : Icons.error_outline,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(err)),
              ],
            ),
            backgroundColor: MtColors.rejected,
            duration: Duration(seconds: isOffline ? 5 : 4),
          ),
        );
      }
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text('Request $id submitted to medi-treat admin'),
        backgroundColor: MtColors.completed,
      ),
    );
    // Clear the submission flag so the button re-enables if the patient
    // stays on the form (e.g. for a second submission later).
    ref.read(newRequestProvider.notifier).clearSubmissionStatus();
    // Route the patient to the Activities → "Under Review" sub-tab.
    // The bottom-nav shell exposes a single `goToActivities(...)`
    // helper that coordinates both providers atomically — no widget
    // here has to know which destination owns which sub-tab.
    if (!mounted) return;
    ref.goToActivities(sub: PatientActivitiesTab.underReview);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newRequestProvider);
    final servicesAsync = ref.watch(activeServicesProvider);
    _syncControllers(state);

    // Auto-select the first service once the catalog loads — keeps the form
    // immediately usable rather than blocking on an explicit tap.
    ref.listen<AsyncValue<List<ServiceCatalogItem>>>(activeServicesProvider,
        (prev, next) {
      next.whenData((list) {
        final current = ref.read(newRequestProvider).selectedService;
        if (current == null && list.isNotEmpty) {
          // Defer to the next frame so we don't mutate state mid-build.
          Future.microtask(() {
            if (!mounted) return;
            final stillEmpty =
                ref.read(newRequestProvider).selectedService == null;
            if (stillEmpty) {
              ref.read(newRequestProvider.notifier).selectService(list.first);
            }
          });
        }
      });
    });

    // Hydrate the location card from the user's saved-address book. The API
    // returns the default (`is_default`) address first, so `list.first` is the
    // primary. We only apply it while the form still has no address chosen, so
    // we never stomp a selection the patient made via the address picker.
    ref.listen<AsyncValue<List<SavedAddress>>>(savedAddressesProvider,
        (prev, next) {
      next.whenData((list) {
        if (list.isEmpty) return;
        if (!ref.read(newRequestProvider).address.isEmpty) return;
        Future.microtask(() {
          if (!mounted) return;
          if (!ref.read(newRequestProvider).address.isEmpty) return;
          ref
              .read(newRequestProvider.notifier)
              .applyAddress(_toRequestAddress(list.first));
        });
      });
    });

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
      children: [
        _Header(
          onBack: ref.goToHome,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              const _SectionHeader(en: 'Type of care', bn: 'সেবার ধরন'),
              const SizedBox(height: 8),
              _ServiceSelector(
                async: servicesAsync,
                selectedId: state.selectedService?.id,
              ),
              const SizedBox(height: 20),
              const _SectionHeader(
                en: 'Who is this care session for?',
                bn: 'এই সেবা কার জন্য?',
              ),
              const SizedBox(height: 8),
              _CareRecipientChips(selected: state.careRecipient),
              const SizedBox(height: 20),
              const _SectionHeader(
                en: 'Patient location',
                bn: 'রোগীর ঠিকানা',
              ),
              const SizedBox(height: 8),
              _LocationCard(
                address: state.address,
                showLandmarkField: _showLandmarkField,
                landmarkController: _landmarkController,
                onEdit: () => _openAddressPicker(context, ref),
                onToggleLandmark: () =>
                    setState(() => _showLandmarkField = !_showLandmarkField),
                onLandmarkChanged: (v) =>
                    ref.read(newRequestProvider.notifier).setLandmark(
                          v.trim().isEmpty ? null : v.trim(),
                        ),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(en: 'When', bn: 'কখন'),
              const SizedBox(height: 8),
              _WhenSelector(
                timing: state.timing,
                scheduledAt: state.scheduledAt,
                onAsap: () => ref
                    .read(newRequestProvider.notifier)
                    .setTiming(RequestTiming.asSoonAsPossible),
                onSchedule: () => _pickSchedule(context, ref, state),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(
                en: 'Notes for medical team',
                bn: 'চিকিৎসা সংক্রান্ত তথ্য',
              ),
              const SizedBox(height: 8),
              _NotesCard(
                controller: _notesController,
                attachments: state.attachments,
                onNotesChanged: (v) =>
                    ref.read(newRequestProvider.notifier).setNotes(v),
                onAttachDischarge: () => _attachDischarge(context, ref),
                onAttachVitals: () => _attachVitals(context, ref, state),
                onAttachVoice: () => _attachVoiceNote(context, ref),
                onClearDischarge: () =>
                    ref.read(newRequestProvider.notifier).setDischarge(null),
                onClearVitals: () =>
                    ref.read(newRequestProvider.notifier).setVitals(null),
                onClearVoice: () =>
                    ref.read(newRequestProvider.notifier).setVoiceNote(null),
              ),
              if (state.validationError != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: state.validationError ?? ''),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
        _SubmitBar(
          enabled: state.selectedService != null &&
              !state.address.isEmpty &&
              !state.isSubmitting,
          isLoading: state.isSubmitting,
          onSubmit: () => _handleSubmit(context, ref),
        ),
      ],
      ),
    );
  }

  // --------------------------------------------------------------- dialogs

  // Checkout address selection — opens the saved-address picker. Tapping a
  // saved card applies its structured fields + GPS coordinates straight into
  // the booking state; the sheet's "Manage / add" routes to the full editor.
  Future<void> _openAddressPicker(BuildContext context, WidgetRef ref) async {
    final picked = await showSelectAddressSheet(context);
    if (picked == null) return;
    ref.read(newRequestProvider.notifier).applyAddress(_toRequestAddress(picked));
  }

  /// Maps a saved-address-book entry into the booking form's [RequestAddress].
  /// Shared by the address picker and the default-address hydration listener
  /// so both produce an identical shape.
  static RequestAddress _toRequestAddress(SavedAddress a) {
    return RequestAddress(
      line1: a.flatFloorHolding,
      areaCityZip: a.fullAddressText,
      label: a.label,
      landmark: a.landmarkInstructions.trim().isEmpty
          ? null
          : a.landmarkInstructions.trim(),
      latitude: a.latitude,
      longitude: a.longitude,
    );
  }

  Future<void> _pickSchedule(
    BuildContext context,
    WidgetRef ref,
    NewRequestState state,
  ) async {
    final now = DateTime.now();
    final initialDate = state.scheduledAt ?? now.add(const Duration(hours: 4));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now) ? now : initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: MtColors.brand,
            onPrimary: Colors.white,
            onSurface: MtColors.ink,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      // ignore: use_build_context_synchronously
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: MtColors.brand,
            onPrimary: Colors.white,
            onSurface: MtColors.ink,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    ref.read(newRequestProvider.notifier).setScheduledAt(picked);
  }

  Future<void> _attachDischarge(BuildContext context, WidgetRef ref) async {
    // Production-ready placeholder: opens a dialog asking the patient to
    // confirm they have a discharge summary on file. Wires to file_picker
    // in a follow-up pass without changing this UI surface.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Attach discharge summary', style: MtTextStyles.h3),
        content: Text(
          'Confirm the patient has a discharge summary or recent prescription. The doctor team will review it on arrival.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.brand),
            child: Text('Attach', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(newRequestProvider.notifier).setDischarge('discharge_summary.pdf');
    }
  }

  Future<void> _attachVitals(
    BuildContext context,
    WidgetRef ref,
    NewRequestState state,
  ) async {
    final existing = state.attachments.vitals;
    final bpCtrl = TextEditingController();
    final hrCtrl = TextEditingController();
    final tempCtrl = TextEditingController();

    // If we already have a vitals string, pre-fill best-effort.
    if (existing != null) {
      final bp = RegExp(r'BP\s+([0-9/]+)').firstMatch(existing)?.group(1);
      final hr = RegExp(r'HR\s+([0-9]+)').firstMatch(existing)?.group(1);
      final tp = RegExp(r'Temp\s+([0-9.]+)').firstMatch(existing)?.group(1);
      if (bp != null) bpCtrl.text = bp;
      if (hr != null) hrCtrl.text = hr;
      if (tp != null) tempCtrl.text = tp;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Add vitals', style: MtTextStyles.h3),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(
                controller: bpCtrl,
                label: 'Blood pressure (e.g. 120/80)',
                keyboardType: TextInputType.text,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _DialogField(
                controller: hrCtrl,
                label: 'Heart rate (bpm)',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 12),
              _DialogField(
                controller: tempCtrl,
                label: 'Temperature (°F)',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.brand),
            child: Text('Save', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );

    if (result == true) {
      final parts = <String>[];
      if (bpCtrl.text.trim().isNotEmpty) parts.add('BP ${bpCtrl.text.trim()}');
      if (hrCtrl.text.trim().isNotEmpty) parts.add('HR ${hrCtrl.text.trim()}');
      if (tempCtrl.text.trim().isNotEmpty) {
        parts.add('Temp ${tempCtrl.text.trim()}°F');
      }
      final summary = parts.isEmpty ? null : parts.join(' · ');
      ref.read(newRequestProvider.notifier).setVitals(summary);
    }
    bpCtrl.dispose();
    hrCtrl.dispose();
    tempCtrl.dispose();
  }

  Future<void> _attachVoiceNote(BuildContext context, WidgetRef ref) async {
    // Simulated record dialog (real audio recording will be wired in a
    // follow-up). Times a fake recording so the chip shows a duration label.
    final seconds = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _VoiceRecorderDialog(),
    );
    if (seconds != null && seconds > 0) {
      final label = 'voice_note_${seconds}s.m4a';
      ref.read(newRequestProvider.notifier).setVoiceNote(label);
    }
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MtColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: MtColors.ink),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New care request',
                        style: MtTextStyles.h3.copyWith(color: MtColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Step 1 of 1 · All details',
                        style: MtTextStyles.bodySm.copyWith(
                          color: MtColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 4,
            color: MtColors.line,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.4,
              child: Container(color: MtColors.brand),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String en;
  final String? bn;
  const _SectionHeader({required this.en, this.bn});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          en.toUpperCase(),
          style: MtTextStyles.sectionLabel.copyWith(
            color: MtColors.ink3,
            letterSpacing: 1.0,
          ),
        ),
        if (bn != null)
          Text(
            bn ?? '',
            style: MtTextStyles.sectionLabel.copyWith(
              color: MtColors.ink3,
              fontFamily: 'Kalpurush',
            ),
          ),
      ],
    );
  }
}

class _ServiceSelector extends ConsumerWidget {
  final AsyncValue<List<ServiceCatalogItem>> async;
  final String? selectedId;

  const _ServiceSelector({
    required this.async,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<ServiceCatalogItem>>(
      value: async,
      onRetry: () => ref.refresh(activeServicesProvider),
      loadingBuilder: (_) => Column(
        children: List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MtSkeleton.box(height: 76, radius: 12),
          ),
        ),
      ),
      isEmpty: (list) => list.isEmpty,
      emptyBuilder: (_) => const MtEmptyState(
        icon: Icons.medical_services_outlined,
        title: 'No services available',
        subtitle: 'New services will appear here once the admin team enables them.',
      ),
      dataBuilder: (_, items) {
        return Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _CareTypeOption(
                item: items[i],
                selected: items[i].id == selectedId,
                onTap: () => ref
                    .read(newRequestProvider.notifier)
                    .selectService(items[i]),
              ),
              if (i != items.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _CareTypeOption extends StatelessWidget {
  final ServiceCatalogItem item;
  final bool selected;
  final VoidCallback onTap;

  const _CareTypeOption({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: selected ? MtColors.brandSofter : MtColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? MtColors.brand : MtColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _Radio(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                    ),
                    if (item.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.category,
                        style: MtTextStyles.bodySm.copyWith(
                          color: MtColors.ink2,
                          fontFamily: 'Kalpurush',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  const _Radio({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? MtColors.brand : MtColors.ink3,
          width: 2,
        ),
        color: selected ? MtColors.brand : Colors.transparent,
      ),
      child: selected
          ? const Center(
              child: Icon(Icons.circle, size: 8, color: Colors.white),
            )
          : null,
    );
  }
}

class _LocationCard extends StatelessWidget {
  final RequestAddress address;
  final bool showLandmarkField;
  final TextEditingController landmarkController;
  final VoidCallback onEdit;
  final VoidCallback onToggleLandmark;
  final ValueChanged<String> onLandmarkChanged;

  const _LocationCard({
    required this.address,
    required this.showLandmarkField,
    required this.landmarkController,
    required this.onEdit,
    required this.onToggleLandmark,
    required this.onLandmarkChanged,
  });

  @override
  Widget build(BuildContext context) {
    // No saved address yet — prompt the patient to add one. Submission is
    // blocked (see `_SubmitBar.enabled`) until a real address is chosen.
    if (address.isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MtColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MtColors.brand, width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MtColors.brandSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_location_alt_outlined,
                      color: MtColors.brand, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add your address', style: MtTextStyles.labelLg),
                      const SizedBox(height: 2),
                      Text(
                        'Choose where the medical team should visit',
                        style:
                            MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: MtColors.ink3),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MtColors.brandSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: MtColors.brand,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address.line1,
                        style: MtTextStyles.labelLg,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${address.areaCityZip} · ${address.label}',
                        style: MtTextStyles.bodySm.copyWith(
                          color: MtColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18, color: MtColors.ink3),
                  onPressed: onEdit,
                  tooltip: 'Edit address',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MtColors.line),
          if (!showLandmarkField)
            InkWell(
              onTap: onToggleLandmark,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 18, color: MtColors.ink2),
                    const SizedBox(width: 6),
                    Text(
                      'Add landmark or unit number',
                      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 18, color: MtColors.ink2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: landmarkController,
                      onChanged: onLandmarkChanged,
                      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        hintText: 'Landmark, floor, or unit number',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      landmarkController.clear();
                      onLandmarkChanged('');
                      onToggleLandmark();
                    },
                    icon: const Icon(Icons.close, size: 18, color: MtColors.ink3),
                    tooltip: 'Remove landmark',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WhenSelector extends StatelessWidget {
  final RequestTiming timing;
  final DateTime? scheduledAt;
  final VoidCallback onAsap;
  final VoidCallback onSchedule;

  const _WhenSelector({
    required this.timing,
    required this.scheduledAt,
    required this.onAsap,
    required this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final scheduledLabel = scheduledAt == null
        ? 'Pick a date & time'
        : DateFormat('EEE d MMM · h:mm a').format(scheduledAt ?? DateTime.now());
    return Row(
      children: [
        Expanded(
          child: _WhenCard(
            title: 'As soon as possible',
            subtitle: '~45 min dispatch',
            selected: timing == RequestTiming.asSoonAsPossible,
            onTap: onAsap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _WhenCard(
            title: 'Schedule',
            subtitle: scheduledLabel,
            selected: timing == RequestTiming.scheduled,
            onTap: onSchedule,
          ),
        ),
      ],
    );
  }
}

class _WhenCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _WhenCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? MtColors.brandSofter : MtColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? MtColors.brand : MtColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  final TextEditingController controller;
  final RequestAttachments attachments;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onAttachDischarge;
  final VoidCallback onAttachVitals;
  final VoidCallback onAttachVoice;
  final VoidCallback onClearDischarge;
  final VoidCallback onClearVitals;
  final VoidCallback onClearVoice;

  const _NotesCard({
    required this.controller,
    required this.attachments,
    required this.onNotesChanged,
    required this.onAttachDischarge,
    required this.onAttachVitals,
    required this.onAttachVoice,
    required this.onClearDischarge,
    required this.onClearVitals,
    required this.onClearVoice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: onNotesChanged,
            maxLines: 4,
            minLines: 2,
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              hintText: 'Add details for the medical team…',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AttachChip(
                icon: Icons.description_outlined,
                emptyLabel: 'Attach discharge',
                value: attachments.discharge,
                onTap: onAttachDischarge,
                onClear: onClearDischarge,
              ),
              _AttachChip(
                icon: Icons.favorite_outline,
                emptyLabel: 'Add vitals',
                value: attachments.vitals,
                onTap: onAttachVitals,
                onClear: onClearVitals,
              ),
              _AttachChip(
                icon: Icons.mic_none,
                emptyLabel: 'Voice note',
                value: attachments.voiceNote,
                onTap: onAttachVoice,
                onClear: onClearVoice,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachChip extends StatelessWidget {
  final IconData icon;
  final String emptyLabel;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _AttachChip({
    required this.icon,
    required this.emptyLabel,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.trim().isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: filled ? MtColors.brand : MtColors.brandSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                filled ? Icons.check_circle : icon,
                size: 14,
                color: filled ? Colors.white : MtColors.brand,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  filled ? (value ?? '') : emptyLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelSm.copyWith(
                    color: filled ? Colors.white : MtColors.brand,
                  ),
                ),
              ),
              if (filled) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.rejected.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: MtColors.rejected, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  final bool enabled;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _SubmitBar({
    required this.enabled,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pricing is negotiated by the admin team after submission, so
            // there's no patient-facing total here — just set expectations.
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: MtColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Admin will contact you directly to finalize service payment terms.',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: enabled ? onSubmit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MtColors.brand,
                  disabledBackgroundColor: MtColors.line,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isLoading) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Submitting…',
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white),
                      ),
                    ] else ...[
                      const Icon(Icons.send, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Submit to Medi-Treat admin',
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;

  const _DialogField({
    required this.controller,
    required this.label,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      autofocus: autofocus,
      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
    );
  }
}

/// Simulated voice recorder dialog. Counts seconds while held; returns the
/// elapsed seconds when the user taps Stop. Real audio capture is wired in a
/// follow-up — this widget's contract (returns an `int`) doesn't change.
class _VoiceRecorderDialog extends StatefulWidget {
  const _VoiceRecorderDialog();

  @override
  State<_VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<_VoiceRecorderDialog> {
  int _seconds = 0;
  bool _recording = false;
  Stream<int>? _ticker;
  // ignore: cancel_subscriptions
  // Use a periodic stream tied to a microtask cancellation flag.
  bool _disposed = false;

  void _toggleRecord() {
    if (_recording) {
      setState(() => _recording = false);
      return;
    }
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _ticker = Stream.periodic(const Duration(seconds: 1), (i) => i + 1);
    _ticker?.listen((v) {
      if (_disposed || !_recording) return;
      setState(() => _seconds = v);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text('Voice note', style: MtTextStyles.h3),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _toggleRecord,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording ? MtColors.rejected : MtColors.brand,
                boxShadow: [
                  BoxShadow(
                    color: (_recording ? MtColors.rejected : MtColors.brand)
                        .withValues(alpha: 0.30),
                    blurRadius: 18,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                _recording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _seconds == 0
                ? 'Tap to start recording'
                : _formatSeconds(_seconds),
            style: MtTextStyles.h3.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            _recording
                ? 'Recording… tap to stop'
                : 'Max 60 seconds. Doctors review before arrival.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Cancel', style: MtTextStyles.labelMd),
        ),
        TextButton(
          onPressed: _seconds > 0 && !_recording
              ? () => Navigator.of(context).pop(_seconds)
              : null,
          style: TextButton.styleFrom(foregroundColor: MtColors.brand),
          child: Text('Save', style: MtTextStyles.labelMd),
        ),
      ],
    );
  }

  String _formatSeconds(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}

/// Horizontal "Who is this for?" chips: `Myself` (default) followed by the
/// patient's saved family members. Selecting a member binds their profile +
/// critical history into the outbound booking via `setCareRecipient`.
class _CareRecipientChips extends ConsumerWidget {
  final CareRecipient? selected;
  const _CareRecipientChips({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dependentsProvider);
    final dependents = async.valueOrNull ?? const <Dependent>[];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            label: 'Myself',
            icon: Icons.person,
            active: selected == null,
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(newRequestProvider.notifier).setCareRecipient(null);
            },
          ),
          for (final d in dependents)
            _chip(
              label: d.fullName,
              icon: Icons.family_restroom,
              active: selected?.dependentId == d.id,
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(newRequestProvider.notifier).setCareRecipient(
                      CareRecipient(
                        dependentId: d.id,
                        name: d.fullName,
                        relationship: d.relationshipTag,
                        medicalNotes: d.criticalAllergiesMedicalHistory,
                      ),
                    );
              },
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? MtColors.brandSoft : MtColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? MtColors.brand : MtColors.line,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16, color: active ? MtColors.brand : MtColors.ink3),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: MtTextStyles.labelMd.copyWith(
                    color: active ? MtColors.brand : MtColors.ink2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
