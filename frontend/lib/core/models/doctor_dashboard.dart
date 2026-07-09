import 'package:equatable/equatable.dart';

import 'care_request_status.dart';
import 'doctor_review.dart';

class DoctorDashboard extends Equatable {
  final num todayEarnings;
  final int todayVisits;
  final num weekEarnings;
  final int weekVisits;
  final double rating;
  final int reviewCount;
  final int unreadCount;
  final int profileCompleteness;
  final bool availability;

  /// Most recent review — kept for the legacy single-card layout and for
  /// notifications. The fuller carousel reads from [reviews].
  final LatestReview? latestReview;

  /// Ordered list of recent testimonials (newest first). Empty when the
  /// doctor has no reviews yet.
  final List<DoctorReview> reviews;

  final PendingAssignment? pendingAssignment;
  final List<UpcomingAppointment> upcomingToday;

  const DoctorDashboard({
    required this.todayEarnings,
    required this.todayVisits,
    required this.weekEarnings,
    required this.weekVisits,
    required this.rating,
    required this.reviewCount,
    required this.unreadCount,
    required this.profileCompleteness,
    required this.availability,
    this.latestReview,
    this.reviews = const [],
    this.pendingAssignment,
    this.upcomingToday = const [],
  });

  bool get isEmpty => pendingAssignment == null && upcomingToday.isEmpty;

  /// Items missing for a complete profile, derived from completeness.
  /// In a future iteration this comes from the backend; for now we infer.
  List<ProfileChecklistItem> get profileChecklist {
    final base = const [
      ProfileChecklistItem(
        id: 'photo',
        labelEn: 'Profile photo',
        labelBn: 'প্রোফাইল ছবি',
      ),
      ProfileChecklistItem(
        id: 'license',
        labelEn: 'BMDC license number',
        labelBn: 'বিএমডিসি লাইসেন্স',
      ),
      ProfileChecklistItem(
        id: 'specialization',
        labelEn: 'Specialization details',
        labelBn: 'বিশেষজ্ঞ তথ্য',
      ),
      ProfileChecklistItem(
        id: 'experience',
        labelEn: 'Work experience',
        labelBn: 'কাজের অভিজ্ঞতা',
      ),
      ProfileChecklistItem(
        id: 'bank',
        labelEn: 'Bank / bKash payout details',
        labelBn: 'পেমেন্ট তথ্য',
      ),
    ];
    final filledCount =
        (profileCompleteness * base.length / 100).round().clamp(0, base.length);
    return [
      for (var i = 0; i < base.length; i++) base[i].withFilled(i < filledCount),
    ];
  }

  @override
  List<Object?> get props => [
        todayEarnings,
        todayVisits,
        weekEarnings,
        weekVisits,
        rating,
        reviewCount,
        unreadCount,
        profileCompleteness,
        availability,
        latestReview,
        reviews,
        pendingAssignment,
        upcomingToday,
      ];

  factory DoctorDashboard.fromJson(Map<String, dynamic> json) {
    return DoctorDashboard(
      todayEarnings: (json['todayEarnings'] as num?) ?? 0,
      todayVisits: (json['todayVisits'] as int?) ?? 0,
      weekEarnings: (json['weekEarnings'] as num?) ?? 0,
      weekVisits: (json['weekVisits'] as int?) ?? 0,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      reviewCount: (json['reviewCount'] as int?) ?? 0,
      unreadCount: (json['unreadCount'] as int?) ?? 0,
      profileCompleteness: (json['profileCompleteness'] as int?) ?? 100,
      availability: (json['availability'] as bool?) ?? true,
      latestReview: json['latestReview'] == null
          ? null
          : LatestReview.fromJson(
              json['latestReview'] as Map<String, dynamic>),
      reviews: (json['reviews'] as List?)
              ?.map((e) => DoctorReview.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      pendingAssignment: json['pendingAssignment'] == null
          ? null
          : PendingAssignment.fromJson(
              json['pendingAssignment'] as Map<String, dynamic>),
      upcomingToday: (json['upcomingToday'] as List?)
              ?.map((e) =>
                  UpcomingAppointment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class ProfileChecklistItem extends Equatable {
  final String id;
  final String labelEn;
  final String labelBn;
  final bool filled;

  const ProfileChecklistItem({
    required this.id,
    required this.labelEn,
    required this.labelBn,
    this.filled = false,
  });

  ProfileChecklistItem withFilled(bool value) {
    return ProfileChecklistItem(
      id: id,
      labelEn: labelEn,
      labelBn: labelBn,
      filled: value,
    );
  }

  @override
  List<Object?> get props => [id, labelEn, labelBn, filled];
}

class PendingAssignment extends Equatable {
  final String id;
  final String serviceNameEn;
  final String serviceNameBn;
  final num fee;
  final String duration;
  final String patientName;
  final String patientAgeSex;
  final String patientCondition;
  final String address;
  final double? distanceKm;
  final int? driveMinutes;
  final DateTime expiresAt;
  final List<String> tags;

  const PendingAssignment({
    required this.id,
    required this.serviceNameEn,
    required this.serviceNameBn,
    required this.fee,
    required this.duration,
    required this.patientName,
    required this.patientAgeSex,
    required this.patientCondition,
    required this.address,
    required this.expiresAt,
    this.distanceKm,
    this.driveMinutes,
    this.tags = const [],
  });

  Duration remainingFrom(DateTime now) {
    final r = expiresAt.difference(now);
    return r.isNegative ? Duration.zero : r;
  }

  @override
  List<Object?> get props => [
        id,
        serviceNameEn,
        serviceNameBn,
        fee,
        duration,
        patientName,
        patientAgeSex,
        patientCondition,
        address,
        distanceKm,
        driveMinutes,
        expiresAt,
        tags,
      ];

  factory PendingAssignment.fromJson(Map<String, dynamic> json) {
    return PendingAssignment(
      id: json['id']?.toString() ?? '',
      serviceNameEn: json['serviceNameEn']?.toString() ?? '',
      serviceNameBn: json['serviceNameBn']?.toString() ?? '',
      fee: (json['fee'] as num?) ?? 0,
      duration: json['duration']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
      patientAgeSex: json['patientAgeSex']?.toString() ?? '',
      patientCondition: json['patientCondition']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      driveMinutes: json['driveMinutes'] as int?,
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now().add(const Duration(seconds: 60)),
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}

class UpcomingAppointment extends Equatable {
  final String id;
  final DateTime startTime;
  final String patientName;
  final String serviceName;
  final num fee;
  final double? distanceKm;
  final String? address;

  /// Live `care_requests.status` — drives the dashboard's Accept-button
  /// visibility and the Active Service screen's bottom-action label.
  /// Empty when the backend doesn't surface it (legacy payloads).
  final String status;

  /// Patient phone number for the Message / Call CTA.
  final String? patientPhone;

  /// Patient `accounts._id` — the chat layer needs both participants'
  /// account ids to open a room and send messages.
  final String? patientAccountId;

  const UpcomingAppointment({
    required this.id,
    required this.startTime,
    required this.patientName,
    required this.serviceName,
    required this.fee,
    this.distanceKm,
    this.address,
    this.status = '',
    this.patientPhone,
    this.patientAccountId,
  });

  /// True while admin has assigned but the doctor hasn't accepted yet —
  /// the tile renders an inline Accept button only in this case.
  bool get awaitingAcceptance => status == CareRequestStatus.assigned;

  /// True once the visit is past Acceptance (en route / arrived / in service).
  bool get isActive =>
      status == CareRequestStatus.enroute ||
      status == CareRequestStatus.onTheWay ||
      status == CareRequestStatus.arrived ||
      status == CareRequestStatus.inService;

  @override
  List<Object?> get props => [
        id,
        startTime,
        patientName,
        serviceName,
        fee,
        distanceKm,
        address,
        status,
        patientPhone,
        patientAccountId,
      ];

  factory UpcomingAppointment.fromJson(Map<String, dynamic> json) {
    return UpcomingAppointment(
      id: json['id']?.toString() ?? '',
      startTime: DateTime.tryParse(json['startTime']?.toString() ?? '') ??
          DateTime.now(),
      patientName: json['patientName']?.toString() ?? '',
      serviceName: json['serviceName']?.toString() ?? '',
      fee: (json['fee'] as num?) ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      address: json['address']?.toString(),
      status: json['status']?.toString() ?? '',
      patientPhone: json['patientPhone']?.toString(),
      patientAccountId: (json['patientAccountId'] ??
              json['patient_account_id'])
          ?.toString(),
    );
  }
}

class LatestReview extends Equatable {
  final int rating;
  final String text;
  final String patientName;

  const LatestReview({
    required this.rating,
    required this.text,
    required this.patientName,
  });

  @override
  List<Object?> get props => [rating, text, patientName];

  factory LatestReview.fromJson(Map<String, dynamic> json) {
    return LatestReview(
      rating: (json['rating'] as int?) ?? 5,
      text: json['text']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
    );
  }
}
