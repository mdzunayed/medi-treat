import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/api/promo_banner_providers.dart';
import '../../../../core/models/promo_banner.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_button.dart';
import '../../../../core/widgets/mt_toast.dart';
import 'app_open_ad_panel.dart';

/// Curated two-stop gradient presets for the banner background. Stored on the
/// banner as a `List<String>` of HEX stops. Includes the rich orange-brown and
/// midnight-purple looks the Home slider uses.
class _GradientPreset {
  final String name;
  final List<String> colors;
  const _GradientPreset(this.name, this.colors);
}

const List<_GradientPreset> _kBannerGradientPresets = [
  _GradientPreset('Orange brown', ['#7C2D12', '#EA580C']),
  _GradientPreset('Midnight purple', ['#4C1D95', '#8B5CF6']),
  _GradientPreset('Clinical teal', ['#0F766E', '#2DD4BF']),
  _GradientPreset('Sapphire', ['#1E3A8A', '#3B82F6']),
  _GradientPreset('Emerald', ['#065F46', '#10B981']),
  _GradientPreset('Rose', ['#9F1239', '#FB7185']),
  _GradientPreset('Slate', ['#0F172A', '#475569']),
];

/// Admin CRUD + drag-to-reorder management for the patient Home promo banners.
///
/// Mirrors [ManageServicesTab] (scroll body + white list card + add/edit
/// [Dialog] + inline active toggle + edit/delete menu), and adds a
/// [ReorderableListView] whose drops persist the new `priorityOrder` via
/// `PromoBannerRepository.reorder`.
class AdminBannerManagementPage extends ConsumerWidget {
  const AdminBannerManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allBannersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Singleton app-open interstitial campaign — managed alongside the
          // Home-slider banners since both are patient-facing ad surfaces.
          const AppOpenAdPanel(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      async.maybeWhen(
                        data: (items) =>
                            '${items.length} banner${items.length == 1 ? '' : 's'}',
                        orElse: () => '',
                      ),
                      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Drag the handle to reorder — lower rows show first on the app home.',
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: MtButton(
                  label: 'Add banner',
                  leadingIcon: Icons.add,
                  onPressed: () => _openForm(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MtColors.line),
            ),
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorBlock(
                message: e.toString(),
                onRetry: () => ref.refresh(allBannersProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'No banners yet. Click "Add banner" to create the first one.',
                        style: MtTextStyles.bodyMd,
                      ),
                    ),
                  );
                }
                return ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  onReorder: (oldIndex, newIndex) =>
                      _onReorder(context, ref, items, oldIndex, newIndex),
                  itemBuilder: (context, i) => _BannerRow(
                    key: ValueKey(items[i].id),
                    banner: items[i],
                    index: i,
                    isLast: i == items.length - 1,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onReorder(
    BuildContext context,
    WidgetRef ref,
    List<PromoBanner> items,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView reports newIndex as the slot *before* removal.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final ids = reordered.map((b) => b.id).toList();
    try {
      await ref.read(promoBannerRepositoryProvider).reorder(ids);
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }

  static void _openForm(BuildContext context, WidgetRef ref,
      {PromoBanner? existing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _BannerFormDialog(existing: existing),
    );
  }
}

class _BannerRow extends ConsumerWidget {
  final PromoBanner banner;
  final int index;
  final bool isLast;
  const _BannerRow({
    required this.banner,
    required this.index,
    required this.isLast,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(promoBannerRepositoryProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: MtColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle_rounded, color: MtColors.ink3),
              ),
            ),
            _BannerThumb(banner: banner),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    banner.tagText,
                    style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    banner.title.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.labelLg,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  banner.buttonText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.brand700),
                ),
              ),
            ),
            Row(
              children: [
                Switch(
                  value: banner.isActive,
                  activeColor: MtColors.brand,
                  onChanged: (v) async {
                    try {
                      await repo.setStatus(banner.id, v);
                    } catch (e) {
                      if (!context.mounted) return;
                      final (title, message) = mapBannerError(e);
                      MtToast.error(context, title, message);
                    }
                  },
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 58,
                  child: Text(
                    banner.isActive ? 'Active' : 'Hidden',
                    style: MtTextStyles.labelMd.copyWith(
                      color: banner.isActive ? MtColors.completed : MtColors.ink3,
                    ),
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: MtColors.ink2),
              onSelected: (action) async {
                if (action == 'edit') {
                  AdminBannerManagementPage._openForm(context, ref,
                      existing: banner);
                } else if (action == 'delete') {
                  await _confirmDelete(context, ref, banner);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, PromoBanner banner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete banner?'),
        content: Text(
            '"${banner.title.replaceAll('\n', ' ')}" will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(promoBannerRepositoryProvider).delete(banner);
      if (!context.mounted) return;
      MtToast.success(context, 'Banner deleted');
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }
}

/// A small rounded preview of the banner — its image if present, else its
/// gradient.
class _BannerThumb extends StatelessWidget {
  final PromoBanner banner;
  const _BannerThumb({required this.banner});

  @override
  Widget build(BuildContext context) {
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 44,
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: banner.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _gradientBox(),
                errorWidget: (_, __, ___) => _gradientBox(),
              )
            : _gradientBox(),
      ),
    );
  }

  Widget _gradientBox() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: banner.gradient,
          ),
        ),
      );
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: MtColors.rejected, size: 32),
          const SizedBox(height: 12),
          Text(message, style: MtTextStyles.bodyMd, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SizedBox(
            width: 140,
            child: MtButton(label: 'Retry', onPressed: onRetry, isOutlined: true),
          ),
        ],
      ),
    );
  }
}

// --- Form dialog ------------------------------------------------------------

class _BannerFormDialog extends ConsumerStatefulWidget {
  final PromoBanner? existing;
  const _BannerFormDialog({this.existing});

  @override
  ConsumerState<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends ConsumerState<_BannerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tagText;
  late final TextEditingController _title;
  late final TextEditingController _buttonText;
  late List<String> _gradient;
  late bool _isActive;
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tagText = TextEditingController(text: e?.tagText ?? '');
    _title = TextEditingController(text: e?.title ?? '');
    _buttonText = TextEditingController(text: e?.buttonText ?? '');
    _gradient = e?.gradientColors ?? _kBannerGradientPresets.first.colors;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _tagText.dispose();
    _title.dispose();
    _buttonText.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageName = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      MtToast.error(context, 'Image not selected',
          'Could not read the chosen image. Try another file.');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(promoBannerRepositoryProvider);
    try {
      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          tagText: _tagText.text.trim(),
          title: _title.text.trim(),
          buttonText: _buttonText.text.trim(),
          gradientColors: _gradient,
          isActive: _isActive,
        );
        await repo.update(
          updated,
          newImageBytes: _pickedImageBytes,
          imageFilename: _pickedImageName ?? 'banner.jpg',
        );
      } else {
        await repo.create(
          tagText: _tagText.text.trim(),
          title: _title.text.trim(),
          buttonText: _buttonText.text.trim(),
          gradientColors: _gradient,
          isActive: _isActive,
          imageBytes: _pickedImageBytes,
          imageFilename: _pickedImageName ?? 'banner.jpg',
        );
      }
      if (!mounted) return;
      // Fire the success toast (it lives on the root overlay, so it survives
      // the dialog dismissal) then close the form.
      MtToast.success(context, _isEdit ? 'Banner updated' : 'Banner created');
      Navigator.of(context).pop();
    } catch (e) {
      // A failed save keeps the dialog open so the admin can fix + retry
      // instead of losing their input. Map 404/401/500 to a clean
      // indigo/amber toast rather than surfacing the raw Dio exception.
      if (!mounted) return;
      setState(() => _saving = false);
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_isEdit ? 'Edit banner' : 'Add banner',
                    style: MtTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  _isEdit
                      ? 'Update the banner below. Leave the image empty to keep the current one.'
                      : 'Create a promo banner for the patient Home slider.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 20),
                _GradientPreview(colors: _gradient),
                const SizedBox(height: 16),
                _ImagePickerTile(
                  pickedBytes: _pickedImageBytes,
                  existingUrl: widget.existing?.imageUrl,
                  onTap: _pickImage,
                ),
                const SizedBox(height: 16),
                _Label('Tag text'),
                _Field(
                  controller: _tagText,
                  hint: 'e.g. VERIFIED TEAM',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Tag text is required' : null,
                ),
                const SizedBox(height: 12),
                _Label('Title'),
                _Field(
                  controller: _title,
                  hint: 'e.g. MBBS doctors + certified aides',
                  maxLines: 2,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                _Label('Button text'),
                _Field(
                  controller: _buttonText,
                  hint: 'e.g. Meet providers',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Button text is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _Label('Background gradient'),
                _GradientPicker(
                  selected: _gradient,
                  onSelected: (colors) => setState(() => _gradient = colors),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: MtTextStyles.labelLg),
                  subtitle: Text(
                    _isActive
                        ? 'Visible in the patient Home slider'
                        : 'Hidden from patients',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                  value: _isActive,
                  activeColor: MtColors.brand,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: MtButton(
                        label: 'Cancel',
                        isOutlined: true,
                        onPressed:
                            _saving ? () {} : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MtButton(
                        label: _isEdit ? 'Save changes' : 'Create',
                        leadingIcon: Icons.check,
                        isLoading: _saving,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A live preview strip of the currently selected gradient.
class _GradientPreview extends StatelessWidget {
  final List<String> colors;
  const _GradientPreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    final parsed = PromoBanner(
      id: '',
      tagText: '',
      title: '',
      buttonText: '',
      gradientColors: colors,
    ).gradient;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: parsed,
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'Gradient preview',
        style: MtTextStyles.labelMd.copyWith(color: Colors.white),
      ),
    );
  }
}

/// Horizontal row of tappable gradient swatches. The selected preset gets a
/// ring; picking one reports its HEX stops upward.
class _GradientPicker extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onSelected;
  const _GradientPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final preset in _kBannerGradientPresets)
          _Swatch(
            preset: preset,
            isSelected: _listEquals(preset.colors, selected),
            onTap: () => onSelected(preset.colors),
          ),
      ],
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toUpperCase() != b[i].toUpperCase()) return false;
    }
    return true;
  }
}

class _Swatch extends StatelessWidget {
  final _GradientPreset preset;
  final bool isSelected;
  final VoidCallback onTap;
  const _Swatch({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = PromoBanner(
      id: '',
      tagText: '',
      title: '',
      buttonText: '',
      gradientColors: preset.colors,
    ).gradient;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Tooltip(
        message: preset.name,
        child: Container(
          width: 56,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(
              color: isSelected ? MtColors.ink : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  final Uint8List? pickedBytes;
  final String? existingUrl;
  final VoidCallback onTap;

  const _ImagePickerTile({
    required this.pickedBytes,
    required this.existingUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (pickedBytes != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(pickedBytes!,
            fit: BoxFit.cover, width: double.infinity, height: 140),
      );
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: existingUrl!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 140,
          placeholder: (_, __) => Container(color: MtColors.bg, height: 140),
          errorWidget: (_, __, ___) => Container(
            color: MtColors.bg,
            height: 140,
            child: const Icon(Icons.broken_image_outlined, color: MtColors.ink3),
          ),
        ),
      );
    } else {
      content = Container(
        height: 140,
        decoration: BoxDecoration(
          color: MtColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MtColors.line),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, color: MtColors.ink3, size: 32),
              SizedBox(height: 8),
              Text('Tap to upload image (optional)', style: MtTextStyles.bodyMd),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: content,
        ),
        if (pickedBytes != null || (existingUrl != null && existingUrl!.isNotEmpty))
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Replace',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child:
          Text(text, style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: MtTextStyles.bodyMd,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        filled: true,
        fillColor: MtColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.rejected),
        ),
      ),
    );
  }
}
