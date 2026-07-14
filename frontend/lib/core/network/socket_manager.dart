import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../features/auth/auth_provider.dart';
import '../storage/app_prefs.dart';

// Same origin as the REST client (DioClient._baseUrl) — the socket and the
// API must point at the same backend. Both read the single `API_BASE_URL`
// define, so `--dart-define=API_BASE_URL=http://localhost:5000` steers both at
// once; this default only applies when no define is passed (deployed builds).
const String _socketBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:5000',
);

/// An incoming dispatch pushed by the backend over `dispatch:incoming` the
/// instant an admin assigns this clinician a visit.
class DispatchAlert {
  final String appointmentId;
  final String patientName;
  final String careType;
  final String role;
  final String deepLink;

  const DispatchAlert({
    required this.appointmentId,
    required this.patientName,
    required this.careType,
    required this.role,
    required this.deepLink,
  });

  factory DispatchAlert.fromJson(Map<String, dynamic> json) {
    return DispatchAlert(
      appointmentId: (json['appointmentId'] ?? '').toString(),
      patientName: (json['patientName'] ?? 'A patient').toString(),
      careType: (json['careType'] ?? 'a visit').toString(),
      role: (json['role'] ?? '').toString(),
      deepLink: (json['deepLink'] ?? '').toString(),
    );
  }
}

/// The single authenticated, app-wide Socket.io connection for the signed-in
/// user. Connects with the JWT in the handshake (`auth.token`) so the backend
/// can validate it and auto-join this socket to its `user:<id>` + role rooms,
/// then fans the incoming server events out as broadcast streams that feature
/// providers subscribe to — so the whole app shares ONE socket instead of
/// each feature opening its own anonymous connection.
class SocketManager {
  SocketManager({required String token, required String accountId})
      : _accountId = accountId {
    _connect(token);
  }

  final String _accountId;
  io.Socket? _socket;
  bool _disposed = false;

  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  final _dispatches = StreamController<DispatchAlert>.broadcast();
  final _statusChanges = StreamController<Map<String, dynamic>>.broadcast();

  /// `new_notification` payloads (bell badge + hub list).
  Stream<Map<String, dynamic>> get onNotification => _notifications.stream;

  /// `dispatch:incoming` events (intrusive incoming-dispatch overlay).
  Stream<DispatchAlert> get onDispatch => _dispatches.stream;

  /// `appointment_status_change` events (live tracking / console state).
  Stream<Map<String, dynamic>> get onStatusChange => _statusChanges.stream;

  void _connect(String token) {
    final socket = io.io(
      _socketBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1500)
          // Bounded retries: without a cap a rejected handshake (dead JWT,
          // backend down) silently re-dials every 1.5 s forever. A refreshed
          // token rebuilds the whole manager via socketManagerProvider, which
          // resets this budget.
          .setReconnectionAttempts(10)
          .build(),
    );

    socket.onConnectError((err) {
      if (_disposed) return;
      assert(() {
        debugPrint('[socket] connect error: $err');
        return true;
      }());
    });

    socket.onConnect((_) {
      if (_disposed) return;
      // Belt-and-suspenders: the JWT handshake already auto-joins the user +
      // role rooms server-side; emitting `register_user` keeps the legacy
      // room-join path working too, so notifications land either way.
      socket.emit('register_user', _accountId);
    });

    socket.on('new_notification', (payload) {
      if (_disposed || payload is! Map) return;
      _notifications.add(Map<String, dynamic>.from(payload));
    });

    socket.on('dispatch:incoming', (payload) {
      if (_disposed || payload is! Map) return;
      try {
        _dispatches
            .add(DispatchAlert.fromJson(Map<String, dynamic>.from(payload)));
      } catch (_) {
        // Drop a malformed dispatch packet rather than crashing the stream.
      }
    });

    socket.on('appointment_status_change', (payload) {
      if (_disposed || payload is! Map) return;
      _statusChanges.add(Map<String, dynamic>.from(payload));
    });

    _socket = socket;
    socket.connect();
  }

  void dispose() {
    _disposed = true;
    final socket = _socket;
    if (socket != null) {
      try {
        socket.emit('unregister_user', _accountId);
        socket.off('new_notification');
        socket.off('dispatch:incoming');
        socket.off('appointment_status_change');
        socket.disconnect();
        socket.dispose();
      } catch (_) {
        // best-effort teardown
      }
      _socket = null;
    }
    _notifications.close();
    _dispatches.close();
    _statusChanges.close();
  }
}

/// The live [SocketManager] for the signed-in session, or `null` when no one
/// is signed in. Rebuilds (reconnects) when the auth token changes and is
/// disposed when no longer watched.
final socketManagerProvider = Provider.autoDispose<SocketManager?>((ref) {
  // The LIVE JWT comes from the [tokenProvider] leaf — the same source the
  // Dio interceptor reads. A silent 401 refresh updates only that leaf (it
  // never touches authTokenProvider), so watching it here is what lets the
  // socket rebuild with the fresh token instead of reconnect-looping on the
  // dead one. Session expiry nulls the leaf → socket tears down too.
  final token = ref.watch(tokenProvider);
  final accountId = ref.watch(authTokenProvider).valueOrNull?.user.id;
  if (token == null ||
      token.isEmpty ||
      accountId == null ||
      accountId.isEmpty) {
    return null;
  }
  final manager = SocketManager(token: token, accountId: accountId);
  ref.onDispose(manager.dispose);
  return manager;
});

/// Holds the latest incoming dispatch for the global overlay host. Subscribes
/// to the authenticated socket's `onDispatch` stream; `dismiss()` clears it.
class DispatchAlertController extends StateNotifier<DispatchAlert?> {
  DispatchAlertController(this._ref) : super(null) {
    final manager = _ref.read(socketManagerProvider);
    _sub = manager?.onDispatch.listen((alert) {
      if (mounted) state = alert;
    });
  }

  final Ref _ref;
  StreamSubscription<DispatchAlert>? _sub;

  void dismiss() => state = null;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final dispatchAlertProvider =
    StateNotifierProvider.autoDispose<DispatchAlertController, DispatchAlert?>(
        (ref) {
  // Keep the underlying socket alive while the overlay host is mounted.
  ref.watch(socketManagerProvider);
  return DispatchAlertController(ref);
});
