import 'package:equatable/equatable.dart';

/// A saved family member / dependent the patient can book care for
/// (`GET /api/dependents`).
class Dependent extends Equatable {
  final String id;
  final String fullName;
  final String dateOfBirth;
  final String gender;
  final String relationshipTag;
  final String criticalAllergiesMedicalHistory;

  const Dependent({
    required this.id,
    required this.fullName,
    this.dateOfBirth = '',
    this.gender = 'unspecified',
    this.relationshipTag = 'other',
    this.criticalAllergiesMedicalHistory = '',
  });

  /// Capitalised relationship for display ('Parent', 'Child', …).
  String get relationshipLabel {
    if (relationshipTag.isEmpty) return 'Other';
    return relationshipTag[0].toUpperCase() + relationshipTag.substring(1);
  }

  factory Dependent.fromJson(Map<String, dynamic> json) {
    return Dependent(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? '').toString(),
      dateOfBirth: (json['date_of_birth'] ?? '').toString(),
      gender: (json['gender'] ?? 'unspecified').toString(),
      relationshipTag: (json['relationship_tag'] ?? 'other').toString(),
      criticalAllergiesMedicalHistory:
          (json['critical_allergies_medical_history'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        dateOfBirth,
        gender,
        relationshipTag,
        criticalAllergiesMedicalHistory,
      ];
}
