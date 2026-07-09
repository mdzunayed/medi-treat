import 'package:equatable/equatable.dart';

/// One chat message exchanged between a patient and the doctor assigned
/// to their care request. Wire shape mirrors the Mongoose `Message`
/// schema on the backend — `id` is the Mongo `_id`, every ObjectId
/// field arrives stringified, `timestamp` is an ISO 8601 string.
class MessageModel extends Equatable {
  final String id;
  final String appointmentId;
  final String senderId;
  final String receiverId;
  final String messageText;
  final DateTime timestamp;
  final bool isRead;

  const MessageModel({
    required this.id,
    required this.appointmentId,
    required this.senderId,
    required this.receiverId,
    required this.messageText,
    required this.timestamp,
    this.isRead = false,
  });

  /// Is this message coming FROM the supplied user — i.e. should it
  /// render right-aligned with the brand bubble?
  bool isMine(String currentUserId) => senderId == currentUserId;

  MessageModel copyWith({
    bool? isRead,
  }) =>
      MessageModel(
        id: id,
        appointmentId: appointmentId,
        senderId: senderId,
        receiverId: receiverId,
        messageText: messageText,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
      );

  @override
  List<Object?> get props => [
        id,
        appointmentId,
        senderId,
        receiverId,
        messageText,
        timestamp,
        isRead,
      ];

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    DateTime parseTs(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is DateTime) return raw;
      return DateTime.tryParse(raw.toString()) ?? DateTime.now();
    }

    return MessageModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      appointmentId: (json['appointmentId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      receiverId: (json['receiverId'] ?? '').toString(),
      messageText: (json['messageText'] ?? '').toString(),
      timestamp: parseTs(json['timestamp']),
      isRead: (json['isRead'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'appointmentId': appointmentId,
        'senderId': senderId,
        'receiverId': receiverId,
        'messageText': messageText,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };
}
