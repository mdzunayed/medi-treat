import 'package:equatable/equatable.dart';

/// Rich message kind. Attachments are scaffolded — the wire + render paths
/// handle them if present, but only [text] is sent in this pass.
enum MessageType { text, image, document, location }

MessageType _messageTypeFrom(dynamic raw) {
  switch (raw?.toString().toUpperCase()) {
    case 'IMAGE':
      return MessageType.image;
    case 'DOCUMENT':
      return MessageType.document;
    case 'LOCATION':
      return MessageType.location;
    case 'TEXT':
    default:
      return MessageType.text;
  }
}

/// One chat message. Serves BOTH thread models the backend shares in the
/// single `messages` collection:
///   • Appointment chat (legacy 1:1) — [appointmentId] + [receiverId] set.
///   • Conversation engine (multi-role / group) — [conversationId] set,
///     with the richer [senderRole] / [senderName] / [messageType] fields.
/// Wire shape mirrors the Mongoose `Message` schema; every ObjectId field
/// arrives stringified and `timestamp` is an ISO 8601 string.
class MessageModel extends Equatable {
  final String id;
  final String appointmentId;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final String senderRole;
  final String senderName;
  final MessageType messageType;
  final String? attachmentUrl;
  final String messageText;
  final DateTime timestamp;
  final bool isRead;

  const MessageModel({
    required this.id,
    this.appointmentId = '',
    this.conversationId = '',
    required this.senderId,
    this.receiverId = '',
    this.senderRole = '',
    this.senderName = '',
    this.messageType = MessageType.text,
    this.attachmentUrl,
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
        conversationId: conversationId,
        senderId: senderId,
        receiverId: receiverId,
        senderRole: senderRole,
        senderName: senderName,
        messageType: messageType,
        attachmentUrl: attachmentUrl,
        messageText: messageText,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
      );

  @override
  List<Object?> get props => [
        id,
        appointmentId,
        conversationId,
        senderId,
        receiverId,
        senderRole,
        senderName,
        messageType,
        attachmentUrl,
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
      conversationId: (json['conversationId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      receiverId: (json['receiverId'] ?? '').toString(),
      senderRole: (json['senderRole'] ?? '').toString(),
      senderName: (json['senderName'] ?? '').toString(),
      messageType: _messageTypeFrom(json['messageType']),
      attachmentUrl: (json['attachmentUrl'] as String?)?.isNotEmpty == true
          ? json['attachmentUrl'] as String
          : null,
      messageText: (json['messageText'] ?? '').toString(),
      timestamp: parseTs(json['timestamp']),
      isRead: (json['isRead'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'appointmentId': appointmentId,
        'conversationId': conversationId,
        'senderId': senderId,
        'receiverId': receiverId,
        'senderRole': senderRole,
        'senderName': senderName,
        'messageType': messageType.name.toUpperCase(),
        'attachmentUrl': attachmentUrl,
        'messageText': messageText,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };
}
