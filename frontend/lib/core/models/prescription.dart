import 'package:equatable/equatable.dart';

import 'assigned_doctor.dart';

/// Three canonical timing slots a prescription line item can be
/// scheduled for. Mirrors the backend `FrequencySlotSchema`.
enum DoseSlot { morning, afternoon, night }

extension DoseSlotX on DoseSlot {
  String get wire {
    switch (this) {
      case DoseSlot.morning:
        return 'morning';
      case DoseSlot.afternoon:
        return 'afternoon';
      case DoseSlot.night:
        return 'night';
    }
  }

  String get labelEn {
    switch (this) {
      case DoseSlot.morning:
        return 'Morning';
      case DoseSlot.afternoon:
        return 'Afternoon';
      case DoseSlot.night:
        return 'Night';
    }
  }

  String get labelBn {
    switch (this) {
      case DoseSlot.morning:
        return 'সকাল';
      case DoseSlot.afternoon:
        return 'দুপুর';
      case DoseSlot.night:
        return 'রাত';
    }
  }

  static DoseSlot fromWire(String s) {
    switch (s.toLowerCase()) {
      case 'afternoon':
        return DoseSlot.afternoon;
      case 'night':
        return DoseSlot.night;
      case 'morning':
      default:
        return DoseSlot.morning;
    }
  }
}

/// Mealtime context — three-state because some scripts say "any
/// time" and forcing before/after would lie to the patient.
enum MealContext { before, after, either }

extension MealContextX on MealContext {
  String get wire {
    switch (this) {
      case MealContext.before:
        return 'before';
      case MealContext.after:
        return 'after';
      case MealContext.either:
        return 'either';
    }
  }

  String get labelEn {
    switch (this) {
      case MealContext.before:
        return 'Before meal';
      case MealContext.after:
        return 'After meal';
      case MealContext.either:
        return 'Either';
    }
  }

  String get labelBn {
    switch (this) {
      case MealContext.before:
        return 'খাবারের আগে';
      case MealContext.after:
        return 'খাবারের পরে';
      case MealContext.either:
        return 'যেকোনো সময়';
    }
  }

  static MealContext fromWire(String s) {
    switch (s.toLowerCase()) {
      case 'before':
        return MealContext.before;
      case 'after':
        return MealContext.after;
      case 'either':
      default:
        return MealContext.either;
    }
  }
}

class PrescriptionItem extends Equatable {
  /// Mongo `_id` of this row inside the parent prescription. Empty
  /// when the row is a freshly-built draft on the client.
  final String id;
  final String drugName;
  final String dosage;
  final Set<DoseSlot> frequency;
  final MealContext mealContext;
  final int durationDays;
  final String notes;

  const PrescriptionItem({
    this.id = '',
    required this.drugName,
    required this.dosage,
    required this.frequency,
    this.mealContext = MealContext.either,
    this.durationDays = 7,
    this.notes = '',
  });

  /// Bangladeshi-pharmacy shorthand for the daily schedule, e.g. a
  /// morning + night script reads `1+0+1`. Order is always
  /// morning + afternoon + night.
  String get frequencyCode {
    String bit(DoseSlot s) => frequency.contains(s) ? '1' : '0';
    return '${bit(DoseSlot.morning)}+'
        '${bit(DoseSlot.afternoon)}+'
        '${bit(DoseSlot.night)}';
  }

  PrescriptionItem copyWith({
    String? drugName,
    String? dosage,
    Set<DoseSlot>? frequency,
    MealContext? mealContext,
    int? durationDays,
    String? notes,
  }) =>
      PrescriptionItem(
        id: id,
        drugName: drugName ?? this.drugName,
        dosage: dosage ?? this.dosage,
        frequency: frequency ?? this.frequency,
        mealContext: mealContext ?? this.mealContext,
        durationDays: durationDays ?? this.durationDays,
        notes: notes ?? this.notes,
      );

  @override
  List<Object?> get props => [
        id,
        drugName,
        dosage,
        frequency,
        mealContext,
        durationDays,
        notes,
      ];

  Map<String, dynamic> toJson() => {
        'drug_name': drugName,
        'dosage': dosage,
        'frequency': {
          'morning': frequency.contains(DoseSlot.morning),
          'afternoon': frequency.contains(DoseSlot.afternoon),
          'night': frequency.contains(DoseSlot.night),
        },
        'meal_context': mealContext.wire,
        'duration_days': durationDays,
        'notes': notes,
      };

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) {
    final freqMap = (json['frequency'] as Map?) ?? const {};
    final freq = <DoseSlot>{};
    if (freqMap['morning'] == true) freq.add(DoseSlot.morning);
    if (freqMap['afternoon'] == true) freq.add(DoseSlot.afternoon);
    if (freqMap['night'] == true) freq.add(DoseSlot.night);
    return PrescriptionItem(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      drugName: (json['drug_name'] ?? '').toString(),
      dosage: (json['dosage'] ?? '').toString(),
      frequency: freq,
      mealContext: MealContextX.fromWire(
          (json['meal_context'] ?? 'either').toString()),
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 7,
      notes: (json['notes'] ?? '').toString(),
    );
  }
}

/// One row in the prescription's `dose_log[]`. Records a single
/// "Mark as Taken" event for a (item, slot, day_key) triple.
class DoseLogEntry extends Equatable {
  final String id;
  final String prescriptionItemId;
  final DoseSlot slot;
  final String dayKey; // YYYY-MM-DD
  final DateTime takenAt;

  const DoseLogEntry({
    required this.id,
    required this.prescriptionItemId,
    required this.slot,
    required this.dayKey,
    required this.takenAt,
  });

  @override
  List<Object?> get props => [id, prescriptionItemId, slot, dayKey, takenAt];

  factory DoseLogEntry.fromJson(Map<String, dynamic> json) {
    return DoseLogEntry(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      prescriptionItemId: (json['prescription_item_id'] ?? '').toString(),
      slot: DoseSlotX.fromWire((json['slot'] ?? 'morning').toString()),
      dayKey: (json['day_key'] ?? '').toString(),
      takenAt: DateTime.tryParse((json['taken_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Lifecycle bucket derived from `issued_at` + the longest item
/// duration. Mirrors the backend's `my-active` window filter so the
/// Medications hub can badge each card without another round-trip.
enum PrescriptionStatus { active, completed }

class Prescription extends Equatable {
  final String id;
  final String appointmentId;
  final String patientAccountId;
  final String doctorAccountId;
  final String doctorName;
  final String diagnosis;
  final DateTime issuedAt;
  final List<PrescriptionItem> items;
  final List<DoseLogEntry> doseLog;

  /// Full public profile of the issuing doctor (photo, specialization,
  /// hospital affiliation, BMDC licence, verified flag). Populated by
  /// every prescription read endpoint since the doctor-block
  /// enrichment landed server-side; `null` when the provider row could
  /// not be resolved — the UI falls back to [doctorName] + initials.
  final AssignedDoctor? doctor;

  /// Flat convenience mirrors of the credential fields inside
  /// [doctor], kept so older call sites (vault detail card) don't have
  /// to null-chase the nested block.
  final String doctorBmdc;
  final String doctorSpecialization;
  final bool doctorVerified;

  /// The originating visit's reported condition, surfaced as "symptoms" on
  /// the vault detail card. Only present on the detail fetch.
  final String symptoms;

  const Prescription({
    required this.id,
    required this.appointmentId,
    required this.patientAccountId,
    required this.doctorName,
    required this.diagnosis,
    required this.issuedAt,
    required this.items,
    this.doctorAccountId = '',
    this.doseLog = const [],
    this.doctor,
    this.doctorBmdc = '',
    this.doctorSpecialization = '',
    this.doctorVerified = false,
    this.symptoms = '',
  });

  /// Longest calendar window across all line items — the whole script
  /// stays "active" until every course has run out.
  int get maxDurationDays => items.fold(
      0, (m, it) => it.durationDays > m ? it.durationDays : m);

  /// Calendar day the last course lapses.
  DateTime get endsAt => issuedAt.add(Duration(days: maxDurationDays));

  /// Active vs Completed, matching the backend `my-active` window
  /// filter (a zero-duration script is treated as open-ended).
  PrescriptionStatus get status =>
      maxDurationDays <= 0 || !DateTime.now().isAfter(endsAt)
          ? PrescriptionStatus.active
          : PrescriptionStatus.completed;

  @override
  List<Object?> get props => [
        id,
        appointmentId,
        patientAccountId,
        doctorAccountId,
        doctorName,
        diagnosis,
        issuedAt,
        items,
        doseLog,
        doctor,
        doctorBmdc,
        doctorSpecialization,
        doctorVerified,
        symptoms,
      ];

  /// Is the given (item, slot, day) already logged as taken?
  bool isDoseTaken({
    required String itemId,
    required DoseSlot slot,
    required String dayKey,
  }) {
    for (final d in doseLog) {
      if (d.prescriptionItemId == itemId &&
          d.slot == slot &&
          d.dayKey == dayKey) {
        return true;
      }
    }
    return false;
  }

  factory Prescription.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    final rawLog = (json['dose_log'] as List?) ?? const [];
    final doctor = json['doctor'] is Map
        ? Map<String, dynamic>.from(json['doctor'] as Map)
        : const <String, dynamic>{};
    return Prescription(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      appointmentId: (json['appointmentId'] ??
              json['appointment_id'] ??
              '')
          .toString(),
      patientAccountId: (json['patientAccountId'] ??
              json['patient_account_id'] ??
              '')
          .toString(),
      doctorAccountId: (json['doctor_account_id'] ?? '').toString(),
      doctorName: (json['doctor_name'] ?? '').toString(),
      diagnosis: (json['diagnosis'] ?? '').toString(),
      issuedAt: DateTime.tryParse((json['issued_at'] ?? '').toString()) ??
          DateTime.now(),
      items: [
        for (final r in rawItems)
          if (r is Map)
            PrescriptionItem.fromJson(Map<String, dynamic>.from(r)),
      ],
      doseLog: [
        for (final r in rawLog)
          if (r is Map) DoseLogEntry.fromJson(Map<String, dynamic>.from(r)),
      ],
      doctor: doctor.isEmpty ? null : AssignedDoctor.fromJson(doctor),
      doctorBmdc: (doctor['bmdc_license'] ?? '').toString(),
      doctorSpecialization: (doctor['specialization'] ?? '').toString(),
      doctorVerified: (doctor['is_verified_doctor'] as bool?) ?? false,
      symptoms: (json['symptoms'] ?? '').toString(),
    );
  }
}
