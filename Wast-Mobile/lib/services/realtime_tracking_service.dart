import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live pickup tracking, replacing [TrackingService] (the Django Channels
/// WebSocket client). Same public API shape (connect/disconnect/
/// sendLocation/sendStatus/stream/stateStream) so it's a drop-in swap once
/// a screen is migrated.
///
/// Implementation: Postgres Changes on the pickup_requests row, which
/// already has correct RLS (customer_id = auth.uid() or collector_id =
/// auth.uid()) from Phase 1 — both location and status updates ride the
/// same subscription. (Realtime Broadcast private-channel authorization
/// was the original design, but that needs ownership of realtime.messages
/// that isn't grantable on this project — confirmed blocked via direct
/// connection, the Management API, and the Dashboard SQL Editor alike.)
class RealtimeTrackingService {
  RealtimeChannel? _channel;
  int? _requestId;

  final _dataController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<TrackingState>.broadcast();

  bool _disposed = false;
  bool _connected = false;

  Stream<Map<String, dynamic>> get stream => _dataController.stream;
  Stream<TrackingState> get stateStream => _stateController.stream;
  bool get isConnected => _connected;

  void connect(int requestId) {
    if (_disposed) return;
    _closeChannel();
    _requestId = requestId;

    final client = Supabase.instance.client;
    _channel = client.channel('pickup_request_tracking_$requestId');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pickup_requests',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: requestId),
          callback: (payload) {
            final row = payload.newRecord;
            if (row['collector_current_lat'] != null && row['collector_current_lng'] != null) {
              _dataController.add({
                'type': 'location_update',
                'latitude': row['collector_current_lat'],
                'longitude': row['collector_current_lng'],
              });
            }
            _dataController.add({'type': 'status_update', 'status': row['status']});
          },
        )
        .subscribe((status, error) {
          if (_disposed) return;
          _setConnected(status == RealtimeSubscribeStatus.subscribed);
        });
  }

  void disconnect() {
    _closeChannel();
    _setConnected(false);
  }

  /// Collector pushes their GPS position — written directly to the
  /// pickup_requests row (RLS already restricts this to collector_id =
  /// auth.uid()), which is what the subscription above picks up.
  Future<void> sendLocation({
    required double lat,
    required double lng,
    required double bearing,
    required double speed,
  }) async {
    if (_requestId == null) return;
    await Supabase.instance.client.from('pickup_requests').update({
      'collector_current_lat': lat,
      'collector_current_lng': lng,
    }).eq('id', _requestId!);
  }

  /// Status is already updated via the mark_pickup_on_way/arrived/complete
  /// RPCs — this is a no-op kept only so callers don't need special-casing.
  void sendStatus(String status) {}

  void dispose() {
    _disposed = true;
    disconnect();
    _dataController.close();
    _stateController.close();
  }

  void _closeChannel() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_stateController.isClosed) {
      _stateController.add(value ? TrackingState.connected : TrackingState.disconnected);
    }
  }
}

enum TrackingState { connected, disconnected }
