import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../utils/map_markers.dart';
import '../utils/parse_utils.dart';
import '../utils/phone_utils.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF0F7F0);
const Color _kCard = Colors.white;
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class CollectorCollectionDetailPage extends StatefulWidget {
  final int collectionId;
  const CollectorCollectionDetailPage({super.key, required this.collectionId});

  @override
  State<CollectorCollectionDetailPage> createState() =>
      _CollectorCollectionDetailPageState();
}

class _CollectorCollectionDetailPageState
    extends State<CollectorCollectionDetailPage> {
  Map<String, dynamic>? _item;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context
          .read<AppProvider>()
          .fetchCollectorCollectionDetail(widget.collectionId);
      if (mounted) setState(() { _item = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final pLat = item?['pickupLat'] as double?;
    final pLng = item?['pickupLng'] as double?;
    final cLat = item?['collectorStartLat'] as double?;
    final cLng = item?['collectorStartLng'] as double?;
    final hasRoute = pLat != null && pLng != null && cLat != null && cLng != null;
    final hasPickup = pLat != null && pLng != null;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: Text('Collection #${widget.collectionId}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (hasRoute || hasPickup)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'View Route',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _CollectionRouteMapPage(
                    pickupLat: pLat,
                    pickupLng: pLng,
                    collectorLat: cLat,
                    collectorLng: cLng,
                    address: item?['location'] as String? ?? '',
                    distanceKm: (item?['distanceKm'] as double?) ?? 0,
                    date: item?['date'] as String? ?? '',
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : item == null
              ? const Center(child: Text('Collection not found'))
              : Column(
                  children: [
                    // Map preview — tappable
                    if (hasPickup)
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _CollectionRouteMapPage(
                              pickupLat: pLat,
                              pickupLng: pLng,
                              collectorLat: cLat,
                              collectorLng: cLng,
                              address: item['location'] as String? ?? '',
                              distanceKm: (item['distanceKm'] as double?) ?? 0,
                              date: item['date'] as String? ?? '',
                            ),
                          ),
                        ),
                        child: Stack(
                          children: [
                            SizedBox(
                              height: 200,
                              child: gm.GoogleMap(
                                initialCameraPosition: gm.CameraPosition(
                                  target: hasRoute
                                      ? gm.LatLng(
                                          (pLat + cLat) / 2,
                                          (pLng + cLng) / 2,
                                        )
                                      : gm.LatLng(pLat, pLng),
                                  zoom: hasRoute ? 12 : 15,
                                ),
                                markers: {
                                  gm.Marker(
                                    markerId: const gm.MarkerId('pickup'),
                                    position: gm.LatLng(pLat, pLng),
                                    icon: gm.BitmapDescriptor.defaultMarkerWithHue(
                                        gm.BitmapDescriptor.hueGreen),
                                  ),
                                  if (hasRoute)
                                    gm.Marker(
                                      markerId: const gm.MarkerId('collector'),
                                      position: gm.LatLng(cLat, cLng),
                                      icon: gm.BitmapDescriptor.defaultMarkerWithHue(
                                          gm.BitmapDescriptor.hueBlue),
                                    ),
                                },
                                zoomControlsEnabled: false,
                                myLocationButtonEnabled: false,
                                liteModeEnabled: true,
                              ),
                            ),
                            // "View full route" overlay
                            Positioned(
                              bottom: 10,
                              right: 10,
                              child: Material(
                                color: _kPrimary,
                                borderRadius: BorderRadius.circular(20),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.route, color: Colors.white, size: 16),
                                      SizedBox(width: 4),
                                      Text('View Route',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _card([
                            _row('Customer', item['customerName'] as String? ?? '—'),
                            _row('Phone', item['customerPhone'] as String? ?? '—',
                                onTap: () {
                                  final phone = item['customerPhone'] as String?;
                                  if (phone != null && phone.isNotEmpty) {
                                    callPhone(phone);
                                  }
                                }),
                            _row('Location', item['location'] as String? ?? '—'),
                            _row('Waste type', item['wasteType'] as String? ?? '—'),
                            _row('Distance', '${item['distanceKm']} km'),
                            _row('Date', item['date'] as String? ?? '—'),
                          ]),
                          const SizedBox(height: 12),
                          _card([
                            _row('Base price', money(item['basePrice'], prefix: 'GH₵')),
                            _row('Distance fee', money(item['distanceFee'], prefix: 'GH₵')),
                            _row('Total paid', money(item['price'], prefix: 'GH₵'),
                                bold: true, color: _kPrimary),
                            if (item['rating'] != null)
                              _row('Customer rating', '${item['rating']} ★'),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? color, VoidCallback? onTap}) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(color: _kTextGray, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  color: color ?? _kTextDark,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  fontSize: bold ? 16 : 14,
                )),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(onTap: onTap, child: child);
    }
    return child;
  }
}

// ── Full-screen route map for completed collections ───────────────────────────
class _CollectionRouteMapPage extends StatefulWidget {
  final double pickupLat, pickupLng;
  final double? collectorLat, collectorLng;
  final String address, date;
  final double distanceKm;

  const _CollectionRouteMapPage({
    required this.pickupLat,
    required this.pickupLng,
    this.collectorLat,
    this.collectorLng,
    required this.address,
    required this.date,
    required this.distanceKm,
  });

  @override
  State<_CollectionRouteMapPage> createState() => _CollectionRouteMapPageState();
}

class _CollectionRouteMapPageState extends State<_CollectionRouteMapPage> {
  gm.GoogleMapController? _mapCtrl;
  Set<gm.Polyline> _polylines = {};
  Set<gm.Marker> _markers = {};
  bool _loading = true;

  bool get _hasCollector =>
      widget.collectorLat != null && widget.collectorLng != null;

  @override
  void initState() {
    super.initState();
    _buildMarkersAndRoute();
  }

  Future<void> _buildMarkersAndRoute() async {
    // Build custom markers
    final collectorDot = await MapMarkers.buildLocationDot(
      color: const Color(0xFF1A73E8),
    );
    final pickupPin = await MapMarkers.buildDestinationPin(
      color: _kPrimary,
    );

    if (!mounted) return;

    final pickupPos = gm.LatLng(widget.pickupLat, widget.pickupLng);

    final markers = <gm.Marker>{
      gm.Marker(
        markerId: const gm.MarkerId('pickup'),
        position: pickupPos,
        icon: pickupPin,
        infoWindow: gm.InfoWindow(title: 'Pickup: ${widget.address}'),
        anchor: const Offset(0.5, 1.0),
        zIndexInt: 1,
      ),
    };

    if (_hasCollector) {
      final collectorPos =
          gm.LatLng(widget.collectorLat!, widget.collectorLng!);
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('collector'),
          position: collectorPos,
          icon: collectorDot,
          infoWindow: const gm.InfoWindow(title: 'Collector start'),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 2,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _markers = markers);

    // Fetch OSRM route if both points available
    if (_hasCollector) {
      await _fetchRoute();
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchRoute() async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${widget.collectorLng},${widget.collectorLat};'
        '${widget.pickupLng},${widget.pickupLat}'
        '?overview=full&geometries=polyline',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = body['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final pts = _decodePolyline(routes[0]['geometry'] as String);
          setState(() {
            _polylines = MapMarkers.routePolylines(
              points: pts.map((p) => gm.LatLng(p.latitude, p.longitude)).toList(),
              color: const Color(0xFF1A73E8),
            );
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    _fitCamera();
  }

  void _fitCamera() {
    if (_mapCtrl == null || !_hasCollector) return;
    final cLat = widget.collectorLat!;
    final cLng = widget.collectorLng!;
    final pLat = widget.pickupLat;
    final pLng = widget.pickupLng;
    _mapCtrl!.animateCamera(
      gm.CameraUpdate.newLatLngBounds(
        gm.LatLngBounds(
          southwest: gm.LatLng(
            cLat < pLat ? cLat : pLat,
            cLng < pLng ? cLng : pLng,
          ),
          northeast: gm.LatLng(
            cLat > pLat ? cLat : pLat,
            cLng > pLng ? cLng : pLng,
          ),
        ),
        80,
      ),
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final pts = <LatLng>[];
    int i = 0, lat = 0, lng = 0;
    while (i < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      shift = 0; result = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    final midLat = _hasCollector
        ? (widget.collectorLat! + widget.pickupLat) / 2
        : widget.pickupLat;
    final midLng = _hasCollector
        ? (widget.collectorLng! + widget.pickupLng) / 2
        : widget.pickupLng;

    return Scaffold(
      body: Stack(
        children: [
          gm.GoogleMap(
            initialCameraPosition: gm.CameraPosition(
              target: gm.LatLng(midLat, midLng),
              zoom: _hasCollector ? 13.0 : 15.0,
            ),
            onMapCreated: (c) {
              _mapCtrl = c;
              if (!_loading) _fitCamera();
            },
            markers: _markers,
            polylines: _polylines,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: _kPrimary),
            ),
          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: _kTextDark),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          // Legend + info panel at bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Legend
                    Row(
                      children: [
                        _legendItem(
                            const Color(0xFF1A73E8), Icons.circle,
                            'Collector start'),
                        const SizedBox(width: 16),
                        _legendItem(_kPrimary, Icons.location_on,
                            'Pickup point'),
                      ],
                    ),
                    const Divider(height: 16),
                    // Info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _infoChip(Icons.straighten,
                            '${widget.distanceKm.toStringAsFixed(1)} km'),
                        _infoChip(Icons.calendar_today, widget.date),
                        _infoChip(Icons.location_on_outlined, widget.address,
                            maxWidth: 140),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: _kTextGray)),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, {double? maxWidth}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _kPrimary),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? 80),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _kTextDark),
          ),
        ),
      ],
    );
  }
}
