import 'package:equatable/equatable.dart';

import 'assigned_doctor.dart';
import 'assigned_nurse.dart';
import 'patient_request_status.dart';

/// The patient's currently-open service request. Drives both the Home active
/// card and the Under Review / Tracking tabs.
///
/// Optional fields (`requestedAt`, `acceptedAt`, `offer`, `durationHours`,
/// `reviewEtaMinutes`) are populated on submit and as the backend updates the
/// request lifecycle. They're optional so older payloads keep parsing.
class PatientActiveRequest extends Equatable {
  final String id;
  final String serviceTitleEn;
  final String serviceTitleBn;
  final PatientRequestStatus status;
  final String? providerName;
  final String? providerInitials;
  final String? providerAvatarUrl;
  final String? providerSpecialization;

  /// Populated doctor profile attached by the backend once the admin
  /// completes the assignment. `null` while the request is still pending.
  /// Drives the "Your Doctor is Assigned" card on the Tracking tab and
  /// the read-only `view_assigned_doctor_screen.dart`.
  final AssignedDoctor? assignedDoctor;

  /// Populated nurse profile attached by the backend when the admin
  /// adds a nursing-care provider to the visit. `null` for doctor-only
  /// visits. Surfaces a second row on YOUR CARE TIMELINE and a
  /// separate avatar in the patient's active-care card.
  final AssignedNurse? assignedNurse;

  /// When the patient submitted the request.
  final DateTime? requestedAt;

  /// When the admin matched the doctor (or `null` if still pending).
  final DateTime? acceptedAt;

  /// When the visit is scheduled for (or `null` for ASAP).
  final DateTime? scheduledAt;

  final String locationLabel;
  final int? etaMinutes;
  final int? reviewEtaMinutes;
  final int? durationHours;
  final int? offer;

  final DateTime updatedAt;

  const PatientActiveRequest({
    required this.id,
    required this.serviceTitleEn,
    required this.serviceTitleBn,
    required this.status,
    required this.locationLabel,
    required this.updatedAt,
    this.providerName,
    this.providerInitials,
    this.providerAvatarUrl,
    this.providerSpecialization,
    this.assignedDoctor,
    this.assignedNurse,
    this.requestedAt,
    this.acceptedAt,
    this.scheduledAt,
    this.etaMinutes,
    this.reviewEtaMinutes,
    this.durationHours,
    this.offer,
  });

  PatientActiveRequest copyWith({
    PatientRequestStatus? status,
    DateTime? updatedAt,
    DateTime? acceptedAt,
    int? etaMinutes,
    int? reviewEtaMinutes,
    AssignedDoctor? assignedDoctor,
    AssignedNurse? assignedNurse,
  }) {
    return PatientActiveRequest(
      id: id,
      serviceTitleEn: serviceTitleEn,
      serviceTitleBn: serviceTitleBn,
      status: status ?? this.status,
      locationLabel: locationLabel,
      updatedAt: updatedAt ?? this.updatedAt,
      providerName: providerName,
      providerInitials: providerInitials,
      providerAvatarUrl: providerAvatarUrl,
      providerSpecialization: providerSpecialization,
      assignedDoctor: assignedDoctor ?? this.assignedDoctor,
      assignedNurse: assignedNurse ?? this.assignedNurse,
      requestedAt: requestedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      scheduledAt: scheduledAt,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      reviewEtaMinutes: reviewEtaMinutes ?? this.reviewEtaMinutes,
      durationHours: durationHours,
      offer: offer,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serviceTitleEn,
        serviceTitleBn,
        status,
        providerName,
        providerInitials,
        providerAvatarUrl,
        providerSpecialization,
        assignedDoctor,
        assignedNurse,
        requestedAt,
        acceptedAt,
        scheduledAt,
        locationLabel,
        etaMinutes,
        reviewEtaMinutes,
        durationHours,
        offer,
        updatedAt,
      ];

  factory PatientActiveRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseOptional(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return PatientActiveRequest(
      id: json['id']?.toString() ?? '',
      serviceTitleEn: json['serviceTitleEn']?.toString() ?? '',
      serviceTitleBn: json['serviceTitleBn']?.toString() ?? '',
      status: PatientRequestStatusX.fromWire(json['status']?.toString()),
      providerName: json['providerName']?.toString(),
      providerInitials: json['providerInitials']?.toString(),
      providerAvatarUrl: json['providerAvatarUrl']?.toString(),
      providerSpecialization: json['providerSpecialization']?.toString(),
      requestedAt: parseOptional(json['requestedAt']),
      acceptedAt: parseOptional(json['acceptedAt']),
      scheduledAt: parseOptional(json['scheduledAt']),
      locationLabel: json['locationLabel']?.toString() ?? '',
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      reviewEtaMinutes: (json['reviewEtaMinutes'] as num?)?.toInt(),
      durationHours: (json['durationHours'] as num?)?.toInt(),
      offer: (json['offer'] as num?)?.toInt(),
      updatedAt: parseOptional(json['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serviceTitleEn': serviceTitleEn,
        'serviceTitleBn': serviceTitleBn,
        'status': status.toWire(),
        'providerName': providerName,
        'providerInitials': providerInitials,
        'providerAvatarUrl': providerAvatarUrl,
        'providerSpecialization': providerSpecialization,
        'requestedAt': requestedAt?.toIso8601String(),
        'acceptedAt': acceptedAt?.toIso8601String(),
        'scheduledAt': scheduledAt?.toIso8601String(),
        'locationLabel': locationLabel,
        'etaMinutes': etaMinutes,
        'reviewEtaMinutes': reviewEtaMinutes,
        'durationHours': durationHours,
        'offer': offer,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
