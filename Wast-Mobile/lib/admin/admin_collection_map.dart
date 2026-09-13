import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../utils/map_markers.dart';
import '../utils/parse_utils.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF1F8F1);
const Color _kCard = Colors.white;
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);
const Color _kBlue = Color(0xFF1565C0);
const LatLng _kDefaultCenter = LatLng(4.9016, -1.7574);

class AdminCollectionMapPage extends StatefulWidget {
  final Map<String, dynamic> collection;

  const AdminCollectionMapPage({super.key, required this.collection});

  @override
  State<AdminCollectionMapPage> createState() => _AdminCollectionMapPageState();
}

class _AdminCollectionMapPageState extends State<AdminCollectionMapPage> {
  gm.GoogleMapController? _mapController;
  gm.BitmapDescriptor? _pickupIcon;
  gm.BitmapDescriptor? _collectorStartIcon;
  Set<gm.Marker> _markers = {};
  Set<gm.Polyline> _polylines = {};
  bool _mapReady = false;

  LatLng get _pickup {
    final lat = parseDoubleOrNull(widget.collection['pickup_lat']);
    final lng = parseDoubleOrNull(widget.collection['pickup_lng']);
    if (lat != null && lng != null) return LatLng(lat, lng);
    return _kDefaultCenter;
  }

  LatLng? get _destination {
    final lat = parseDoubleOrNull(widget.collection['destination_lat']);
    final lng = parseDoubleOrNull(widget.collection['destination_lng']);
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  LatLng? get _collectorStart {
    final lat = parseDoubleOrNull(widget.collection['collector_start_lat']);
    final lng = parseDoubleOrNull(widget.collection['collector_start_lng']);
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadIcons();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRoute());
  }

  Future<void> _loadIcons() async {
    final pickup = await MapMarkers.buildDestinationPin();
    final collectorStart = await MapMarkers.buildLocationDot(color: _kBlue);
    if (!mounted) return;
    setState(() {
      _pickupIcon = pickup;
      _collectorStartIcon = collectorStart;
      _updateMarkers();
    });
  }

  void _updateMarkers() {
    final pickup = _pickup;
    final collectorStart = _collectorStart;
    final markers = <gm.Marker>{
      gm.Marker(
        markerId: const gm.MarkerId('pickup'),
        position: gm.LatLng(pickup.latitude, pickup.longitude),
        icon: _pickupIcon ?? gm.BitmapDescriptor.defaultMarkerWithHue(gm.BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 1.0),
        infoWindow: gm.InfoWindow(
          title: 'Pickup Location',
          snippet: widget.collection['pickup_address'] as String? ?? '',
        ),
      ),
    };
    if (collectorStart != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('collector_start'),
          position: gm.LatLng(collectorStart.latitude, collectorStart.longitude),
          icon: _collectorStartIcon ?? gm.BitmapDescriptor.defaultMarkerWithHue(gm.BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const gm.InfoWindow(
            title: 'Collector Start',
          ),
        ),
      );
    }
    setState(() => _markers = markers);
  }

  Future<void> _fetchRoute() async {
    final collectorStart = _collectorStart;
    final pickup = _pickup;

    // Determine origin: collector start if available, else fall back to destination→pickup
    final LatLng origin;
    final LatLng destination;
    if (collectorStart != null) {
      origin = collectorStart;
      destination = pickup;
    } else {
      final dest = _destination;
      if (dest == null) {
        _fitCamera();
        return;
      }
      origin = dest;
      destination = pickup;
    }

    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=polyline',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted || res.statusCode != 200) {
        _setFallbackRoute(origin, destination);
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        _setFallbackRoute(origin, destination);
        return;
      }
      final route = routes[0] as Map<String, dynamic>;
      final encoded = route['geometry'] as String;
      final points = _decodePolyline(encoded);
      setState(() {
        _polylines = MapMarkers.routePolylines(
          points: points.map((p) => gm.LatLng(p.latitude, p.longitude)).toList(),
          color: _kBlue,
        );
      });
    } catch (_) {
      _setFallbackRoute(origin, destination);
    } finally {
      _fitCamera();
    }
  }

  void _setFallbackRoute(LatLng origin, LatLng destination) {
    if (!mounted) return;
    setState(() {
      _polylines = MapMarkers.fallbackPolylines(
        points: [
          gm.LatLng(origin.latitude, origin.longitude),
          gm.LatLng(destination.latitude, destination.longitude),
        ],
        color: _kBlue,
      );
    });
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void _fitCamera() {
    if (!_mapReady || _mapController == null) return;
    final pickup = _pickup;
    final collectorStart = _collectorStart;

    if (collectorStart == null) {
      _mapController!.animateCamera(
        gm.CameraUpdate.newLatLngZoom(
          gm.LatLng(pickup.latitude, pickup.longitude),
          14,
        ),
      );
      return;
    }

    final lats = [pickup.latitude, collectorStart.latitude];
    final lngs = [pickup.longitude, collectorStart.longitude];
    final bounds = gm.LatLngBounds(
      southwest: gm.LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
      northeast: gm.LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
    );
    _mapController!.animateCamera(gm.CameraUpdate.newLatLngBounds(bounds, 72));
  }

  @override
  Widget build(BuildContext context) {
    final pickupAddress = widget.collection['pickup_address'] as String? ?? '';
    final customer = widget.collection['customer_name'] as String? ?? 'Customer';
    final status = widget.collection['status'] as String? ?? '';
    final collectorStart = _collectorStart;

    // Build collector start display string
    String collectorStartDisplay;
    if (collectorStart != null) {
      collectorStartDisplay =
          '${collectorStart.latitude.toStringAsFixed(5)}, ${collectorStart.longitude.toStringAsFixed(5)}';
    } else {
      collectorStartDisplay = 'Not recorded';
    }

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Track Collection',
          style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                gm.GoogleMap(
                  initialCameraPosition: gm.CameraPosition(
                    target: gm.LatLng(_pickup.latitude, _pickup.longitude),
                    zoom: 13,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _mapReady = true;
                    _fitCamera();
                  },
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
                    ),
                    child: Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _kTextDark),
                ),
                const SizedBox(height: 12),
                _LocationRow(
                  icon: Icons.my_location,
                  color: _kBlue,
                  label: 'From',
                  value: collectorStartDisplay,
                ),
                const SizedBox(height: 10),
                _LocationRow(
                  icon: Icons.location_on,
                  color: _kPrimary,
                  label: 'To',
                  value: pickupAddress.isNotEmpty ? pickupAddress : 'Not recorded',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _LocationRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: _kTextGray, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, color: _kTextDark, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}
