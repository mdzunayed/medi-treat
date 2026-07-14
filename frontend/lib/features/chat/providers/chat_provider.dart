import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/audio/notification_sound_service.dart';
import '../../auth/auth_provider.dart';
import '../models/message_model.dart';

/// Async UI status for the chat surface. Mirrors the AsyncValue pattern
/// used elsewhere in the app but as a flat enum so the screen can
/// switch on it cheaply.
enum ChatStatus { idle, loading, ready, error }

/// Immutable state container for one open chat (one appointment +
/// participant pair).
@immutable
class ChatState {
  final ChatStatus status;
  final List<MessageModel> messages;
  final String? errorMessage;
  final bool isConnected;
  final bool isSending;

  /// Live appointment status as broadcast by
  /// `appointment_status_change`. Drives the chat input lockdown:
  /// when the value transitions to `completed`, the input pane is
  /// disabled on BOTH sides and the conversation reads as a
  /// historical transcript. `null` means the status hasn't been
  /// reported yet (defaults to "open for messaging").
  final String? appointmentStatus;

  const ChatState({
    this.status = ChatStatus.idle,
    this.messages = const [],
    this.errorMessage,
    this.isConnected = false,
    this.isSending = false,
    this.appointmentStatus,
  });

  /// `true` when the visit is still in-flight — accepted /
  /// on-the-way / arrived / in-service. The chat is read-only once
  /// the status flips to `completed` / `cancelled` / `rejected`.
  bool get canSendMessages {
    final s = appointmentStatus;
    if (s == null) return true;
    const closed = {'completed', 'cancelled', 'rejected'};
    return !closed.contains(s);
  }

  ChatState copyWith({
    ChatStatus? status,
    List<MessageModel>? messages,
    String? errorMessage,
    bool clearError = false,
    bool? isConnected,
    bool? isSending,
    String? appointmentStatus,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isConnected: isConnected ?? this.isConnected,
      isSending: isSending ?? this.isSending,
      appointmentStatus: appointmentStatus ?? this.appointmentStatus,
    );
  }
}

/// Per-conversation key — one `(appointmentId, currentUserId)` pair gets
/// one notifier instance. `autoDispose` cleans the socket when the
/// patient navigates away.
class ChatArgs {
  final String appointmentId;
  final String currentUserId;
  final String otherUserId;

  const ChatArgs({
    required this.appointmentId,
    required this.currentUserId,
    required this.otherUserId,
  });

  @override
  bool operator ==(Object other) =>
      other is ChatArgs &&
      other.appointmentId == appointmentId &&
      other.currentUserId == currentUserId &&
      other.otherUserId == otherUserId;

  @override
  int get hashCode => Object.hash(appointmentId, currentUserId, otherUserId);
}

/// Riverpod notifier driving the chat surface. Owns the Socket.io
/// connection lifecycle: opens on creation, joins the appointment room,
/// listens for `receive_message`, and tears everything down on dispose.
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier(this.ref, this.args) : super(const ChatState()) {
    _bootstrap();
  }

  final Ref ref;
  final ChatArgs args;
  io.Socket? _socket;
  bool _disposed = false;

  // The Dio client + the socket connection both target the same
  // backend host. We pull the base URL out of DioClient so a single
  // `--dart-define=API_BASE_URL=…` covers both transports.
  static const String _socketBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000',
  );

  Future<void> _bootstrap() async {
    state = state.copyWith(status: ChatStatus.loading, clearError: true);
    try {
      await _loadHistory();
      _connectSocket();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // --- HTTP history --------------------------------------------------------

  Future<void> _loadHistory() async {
    final client = ref.read(dioClientProvider);
    final rawList = await client.getChatHistory(args.appointmentId);
    final parsed = <MessageModel>[];
    for (final raw in rawList) {
      try {
        parsed.add(MessageModel.fromJson(raw));
      } catch (_) {
        // Skip a malformed row, keep the rest of the conversation.
      }
    }
    if (_disposed) return;
    state = state.copyWith(
      status: ChatStatus.ready,
      messages: parsed,
    );
  }

  // --- Socket lifecycle ----------------------------------------------------

  void _connectSocket() {
    if (_socket != null) return;
    final socket = io.io(
      _socketBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1500)
          .build(),
    );

    socket.onConnect((_) {
      if (_disposed) return;
      state = state.copyWith(isConnected: true);
      socket.emit('join_room', args.appointmentId);
    });

    socket.on('receive_message', (payload) {
      if (_disposed) return;
      if (payload is! Map) return;
      try {
        final incoming =
            MessageModel.fromJson(Map<String, dynamic>.from(payload));
        // De-dupe — the optimistic local row gets replaced by the
        // canonical one if their ids match (or appointmentId+text+sender
        // collision for the fallback case).
        final list = [...state.messages];
        final existingIdx = list.indexWhere((m) => m.id == incoming.id);
        final isBrandNew = existingIdx < 0;
        if (existingIdx >= 0) {
          list[existingIdx] = incoming;
        } else {
          list.add(incoming);
        }
        state = state.copyWith(messages: list);
        // Sound feedback fires only when the message is BOTH new to
        // this client AND not our own outbound echo — otherwise every
        // tap of "Send" would ring our own ears.
        if (isBrandNew && !incoming.isMine(args.currentUserId)) {
          // ignore: unawaited_futures
          ref.read(notificationSoundProvider).playBubble();
        }
      } catch (e) {
        assert(() {
          debugPrint('[chat] failed to parse incoming message: $e');
          return true;
        }());
      }
    });

    // Provider-driven status transitions broadcast by
    // `PATCH /api/appointments/:id/update-status`. The chat input
    // gate watches `state.canSendMessages`; the moment the visit
    // flips to `completed` the send button + text field disable
    // automatically on both sides — no extra round-trip needed.
    socket.on('appointment_status_change', (payload) {
      if (_disposed) return;
      if (payload is! Map) return;
      final apptId = payload['appointmentId']?.toString();
      if (apptId != args.appointmentId) return;
      final wireStatus = payload['status']?.toString().toLowerCase();
      if (wireStatus == null || wireStatus.isEmpty) return;
      state = state.copyWith(appointmentStatus: wireStatus);
    });

    socket.onDisconnect((_) {
      if (_disposed) return;
      state = state.copyWith(isConnected: false);
    });

    socket.onConnectError((err) {
      assert(() {
        debugPrint('[chat] socket connect error: $err');
        return true;
      }());
    });

    socket.onError((err) {
      assert(() {
        debugPrint('[chat] socket error: $err');
        return true;
      }());
    });

    _socket = socket;
    socket.connect();
  }

  // --- Send ----------------------------------------------------------------

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // Spec guardrail — once the appointment status is `completed`
    // (or otherwise closed) the conversation becomes read-only on
    // both sides. The UI also disables the input, but this is the
    // server-of-truth gate so a stale-cache client still can't push
    // a new row into a completed thread.
    if (!state.canSendMessages) return;
    final socket = _socket;
    if (socket == null) return;

    state = state.copyWith(isSending: true);
    final completer = Completer<void>();
    socket.emitWithAck(
      'send_message',
      {
        'appointmentId': args.appointmentId,
        'senderId': args.currentUserId,
        'receiverId': args.otherUserId,
        'messageText': trimmed,
      },
      ack: (response) {
        if (_disposed) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        if (response is Map && response['ok'] == false) {
          state = state.copyWith(
            isSending: false,
            errorMessage: response['message']?.toString() ?? 'Send failed',
          );
        } else {
          // Success — the `receive_message` broadcast we'll see in a
          // moment carries the canonical row. Nothing else to do.
          state = state.copyWith(isSending: false, clearError: true);
        }
        if (!completer.isCompleted) completer.complete();
      },
    );
    // Safety timeout — without an ack from the server we shouldn't hang
    // the UI's "Sending…" indicator forever.
    Future<void>.delayed(const Duration(seconds: 8)).then((_) {
      if (!completer.isCompleted) {
        completer.complete();
        if (!_disposed && state.isSending) {
          state = state.copyWith(isSending: false);
        }
      }
    });
    return completer.future;
  }

  /// Re-load history from the server (pull-to-refresh).
  Future<void> refresh() async {
    try {
      await _loadHistory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final socket = _socket;
    if (socket != null) {
      try {
        socket.emit('leave_room', args.appointmentId);
        socket.off('receive_message');
        socket.off('appointment_status_change');
        socket.disconnect();
        socket.dispose();
      } catch (_) {
        // Best-effort cleanup — failure here is harmless because we're
        // tearing down anyway.
      }
      _socket = null;
    }
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, ChatArgs>(
  (ref, args) => ChatNotifier(ref, args),
);
