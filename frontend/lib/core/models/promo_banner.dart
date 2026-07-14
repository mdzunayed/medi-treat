import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/hex_color.dart';

/// A single admin-managed marketing banner shown in the patient Home slider.
///
/// Mirrors the backend `PromoBanner` document (which emits camelCase keys +
/// an `id` via its `toJSON` transform), so [fromJson] reads keys directly.
class PromoBanner extends Equatable {
  final String id;
  final String tagText;
  final String title;
  final String buttonText;
  final String? imageUrl;

  /// HEX stops driving the card gradient, e.g. `['#4C1D95', '#8B5CF6']`.
  final List<String> gradientColors;

  /// Ascending display order in the slider — lower shows first.
  final int priorityOrder;
  final bool isActive;
  final DateTime? createdAt;

  const PromoBanner({
    required this.id,
    required this.tagText,
    required this.title,
    required this.buttonText,
    this.imageUrl,
    this.gradientColors = const ['#4C1D95', '#8B5CF6'],
    this.priorityOrder = 0,
    this.isActive = true,
    this.createdAt,
  });

  /// The gradient stops parsed into [Color]s, ready for a `LinearGradient`.
  /// Always returns at least two colors so a gradient can be built safely.
  List<Color> get gradient {
    final parsed = gradientColors
        .map(hexToColor)
        .whereType<Color>()
        .toList();
    if (parsed.isEmpty) {
      return const [Color(0xFF4C1D95), Color(0xFF8B5CF6)];
    }
    if (parsed.length == 1) return [parsed.first, parsed.first];
    return parsed;
  }

  PromoBanner copyWith({
    String? id,
    String? tagText,
    String? title,
    String? buttonText,
    String? imageUrl,
    List<String>? gradientColors,
    int? priorityOrder,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return PromoBanner(
      id: id ?? this.id,
      tagText: tagText ?? this.tagText,
      title: title ?? this.title,
      buttonText: buttonText ?? this.buttonText,
      imageUrl: imageUrl ?? this.imageUrl,
      gradientColors: gradientColors ?? this.gradientColors,
      priorityOrder: priorityOrder ?? this.priorityOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory PromoBanner.fromJson(Map<String, dynamic> json) {
    final rawColors = json['gradientColors'];
    final colors = rawColors is List
        ? rawColors.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return PromoBanner(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      tagText: (json['tagText'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      buttonText: (json['buttonText'] ?? '') as String,
      imageUrl: json['imageUrl'] as String?,
      gradientColors:
          colors.isNotEmpty ? colors : const ['#4C1D95', '#8B5CF6'],
      priorityOrder: (json['priorityOrder'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: _parseDate(json['createdAt']),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        tagText,
        title,
        buttonText,
        imageUrl,
        gradientColors,
        priorityOrder,
        isActive,
        createdAt,
      ];
}
