import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../constants/api_constants.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../services/app_config.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

bool looksLikeCoordinates(String value) {
  final trimmed = value.trim();
  return RegExp(r'^-?\d+\.\d+\s*,\s*-?\d+\.\d+$').hasMatch(trimmed);
}

Future<String> reverseGeocodeAddress(double lat, double lng) async {
  // Prefer backend geocoding (server API key, no mobile restrictions) —
  // whichever backend this session actually has a working session for.
  if (SupabaseService.isLoggedIn) {
    try {
      final address = await SupabaseService.reverseGeocode(lat, lng);
      if (address != null && address.trim().isNotEmpty && !looksLikeCoordinates(address)) {
        return address.trim();
      }
    } catch (_) {}
  } else {
    try {
      final res = await ApiService.get(ApiConstants.geoReverse(lat, lng));
      final address = res['address'] as String?;
      if (address != null &&
          address.trim().isNotEmpty &&
          !looksLikeCoordinates(address)) {
        return address.trim();
      }
    } catch (_) {}
  }

  // Direct Google Geocoding fallback.
  try {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=$lat,$lng'
      '&region=gh'
      '&language=en'
      '&key=${AppConfig.googleMapsApiKey}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? [];
      const preferred = [
        'street_address',
        'route',
        'premise',
        'subpremise',
        'neighborhood',
        'sublocality',
        'locality',
      ];
      for (final type in preferred) {
        for (final item in results) {
          final types = (item['types'] as List?)?.cast<String>() ?? [];
          if (types.contains(type)) {
            final address = item['formatted_address'] as String?;
            if (address != null && address.trim().isNotEmpty) {
              return address.trim();
            }
          }
        }
      }
      if (results.isNotEmpty) {
        final address = results[0]['formatted_address'] as String?;
        if (address != null && address.trim().isNotEmpty) {
          return address.trim();
        }
      }
    }
  } catch (_) {}

  return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
  if (SupabaseService.isLoggedIn) {
    try {
      final results = await SupabaseService.searchAddress(query);
      if (results.isNotEmpty) {
        return results.map((map) => {
              'address': map['address'] as String,
              'lat': (map['lat'] as num).toDouble(),
              'lng': (map['lng'] as num).toDouble(),
            }).toList();
      }
    } catch (_) {}
  } else {
    try {
      final res = await ApiService.get(ApiConstants.geoSearch(query));
      final raw = (res['results'] as List?) ?? [];
      return raw.map<Map<String, dynamic>>((item) {
        final map = item as Map<String, dynamic>;
        return {
          'address': map['address'] as String,
          'lat': (map['lat'] as num).toDouble(),
          'lng': (map['lng'] as num).toDouble(),
        };
      }).toList();
    } catch (_) {}
  }

  // Direct geocode fallback if backend search fails.
  try {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?address=${Uri.encodeComponent(query)}'
      '&region=gh'
      '&components=country:GH'
      '&language=en'
      '&key=${AppConfig.googleMapsApiKey}',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? [];
    return results.take(8).map<Map<String, dynamic>>((item) {
      final loc = (item['geometry'] as Map)['location'] as Map;
      return {
        'address': item['formatted_address'] as String,
        'lat': (loc['lat'] as num).toDouble(),
        'lng': (loc['lng'] as num).toDouble(),
      };
    }).toList();
  } catch (_) {
    return [];
  }
}

Future<Map<String, dynamic>?> showLocationPicker(BuildContext context, {bool allowAnyLocation = false}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LocationPickerSheet(allowAnyLocation: allowAnyLocation),
  );
}

class _LocationPickerSheet extends StatefulWidget {
  final bool allowAnyLocation;
  const _LocationPickerSheet({this.allowAnyLocation = false});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _savedMatches = [];
  bool _searching = false;
  bool _gpsLoading = false;
  String? _gpsError;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _savedMatches = [];
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _search(trimmed),
    );
  }

  List<Map<String, dynamic>> _filterSavedAddresses(
    List<Map<String, dynamic>> saved,
    String query,
  ) {
    final q = query.toLowerCase();
    return saved.where((s) {
      final label = (s['label'] as String? ?? '').toLowerCase();
      final address = (s['address'] as String? ?? '').toLowerCase();
      return label.contains(q) || address.contains(q);
    }).toList();
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final provider = context.read<AppProvider>();
      final saved = _filterSavedAddresses(provider.savedAddresses, query);
      final google = await searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _savedMatches = saved;
        _searchResults = google;
        if (google.isEmpty && saved.isEmpty) {
          _searchError = 'No places found. Try a street name, area, or landmark.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _searchError = 'Search failed. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectLocation(Map<String, dynamic> result) {
    final lat = (result['lat'] as num).toDouble();
    final lng = (result['lng'] as num).toDouble();
    if (!widget.allowAnyLocation) {
      final provider = context.read<AppProvider>();
      if (!provider.isInServiceArea(lat, lng)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bɔla Aba is not currently available in your location. '
              'Please choose a location within a service area.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    Navigator.pop(context, result);
  }

  Future<void> _useGps() async {
    setState(() {
      _gpsLoading = true;
      _gpsError = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _gpsError = 'Location permission denied. Enable it in Settings.';
          _gpsLoading = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      if (!widget.allowAnyLocation) {
        final provider = context.read<AppProvider>();
        if (!provider.isInServiceArea(pos.latitude, pos.longitude)) {
          setState(() {
            _gpsError =
                'Bɔla Aba is not currently available in your location. '
                'Please search for your pickup address manually.';
            _gpsLoading = false;
          });
          return;
        }
      }

      if (!mounted) return;
      final address = 'My Location (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';

      Navigator.pop(context, {
        'address': address,
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsError = 'Could not get location. Try again.';
          _gpsLoading = false;
        });
      }
    } finally {
      if (mounted && _gpsLoading) setState(() => _gpsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final saved = provider.savedAddresses;
    final query = _searchController.text.trim();
    final isSearching = query.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Set Pickup Location',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kTextDark,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: _kTextDark),
                decoration: InputDecoration(
                  hintText: 'Search street, area, landmark…',
                  hintStyle:
                      const TextStyle(color: _kTextGray, fontSize: 14),
                  prefixIcon:
                      const Icon(Icons.search, color: _kPrimary, size: 22),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kPrimary,
                            ),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: _kPrimary, width: 1.5),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _GpsTile(
                    loading: _gpsLoading,
                    error: _gpsError,
                    onTap: _gpsLoading ? null : _useGps,
                  ),
                  const SizedBox(height: 8),
                  _MapPickerTile(
                    allowAnyLocation: widget.allowAnyLocation,
                    onPicked: (result) {
                      if (!widget.allowAnyLocation) {
                        final provider = context.read<AppProvider>();
                        if (!provider.isInServiceArea(
                            (result['lat'] as num).toDouble(),
                            (result['lng'] as num).toDouble())) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Bɔla Aba is not currently available in your location.',
                              ),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                      }
                      Navigator.pop(context, result);
                    },
                  ),
                  const SizedBox(height: 8),
                  _ManualAddressTile(onSubmit: _selectLocation),
                  const SizedBox(height: 4),
                  if (isSearching) ...[
                    if (_savedMatches.isNotEmpty) ...[
                      const _SectionLabel('YOUR SAVED ADDRESSES'),
                      ..._savedMatches.map(
                        (s) {
                          final lat = (s['lat'] as double?) ??
                              provider.customerLocation.latitude;
                          final lng = (s['lng'] as double?) ??
                              provider.customerLocation.longitude;
                          return _LocationTile(
                            icon: s['label'] == 'Home'
                                ? Icons.home_outlined
                                : Icons.work_outline,
                            title: s['label'] as String,
                            subtitle: s['address'] as String,
                            onTap: () => _selectLocation({
                              'address': s['address'],
                              'lat': lat,
                              'lng': lng,
                            }),
                          );
                        },
                      ),
                    ],
                    if (_searchResults.isNotEmpty) ...[
                      const _SectionLabel('GOOGLE PLACES'),
                      ..._searchResults.map(
                        (r) => _LocationTile(
                          icon: Icons.location_on_outlined,
                          title: _shortAddress(r['address'] as String),
                          subtitle: r['address'] as String,
                          onTap: () => _selectLocation(r),
                        ),
                      ),
                    ],
                    if (_searchError != null &&
                        !_searching &&
                        _searchResults.isEmpty &&
                        _savedMatches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _searchError!,
                          style: const TextStyle(color: _kTextGray, fontSize: 13),
                        ),
                      ),
                  ] else ...[
                    const _SectionLabel('SAVED ADDRESSES'),
                    if (saved.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Search above for any place in Ghana, or save addresses from your profile.',
                          style: TextStyle(color: _kTextGray, fontSize: 13),
                        ),
                      )
                    else
                      ...saved.map(
                        (s) {
                          final lat = (s['lat'] as double?) ??
                              provider.customerLocation.latitude;
                          final lng = (s['lng'] as double?) ??
                              provider.customerLocation.longitude;
                          return _LocationTile(
                            icon: s['label'] == 'Home'
                                ? Icons.home_outlined
                                : Icons.work_outline,
                            title: s['label'] as String,
                            subtitle: s['address'] as String,
                            onTap: () => _selectLocation({
                              'address': s['address'],
                              'lat': lat,
                              'lng': lng,
                            }),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortAddress(String full) {
    final parts = full.split(',');
    return parts.take(2).join(',').trim();
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _kTextGray,
            letterSpacing: 1.1,
          ),
        ),
      );
}

class _GpsTile extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback? onTap;

  const _GpsTile({required this.loading, this.error, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _kLightGreen,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kPrimary,
                      ),
                    )
                  : const Icon(Icons.my_location, color: _kPrimary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Use my current location',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _kPrimary,
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          error!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _LocationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LocationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kLightGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _kPrimary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _kTextDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: _kTextGray),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: _kTextGray),
            ],
          ),
        ),
      );
}

// ── Map picker tile ───────────────────────────────────────────────────────────

class _MapPickerTile extends StatelessWidget {
  final bool allowAnyLocation;
  final void Function(Map<String, dynamic> result) onPicked;

  const _MapPickerTile({
    required this.allowAnyLocation,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(builder: (_) => const _MapPickerPage()),
        );
        if (result != null) onPicked(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.map_outlined, color: _kPrimary, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pin location on map',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _kTextDark,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Drag the map to pinpoint your exact location',
                    style: TextStyle(fontSize: 12, color: _kTextGray),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: _kTextGray),
          ],
        ),
      ),
    );
  }
}

// ── Manual address entry (for customers who can't use the map) ────────────────

class _ManualAddressTile extends StatelessWidget {
  final void Function(Map<String, dynamic> result) onSubmit;

  const _ManualAddressTile({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _ManualAddressSheet(),
        );
        if (result != null) onSubmit(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_location_alt_outlined, color: _kPrimary, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type your address instead',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _kTextDark,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Having trouble with the map? Enter it manually',
                    style: TextStyle(fontSize: 12, color: _kTextGray),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: _kTextGray),
          ],
        ),
      ),
    );
  }
}

class _ManualAddressSheet extends StatefulWidget {
  const _ManualAddressSheet();

  @override
  State<_ManualAddressSheet> createState() => _ManualAddressSheetState();
}

class _ManualAddressSheetState extends State<_ManualAddressSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Enter your address, e.g. house number, street, and area');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    // Best-effort geocode of what they typed, purely to attach coordinates
    // for pricing/matching — the address they typed is always what gets used,
    // never a corrected/rewritten version.
    double? lat;
    double? lng;
    try {
      final matches = await searchPlaces(text);
      if (matches.isNotEmpty) {
        lat = (matches.first['lat'] as num).toDouble();
        lng = (matches.first['lng'] as num).toDouble();
      }
    } catch (_) {}

    if (lat == null || lng == null) {
      // Fall back to the customer's last known location so the request can
      // still be created even when the address can't be geocoded at all.
      if (mounted) {
        final loc = context.read<AppProvider>().customerLocation;
        lat = loc.latitude;
        lng = loc.longitude;
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.pop(context, {'address': text, 'lat': lat, 'lng': lng});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 40,
              height: 4,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('Enter Your Address',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextDark)),
            const SizedBox(height: 6),
            const Text(
              'Describe your location as clearly as you can — house number, street name, landmark, or area.',
              style: TextStyle(color: _kTextGray, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: _kTextDark),
              decoration: InputDecoration(
                hintText: 'e.g. House 12, Off Liberation Road, near Shell filling station',
                hintStyle: const TextStyle(color: _kTextGray, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  disabledBackgroundColor: _kPrimary.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Use This Address', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Full-screen map picker page ───────────────────────────────────────────────

class _MapPickerPage extends StatefulWidget {
  const _MapPickerPage();

  @override
  State<_MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<_MapPickerPage> {
  gm.GoogleMapController? _ctrl;
  gm.LatLng _center = const gm.LatLng(4.9016, -1.7574); // ST default
  bool _geocoding = false;
  bool _locating = true;
  String _address = '';

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  Future<void> _initGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      if (!mounted) return;
      final loc = gm.LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = loc;
        _locating = false;
      });
      _ctrl?.animateCamera(gm.CameraUpdate.newLatLngZoom(loc, 16));
      _reverseGeocode(loc);
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _reverseGeocode(gm.LatLng pos) async {
    setState(() { _geocoding = true; _address = ''; });
    try {
      final addr = await reverseGeocodeAddress(pos.latitude, pos.longitude);
      if (mounted) setState(() => _address = addr);
    } catch (_) {
      if (mounted) {
        setState(() => _address =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
      }
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  void _onCameraIdle() {
    _reverseGeocode(_center);
  }

  void _onCameraMove(gm.CameraPosition pos) {
    _center = pos.target;
  }

  void _confirm() {
    if (_address.isEmpty && !_geocoding) return;
    Navigator.pop(context, {
      'lat': _center.latitude,
      'lng': _center.longitude,
      'address': _address.isNotEmpty
          ? _address
          : '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          gm.GoogleMap(
            initialCameraPosition: gm.CameraPosition(target: _center, zoom: 15),
            onMapCreated: (c) {
              _ctrl = c;
              if (!_locating) {
                c.animateCamera(gm.CameraUpdate.newLatLngZoom(_center, 16));
              }
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          // Fixed center pin
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_pin, color: _kPrimary, size: 52),
            ),
          ),
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: _kPrimary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _geocoding
                                  ? const Text('Getting address…',
                                      style: TextStyle(
                                          color: _kTextGray, fontSize: 13))
                                  : Text(
                                      _address.isEmpty
                                          ? 'Drag map to set location'
                                          : _address,
                                      style: TextStyle(
                                        color: _address.isEmpty
                                            ? _kTextGray
                                            : _kTextDark,
                                        fontSize: 13,
                                        fontWeight: _address.isEmpty
                                            ? FontWeight.normal
                                            : FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // My location button
          Positioned(
            right: 12,
            bottom: 100,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                icon: const Icon(Icons.my_location, color: _kPrimary),
                onPressed: _initGps,
              ),
            ),
          ),
          // Confirm button
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                onPressed: _geocoding ? null : _confirm,
                child: _geocoding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Confirm this location',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
