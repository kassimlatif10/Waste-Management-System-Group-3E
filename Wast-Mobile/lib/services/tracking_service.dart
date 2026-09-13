import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_constants.dart';

/// WebSocket client for real-time pickup tracking.
///
/// Fixes vs original:
///   • Exponential backoff on reconnect (1s → 2s → 4s … capped at 30s)
///   • Heartbeat ping every 25 s to keep the connection alive through
///     iOS/Android background network suspension
///   • Pong reply when server sends a ping
///   • Connection-state stream so the UI can show online/offline indicator
///   • Proper disposal order (no write-after-close races)
class TrackingService {
  WebSocketChannel? _channel;

  final _dataController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<TrackingState>.broadcast();

  bool _disposed = false;
  bool _connected = false;
  int? _requestId;
  String? _token;

  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _backoffSeconds = 1;

  /// Decoded messages from the server (location updates, status changes).
  Stream<Map<String, dynamic>> get stream => _dataController.stream;

  /// Connection state changes (connected / disconnected).
  Stream<TrackingState> get stateStream => _stateController.stream;

  bool get isConnected => _connected;

  // ── Public API ──────────────────────────────────────────────────────────────

  void connect(int requestId, String token) {
    if (_disposed) return;
    _requestId = requestId;
    _token = token;
    _backoffSeconds = 1;
    _doConnect();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    _closeChannel();
    _setConnected(false);
  }

  /// Collector sends their GPS position to the server.
  void sendLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speed,
  }) {
    _safeSend({
      'type': 'location_update',
      // Using high-precision floats for Mapbox smoothness
      'latitude': lat,
      'longitude': lng,
      'bearing': bearing,
      'speed': speed,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Broadcast a status change (on_way / arrived / completed).
  void sendStatus(String status) {
    _safeSend({'type': 'status_update', 'status': status});
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _dataController.close();
    _stateController.close();
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  void _doConnect() {
    if (_disposed || _requestId == null || _token == null) return;
    _closeChannel();

    try {
      // URL-encode the JWT token: '+' and '=' characters in base64 are not
      // URL-safe and cause 4001/4003 auth failures on some platforms (iOS).
      final encodedToken = Uri.encodeComponent(_token!);
      final uri = Uri.parse(
        '${ApiConstants.wsTracking(_requestId!)}?token=$encodedToken',
      );
      _channel = WebSocketChannel.connect(uri);
      // Listen first, mark connected only after the ready handshake succeeds
      _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
        cancelOnError: false,
      );
      _channel!.ready.then((_) {
        if (!_disposed) {
          _setConnected(true);
          _backoffSeconds = 1;
          _startHeartbeat();
        }
      }).catchError((_) {
        _onDisconnect();
      });
    } catch (_) {
      _onDisconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      // Respond to server-side pings (keeps mobile connections alive)
      if (data['type'] == 'ping') {
        _safeSend({'type': 'pong'});
        return;
      }
      _dataController.add(data);
    } catch (_) {}
  }

  void _onDisconnect() {
    if (_disposed) return;
    _setConnected(false);
    _stopHeartbeat();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoffSeconds), () {
      if (!_disposed) _doConnect();
    });
    // Exponential backoff capped at 30 s
    _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    // Send a ping every 25 s so the OS doesn't kill the idle socket
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_connected) _safeSend({'type': 'ping'});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _safeSend(Map<String, dynamic> payload) {
    if (!_connected) return;
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _closeChannel() {
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_stateController.isClosed) {
      _stateController.add(
        value ? TrackingState.connected : TrackingState.disconnected,
      );
    }
  }
}

enum TrackingState { connected, disconnected }
