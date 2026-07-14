import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'care_request_status.dart';
import 'patient_active_request.dart';

/// The five canonical states of the two-phase booking-confirmation lifecycle.
///
/// This is a typed VIEW over the existing `care_requests` document — it does
/// not introduce a second collection or network path. The intermediate
/// provider-dispatch states (assigned/enroute/…) collapse into
/// [BookingStatus.completed]'s "in progress" bucket for the booking surface's
/// purposes; the dedicated Tracking tab owns that detail.
enum BookingStatus {
  awaitingDeposit,
  depositPaidAdminReviewing,
  amountAssignedAwaitingFinalPayment,
  completed,
  cancelled,
}

extension BookingStatusX on BookingStatus {
  String toWire() {
    switch (this) {
      case BookingStatus.awaitingDeposit:
        return CareRequestStatus.awaitingDeposit;
      case BookingStatus.depositPaidAdminReviewing:
        return CareRequestStatus.depositPaidAdminReviewing;
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return CareRequestStatus.amountAssignedAwaitingFinalPayment;
      case BookingStatus.completed:
        return CareRequestStatus.completed;
      case BookingStatus.cancelled:
        return CareRequestStatus.cancelled;
    }
  }

  static BookingStatus fromWire(String? raw) {
    switch (raw?.toLowerCase().replaceAll('-', '_')) {
      case CareRequestStatus.awaitingDeposit:
        return BookingStatus.awaitingDeposit;
      case CareRequestStatus.depositPaidAdminReviewing:
        return BookingStatus.depositPaidAdminReviewing;
      case CareRequestStatus.amountAssignedAwaitingFinalPayment:
        return BookingStatus.amountAssignedAwaitingFinalPayment;
      case CareRequestStatus.cancelled:
      case CareRequestStatus.rejected:
        return BookingStatus.cancelled;
      // Everything from `approved` onward (the request has cleared the
      // two-phase gate and entered/finished the dispatch pipeline).
      default:
        return BookingStatus.completed;
    }
  }

  String get labelEn {
    switch (this) {
      case BookingStatus.awaitingDeposit:
        return 'Confirm your booking';
      case BookingStatus.depositPaidAdminReviewing:
        return 'Under Care Management Review';
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return 'Pending Balance Payment';
      case BookingStatus.completed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get labelBn {
    switch (this) {
      case BookingStatus.awaitingDeposit:
        return 'বুকিং নিশ্চিত করুন';
      case BookingStatus.depositPaidAdminReviewing:
        return 'পর্যালোচনায়';
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return 'বাকি পরিশোধ বাকি';
      case BookingStatus.completed:
        return 'নিশ্চিত';
      case BookingStatus.cancelled:
        return 'বাতিল';
    }
  }

  /// Status-pill foreground colour used by the patient invoice surface
  /// (paired with a 14%-alpha background of the same hue). Tuned for the
  /// midnight `#0D151C` canvas — no light surfaces, no orange.
  Color get pillColor {
    switch (this) {
      case BookingStatus.awaitingDeposit:
        return const Color(0xFFA78BFA); // violetBright
      case BookingStatus.depositPaidAdminReviewing:
        return const Color(0xFF60A5FA); // sky (reviewing)
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return const Color(0xFFFBBF24); // amber (action needed — not orange)
      case BookingStatus.completed:
        return const Color(0xFF34D399); // emerald
      case BookingStatus.cancelled:
        return const Color(0xFFF87171); // rose
    }
  }
}

/// Typed booking-transaction view of a `care_requests` document.
class BookingTransaction extends Equatable {
  final String bookingId;
  final String serviceName;
  final BookingStatus status;

  /// Fixed ৳100 slot-confirmation deposit (0 until paid).
  final double depositAmount;
  final String? depositTransactionId;
  final DateTime? depositPaidAt;

  /// Assigned by the admin after the manual phone review.
  final double? finalServiceFee;
  final double? adjustedDiscount;
  final String? adminNotes;

  const BookingTransaction({
    required this.bookingId,
    required this.serviceName,
    required this.status,
    this.depositAmount = 0,
    this.depositTransactionId,
    this.depositPaidAt,
    this.finalServiceFee,
    this.adjustedDiscount,
    this.adminNotes,
  });

  /// Outstanding balance = base fee − deposit − discount. Never negative.
  double get outstanding {
    final fee = finalServiceFee ?? 0;
    final discount = adjustedDiscount ?? 0;
    final owed = fee - depositAmount - discount;
    return owed < 0 ? 0 : owed;
  }

  bool get hasFinalPrice => (finalServiceFee ?? 0) > 0;

  /// Build from the patient's active-request view (the primary source, since
  /// the home feed already carries these fields).
  factory BookingTransaction.fromActiveRequest(PatientActiveRequest r) {
    return BookingTransaction(
      bookingId: r.id,
      serviceName: r.serviceTitleEn,
      status: BookingStatusX.fromWire(r.rawStatus),
      depositAmount: r.depositAmount,
      finalServiceFee: r.finalServiceFee,
      adjustedDiscount: r.adjustedDiscount,
    );
  }

  /// Build directly from a live snake_case `care_requests` document (e.g. a
  /// payment endpoint's response row).
  factory BookingTransaction.fromMongo(Map<String, dynamic> j) {
    double? money(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final cleaned = v.toString().replaceAll(RegExp(r'[^0-9.]'), '');
      return cleaned.isEmpty ? null : double.tryParse(cleaned);
    }

    final rawId = j['id'] ?? j['_id'];
    return BookingTransaction(
      bookingId: rawId?.toString() ?? '',
      serviceName: j['care_type']?.toString() ?? '',
      status: BookingStatusX.fromWire(j['status']?.toString()),
      depositAmount: money(j['deposit_amount']) ?? 0,
      depositTransactionId: j['deposit_transaction_id']?.toString(),
      depositPaidAt: j['deposit_paid_at'] == null
          ? null
          : DateTime.tryParse(j['deposit_paid_at'].toString()),
      finalServiceFee: money(j['final_price']),
      adjustedDiscount: money(j['adjusted_discount']),
      adminNotes: j['admin_note']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        bookingId,
        serviceName,
        status,
        depositAmount,
        depositTransactionId,
        depositPaidAt,
        finalServiceFee,
        adjustedDiscount,
        adminNotes,
      ];
}
