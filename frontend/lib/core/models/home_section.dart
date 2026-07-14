import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/hex_color.dart';

/// Trimmed non-empty string, else null — used when reading optional hex tokens.
String? _optStr(dynamic v) =>
    (v is String && v.trim().isNotEmpty) ? v.trim() : null;

/// Optional per-card color overrides ("micro-branding"), mirroring the backend
/// `contentData[].cardStyles`. Raw `#RRGGBB` hex **strings** are stored and
/// parsed lazily (same pattern as [PromoBanner.gradientColors]); a null token
/// means "use the app's theme fallback". Card bg + accent are Light/Dark pairs;
/// tag colors are single values used in both themes.
@immutable
class CardStyleTokens extends Equatable {
  final String? cardBgLight;
  final String? cardBgDark;
  final String? accentColorLight;
  final String? accentColorDark;
  final String? tagBgColor;
  final String? tagTextColor;

  const CardStyleTokens({
    this.cardBgLight,
    this.cardBgDark,
    this.accentColorLight,
    this.accentColorDark,
    this.tagBgColor,
    this.tagTextColor,
  });

  /// Resolved card background for the ambient brightness, or null (fall back).
  Color? cardBg(bool dark) => hexToColor(dark ? cardBgDark : cardBgLight);

  /// Resolved accent (["+" button] + card glow) for the brightness, or null.
  Color? accent(bool dark) => hexToColor(dark ? accentColorDark : accentColorLight);

  Color? get tagBg => hexToColor(tagBgColor);
  Color? get tagText => hexToColor(tagTextColor);

  /// True when no override is set — used to drop the object entirely.
  bool get isEmpty =>
      cardBgLight == null &&
      cardBgDark == null &&
      accentColorLight == null &&
      accentColorDark == null &&
      tagBgColor == null &&
      tagTextColor == null;

  factory CardStyleTokens.fromJson(Map<String, dynamic> json) => CardStyleTokens(
        cardBgLight: _optStr(json['cardBgLight']),
        cardBgDark: _optStr(json['cardBgDark']),
        accentColorLight: _optStr(json['accentColorLight']),
        accentColorDark: _optStr(json['accentColorDark']),
        tagBgColor: _optStr(json['tagBgColor']),
        tagTextColor: _optStr(json['tagTextColor']),
      );

  Map<String, dynamic> toJson() => {
        'cardBgLight': cardBgLight,
        'cardBgDark': cardBgDark,
        'accentColorLight': accentColorLight,
        'accentColorDark': accentColorDark,
        'tagBgColor': tagBgColor,
        'tagTextColor': tagTextColor,
      };

  @override
  List<Object?> get props => [
        cardBgLight,
        cardBgDark,
        accentColorLight,
        accentColorDark,
        tagBgColor,
        tagTextColor,
      ];
}

/// Optional section-container color overrides, mirroring the backend
/// `styleTokens`. Same store-hex / parse-lazily / null-means-fallback contract
/// as [CardStyleTokens].
@immutable
class SectionStyleTokens extends Equatable {
  final String? titleColorLight;
  final String? titleColorDark;
  final String? sectionBackgroundColor;

  const SectionStyleTokens({
    this.titleColorLight,
    this.titleColorDark,
    this.sectionBackgroundColor,
  });

  /// Resolved header-title color for the ambient brightness, or null.
  Color? title(bool dark) => hexToColor(dark ? titleColorDark : titleColorLight);

  /// Resolved section background, or null (no background painted).
  Color? get background => hexToColor(sectionBackgroundColor);

  bool get isEmpty =>
      titleColorLight == null &&
      titleColorDark == null &&
      sectionBackgroundColor == null;

  factory SectionStyleTokens.fromJson(Map<String, dynamic> json) =>
      SectionStyleTokens(
        titleColorLight: _optStr(json['titleColorLight']),
        titleColorDark: _optStr(json['titleColorDark']),
        sectionBackgroundColor: _optStr(json['sectionBackgroundColor']),
      );

  Map<String, dynamic> toJson() => {
        'titleColorLight': titleColorLight,
        'titleColorDark': titleColorDark,
        'sectionBackgroundColor': sectionBackgroundColor,
      };

  @override
  List<Object?> get props =>
      [titleColorLight, titleColorDark, sectionBackgroundColor];
}

/// One content element inside a [HomeSection] (an avatar, product card,
/// grid tile, or banner slide depending on the section's template).
///
/// Mirrors the backend `DynamicSection.contentData[]` embedded doc
/// (camelCase keys). [toJson] exists because sections are saved back with
/// a whole-array `contentData` replace.
class HomeSectionItem extends Equatable {
  /// Client-generated stable key; also drives the uploaded image public_id.
  final String itemId;
  final String title;
  final String? subtitle;
  final String imageUrl;
  final String? priceTag;

  /// Client route string, e.g. `new_request`, `service:<id>`,
  /// `activities:tracking`, or an `https://` URL. Unknown values no-op.
  final String? navigationRoute;
  final Map<String, String> routeArguments;

  /// Optional per-card color overrides; null when the card uses theme defaults.
  final CardStyleTokens? cardStyles;

  const HomeSectionItem({
    required this.itemId,
    required this.title,
    this.subtitle,
    required this.imageUrl,
    this.priceTag,
    this.navigationRoute,
    this.routeArguments = const {},
    this.cardStyles,
  });

  HomeSectionItem copyWith({
    String? itemId,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? priceTag,
    String? navigationRoute,
    Map<String, String>? routeArguments,
    CardStyleTokens? cardStyles,
  }) {
    return HomeSectionItem(
      itemId: itemId ?? this.itemId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      priceTag: priceTag ?? this.priceTag,
      navigationRoute: navigationRoute ?? this.navigationRoute,
      routeArguments: routeArguments ?? this.routeArguments,
      cardStyles: cardStyles ?? this.cardStyles,
    );
  }

  factory HomeSectionItem.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['routeArguments'];
    final args = <String, String>{};
    if (rawArgs is Map) {
      rawArgs.forEach((k, v) {
        if (v != null) args[k.toString()] = v.toString();
      });
    }
    final rawStyles = json['cardStyles'];
    final styles = rawStyles is Map
        ? CardStyleTokens.fromJson(Map<String, dynamic>.from(rawStyles))
        : null;
    return HomeSectionItem(
      itemId: (json['itemId'] ?? '').toString(),
      title: (json['title'] ?? '') as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: (json['imageUrl'] ?? '') as String,
      priceTag: json['priceTag'] as String?,
      navigationRoute: json['navigationRoute'] as String?,
      routeArguments: args,
      cardStyles: (styles != null && !styles.isEmpty) ? styles : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'title': title,
        'subtitle': subtitle,
        'imageUrl': imageUrl,
        'priceTag': priceTag,
        'navigationRoute': navigationRoute,
        'routeArguments': routeArguments,
        if (cardStyles != null) 'cardStyles': cardStyles!.toJson(),
      };

  @override
  List<Object?> get props => [
        itemId,
        title,
        subtitle,
        imageUrl,
        priceTag,
        navigationRoute,
        routeArguments,
        cardStyles,
      ];
}

/// An admin-managed dynamic section rendered on the patient Home below the
/// fixed Banners + Care Services blocks.
///
/// Mirrors the backend `DynamicSection` document (camelCase keys + `id` via
/// its `toJSON` transform). [uiTemplate] is kept as a raw string — not an
/// enum — so a future backend can ship new template values without breaking
/// this client; the renderer skips anything not in [supportedTemplates].
class HomeSection extends Equatable {
  final String id;
  final String sectionKey;
  final String titleEn;
  final String? titleBn;
  final String uiTemplate;

  /// Ascending display order below the fixed blocks — lower shows first.
  final int orderIndex;
  final bool isActive;
  final List<HomeSectionItem> contentData;

  /// Optional section-container color overrides; null when using theme defaults.
  final SectionStyleTokens? styleTokens;
  final DateTime? createdAt;

  const HomeSection({
    required this.id,
    required this.sectionKey,
    required this.titleEn,
    this.titleBn,
    required this.uiTemplate,
    this.orderIndex = 0,
    this.isActive = true,
    this.contentData = const [],
    this.styleTokens,
    this.createdAt,
  });

  static const templateHorizontalRoundAvatar = 'HORIZONTAL_ROUND_AVATAR';
  static const templateHorizontalProductCard = 'HORIZONTAL_PRODUCT_CARD';
  static const templateGrid2x2Tiles = 'GRID_2X2_TILES';
  static const templateSingleWideBanner = 'SINGLE_WIDE_BANNER';

  /// Every template this app version knows how to render.
  static const supportedTemplates = {
    templateHorizontalRoundAvatar,
    templateHorizontalProductCard,
    templateGrid2x2Tiles,
    templateSingleWideBanner,
  };

  HomeSection copyWith({
    String? id,
    String? sectionKey,
    String? titleEn,
    String? titleBn,
    String? uiTemplate,
    int? orderIndex,
    bool? isActive,
    List<HomeSectionItem>? contentData,
    SectionStyleTokens? styleTokens,
    DateTime? createdAt,
  }) {
    return HomeSection(
      id: id ?? this.id,
      sectionKey: sectionKey ?? this.sectionKey,
      titleEn: titleEn ?? this.titleEn,
      titleBn: titleBn ?? this.titleBn,
      uiTemplate: uiTemplate ?? this.uiTemplate,
      orderIndex: orderIndex ?? this.orderIndex,
      isActive: isActive ?? this.isActive,
      contentData: contentData ?? this.contentData,
      styleTokens: styleTokens ?? this.styleTokens,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['contentData'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) =>
                HomeSectionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <HomeSectionItem>[];
    final rawStyles = json['styleTokens'];
    final styles = rawStyles is Map
        ? SectionStyleTokens.fromJson(Map<String, dynamic>.from(rawStyles))
        : null;
    return HomeSection(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      sectionKey: (json['sectionKey'] ?? '') as String,
      titleEn: (json['titleEn'] ?? '') as String,
      titleBn: json['titleBn'] as String?,
      uiTemplate: (json['uiTemplate'] ?? '') as String,
      orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      contentData: items,
      styleTokens: (styles != null && !styles.isEmpty) ? styles : null,
      createdAt: _parseDate(json['createdAt']),
    );
  }

  /// Serialized for POST/PUT bodies — omits `id`/`createdAt` (server-owned).
  Map<String, dynamic> toJson() => {
        'sectionKey': sectionKey,
        'titleEn': titleEn,
        'titleBn': titleBn,
        'uiTemplate': uiTemplate,
        'orderIndex': orderIndex,
        'isActive': isActive,
        'contentData': contentData.map((e) => e.toJson()).toList(),
        if (styleTokens != null) 'styleTokens': styleTokens!.toJson(),
      };

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        sectionKey,
        titleEn,
        titleBn,
        uiTemplate,
        orderIndex,
        isActive,
        contentData,
        styleTokens,
        createdAt,
      ];
}
