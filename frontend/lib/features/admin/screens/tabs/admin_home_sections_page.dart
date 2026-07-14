import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/api/home_section_providers.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/theme/hex_color.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_button.dart';
import '../../../../core/widgets/mt_toast.dart';

/// Human-readable labels for the reusable UI templates.
const Map<String, String> _kTemplateLabels = {
  HomeSection.templateHorizontalRoundAvatar: 'Round avatars (horizontal)',
  HomeSection.templateHorizontalProductCard: 'Product cards (horizontal)',
  HomeSection.templateGrid2x2Tiles: 'Grid tiles (2 columns)',
  HomeSection.templateSingleWideBanner: 'Single wide banner',
};

/// Prefers the backend's own message (e.g. "sectionKey already exists" on a
/// 409) before falling back to the shared status-code copy.
(String, String) _mapSectionError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return ('Could not save section', data['message'] as String);
    }
  }
  return mapBannerError(error);
}

/// Admin CRUD + drag-to-reorder management for the server-driven dynamic
/// home sections rendered below Banners + Care Services on the patient Home.
///
/// Mirrors [AdminBannerManagementPage] (scroll body + white list card +
/// add/edit [Dialog] + inline active toggle + edit/delete menu +
/// [ReorderableListView] persisting `orderIndex` via
/// `HomeSectionRepository.reorder`).
class AdminHomeSectionsPage extends ConsumerWidget {
  const AdminHomeSectionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allHomeSectionsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      async.maybeWhen(
                        data: (items) =>
                            '${items.length} section${items.length == 1 ? '' : 's'}',
                        orElse: () => '',
                      ),
                      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sections render below Banners & Care Services on the app home. '
                      'Drag the handle to reorder — lower rows show first.',
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: MtButton(
                  label: 'Add section',
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
                onRetry: () => ref.refresh(allHomeSectionsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'No sections yet. Click "Add section" to create the first one.',
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
                  itemBuilder: (context, i) => _SectionRow(
                    key: ValueKey(items[i].id),
                    section: items[i],
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
    List<HomeSection> items,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView reports newIndex as the slot *before* removal.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final ids = reordered.map((s) => s.id).toList();
    try {
      await ref.read(homeSectionRepositoryProvider).reorder(ids);
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = _mapSectionError(e);
      MtToast.error(context, title, message);
    }
  }

  static void _openForm(BuildContext context, WidgetRef ref,
      {HomeSection? existing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _SectionFormDialog(existing: existing),
    );
  }
}

class _SectionRow extends ConsumerWidget {
  final HomeSection section;
  final int index;
  final bool isLast;
  const _SectionRow({
    required this.section,
    required this.index,
    required this.isLast,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(homeSectionRepositoryProvider);

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
            _SectionThumb(section: section),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.sectionKey,
                    style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    section.titleEn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.labelLg,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_kTemplateLabels[section.uiTemplate] ?? section.uiTemplate}'
                  ' · ${section.contentData.length} item'
                  '${section.contentData.length == 1 ? '' : 's'}',
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
                  value: section.isActive,
                  activeColor: MtColors.brand,
                  onChanged: (v) async {
                    try {
                      await repo.setStatus(section.id, v);
                    } catch (e) {
                      if (!context.mounted) return;
                      final (title, message) = _mapSectionError(e);
                      MtToast.error(context, title, message);
                    }
                  },
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 58,
                  child: Text(
                    section.isActive ? 'Active' : 'Hidden',
                    style: MtTextStyles.labelMd.copyWith(
                      color:
                          section.isActive ? MtColors.completed : MtColors.ink3,
                    ),
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: MtColors.ink2),
              onSelected: (action) async {
                if (action == 'edit') {
                  AdminHomeSectionsPage._openForm(context, ref,
                      existing: section);
                } else if (action == 'delete') {
                  await _confirmDelete(context, ref, section);
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
      BuildContext context, WidgetRef ref, HomeSection section) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete section?'),
        content: Text(
            '"${section.titleEn}" and its ${section.contentData.length} '
            'item${section.contentData.length == 1 ? '' : 's'} will be '
            'permanently removed.'),
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
      await ref.read(homeSectionRepositoryProvider).delete(section);
      if (!context.mounted) return;
      MtToast.success(context, 'Section deleted');
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = _mapSectionError(e);
      MtToast.error(context, title, message);
    }
  }
}

/// A small rounded preview of the section — its first item image if present.
class _SectionThumb extends StatelessWidget {
  final HomeSection section;
  const _SectionThumb({required this.section});

  @override
  Widget build(BuildContext context) {
    final url =
        section.contentData.isNotEmpty ? section.contentData.first.imageUrl : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 44,
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => _placeholder(),
                errorWidget: (_, _, _) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: MtColors.bg,
        child: const Icon(Icons.dashboard_customize_outlined,
            color: MtColors.ink3, size: 20),
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

/// A mutable per-item draft driving one card in the content editor. The
/// [itemId] is generated client-side (creation timestamp) so the image can be
/// uploaded — keyed by it — before the section itself exists on the server.
class _DraftItem {
  final String itemId;
  final TextEditingController title;
  final TextEditingController subtitle;
  final TextEditingController priceTag;
  final TextEditingController route;
  // Optional per-card color overrides (blank ⇒ theme default on the app).
  final TextEditingController cardBgLight;
  final TextEditingController cardBgDark;
  final TextEditingController accentLight;
  final TextEditingController accentDark;
  final TextEditingController tagBg;
  final TextEditingController tagText;
  String? imageUrl;
  bool uploading = false;

  _DraftItem({
    String? itemId,
    HomeSectionItem? from,
  })  : itemId = itemId ??
            from?.itemId ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title = TextEditingController(text: from?.title ?? ''),
        subtitle = TextEditingController(text: from?.subtitle ?? ''),
        priceTag = TextEditingController(text: from?.priceTag ?? ''),
        route = TextEditingController(text: from?.navigationRoute ?? ''),
        cardBgLight =
            TextEditingController(text: from?.cardStyles?.cardBgLight ?? ''),
        cardBgDark =
            TextEditingController(text: from?.cardStyles?.cardBgDark ?? ''),
        accentLight = TextEditingController(
            text: from?.cardStyles?.accentColorLight ?? ''),
        accentDark = TextEditingController(
            text: from?.cardStyles?.accentColorDark ?? ''),
        tagBg =
            TextEditingController(text: from?.cardStyles?.tagBgColor ?? ''),
        tagText =
            TextEditingController(text: from?.cardStyles?.tagTextColor ?? ''),
        imageUrl = from?.imageUrl;

  HomeSectionItem toItem() {
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final styles = CardStyleTokens(
      cardBgLight: t(cardBgLight),
      cardBgDark: t(cardBgDark),
      accentColorLight: t(accentLight),
      accentColorDark: t(accentDark),
      tagBgColor: t(tagBg),
      tagTextColor: t(tagText),
    );
    return HomeSectionItem(
      itemId: itemId,
      title: title.text.trim(),
      subtitle: subtitle.text.trim().isEmpty ? null : subtitle.text.trim(),
      imageUrl: imageUrl ?? '',
      priceTag: priceTag.text.trim().isEmpty ? null : priceTag.text.trim(),
      navigationRoute: route.text.trim().isEmpty ? null : route.text.trim(),
      cardStyles: styles.isEmpty ? null : styles,
    );
  }

  void dispose() {
    title.dispose();
    subtitle.dispose();
    priceTag.dispose();
    route.dispose();
    cardBgLight.dispose();
    cardBgDark.dispose();
    accentLight.dispose();
    accentDark.dispose();
    tagBg.dispose();
    tagText.dispose();
  }
}

class _SectionFormDialog extends ConsumerStatefulWidget {
  final HomeSection? existing;
  const _SectionFormDialog({this.existing});

  @override
  ConsumerState<_SectionFormDialog> createState() => _SectionFormDialogState();
}

class _SectionFormDialogState extends ConsumerState<_SectionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sectionKey;
  late final TextEditingController _titleEn;
  late final TextEditingController _titleBn;
  // Optional section-container color overrides (blank ⇒ theme default).
  late final TextEditingController _titleColorLight;
  late final TextEditingController _titleColorDark;
  late final TextEditingController _sectionBg;
  late String _uiTemplate;
  late bool _isActive;
  late final List<_DraftItem> _items;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  bool get _uploadsInFlight => _items.any((d) => d.uploading);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _sectionKey = TextEditingController(text: e?.sectionKey ?? '');
    _titleEn = TextEditingController(text: e?.titleEn ?? '');
    _titleBn = TextEditingController(text: e?.titleBn ?? '');
    _titleColorLight =
        TextEditingController(text: e?.styleTokens?.titleColorLight ?? '');
    _titleColorDark =
        TextEditingController(text: e?.styleTokens?.titleColorDark ?? '');
    _sectionBg = TextEditingController(
        text: e?.styleTokens?.sectionBackgroundColor ?? '');
    _uiTemplate = e?.uiTemplate ?? HomeSection.templateHorizontalProductCard;
    _isActive = e?.isActive ?? true;
    _items = [
      for (final item in e?.contentData ?? const <HomeSectionItem>[])
        _DraftItem(from: item),
    ];
  }

  @override
  void dispose() {
    _sectionKey.dispose();
    _titleEn.dispose();
    _titleBn.dispose();
    _titleColorLight.dispose();
    _titleColorDark.dispose();
    _sectionBg.dispose();
    for (final d in _items) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(_DraftItem draft) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      if (!mounted) return;
      MtToast.error(context, 'Image not selected',
          'Could not read the chosen image. Try another file.');
      return;
    }
    if (picked == null) return;
    final Uint8List bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => draft.uploading = true);
    try {
      final url = await ref
          .read(homeSectionRepositoryProvider)
          .uploadItemImage(bytes, draft.itemId, filename: picked.name);
      if (!mounted) return;
      setState(() {
        draft.imageUrl = url;
        draft.uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => draft.uploading = false);
      final (title, message) = _mapSectionError(e);
      MtToast.error(context, title, message);
    }
  }

  Future<void> _pasteImageUrl(_DraftItem draft) async {
    final controller = TextEditingController(text: draft.imageUrl ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Image URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Use URL'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    if (!mounted) return;
    setState(() => draft.imageUrl = url);
  }

  void _addItem() => setState(() => _items.add(_DraftItem()));

  void _removeItem(int i) => setState(() => _items.removeAt(i).dispose());

  void _moveItem(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _items.length) return;
    setState(() {
      final moved = _items.removeAt(i);
      _items.insert(j, moved);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      MtToast.error(context, 'No content items',
          'Add at least one item — empty sections are hidden on the app home.');
      return;
    }
    final missingImage = _items.indexWhere(
        (d) => d.imageUrl == null || d.imageUrl!.isEmpty);
    if (missingImage != -1) {
      MtToast.error(context, 'Item image missing',
          'Item ${missingImage + 1} has no image. Upload or paste one first.');
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(homeSectionRepositoryProvider);
    final contentData = [for (final d in _items) d.toItem()];
    String? tk(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final sectionStyles = SectionStyleTokens(
      titleColorLight: tk(_titleColorLight),
      titleColorDark: tk(_titleColorDark),
      sectionBackgroundColor: tk(_sectionBg),
    );
    try {
      if (_isEdit) {
        // Pass the concrete tokens object (even when all-empty) so clearing a
        // previously-set color round-trips — section styleTokens is a partial
        // update on the backend, unlike the whole-array contentData replace.
        await repo.update(widget.existing!.copyWith(
          titleEn: _titleEn.text.trim(),
          titleBn: _titleBn.text.trim(),
          uiTemplate: _uiTemplate,
          isActive: _isActive,
          contentData: contentData,
          styleTokens: sectionStyles,
        ));
      } else {
        await repo.create(HomeSection(
          id: '',
          sectionKey: _sectionKey.text.trim(),
          titleEn: _titleEn.text.trim(),
          titleBn: _titleBn.text.trim().isEmpty ? null : _titleBn.text.trim(),
          uiTemplate: _uiTemplate,
          isActive: _isActive,
          contentData: contentData,
          styleTokens: sectionStyles.isEmpty ? null : sectionStyles,
        ));
      }
      if (!mounted) return;
      MtToast.success(context, _isEdit ? 'Section updated' : 'Section created');
      Navigator.of(context).pop();
    } catch (e) {
      // A failed save keeps the dialog open so the admin can fix + retry.
      if (!mounted) return;
      setState(() => _saving = false);
      final (title, message) = _mapSectionError(e);
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
                Text(_isEdit ? 'Edit section' : 'Add section',
                    style: MtTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  _isEdit
                      ? 'Update the section below. It re-renders on the app home instantly.'
                      : 'Create a dynamic section for the patient Home — no app update needed.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 20),
                _Label('Section key'),
                _Field(
                  controller: _sectionKey,
                  hint: 'e.g. trending_doctors',
                  readOnly: _isEdit,
                  validator: (v) {
                    if (_isEdit) return null;
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Section key is required';
                    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(s)) {
                      return 'Lowercase letters, digits and _ only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _Label('Title (English)'),
                _Field(
                  controller: _titleEn,
                  hint: 'e.g. Specialist consultations',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                _Label('Title (Bangla, optional)'),
                _Field(controller: _titleBn, hint: 'e.g. বিশেষজ্ঞ পরামর্শ'),
                const SizedBox(height: 12),
                _Label('UI template'),
                DropdownButtonFormField<String>(
                  initialValue: _uiTemplate,
                  style: MtTextStyles.bodyMd,
                  decoration: _fieldDecoration(),
                  items: [
                    for (final entry in _kTemplateLabels.entries)
                      DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (v) =>
                      setState(() => _uiTemplate = v ?? _uiTemplate),
                ),
                const SizedBox(height: 8),
                _SectionColorsExpander(
                  titleLight: _titleColorLight,
                  titleDark: _titleColorDark,
                  background: _sectionBg,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Label('Content items'),
                    TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add item'),
                    ),
                  ],
                ),
                if (_items.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: MtColors.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: MtColors.line),
                    ),
                    child: Text(
                      'No items yet — add the cards/tiles this section will show.',
                      textAlign: TextAlign.center,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ),
                for (var i = 0; i < _items.length; i++)
                  _ItemCard(
                    draft: _items[i],
                    index: i,
                    count: _items.length,
                    onPickImage: () => _pickImage(_items[i]),
                    onPasteUrl: () => _pasteImageUrl(_items[i]),
                    onRemove: () => _removeItem(i),
                    onMoveUp: () => _moveItem(i, -1),
                    onMoveDown: () => _moveItem(i, 1),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: MtTextStyles.labelLg),
                  subtitle: Text(
                    _isActive
                        ? 'Visible on the patient Home'
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
                        label: _uploadsInFlight
                            ? 'Uploading…'
                            : (_isEdit ? 'Save changes' : 'Create'),
                        leadingIcon: Icons.check,
                        isLoading: _saving,
                        onPressed: _uploadsInFlight ? () {} : _save,
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

/// One editable content-item card: image tile + text fields + reorder/remove.
class _ItemCard extends StatelessWidget {
  final _DraftItem draft;
  final int index;
  final int count;
  final VoidCallback onPickImage;
  final VoidCallback onPasteUrl;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _ItemCard({
    required this.draft,
    required this.index,
    required this.count,
    required this.onPickImage,
    required this.onPasteUrl,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Item ${index + 1}',
                  style:
                      MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: index == 0 ? null : onMoveUp,
                icon: const Icon(Icons.arrow_upward, size: 16),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: index == count - 1 ? null : onMoveDown,
                icon: const Icon(Icons.arrow_downward, size: 16),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: MtColors.rejected),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ItemImageTile(
                imageUrl: draft.imageUrl,
                uploading: draft.uploading,
                onPick: onPickImage,
                onPasteUrl: onPasteUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _Field(
                      controller: draft.title,
                      hint: 'Title (required)',
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Item title is required'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    _Field(controller: draft.subtitle, hint: 'Subtitle'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: draft.priceTag,
                  hint: 'Price tag, e.g. ৳2400',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _Field(
                  controller: draft.route,
                  hint: 'Route: new_request · service:<id> · https://…',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _CardColorsExpander(draft: draft),
        ],
      ),
    );
  }
}

/// Collapsible section-container color overrides. Every field is optional
/// (blank = the app's theme default).
class _SectionColorsExpander extends StatelessWidget {
  final TextEditingController titleLight;
  final TextEditingController titleDark;
  final TextEditingController background;
  const _SectionColorsExpander({
    required this.titleLight,
    required this.titleDark,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('Section colors (optional)',
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
        children: [
          _HexColorField(label: 'Title color (light)', controller: titleLight),
          _HexColorField(label: 'Title color (dark)', controller: titleDark),
          _HexColorField(label: 'Section background', controller: background),
        ],
      ),
    );
  }
}

/// Collapsible per-card color overrides. Kept folded by default so the item
/// form stays uncluttered — every field is optional (blank = theme default).
class _CardColorsExpander extends StatelessWidget {
  final _DraftItem draft;
  const _CardColorsExpander({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Drop the default ExpansionTile dividers to sit flush in the item card.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('Card colors (optional)',
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
        children: [
          _HexColorField(label: 'Card background (light)', controller: draft.cardBgLight),
          _HexColorField(label: 'Card background (dark)', controller: draft.cardBgDark),
          _HexColorField(label: 'Accent — + button & glow (light)', controller: draft.accentLight),
          _HexColorField(label: 'Accent — + button & glow (dark)', controller: draft.accentDark),
          _HexColorField(label: 'Tag background', controller: draft.tagBg),
          _HexColorField(label: 'Tag text', controller: draft.tagText),
        ],
      ),
    );
  }
}

/// Compact square image tile with upload spinner + paste-URL affordance.
class _ItemImageTile extends StatelessWidget {
  final String? imageUrl;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onPasteUrl;

  const _ItemImageTile({
    required this.imageUrl,
    required this.uploading,
    required this.onPick,
    required this.onPasteUrl,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (uploading) {
      content = const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          fit: BoxFit.cover,
          width: 96,
          height: 96,
          placeholder: (_, _) => Container(color: MtColors.bg),
          errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined,
              color: MtColors.ink3),
        ),
      );
    } else {
      content = const Center(
        child: Icon(Icons.cloud_upload_outlined,
            color: MtColors.ink3, size: 28),
      );
    }

    return Column(
      children: [
        InkWell(
          onTap: uploading ? null : onPick,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: MtColors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MtColors.line),
            ),
            child: content,
          ),
        ),
        TextButton(
          onPressed: uploading ? null : onPasteUrl,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: MtTextStyles.labelSm,
          ),
          child: const Text('Paste URL'),
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
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
    );

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
  final bool readOnly;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    this.hint,
    this.readOnly = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      validator: validator,
      style: MtTextStyles.bodyMd.copyWith(
        color: readOnly ? MtColors.ink3 : null,
      ),
      decoration: _fieldDecoration(hint: hint),
    );
  }
}

/// Optional hex-color field validator: empty is allowed ("use theme default");
/// otherwise the value must parse as `#RRGGBB`/`#RGB` (mirrors the backend's
/// `sanitizeHex`). Shared by the section and card color inputs.
String? _validateOptionalHex(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return null;
  if (!RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(s)) {
    return 'Use #RRGGBB (or leave blank)';
  }
  return null;
}

/// A labeled hex-color input with a live swatch that repaints as the admin
/// types. Blank = "fall back to the app theme". No color-picker dependency —
/// just a validated text field next to a preview chip.
class _HexColorField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  const _HexColorField({required this.label, required this.controller});

  @override
  State<_HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<_HexColorField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final swatch = hexToColor(widget.controller.text.trim());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: swatch ?? MtColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MtColors.line),
            ),
            child: swatch == null
                ? const Icon(Icons.format_color_reset_outlined,
                    size: 18, color: MtColors.ink3)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: widget.controller,
              validator: _validateOptionalHex,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: MtTextStyles.bodyMd,
              decoration: _fieldDecoration(hint: '#RRGGBB (blank = theme default)')
                  .copyWith(labelText: widget.label),
            ),
          ),
        ],
      ),
    );
  }
}
