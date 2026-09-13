import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../services/tracking_service.dart';
import '../services/realtime_tracking_service.dart' as rt;
import '../utils/map_markers.dart';
import '../utils/parse_utils.dart';

// TrackingState is exported from tracking_service.dart

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBlue = Color(0xFF1A73E8);
const Color _kOrange = Color(0xFFF57C00);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);
const Color _kCard = Colors.white;

class CollectorTrackingPage extends StatefulWidget {
  final Map<String, dynamic> request;
  const CollectorTrackingPage({super.key, required this.request});

  @override
  State<CollectorTrackingPage> createState() => _CollectorTrackingPageState();
}

class _CollectorTrackingPageState extends State<CollectorTrackingPage> {
  // ── Map ──────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  bool _mapReady = false;
  bool _cameraFollow = true;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // ── Custom marker icons ───────────────────────────────────────────
  BitmapDescriptor? _arrowIcon;
  BitmapDescriptor? _pinIcon;

  // ── GPS positions ────────────────────────────────────────────────
  // selfLatLng starts null so we don't compute a bad route before GPS locks.
  LatLng? _selfLatLngOpt;
  LatLng get _selfLatLng => _selfLatLngOpt ?? _customerLatLng;
  LatLng _customerLatLng = const LatLng(4.9016, -1.7574);

  // ── Trip start position & distance covered ───────────────────────
  LatLng? _startLatLng;       // collector's position when trip began
  double _distanceCoveredM = 0; // accumulated distance traveled so far

  // ── GPS streaming ─────────────────────────────────────────────────
  StreamSubscription<geo.Position>? _gpsSub;
  LatLng? _lastSentPos;
  DateTime? _lastSentAt;

  // ── Live tracking transport ──────────────────────────────────────
  // Django sessions use the WebSocket TrackingService; Supabase sessions
  // use RealtimeTrackingService (Postgres Changes) — same public API shape
  // (connect/sendLocation/sendStatus/stream/stateStream/dispose), so only
  // one of these two is ever created and driven per session.
  TrackingService? _djangoWs;
  rt.RealtimeTrackingService? _supabaseWs;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _wsConnected = false;

  double _distanceM = 0;
  double _etaSecs = 0;
  Timer? _routeThrottle;
  DateTime? _lastRouteFetch;

  // ── Pickup state ──────────────────────────────────────────────────
  bool _arrived = false;
  bool _completed = false;
  bool _proximityPromptShown = false;
  bool _onWayMarked = false; // guard so markOnWay() fires only once
  int _requestId = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final id = widget.request['id'];
    if (id is int) _requestId = id;

    // Support both camelCase (from _mapIncomingRequest) and snake_case
    // (pickup_lat/pickup_lng are the authoritative coordinate keys).
    final cusLat = (widget.request['pickup_lat'] as num?)?.toDouble()
        ?? (widget.request['customerLat'] as num?)?.toDouble();
    final cusLng = (widget.request['pickup_lng'] as num?)?.toDouble()
        ?? (widget.request['customerLng'] as num?)?.toDouble();
    if (cusLat != null && cusLng != null) {
      _customerLatLng = LatLng(cusLat, cusLng);
    }

    // Reflect the real backend status immediately — without this, reopening
    // an already in-progress job (e.g. from the dashboard's active-job
    // banner, or after an app restart) always showed the "I've Arrived"
    // button from scratch regardless of how far the job had actually
    // progressed, and re-sent now-invalid status transitions to the backend.
    final status = widget.request['status'] as String?;
    if (status == 'on_way' || status == 'arrived') _onWayMarked = true;
    if (status == 'arrived') _arrived = true;
    if (status == 'completed') {
      _arrived = true;
      _completed = true;
    }

    _updateMarkers();
    _loadMapIcons();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initGps();
      _connectWebSocket();
    });
  }

  Future<void> _loadMapIcons() async {
    final arrow = await MapMarkers.buildNavArrow();
    final pin   = await MapMarkers.buildDestinationPin();
    if (!mounted) return;
    setState(() {
      _arrowIcon = arrow;
      _pinIcon   = pin;
      _updateMarkers();
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _wsSub?.cancel();
    _djangoWs?.dispose();
    _supabaseWs?.dispose();
    _routeThrottle?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ── GPS ───────────────────────────────────────────────────────────

  Future<void> _initGps() async {
    var perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }
    if (perm == geo.LocationPermission.denied ||
        perm == geo.LocationPermission.deniedForever) {
      return;
    }

    try {
      final p = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      _onGpsUpdate(p);
    } catch (_) {}

    _gpsSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) {
      if (mounted) _onGpsUpdate(p);
    });
  }

  void _onGpsUpdate(geo.Position pos) {
    final newLatLng = LatLng(pos.latitude, pos.longitude);
    final bearing = pos.heading;
    final speed = pos.speed >= 0 ? pos.speed : 0.0;
    final firstFix = _selfLatLngOpt == null;

    // Capture the trip start position on first GPS fix
    if (firstFix) {
      _startLatLng = newLatLng;
    }

    // Accumulate distance covered since last GPS update
    if (!firstFix && _selfLatLngOpt != null) {
      final moved = ll.Distance().as(
        ll.LengthUnit.Meter,
        ll.LatLng(_selfLatLngOpt!.latitude, _selfLatLngOpt!.longitude),
        ll.LatLng(newLatLng.latitude, newLatLng.longitude),
      );
      // Filter out GPS noise (ignore jumps under 2 m or over 500 m)
      if (moved >= 2 && moved <= 500) {
        _distanceCoveredM += moved;
      }
    }

    setState(() {
      _selfLatLngOpt = newLatLng;
      _updateMarkers();
    });

    // On the very first GPS fix, fetch the route so it starts from real position
    if (firstFix && _mapReady) {
      _fetchRoute();
      _fitBothMarkers();
    }

    if (_mapReady && _cameraFollow) {
      _followSelf(newLatLng, bearing);
      _throttledFetchRoute();
    }

    // Prompt to end collection when very close to customer (~80 m)
    final distKm = ll.Distance().as(
      ll.LengthUnit.Kilometer,
      ll.LatLng(_selfLatLng.latitude, _selfLatLng.longitude),
      ll.LatLng(_customerLatLng.latitude, _customerLatLng.longitude),
    );
    if (distKm < 0.08 && !_completed && !_proximityPromptShown) {
      _proximityPromptShown = true;
      _showEndCollectionPrompt(distKm * 1000);
    }

    double movedM =
        _lastSentPos != null
            ? ll.Distance().as(
              ll.LengthUnit.Meter,
              ll.LatLng(_lastSentPos!.latitude, _lastSentPos!.longitude),
              ll.LatLng(newLatLng.latitude, newLatLng.longitude),
            )
            : 10.0;

    if (movedM > 8 || _lastSentAt == null) {
      _wsSendLocation(lat: pos.latitude, lng: pos.longitude, bearing: bearing, speed: speed);
      _lastSentPos = newLatLng;
      _lastSentAt = DateTime.now().toUtc();
    }
  }

  void _updateMarkers() {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('customer'),
        position: _customerLatLng,
        icon: _pinIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Customer Pickup'),
        anchor: const Offset(0.5, 1.0),
      ),
    };
    // Show where the collector started this trip
    if (_startLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('trip_start'),
        position: _startLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Trip Start'),
        anchor: const Offset(0.5, 1.0),
      ));
    }
    // Only add collector marker once we have real GPS
    if (_selfLatLngOpt != null) {
      markers.add(Marker(
        markerId: const MarkerId('collector'),
        position: _selfLatLng,
        icon: _arrowIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You'),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: _lastSentPos != null
            ? _calcBearing(_lastSentPos!, _selfLatLng)
            : 0.0,
      ));
    }
    _markers = markers;
  }

  // ── WebSocket ─────────────────────────────────────────────────────

  Future<void> _connectWebSocket() async {
    if (_requestId == 0) return;

    // The assigned → on_way transition must happen regardless of whether the
    // live-tracking transport connects at all — it used to live inside the
    // Django-token-gated branch below, so a Supabase session (which has no
    // Django token) skipped it entirely and silently never left 'assigned',
    // making every later "mark arrived" attempt fail with "cannot mark
    // arrived from the current status".
    if (!_onWayMarked && mounted) {
      _onWayMarked = true;
      try {
        await context.read<AppProvider>().markOnWay(requestId: _requestId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update status: ${e.toString().replaceFirst('Exception: ', '')}')),
          );
        }
      }
    }

    if (SupabaseService.isLoggedIn) {
      final ws = rt.RealtimeTrackingService();
      _supabaseWs = ws;
      ws.connect(_requestId);
      _wsSub = ws.stream.listen(_onWsMessage, onError: (_) {}, cancelOnError: false);
      ws.stateStream
          .firstWhere((s) => s == rt.TrackingState.connected)
          .timeout(const Duration(seconds: 8))
          .then((_) { if (mounted) setState(() => _wsConnected = true); })
          .catchError((_) { if (mounted) setState(() => _wsConnected = false); });
      return;
    }

    final token = await ApiService.getAccessToken();
    if (token == null) return;
    final ws = TrackingService();
    _djangoWs = ws;
    ws.connect(_requestId, token);
    _wsSub = ws.stream.listen(
      _onWsMessage,
      onError: (_) {},
      cancelOnError: false,
    );
    // Wait for the handshake before sending the first status message so it
    // isn't silently dropped.
    ws.stateStream
        .firstWhere((s) => s == TrackingState.connected)
        .timeout(const Duration(seconds: 8))
        .then((_) {
          if (mounted && !_arrived) ws.sendStatus('on_way');
          if (mounted) setState(() => _wsConnected = true);
        })
        .catchError((_) {
          if (mounted) setState(() => _wsConnected = false);
        });
  }

  void _onWsMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type'] as String?;
    if (type == 'status_update') {
      final s = data['status'] as String?;
      if (s == 'completed' && !_completed) {
        setState(() => _completed = true);
      }
    }
  }

  void _wsSendLocation({required double lat, required double lng, required double bearing, required double speed}) {
    _supabaseWs?.sendLocation(lat: lat, lng: lng, bearing: bearing, speed: speed);
    _djangoWs?.sendLocation(lat: lat, lng: lng, bearing: bearing, speed: speed);
  }

  void _wsSendStatus(String status) {
    _supabaseWs?.sendStatus(status);
    _djangoWs?.sendStatus(status);
  }

  // ── Camera ────────────────────────────────────────────────────────

  void _followSelf(LatLng pos, double bearing) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos,
          bearing: bearing,
          tilt: 45.0,
          zoom: 16.0,
        ),
      ),
    );
  }

  void _fitBothMarkers() {
    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(_selfLatLng.latitude, _customerLatLng.latitude),
        math.min(_selfLatLng.longitude, _customerLatLng.longitude),
      ),
      northeast: LatLng(
        math.max(_selfLatLng.latitude, _customerLatLng.latitude),
        math.max(_selfLatLng.longitude, _customerLatLng.longitude),
      ),
    );
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  void _zoomToCustomer() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _customerLatLng, zoom: 18.0),
      ),
    );
  }

  // ── Route (Google Directions API) ─────────────────────────────────

  void _throttledFetchRoute() {
    final now = DateTime.now();
    if (_lastRouteFetch != null &&
        now.difference(_lastRouteFetch!).inSeconds < 5) {
      return;
    }
    _routeThrottle?.cancel();
    _routeThrottle = Timer(const Duration(seconds: 2), _fetchRoute);
  }

  Future<void> _fetchRoute() async {
    if (!mounted) return;
    _lastRouteFetch = DateTime.now();

    final selfLat = _selfLatLng.latitude;
    final selfLng = _selfLatLng.longitude;
    final cusLat = _customerLatLng.latitude;
    final cusLng = _customerLatLng.longitude;

    try {
      // OSRM open routing — road-following polylines, no API key needed
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$selfLng,$selfLat;$cusLng,$cusLat'
        '?overview=full&geometries=polyline',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted || res.statusCode != 200) {
        _setFallbackRoute();
        return;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        _setFallbackRoute();
        return;
      }

      final route   = routes[0] as Map<String, dynamic>;
      final distance = (route['distance'] as num).toDouble();
      final duration = (route['duration'] as num).toDouble();
      final encoded  = route['geometry'] as String;
      final points   = _decodePolyline(encoded);

      if (!mounted) return;
      setState(() {
        _distanceM = distance;
        _etaSecs = duration;
        _polylines = MapMarkers.routePolylines(points: points);
      });
    } catch (_) {
      _setFallbackRoute();
    }
  }

  void _setFallbackRoute() {
    if (!mounted) return;
    setState(() {
      _polylines = MapMarkers.fallbackPolylines(
        points: [_selfLatLng, _customerLatLng],
      );
    });
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // ── Bearing ───────────────────────────────────────────────────────

  double _calcBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  // ── Formatters ────────────────────────────────────────────────────

  String get _distanceText {
    if (_distanceM > 0) {
      return _distanceM >= 1000
          ? '${(_distanceM / 1000).toStringAsFixed(1)} km'
          : '${_distanceM.round()} m';
    }
    return '--';
  }

  String get _distanceCoveredText {
    if (_distanceCoveredM >= 1000) {
      return '${(_distanceCoveredM / 1000).toStringAsFixed(1)} km';
    }
    return '${_distanceCoveredM.round()} m';
  }

  String get _etaText {
    if (_etaSecs > 0) {
      final m = (_etaSecs / 60).round();
      if (m >= 60) {
        final h = m ~/ 60;
        final rem = m % 60;
        return rem > 0 ? '$h hr $rem min' : '$h hr';
      }
      return m > 0 ? '$m min' : '< 1 min';
    }
    return '--';
  }

  // ── Actions ───────────────────────────────────────────────────────

  Future<void> _showEndCollectionPrompt(double distanceM) async {
    if (!mounted || _completed) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Near Pickup Location'),
        content: Text(
          'You are about ${distanceM.round()} m from the customer. '
          'Has the waste been collected? Tap End Collection to complete this pickup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: const Text('End Collection'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (!_arrived) await _markArrived();
      await _completePickup();
    }
  }

  Future<void> _markArrived() async {
    if (_arrived) return;
    setState(() => _arrived = true);
    _zoomToCustomer();
    // Broadcast via WS (instant customer feedback)
    _wsSendStatus('arrived');
    // Persist to backend DB (on_way → arrived)
    try {
      await context.read<AppProvider>().markArrived(requestId: _requestId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _arrived = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark arrived: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _completePickup() async {
    if (_completed) return;
    setState(() => _completed = true);
    // Broadcast via WS (customer sees "completed" immediately)
    _wsSendStatus('completed');
    // Persist to backend DB and credit collector earnings
    try {
      await context.read<AppProvider>().completePickup(requestId: _requestId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _completed = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete pickup: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const sheetInit = 0.32;
    const sheetMin = 0.22;
    const sheetMax = 0.65;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selfLatLng,
              zoom: 14.0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              setState(() => _mapReady = true);
              // Only fit/fetch once we have real GPS — avoids stale-position route
              if (_selfLatLngOpt != null) {
                _fitBothMarkers();
                _fetchRoute();
              }
            },
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onTap: (_) => setState(() => _cameraFollow = false),
          ),

          // ── ETA pill ────────────────────────────────────────────────
          if (_mapReady && _etaSecs > 0 && !_arrived)
            Positioned(
              left: 16,
              bottom: MediaQuery.of(context).size.height * sheetInit + 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _kBlue,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_etaText  ·  $_distanceText',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Map controls ─────────────────────────────────────────────
          Positioned(
            right: 14,
            bottom: MediaQuery.of(context).size.height * sheetInit + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapBtn(
                  onTap: _fitBothMarkers,
                  child: const Icon(
                    Icons.center_focus_strong,
                    color: _kTextDark,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 8),
                _MapBtn(
                  onTap: () => setState(() => _cameraFollow = !_cameraFollow),
                  child: Icon(
                    _cameraFollow
                        ? Icons.my_location
                        : Icons.location_searching,
                    color: _cameraFollow ? _kBlue : _kTextGray,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          // ── Top bar ──────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _MapBtn(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back,
                      color: _kTextDark,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  _StatusChip(
                    arrived: _arrived,
                    connected: _wsConnected,
                    distanceText: _distanceText,
                  ),
                ],
              ),
            ),
          ),

          // ── Draggable bottom sheet ───────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: sheetInit,
            minChildSize: sheetMin,
            maxChildSize: sheetMax,
            builder:
                (ctx, scrollCtrl) => Container(
                  decoration: const BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 20,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Customer info row
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.red,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (widget.request['customerName'] as String?)
                                              ?.isNotEmpty ==
                                          true
                                      ? widget.request['customerName'] as String
                                      : 'Customer',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: _kTextDark,
                                  ),
                                ),
                                if ((widget.request['phone'] as String?)
                                        ?.isNotEmpty ==
                                    true)
                                  Text(
                                    widget.request['phone'] as String,
                                    style: const TextStyle(
                                      color: _kTextGray,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      const Divider(color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 10),

                      _InfoRow(
                        icon: Icons.location_on_outlined,
                        label: 'Pickup',
                        value: (widget.request['location'] as String?) ?? '--',
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.delete_outline,
                        label: 'Waste',
                        value: (widget.request['wasteType'] as String?) ?? '--',
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.social_distance_outlined,
                        label: 'Remaining',
                        value: _distanceText,
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.route_outlined,
                        label: 'Covered',
                        value: _distanceCoveredText,
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.payments_outlined,
                        label: 'Earnings',
                        value: money(widget.request['price'], prefix: 'GH₵', fallback: '--'),
                      ),

                      const SizedBox(height: 20),

                      if (_completed)
                        Container(
                          width: double.infinity,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _kPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'Pickup Completed',
                            style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        )
                      else if (_arrived)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _completePickup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Complete Pickup',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _markArrived,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kOrange,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              "I've Arrived at Customer",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 28),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final bool arrived;
  final bool connected;
  final String distanceText;
  const _StatusChip({
    required this.arrived,
    required this.connected,
    required this.distanceText,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        arrived
            ? _kPrimary
            : connected
            ? _kBlue
            : _kTextGray;
    final label =
        arrived
            ? 'Arrived'
            : connected
            ? distanceText
            : 'Connecting…';
    final icon = arrived ? Icons.check_circle : Icons.navigation;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: _kTextGray),
      const SizedBox(width: 10),
      SizedBox(
        width: 60,
        child: Text(
          label,
          style: const TextStyle(color: _kTextGray, fontSize: 13),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            color: _kTextDark,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    ],
  );
}

class _MapBtn extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _MapBtn({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.13), blurRadius: 8),
        ],
      ),
      child: Center(child: child),
    ),
  );
}
