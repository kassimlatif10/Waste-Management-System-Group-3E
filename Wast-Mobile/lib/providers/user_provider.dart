import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../services/app_config.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/file_image.dart';
import '../services/notification_service.dart';
import '../constants/api_constants.dart';
import '../utils/parse_utils.dart';

class AppProvider with ChangeNotifier {
  // ── Auth state ─────────────────────────────────────────────────────────────
  bool _isLoggedIn = false;
  bool _isCollector = false;
  bool _isAdmin = false;
  bool _isInvestor = false;
  Map<String, dynamic>? _currentUser;

  bool get isAuthenticated => _isLoggedIn;
  bool get isCollector => _isCollector;
  bool get isAdmin => _isAdmin;
  bool get isInvestor => _isInvestor;
  bool get isSuperAdmin =>
      (_currentUser?['role'] as String?) == 'super_admin' ||
      (_currentUser?['is_super_admin'] as bool? ?? false);
  Map<String, dynamic>? get currentUser => _currentUser;

  /// True once a customer's session is Supabase-native (registered/logged
  /// in via the new path) — routes the customer data methods below through
  /// SupabaseService instead of ApiService/Django, since a Supabase-only
  /// session has no Django JWT for ApiService to use at all.
  bool get _useSupabase => SupabaseService.isLoggedIn;

  void setCurrentUser(Map<String, dynamic> user) {
    _currentUser = user;
    final role = user['role'] as String? ?? 'customer';
    _isLoggedIn = true;
    _isCollector = role == 'collector';
    _isAdmin = role == 'staff' || role == 'admin' || role == 'super_admin';
    _isInvestor = role == 'investor';
    notifyListeners();
    // Load active request immediately on every customer authentication (login or restart)
    if (role == 'customer' && _activeRequest == null && !_activeRequestLoading) {
      _loadActiveRequest();
    }
  }

  Future<void> initialize() async {
    // supabase_flutter restores its own session automatically on app start —
    // if one exists, that takes priority (it's how customer accounts,
    // Supabase-native since the Django->Supabase migration, restore).
    if (SupabaseService.isLoggedIn) {
      try {
        final profile = await SupabaseService.fetchCurrentProfile();
        setCurrentUser(profile);
        return;
      } catch (_) {
        // Fall through to the Django path below if the Supabase session
        // turned out to be stale/invalid.
      }
    }

    final hasToken = await ApiService.hasTokens();
    if (!hasToken) return;
    try {
      final data = await ApiService.get(ApiConstants.me);
      setCurrentUser(data);
      if (data['role'] == 'customer' && data['profile_image'] == null) {
        try {
          final profile = await ApiService.get(ApiConstants.customerProfileUpdate);
          if (profile['profile_image'] != null) {
            mergeProfileImage(profile['profile_image'] as String);
          }
        } catch (_) {}
      }
    } catch (_) {
      await ApiService.clearTokens();
    }
  }

  Future<void> _loadActiveRequest() async {
    if (_activeRequestLoading) return;
    _activeRequestLoading = true;
    try {
      Map<String, dynamic>? req;
      if (_useSupabase) {
        req = await SupabaseService.fetchActivePickupRequest();
      } else {
        final data = await ApiService.get(ApiConstants.customerActiveRequest);
        req = data['active_request'] as Map<String, dynamic>?;
      }
      if (req == null) {
        _activeRequestLoading = false;
        return;
      }
      _activeRequest = req;
      _selectedWasteType = (_activeRequest!['waste_type'] as String?) ?? 'general';
      _pickupAddress    = (_activeRequest!['pickup_address'] as String?) ?? '';
      _selectedWastePrice = parseInt(_activeRequest!['price'], 20);
      final s = requestStatus;
      if (s != null && s != 'completed' && s != 'cancelled') {
        _lastPolledStatus = s;
        _startPolling();
        _syncLocationsFromActiveRequest();
      }
      notifyListeners();
    } catch (_) {}
    _activeRequestLoading = false;
  }

  void login() { _isLoggedIn = true; _isCollector = false; _isAdmin = false; _isInvestor = false; notifyListeners(); }
  Future<void> logout() async {
    if (SupabaseService.isLoggedIn) {
      try { await SupabaseService.logout(); } catch (_) {}
    }
    final refresh = await ApiService.getRefreshToken();
    try {
      if (refresh != null) await ApiService.post(ApiConstants.logout, {'refresh': refresh});
    } catch (_) {}
    await ApiService.clearTokens();
    _isLoggedIn = false;
    _isCollector = false;
    _isAdmin = false;
    _isInvestor = false;
    _currentUser = null;
    _pollTimer?.cancel();
    _activeRequest = null;
    _activeRequestLoading = false;
    _selectedBinTypeId = null;
    _selectedBinName = '';
    _selectedWastePrice = 0;
    _pickupAddress = '';
    _collectorOnline = false;
    _incomingRequestTimer?.cancel();
    _incomingRequests = [];
    _collectorLocation = _defaultCollectorStart;
    _collectorProfile = null;
    _historyLoaded = false;
    _history = [];
    NotificationService.reset();
    notifyListeners();
  }

  // ── User display helpers ───────────────────────────────────────────────────
  String get displayName {
    if (_currentUser == null) return 'User';
    final full = (_currentUser!['full_name'] ?? '') as String;
    if (full.isNotEmpty) return full;
    final first = (_currentUser!['first_name'] ?? '') as String;
    return first.isNotEmpty ? first : 'User';
  }

  String get displayInitial => displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

  String? get profileImageUrl {
    final profile = _currentUser?['profile'] as Map<String, dynamic>?;
    final collectorUrl = _collectorProfile?['profile_image'] as String?;
    final url = (profile?['profile_image']
        ?? _currentUser?['profile_image']
        ?? collectorUrl) as String?;
    if (url == null || url.isEmpty) return null;
    final resolved = url.startsWith('http') ? url : '${AppConfig.baseUrl}$url';
    final stamp = _profileImageVersion;
    return stamp > 0 ? '$resolved?v=$stamp' : resolved;
  }

  int _profileImageVersion = 0;

  void mergeProfileImage(String? url) {
    if (url == null || url.isEmpty) return;
    _profileImageVersion = DateTime.now().millisecondsSinceEpoch;
    _currentUser ??= {};
    final resolved = url.startsWith('http') ? url : '${AppConfig.baseUrl}$url';
    _currentUser!['profile_image'] = resolved;
    if (_collectorProfile != null) {
      _collectorProfile!['profile_image'] = resolved;
    }
    SslImageLoader.bustCache(resolved);
    notifyListeners();
  }

  Future<void> refreshProfileImageFromServer() async {
    try {
      final Map<String, dynamic> data;
      if (_useSupabase) {
        data = await SupabaseService.fetchCurrentProfile();
      } else if (_isAdmin) {
        data = await ApiService.get(ApiConstants.adminProfile);
      } else if (_isCollector) {
        data = await ApiService.get(ApiConstants.collectorProfile);
      } else if (_isInvestor) {
        data = await ApiService.get(ApiConstants.investorProfile);
      } else {
        data = await ApiService.get(ApiConstants.customerProfileUpdate);
      }
      final image = data['profile_image'] as String?;
      if (image != null && image.isNotEmpty) {
        mergeProfileImage(image);
      }
    } catch (_) {}
  }

  // Sekondi-Takoradi service area — keep defaults aligned with home map.
  static const LatLng _kServiceCenter = LatLng(4.9016, -1.7574);
  static const LatLng _defaultCustomerLocation = _kServiceCenter;
  static const LatLng _defaultCollectorStart = LatLng(4.9120, -1.7600);

  List<Map<String, dynamic>> _publicBranches = [];
  bool _branchesLoaded = false;

  Future<void> loadPublicBranches({bool forceReload = false}) async {
    if (_branchesLoaded && !forceReload) return;
    try {
      final raw = _useSupabase
          ? await SupabaseService.fetchPublicBranches()
          : await ApiService.getList(ApiConstants.publicBranches);
      _publicBranches = raw.cast<Map<String, dynamic>>();
      _branchesLoaded = true;
    } catch (_) {}
  }

  bool isInServiceArea(double lat, double lng) {
    if (_publicBranches.isEmpty) return true; // fallback: allow if no data yet
    for (final b in _publicBranches) {
      final bLat = (b['lat'] as num).toDouble();
      final bLng = (b['lng'] as num).toDouble();
      final radius = (b['service_radius_km'] as num).toDouble();
      final dist = _haversineKm(lat, lng, bLat, bLng);
      if (dist <= radius) return true;
    }
    return false;
  }

  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  LatLng _customerLocation = _defaultCustomerLocation;
  LatLng _collectorLocation = _defaultCollectorStart;

  LatLng get customerLocation => _customerLocation;

  void setCustomerLocation(LatLng loc) {
    _customerLocation = loc;
    notifyListeners();
  }

  void _syncLocationsFromActiveRequest() {
    if (_activeRequest == null) return;
    final pLat = parseDoubleOrNull(_activeRequest!['pickup_lat']);
    final pLng = parseDoubleOrNull(_activeRequest!['pickup_lng']);
    if (pLat != null && pLng != null) {
      _customerLocation = LatLng(pLat, pLng);
    }
    final profile = _activeRequest!['collector_profile'] as Map<String, dynamic>?;
    if (profile != null) {
      final cLat = parseDoubleOrNull(profile['current_lat']);
      final cLng = parseDoubleOrNull(profile['current_lng']);
      if (cLat != null && cLng != null) {
        _collectorLocation = LatLng(cLat, cLng);
      }
    }
  }

  double _calcDistanceKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(a.latitude)) *
            math.cos(_toRad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  double _toRad(double d) => d * math.pi / 180;

  // ── Waste types — from API, fallback hardcoded ─────────────────────────────
  List<Map<String, dynamic>> _wasteTypesFromApi = [];

  List<Map<String, dynamic>> get wasteTypes =>
      _wasteTypesFromApi.isNotEmpty ? _wasteTypesFromApi : _fallbackWasteTypes;

  static List<Map<String, dynamic>> _makeBins(List<List<dynamic>> rows) => rows
      .map((r) => {
            'id': null,
            'name': r[0] as String,
            'display_name': r[1] as String,
            'price': r[2] as int,
            'description': r[3] as String,
          })
      .toList();

  static final List<Map<String, dynamic>> _fallbackWasteTypes = [
    {
      'name': 'general', 'label': 'General Waste',
      'sub': 'Household and everyday waste',
      'icon': Icons.delete_outline, 'color': const Color(0xFF757575),
      'bin_types': _makeBins([
        ['small',  'Small Bin',  20, 'Up to 20 litres'],
        ['medium', 'Medium Bin', 35, 'Up to 60 litres'],
        ['large',  'Large Bin',  55, 'Up to 120 litres'],
      ]),
    },
    {
      'name': 'recyclable', 'label': 'Recyclable',
      'sub': 'Paper, plastic, glass, metal',
      'icon': Icons.recycling, 'color': const Color(0xFF1565C0),
      'bin_types': _makeBins([
        ['small',  'Small Bin',  18, 'Up to 20 litres'],
        ['medium', 'Medium Bin', 30, 'Up to 60 litres'],
        ['large',  'Large Bin',  45, 'Up to 120 litres'],
      ]),
    },
    {
      'name': 'organic', 'label': 'Organic / Compost',
      'sub': 'Food scraps and garden waste',
      'icon': Icons.eco, 'color': const Color(0xFF2E7D32),
      'bin_types': _makeBins([
        ['small',  'Small Bin',  15, 'Up to 20 litres'],
        ['medium', 'Medium Bin', 25, 'Up to 60 litres'],
        ['large',  'Large Bin',  40, 'Up to 120 litres'],
      ]),
    },
    {
      'name': 'hazardous', 'label': 'Hazardous',
      'sub': 'Chemicals, batteries, e-waste',
      'icon': Icons.science_outlined, 'color': const Color(0xFFE65100),
      'bin_types': _makeBins([
        ['standard', 'Standard Pack',    55,  'Up to 10 kg'],
        ['large',    'Large Pack',        85,  'Up to 25 kg'],
        ['special',  'Special Disposal', 120, 'Bulk/special'],
      ]),
    },
  ];

  Future<void> fetchWasteTypes() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchWasteTypes();
      } else {
        final data = await ApiService.get(ApiConstants.wasteTypes);
        final r = data['data'] ?? data['results'];
        if (r == null) return;
        raw = r as List<dynamic>;
      }
      _wasteTypesFromApi = raw.map((t) {
        final m = t as Map<String, dynamic>;
        final binsRaw = (m['bin_types'] as List?) ?? [];
        return {
          'name': m['key'] as String,
          'label': m['label'] as String,
          'sub': m['description'] as String,
          'icon': _iconFromName(m['icon'] as String? ?? ''),
          'color': _colorFromHex(m['color_hex'] as String? ?? '#757575'),
          'bin_types': binsRaw.map((b) {
            final bm = b as Map<String, dynamic>;
            return {
              'id': (bm['id'] as num).toInt(),
              'name': bm['name'] as String,
              'display_name': bm['display_name'] as String,
              'price': parseInt(bm['price']),
              'description': (bm['description'] as String?) ?? '',
            };
          }).toList(),
        };
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'recycling':        return Icons.recycling;
      case 'eco':              return Icons.eco;
      case 'science_outlined': return Icons.science_outlined;
      default:                 return Icons.delete_outline;
    }
  }

  Color _colorFromHex(String hex) {
    try {
      final value = int.parse(hex.replaceFirst('#', ''), radix: 16);
      return Color(0xFF000000 | value);
    } catch (_) {
      return const Color(0xFF757575);
    }
  }

  // ── Customer active request ─────────────────────────────────────────────────
  Map<String, dynamic>? _activeRequest;
  bool _activeRequestLoading = false;
  Timer? _pollTimer;

  Map<String, dynamic>? get activeRequest => _activeRequest;
  String? get requestStatus => _activeRequest?['status'] as String?;
  bool get hasActiveRequest =>
      _activeRequest != null &&
      requestStatus != 'completed' &&
      requestStatus != 'cancelled';

  // Tracking is only "active" (map + WS route) once the collector is moving.
  // 'assigned' = collector accepted, customer needs to pay — not tracking yet.
  bool get isTrackingActive {
    final s = requestStatus;
    return s == 'on_way' || s == 'arrived';
  }

  // True when the collector has confirmed (assigned) OR is already on the way.
  bool get collectorConfirmed {
    final s = requestStatus;
    return s == 'assigned' || s == 'on_way' || s == 'arrived';
  }

  Map<String, dynamic>? get proposedCollector {
    final s = requestStatus;
    // Show collector card for both 'assigned' (collector accepted) and
    // 'proposed' (for manual-grab flow where customer confirms).
    if (s != 'proposed' && s != 'assigned') return null;
    final profile = _activeRequest?['collector_profile'] as Map<String, dynamic>?;
    if (profile == null) return null;
    final lat = parseDoubleOrNull(profile['current_lat']);
    final lng = parseDoubleOrNull(profile['current_lng']);
    double distKm = 2.0;
    if (lat != null && lng != null) {
      distKm = _calcDistanceKm(LatLng(lat, lng), _customerLocation);
    }
    return {
      'name':       (_activeRequest!['collector_name'] ?? 'Collector') as String,
      'vehicle':    (profile['vehicle_type'] ?? 'Vehicle') as String,
      'rating':     parseDouble(profile['rating']),
      'phone':      (_activeRequest!['collector_phone'] ?? '') as String,
      'distanceKm': distKm,
    };
  }

  int get proposedPrice {
    if (_activeRequest == null) return dynamicPrice;
    final price = _activeRequest!['price'];
    return price != null ? parseInt(price, dynamicPrice) : dynamicPrice;
  }

  Map<String, dynamic> get priceBreakdown {
    final breakdown = _activeRequest?['price_breakdown'] as Map<String, dynamic>?;
    if (breakdown != null) return breakdown;
    return {
      'base_price': _activeRequest?['base_price'] ?? '0',
      'distance_km': parseDouble(_activeRequest?['distance_km']) ,
      'distance_fee': _activeRequest?['distance_fee'] ?? '0',
      'total': _activeRequest?['price'] ?? '0',
    };
  }

  LatLng get collectorLocation {
    final profile = _activeRequest?['collector_profile'] as Map<String, dynamic>?;
    if (profile != null) {
      final lat = parseDoubleOrNull(profile['current_lat']);
      final lng = parseDoubleOrNull(profile['current_lng']);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return _collectorLocation;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollActiveRequest(),
    );
  }

  String? _lastPolledStatus;

  Future<void> _pollActiveRequest() async {
    try {
      Map<String, dynamic>? req;
      if (_useSupabase) {
        req = await SupabaseService.fetchActivePickupRequest();
      } else {
        final data = await ApiService.get(ApiConstants.customerActiveRequest);
        req = data['active_request'] as Map<String, dynamic>?;
      }
      if (req == null) {
        final priorId = _activeRequest?['id'] as int?;
        final wasActive = _activeRequest != null;
        // fetchActivePickupRequest excludes completed/cancelled rows, so a
        // null result here just means "no longer active" — it doesn't say
        // whether the collector actually finished the job or it was
        // cancelled. Re-fetch the specific row (ignoring that filter) so a
        // real completion still routes to the rating screen instead of the
        // active request just vanishing back to the idle home state.
        if (_useSupabase && priorId != null) {
          final finalRow = await SupabaseService.fetchPickupRequestById(priorId);
          if (finalRow?['status'] == 'completed') {
            _activeRequest = finalRow;
            _pollTimer?.cancel();
            _lastPolledStatus = 'completed';
            notifyListeners();
            return;
          }
        }
        _activeRequest = null;
        _pollTimer?.cancel();
        _lastPolledStatus = null;
        if (wasActive) notifyListeners();
        return;
      }
      _activeRequest = req;
      final newStatus = requestStatus;
      _syncLocationsFromActiveRequest();
      // Fire local notification on status change
      if (newStatus != _lastPolledStatus) {
        final collectorName = _activeRequest?['collector_name'] as String?;
        NotificationService.onRequestStatusChanged(newStatus, collectorName: collectorName);
        _lastPolledStatus = newStatus;
      }
      if (requestStatus == 'completed' || requestStatus == 'cancelled') {
        _pollTimer?.cancel();
      }
      notifyListeners();
    } catch (_) {}
  }

  // ── Customer request flow ──────────────────────────────────────────────────
  String _selectedWasteType = 'general';
  int _selectedWastePrice = 0;
  int? _selectedBinTypeId;
  String _selectedBinName = '';
  String _pickupAddress = '';

  String get selectedWasteType => _selectedWasteType;
  int get selectedWastePrice => _selectedWastePrice;
  int? get selectedBinTypeId => _selectedBinTypeId;
  String get selectedBinName => _selectedBinName;
  String get pickupAddress => _pickupAddress;

  int get dynamicPrice => _selectedWastePrice;

  /// Distance to assigned/proposed collector, or 0 before matching.
  double get collectorDistanceKm {
    final km = parseDoubleOrNull(_activeRequest?['distance_km']);
    if (km != null && km > 0) return km;
    final proposed = proposedCollector;
    if (proposed != null) return parseDouble(proposed['distanceKm']);
    return 0;
  }

  void setPickupDetails(
    String wasteType,
    int binPrice,
    String address, {
    int? binTypeId,
    String binTypeName = '',
  }) {
    _selectedWasteType = wasteType;
    _selectedWastePrice = binPrice;
    _selectedBinTypeId = binTypeId;
    _selectedBinName = binTypeName;
    _pickupAddress = address;
    notifyListeners();
  }

  Future<void> startRequest() async {
    _activeRequest = {
      'status': 'finding',
      'waste_type': _selectedWasteType,
      'pickup_address': _pickupAddress,
      'price': _selectedWastePrice,
      'pickup_lat': _customerLocation.latitude,
      'pickup_lng': _customerLocation.longitude,
    };
    _lastPolledStatus = 'finding';
    _pollTimer?.cancel();
    notifyListeners();

    try {
      final Map<String, dynamic> data;
      if (_useSupabase) {
        data = await SupabaseService.createPickupRequest(
          binTypeId: _selectedBinTypeId ?? 0,
          price: _selectedWastePrice.toDouble(),
          basePrice: _selectedWastePrice.toDouble(),
          wasteType: _selectedWasteType,
          pickupAddress: _pickupAddress,
          pickupLat: _customerLocation.latitude,
          pickupLng: _customerLocation.longitude,
        );
      } else {
        final body = <String, dynamic>{
          'waste_type': _selectedWasteType.toLowerCase(),
          'pickup_address': _pickupAddress,
          'pickup_lat': _customerLocation.latitude,
          'pickup_lng': _customerLocation.longitude,
        };
        if (_selectedBinTypeId != null) body['bin_type'] = _selectedBinTypeId;
        data = await ApiService.post(ApiConstants.customerRequests, body);
      }
      _activeRequest = data;
      _syncLocationsFromActiveRequest();
      _startPolling();
      notifyListeners();
    } on ApiException catch (e) {
      _activeRequest = null;
      notifyListeners();
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      _activeRequest = null;
      notifyListeners();
      throw Exception(e.message);
    } catch (_) {
      _activeRequest = null;
      notifyListeners();
      throw Exception('Unable to connect. Check your connection.');
    }
  }

  Future<void> acceptProposedCollector() async {
    if (requestStatus != 'proposed') return;
    final id = _activeRequest?['id'] as int?;
    if (id == null) return;
    try {
      final data = _useSupabase
          ? await SupabaseService.confirmProposedCollector(id)
          : await ApiService.post(ApiConstants.acceptCollector(id), {});
      _activeRequest = data;
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> skipProposedCollector() async {
    if (requestStatus != 'proposed') return;
    final id = _activeRequest?['id'] as int?;
    if (id == null) return;
    _activeRequest = Map.of(_activeRequest!)..['status'] = 'finding';
    notifyListeners();
    try {
      final data = _useSupabase
          ? await SupabaseService.skipProposedCollector(id)
          : await ApiService.post(ApiConstants.skipCollector(id), {});
      _activeRequest = data;
      notifyListeners();
    } on ApiException catch (e) {
      _pollTimer?.cancel();
      _startPolling();
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      _pollTimer?.cancel();
      _startPolling();
      throw Exception(e.message);
    }
  }

  Future<void> cancelRequest() async {
    final id = _activeRequest?['id'] as int?;
    _pollTimer?.cancel();
    _activeRequest = null;
    _lastPolledStatus = null;
    _collectorLocation = _defaultCollectorStart;
    NotificationService.reset();
    notifyListeners();
    if (id != null) {
      try {
        if (_useSupabase) {
          await SupabaseService.cancelPickupRequest(id);
        } else {
          await ApiService.post(ApiConstants.cancelRequest(id), {});
        }
      } catch (_) {}
    }
  }

  void completeRequest() {
    _pollTimer?.cancel();
    if (_activeRequest != null) {
      _activeRequest = Map.of(_activeRequest!)..['status'] = 'completed';
      _addToHistory();
    }
    notifyListeners();
  }

  Future<void> rateCompletedPickup(int rating, {String? comment}) async {
    final id = _activeRequest?['id'] as int?;
    if (id == null || rating < 1) return;
    try {
      if (_useSupabase) {
        await SupabaseService.ratePickupRequest(id, rating, comment: comment);
      } else {
        await ApiService.post(ApiConstants.rateRequest(id), {
          'rating': rating,
          if (comment != null && comment.isNotEmpty) 'comment': comment,
        });
      }
    } catch (_) {
      // Rating is best-effort after pickup completes
    }
  }

  void _addToHistory() {
    if (_activeRequest == null) return;
    _history.insert(0, {
      'wasteType':  _selectedWasteType,
      'address':    _pickupAddress,
      'date':       _formatDate(DateTime.now()),
      'amount':     proposedPrice,
      'status':     'Completed',
    });
  }

  void clearCompletedRequest() {
    _activeRequest = null;
    _lastPolledStatus = null;
    _collectorLocation = _defaultCollectorStart;
    NotificationService.reset();
    notifyListeners();
  }

  void markCollectorArrived() {
    if (_activeRequest != null) {
      _activeRequest = Map.of(_activeRequest!)..['status'] = 'arrived';
    }
    _collectorLocation = _customerLocation;
    notifyListeners();
  }

  // ── History (from API) ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _history = [];
  bool _historyLoaded = false;

  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  Future<void> fetchHistory({bool force = false}) async {
    if (_historyLoaded && !force) return;
    try {
      final List<dynamic> reqRaw;
      final List<dynamic> schRaw;
      if (_useSupabase) {
        final results = await Future.wait([
          SupabaseService.fetchMyPickupRequests(),
          SupabaseService.fetchSchedules(),
        ]);
        reqRaw = results[0];
        schRaw = results[1];
      } else {
        final results = await Future.wait([
          ApiService.get(ApiConstants.customerRequests),
          ApiService.get(ApiConstants.customerSchedules),
        ]);
        reqRaw = (results[0]['data'] ?? results[0]['results'] ?? results[0]) as List<dynamic>;
        schRaw = (results[1]['data'] ?? results[1]['results'] ?? results[1]) as List<dynamic>;
      }
      final List<Map<String, dynamic>> items = [];
      for (final r in reqRaw) {
        final m = r as Map<String, dynamic>;
        items.add({
          'id':        m['id'],
          'wasteType': m['waste_type'] ?? '',
          'address':   m['pickup_address'] ?? '',
          'date':      _formatApiDate(m['completed_at'] as String? ?? m['created_at'] as String? ?? ''),
          'amount':    parseInt(m['price']),
          'status':    _localizeStatus((m['status'] as String?) ?? ''),
          'type':      'request',
        });
      }
      for (final s in schRaw) {
        final m = s as Map<String, dynamic>;
        final rawStatus = (m['status'] as String?) ?? 'pending';
        items.add({
          'id':        m['id'],
          'wasteType': m['waste_type_label'] ?? m['waste_type'] ?? '',
          'address':   m['pickup_address'] ?? m['address'] ?? '',
          'date':      _formatApiDate(m['pickup_datetime'] as String? ?? m['created_at'] as String? ?? ''),
          'amount':    parseInt(m['price']),
          'status':    rawStatus == 'pending' ? 'Scheduled' : _localizeStatus(rawStatus),
          'type':      'schedule',
        });
      }
      _history = items;
      _historyLoaded = true;
      notifyListeners();
    } catch (_) {}
  }

  // Folds every non-terminal backend status into a single "Active" bucket so
  // it's always reachable from the History screen's filter chips (All /
  // Completed / Active / Scheduled / Cancelled) — the more granular status
  // (finding/proposed/assigned/on_way/arrived) is still shown verbatim on the
  // live tracking screen via bookingStatusLabel/_StatusHeader.
  String _localizeStatus(String s) {
    switch (s) {
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'finding':
      case 'proposed':
      case 'assigned':
      case 'on_way':
      case 'arrived':   return 'Active';
      default:          return s;
    }
  }

  List<Map<String, dynamic>> getFilteredHistory(String filter) {
    if (filter == 'All') return List.unmodifiable(_history);
    return _history
        .where((item) => item['status'].toString().toLowerCase() == filter.toLowerCase())
        .toList();
  }

  // ── Notifications (from API) ───────────────────────────────────────────────
  int _unreadNotifications = 0;
  int get unreadNotifications => _unreadNotifications;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> get notifications => List.unmodifiable(_notifications);

  Future<void> fetchNotifications() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchNotifications();
        _unreadNotifications = raw.where((n) => (n as Map)['is_read'] != true).length;
      } else {
        final data = await ApiService.get(ApiConstants.customerNotifications);
        _unreadNotifications = parseInt(data['unread_count']);
        raw = (data['notifications'] as List?) ?? [];
      }
      _notifications = raw.map((n) {
        final m = n as Map<String, dynamic>;
        return {
          'id':      m['id'],
          'title':   m['title'] ?? '',
          'message': m['body'] ?? '',
          'time':    _formatApiDate(m['created_at'] as String? ?? ''),
          'read':    m['is_read'] ?? false,
          'type':    m['notification_type'] ?? 'system',
        };
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAllNotificationsRead() async {
    try {
      if (_useSupabase) {
        await SupabaseService.markAllNotificationsRead();
      } else {
        await ApiService.post(ApiConstants.customerMarkAllRead, {});
      }
      _unreadNotifications = 0;
      for (final n in _notifications) { n['read'] = true; }
      notifyListeners();
    } catch (_) {}
  }

  // ── Saved addresses (from API) ─────────────────────────────────────────────
  List<Map<String, dynamic>> _savedAddresses = [];
  List<Map<String, dynamic>> get savedAddresses => List.unmodifiable(_savedAddresses);

  Future<void> fetchAddresses() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchSavedAddresses();
      } else {
        final data = await ApiService.get(ApiConstants.customerAddresses);
        raw = (data['data'] ?? data['results'] ?? data) as List<dynamic>;
      }
      _savedAddresses = raw.map((a) {
        final m = a as Map<String, dynamic>;
        return {
          'id':      m['id'],
          'label':   m['label'] ?? '',
          'address': m['address'] ?? '',
          'lat':     parseDoubleOrNull(m['lat']),
          'lng':     parseDoubleOrNull(m['lng']),
        };
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> addAddress(Map<String, dynamic> address) async {
    try {
      final Map<String, dynamic> data;
      if (_useSupabase) {
        data = await SupabaseService.addSavedAddress(
          label: address['label'] as String? ?? '',
          address: address['address'] as String? ?? '',
          lat: parseDoubleOrNull(address['lat']),
          lng: parseDoubleOrNull(address['lng']),
        );
      } else {
        data = await ApiService.post(ApiConstants.customerAddresses, address);
      }
      _savedAddresses.insert(0, data);
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> deleteAddress(int id) async {
    try {
      if (_useSupabase) {
        await SupabaseService.deleteSavedAddress(id);
      } else {
        await ApiService.delete(ApiConstants.deleteAddress(id));
      }
      _savedAddresses.removeWhere((a) => a['id'] == id);
      notifyListeners();
    } catch (_) {}
  }

  // ── Scheduled pickups (from API) ───────────────────────────────────────────
  List<Map<String, dynamic>> _scheduledPickups = [];
  List<Map<String, dynamic>> get scheduledPickups => List.unmodifiable(_scheduledPickups);

  Future<void> fetchSchedules() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchSchedules();
      } else {
        final data = await ApiService.get(ApiConstants.customerSchedules);
        raw = (data['data'] ?? data['results'] ?? data) as List<dynamic>;
      }
      _scheduledPickups = raw.map((s) => _mapSchedule(s as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> addSchedule(Map<String, dynamic> schedule) async {
    try {
      final data = _useSupabase
          ? await SupabaseService.addSchedule(schedule)
          : await ApiService.post(ApiConstants.customerSchedules, schedule);
      _scheduledPickups.insert(0, _mapSchedule(data));
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> cancelSchedule(int id) async {
    try {
      if (_useSupabase) {
        await SupabaseService.cancelSchedule(id);
      } else {
        await ApiService.delete(ApiConstants.cancelSchedule(id));
      }
      _scheduledPickups.removeWhere((s) => s['id'] == id);
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Activates a scheduled pickup immediately and starts finding a collector.
  Future<void> triggerSchedule(int id) async {
    try {
      // `data` is the newly-created pickup_requests row, not a
      // scheduled_pickups row — merging it wholesale into the schedule list
      // entry (rather than just updating status/active_request_id) used to
      // wipe out that entry's own frequency/day/time fields.
      final data = _useSupabase
          ? await SupabaseService.triggerSchedule(id)
          : await ApiService.post(ApiConstants.triggerSchedule(id), {});
      final idx = _scheduledPickups.indexWhere((s) => s['id'] == id);
      if (idx >= 0) {
        _scheduledPickups[idx] = {
          ..._scheduledPickups[idx],
          'status': data['status'] ?? 'active',
          'active_request_id': data['id'],
        };
        notifyListeners();
      }
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Map<String, dynamic> _mapSchedule(Map<String, dynamic> m) {
    final wasteKey =
        (m['wasteType'] as String?) ?? (m['waste_type'] as String?) ?? 'general';
    final wasteLabel = (m['waste_type_label'] as String?) ?? wasteKey;
    final time =
        (m['time'] as String?) ?? (m['pickup_time'] as String?) ?? '';
    final freq = (m['frequency'] as String?) ?? 'once';
    final isRecurring =
        (m['isRecurring'] as bool?) ?? (m['is_recurring'] as bool?) ?? false;

    // `next_pickup_datetime` is the authoritative field the backend computes
    // from day_of_week + pickup_time — there is no separate calendar-date field.
    String pickupDatetime = (m['next_pickup_datetime'] as String?) ??
        (m['pickup_datetime'] as String?) ??
        '';
    var date = (m['date'] as String?) ?? (m['pickup_date'] as String?) ?? '';
    if (date.isEmpty && pickupDatetime.isNotEmpty) {
      date = pickupDatetime.split('T').first;
    }
    if (pickupDatetime.isEmpty && date.isNotEmpty && time.isNotEmpty) {
      pickupDatetime = '${date}T$time:00';
    }

    String binTypeName = '';
    final binTypeRaw = m['bin_type'];
    if (binTypeRaw is Map) {
      binTypeName = (binTypeRaw['display_name'] as String?) ??
          (binTypeRaw['name'] as String?) ??
          '';
    }

    return {
      'id': m['id'],
      'wasteType': wasteLabel,
      'waste_type': wasteKey,
      'date': date,
      'time': time,
      'frequency': freq,
      'isRecurring': isRecurring,
      'status': (m['status'] as String?) ?? 'pending',
      'price': (m['price'] as num?)?.toInt() ?? 0,
      'pickup_datetime': pickupDatetime,
      'payment_period':
          (m['payment_period'] as String?) ?? (m['paymentPeriod'] as String?) ?? '',
      'next_payment_due': (m['next_payment_due'] as String?) ?? '',
      'binTypeName': binTypeName,
    };
  }

  // ── Dumping reports (from API) ─────────────────────────────────────────────
  // ignore: prefer_final_fields — mutated by addDumpingReport
  List<Map<String, dynamic>> _dumpingReports = [];
  List<Map<String, dynamic>> get dumpingReports => List.unmodifiable(_dumpingReports);

  Future<void> addDumpingReport(Map<String, dynamic> report, {File? photo}) async {
    try {
      Map<String, dynamic> data;
      if (_useSupabase) {
        data = await SupabaseService.addDumpingReport(report, photoBytes: photo != null ? await readFileBytes(photo) : null);
      } else if (photo != null) {
        data = await ApiService.postMultipart(ApiConstants.customerReports, {
          'location': report['location']?.toString() ?? '',
          if (report['lat'] != null) 'lat': report['lat'].toString(),
          if (report['lng'] != null) 'lng': report['lng'].toString(),
          'description': report['description']?.toString() ?? '',
        }, {'photo': photo});
      } else {
        data = await ApiService.post(ApiConstants.customerReports, report);
      }
      _dumpingReports.insert(0, _mapDumpingReport(data));
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> fetchDumpingReports() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchDumpingReports();
      } else {
        final data = await ApiService.get(ApiConstants.customerReports);
        raw = (data['results'] ?? data['data'] ?? data) as List<dynamic>;
      }
      _dumpingReports = raw.map((r) => _mapDumpingReport(r as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Map<String, dynamic> _mapDumpingReport(Map<String, dynamic> m) {
    final status = (m['status'] as String?) ?? 'pending';
    return {
      'id': m['id'],
      'location': m['location'] ?? m['address'] ?? '',
      'description': m['description'] ?? '',
      'date': _formatApiDate(m['created_at'] as String? ?? ''),
      'status': status == 'resolved' ? 'Investigated' : 'Pending',
    };
  }

  // ── Collector — profile ───────────────────────────────────────────────────
  Map<String, dynamic>? _collectorProfile;

  Map<String, dynamic>? get collectorProfile    => _collectorProfile;

  bool _collectorOnline = false;
  bool get collectorOnline => _collectorOnline;

  int    get totalCollections => (_collectorProfile?['total_collections'] as num?)?.toInt() ?? 0;
  int    get creditScore => (_collectorProfile?['credit_score'] as num?)?.toInt() ?? 100;
  bool get collectorApproved => (_collectorProfile?['is_approved'] as bool?) ?? false;

  Future<void> fetchCollectorProfile() async {
    try {
      _collectorProfile = _useSupabase
          ? await SupabaseService.fetchCollectorProfile()
          : await ApiService.get(ApiConstants.collectorProfile);
      _collectorOnline  = (_collectorProfile?['is_online'] as bool?) ?? false;
      // Incoming/pending requests (including admin-assigned tasks) must be
      // visible regardless of online status, so start polling as soon as the
      // collector session is active — not just when they toggle online.
      _startIncomingPoll();
      unawaited(_pollIncomingRequests());
      // Restore any already-accepted job so it isn't lost on app restart.
      if (_activeCollectorRequest == null) {
        unawaited(fetchActiveCollectorRequest());
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markCollectorNotificationRead(int id) async {
    if (_useSupabase) {
      await SupabaseService.markNotificationRead(id);
    } else {
      await ApiService.post(ApiConstants.collectorNotificationRead(id), {});
    }
    final idx = _collectorNotifications.indexWhere((n) => n['id'] == id);
    if (idx >= 0 && !(_collectorNotifications[idx]['read'] as bool? ?? false)) {
      _collectorNotifications[idx]['read'] = true;
      _collectorUnreadNotifications = (_collectorUnreadNotifications - 1).clamp(0, 999);
      notifyListeners();
    }
  }

  Future<void> uploadCollectorProfilePhoto(String filePath) async {
    if (_useSupabase) {
      final bytes = await readFileBytes(File(filePath));
      final ext = kIsWeb ? 'jpg' : filePath.split('.').last;
      final url = await SupabaseService.uploadProfileImage(bytes, ext: ext);
      mergeProfileImage(url);
      return;
    }
    await ApiService.putMultipart(
      ApiConstants.collectorProfile,
      {},
      imageFile: File(filePath),
    );
    await refreshProfileImageFromServer();
  }

  // ── Collector — toggle online ──────────────────────────────────────────────
  DateTime? _lastLocationPush;
  LatLng? _lastPushedLocation;

  Future<void> pushCollectorLocation(double lat, double lng) async {
    if (!_collectorOnline) return;

    final now = DateTime.now();
    if (_lastLocationPush != null &&
        _lastPushedLocation != null &&
        now.difference(_lastLocationPush!) < const Duration(seconds: 12)) {
      const earthRadius = 6371000.0;
      final dLat = (lat - _lastPushedLocation!.latitude) * math.pi / 180;
      final dLng = (lng - _lastPushedLocation!.longitude) * math.pi / 180;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(_lastPushedLocation!.latitude * math.pi / 180) *
              math.cos(lat * math.pi / 180) *
              math.sin(dLng / 2) *
              math.sin(dLng / 2);
      final distM = earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      if (distM < 20) return;
    }

    try {
      if (_useSupabase) {
        await SupabaseService.pushCollectorLocation(lat, lng);
      } else {
        await ApiService.put(ApiConstants.collectorLocation, {
          'lat': lat,
          'lng': lng,
        });
      }
      _collectorLocation = LatLng(lat, lng);
      _lastLocationPush = now;
      _lastPushedLocation = LatLng(lat, lng);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleCollectorOnline({double? lat, double? lng}) async {
    try {
      if (_useSupabase) {
        _collectorOnline = !_collectorOnline;
        await SupabaseService.setCollectorOnline(_collectorOnline, lat: lat, lng: lng);
      } else {
        final body = <String, dynamic>{};
        if (lat != null && lng != null) {
          body['lat'] = lat;
          body['lng'] = lng;
        }
        final data = await ApiService.post(ApiConstants.collectorToggleOnline, body);
        _collectorOnline = (data['is_online'] as bool?) ?? !_collectorOnline;
      }
      // Incoming-request polling runs continuously (started in
      // fetchCollectorProfile) so admin-assigned tasks stay visible even
      // while offline — only the location push state resets here.
      if (!_collectorOnline) {
        _lastLocationPush = null;
        _lastPushedLocation = null;
      }
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ── Collector — update profile ─────────────────────────────────────────────
  Future<void> updateCollectorProfile(Map<String, dynamic> fields) async {
    try {
      if (_useSupabase) {
        await SupabaseService.updateCollectorProfile(fields);
      } else {
        await ApiService.put(ApiConstants.collectorProfile, fields);
      }
      await fetchCollectorProfile();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ── Collector — notifications ──────────────────────────────────────────────
  List<Map<String, dynamic>> _collectorNotifications = [];
  int _collectorUnreadNotifications = 0;
  List<Map<String, dynamic>> get collectorNotifications => List.unmodifiable(_collectorNotifications);
  int get collectorUnreadNotifications => _collectorUnreadNotifications;

  Future<void> fetchCollectorNotifications() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchNotifications();
        _collectorUnreadNotifications = raw.where((n) => (n as Map)['is_read'] != true).length;
      } else {
        final data = await ApiService.get(ApiConstants.collectorNotifications);
        _collectorUnreadNotifications = parseInt(data['unread_count']);
        raw = (data['notifications'] as List?) ?? [];
      }
      _collectorNotifications = raw.map((n) {
        final m = n as Map<String, dynamic>;
        return {
          'id':      m['id'],
          'title':   m['title'] ?? '',
          'message': m['body'] ?? '',
          'time':    _formatApiDate(m['created_at'] as String? ?? ''),
          'read':    m['is_read'] ?? false,
          'type':    m['notification_type'] ?? 'system',
        };
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAllCollectorNotificationsRead() async {
    try {
      if (_useSupabase) {
        await SupabaseService.markAllNotificationsRead();
      } else {
        await ApiService.post(ApiConstants.collectorNotifications, {});
      }
      _collectorUnreadNotifications = 0;
      for (final n in _collectorNotifications) { n['read'] = true; }
      notifyListeners();
    } catch (_) {}
  }

  // ── Collector — incoming (admin-assigned/proposed) requests ────────────────
  // The backend can propose more than one task to a collector before they've
  // acted on the first (e.g. two admin assignments in quick succession), so
  // this is a list — not just the single newest one.
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> get incomingRequests => List.unmodifiable(_incomingRequests);

  /// The newest pending task — kept for the existing "new request" full-screen
  /// alert. Use [incomingRequests] to see (and act on) every pending task.
  Map<String, dynamic>? get incomingRequest =>
      _incomingRequests.isNotEmpty ? _incomingRequests.first : null;

  Timer? _incomingRequestTimer;
  Map<String, dynamic>? _lastIncoming;

  void _startIncomingPoll() {
    if (_incomingRequestTimer != null) return; // already running
    _incomingRequestTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollIncomingRequests();
    });
  }

  Future<void> _pollIncomingRequests() async {
    // Admin-assigned tasks target this collector specifically, regardless of
    // their online/offline toggle — unlike auto-matched proposals, they must
    // stay visible either way, so this poll is not gated on _collectorOnline.
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchIncomingProposals();
      } else {
        final data = await ApiService.get(ApiConstants.collectorIncoming);
        raw = (data['data'] ?? data['results'] ?? data) as List<dynamic>;
      }
      if (raw.isNotEmpty) {
        final first = raw.first as Map<String, dynamic>;
        final previousId = _lastIncoming?['id'];
        final newId = first['id'];
        if (previousId != newId) {
          // New incoming request — fire local notification
          final customerName = first['customer_name'] as String?;
          NotificationService.onIncomingRequestChanged(hasNew: true, customerName: customerName);
        }
        _incomingRequests = raw
            .map((r) => _mapIncomingRequest(r as Map<String, dynamic>))
            .toList();
        _lastIncoming = first;
      } else {
        if (_incomingRequests.isNotEmpty) {
          NotificationService.onIncomingRequestChanged(hasNew: false);
        }
        _incomingRequests = [];
        _lastIncoming = null;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Maps snake_case API response to camelCase fields expected by
  /// the collector's _IncomingRequestSheet UI widget.
  Map<String, dynamic> _mapIncomingRequest(Map<String, dynamic> raw) {
    final pLat = parseDoubleOrNull(raw['pickup_lat']);
    final pLng = parseDoubleOrNull(raw['pickup_lng']);

    // Distance from the collector's stored location to the pickup point
    String distanceText = '—';
    if (pLat != null && pLng != null) {
      final cLat = parseDoubleOrNull(_collectorProfile?['current_lat']);
      final cLng = parseDoubleOrNull(_collectorProfile?['current_lng']);
      if (cLat != null && cLng != null) {
        final dist = _calcDistanceKm(LatLng(cLat, cLng), LatLng(pLat, pLng));
        distanceText = '${dist.toStringAsFixed(1)} km';
      }
    }

    // Human-readable time-ago from created_at
    String timeAgo = 'Just now';
    final createdAt = raw['created_at'] as String?;
    if (createdAt != null) {
      try {
        final diff = DateTime.now().difference(DateTime.parse(createdAt));
        if (diff.inMinutes >= 60) {
          timeAgo = '${diff.inHours} hr ago';
        } else if (diff.inMinutes >= 1) {
          timeAgo = '${diff.inMinutes} min ago';
        }
      } catch (_) {}
    }

    final cLat2 = parseDoubleOrNull(_collectorProfile?['current_lat']);
    final cLng2 = parseDoubleOrNull(_collectorProfile?['current_lng']);
    return {
      ...raw,
      'customerName':  (raw['customer_name'] ?? '') as String,
      'phone':         (raw['customer_phone'] ?? '') as String,
      'location':      (raw['pickup_address'] ?? '') as String,
      'distance':      distanceText,
      'wasteType':     (raw['waste_type'] ?? '') as String,
      'price':         parseInt(raw['price']),
      'timeAgo':       timeAgo,
      // Coordinates for route preview and tracking
      'pickup_lat':    pLat,
      'pickup_lng':    pLng,
      'pickupLat':     pLat,
      'pickupLng':     pLng,
      'collectorLat':  cLat2,
      'collectorLng':  cLng2,
    };
  }

  // ── Collector — accept incoming request ───────────────────────────────────
  Map<String, dynamic>? _activeCollectorRequest;
  Map<String, dynamic>? get activeCollectorRequest => _activeCollectorRequest;

  LatLng? get acceptedCustomerLocation {
    final lat = (_activeCollectorRequest?['pickup_lat'] as num?)?.toDouble();
    final lng = (_activeCollectorRequest?['pickup_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  /// Accepts a specific pending task by id, or the newest one if omitted
  /// (keeps existing behavior for the full-screen "new request" alert).
  Future<void> acceptRequest({int? requestId}) async {
    final id = requestId ?? incomingRequest?['id'] as int?;
    if (id == null) return;
    try {
      final data = _useSupabase
          ? await SupabaseService.acceptPickupRequest(id)
          : await ApiService.post(ApiConstants.acceptRequest(id), {});
      _activeCollectorRequest = data;
      _removeIncomingRequest(id);
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Called when the collector accepted from the route-preview page (API already called).
  void onRequestAcceptedFromPreview(Map<String, dynamic> data) {
    _activeCollectorRequest = data;
    final id = data['id'] as int?;
    if (id != null) _removeIncomingRequest(id);
    notifyListeners();
  }

  /// Refresh the active collector request from the server to detect payment confirmation.
  Future<void> refreshActiveCollectorRequest() async {
    final id = _activeCollectorRequest?['id'] as int?;
    if (id == null) return;
    try {
      final data = _useSupabase
          ? await SupabaseService.fetchCollectorCollectionDetail(id)
          : await ApiService.get(ApiConstants.collectorRequest(id));
      _activeCollectorRequest = data;
      notifyListeners();
    } catch (_) {}
  }

  /// Restore the collector's already-accepted job (assigned/on_way/arrived)
  /// from the server. Accept/markOnWay/markArrived only update in-memory
  /// state, so without this, restarting the app (or a fresh login) loses
  /// track of an in-progress job entirely — it becomes invisible even though
  /// the backend still has it assigned to this collector.
  Future<void> fetchActiveCollectorRequest() async {
    try {
      if (_useSupabase) {
        _activeCollectorRequest = await SupabaseService.fetchMyCollectorRequest();
      } else {
        final data = await ApiService.get(ApiConstants.collectorActiveRequest);
        _activeCollectorRequest = data['active_request'] as Map<String, dynamic>?;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Declines a specific pending task by id, or the newest one if omitted.
  Future<void> declineRequest({int? requestId}) async {
    final id = requestId ?? incomingRequest?['id'] as int?;
    if (id == null) return;
    try {
      if (_useSupabase) {
        await SupabaseService.declinePickupRequest(id);
      } else {
        await ApiService.post(ApiConstants.declineRequest(id), {});
      }
      // Only drop it locally once the backend actually confirms the
      // decline — otherwise a failed call (network blip, a race with the
      // customer/another action) left the request permanently stuck
      // 'proposed' on this collector server-side while looking gone here,
      // which could also block them from accepting anything new.
      _removeIncomingRequest(id);
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  void _removeIncomingRequest(int id) {
    _incomingRequests = _incomingRequests.where((r) => r['id'] != id).toList();
    if (_lastIncoming?['id'] == id) _lastIncoming = null;
  }

  // ── Collector — job progression ────────────────────────────────────────────
  // Each accepts an explicit requestId (falling back to the tracked active
  // request) so the tracking screen always acts on the job it's actually
  // showing, even if provider state has drifted — and throws rather than
  // silently no-opping when there's no id to act on at all, so a failure is
  // never mistaken for a working button.
  Future<void> markOnWay({int? requestId}) async {
    final id = requestId ?? _activeCollectorRequest?['id'] as int?;
    if (id == null) throw Exception('No active request to update.');
    try {
      final data = _useSupabase
          ? await SupabaseService.markPickupOnWay(id)
          : await ApiService.post(ApiConstants.markOnWay(id), {});
      _activeCollectorRequest = data;
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> markArrived({int? requestId}) async {
    final id = requestId ?? _activeCollectorRequest?['id'] as int?;
    if (id == null) throw Exception('No active request to update.');
    try {
      final data = _useSupabase
          ? await SupabaseService.markPickupArrived(id)
          : await ApiService.post(ApiConstants.markArrived(id), {});
      _activeCollectorRequest = data;
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> completePickup({int? requestId}) async {
    final id = requestId ?? _activeCollectorRequest?['id'] as int?;
    if (id == null) throw Exception('No active request to update.');
    try {
      if (_useSupabase) {
        await SupabaseService.completePickup(id);
      } else {
        await ApiService.post(ApiConstants.completePickup(id), {});
      }
      _activeCollectorRequest = null;
      await fetchCollectorProfile();
      await fetchCollectorCollections();
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ── Collector — history ────────────────────────────────────────────────────
  List<Map<String, dynamic>> _collectorCollections = [];
  List<Map<String, dynamic>> get collectorCollections => List.unmodifiable(_collectorCollections);

  Map<String, dynamic> _mapCollection(Map<String, dynamic> m) {
    return {
      'id': m['id'],
      'customerName': m['customer_name'] ?? '',
      'customerPhone': m['customer_phone'] ?? '',
      'location': m['pickup_address'] ?? '',
      'pickupLat': parseDoubleOrNull(m['pickup_lat']),
      'pickupLng': parseDoubleOrNull(m['pickup_lng']),
      'collectorStartLat': parseDoubleOrNull(m['collector_start_lat']),
      'collectorStartLng': parseDoubleOrNull(m['collector_start_lng']),
      'wasteType': m['waste_type'] ?? '',
      'price': parseInt(m['price']),
      'basePrice': parseInt(m['base_price']),
      'distanceKm': parseDouble(m['distance_km']),
      'distanceFee': parseDouble(m['distance_fee']),
      'paymentType': m['payment_type'] ?? '',
      'paymentStatus': m['payment_status'] ?? '',
      'rating': parseDoubleOrNull(m['customer_rating']),
      'ratingComment': m['rating_comment'] ?? '',
      'date': _formatApiDate(m['completed_at'] as String? ?? m['created_at'] as String? ?? ''),
      'completedAt': m['completed_at'] ?? m['created_at'],
      'status': 'Completed',
      'priceBreakdown': m['price_breakdown'],
    };
  }

  Future<void> fetchCollectorCollections({String period = 'all'}) async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchCollectorCollections(period: period);
      } else {
        final url = period == 'all'
            ? ApiConstants.collectorCollections
            : '${ApiConstants.collectorCollections}?period=$period';
        final data = await ApiService.get(url);
        raw = (data['results'] ?? data['data'] ?? data) as List<dynamic>;
      }
      _collectorCollections = raw.map((r) => _mapCollection(r as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> fetchCollectorCollectionDetail(int id) async {
    final data = _useSupabase
        ? await SupabaseService.fetchCollectorCollectionDetail(id)
        : await ApiService.get(ApiConstants.collectorCollection(id));
    return _mapCollection(data);
  }

  List<Map<String, dynamic>> _assignedSchedules = [];
  List<Map<String, dynamic>> get assignedSchedules => List.unmodifiable(_assignedSchedules);
  List<Map<String, dynamic>> _activeSchedules = [];
  List<Map<String, dynamic>> get activeSchedules => List.unmodifiable(_activeSchedules);
  List<Map<String, dynamic>> _completedSchedules = [];
  List<Map<String, dynamic>> get completedSchedules => List.unmodifiable(_completedSchedules);

  // Schedule confirmed by collector — shown as active job on home tab
  Map<String, dynamic>? _confirmedActiveSchedule;
  Map<String, dynamic>? get confirmedActiveSchedule => _confirmedActiveSchedule;

  void clearConfirmedSchedule() {
    _confirmedActiveSchedule = null;
    notifyListeners();
  }

  Future<void> fetchAssignedSchedules() async {
    try {
      List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchAssignedSchedules();
      } else {
        final data = await ApiService.get(ApiConstants.collectorSchedules);
        raw = data['results'] as List? ?? [];
        if (raw.isEmpty && data['upcoming'] is List) {
          raw = [
            ...(data['active'] as List? ?? []),
            ...(data['upcoming'] as List? ?? []),
            ...(data['completed'] as List? ?? []),
          ];
        } else if (raw.isEmpty) {
          raw = data['data'] as List? ?? [];
        }
      }
      _activeSchedules = [];
      _completedSchedules = [];
      _assignedSchedules = raw.map((s) {
          final m = s as Map<String, dynamic>;
          final timeStr = (m['next_pickup_datetime'] ?? m['scheduled_time'] ??
              m['pickup_time'] ?? m['pickup_datetime'] ?? '') as String;
          DateTime? pickupDt;
          try {
            if (timeStr.isNotEmpty) pickupDt = DateTime.parse(timeStr).toLocal();
          } catch (_) {}
          final mapped = {
            ...m,
            'id':           m['id'],
            'customerName': (m['customer_name'] ?? m['customerName'] ?? 'Customer') as String,
            'customerPhone':(m['customer_phone'] ?? '') as String,
            'wasteType':    (m['waste_type']    ?? m['wasteType']    ?? 'General')  as String,
            'location':     (m['pickup_address']?? m['location']     ?? '')         as String,
            'pickupLat':    parseDoubleOrNull(m['pickup_lat']),
            'pickupLng':    parseDoubleOrNull(m['pickup_lng']),
            'price':        parseInt(m['price']),
            'pickupTime':   pickupDt?.toIso8601String() ?? timeStr,
            'scheduleStatus': m['schedule_status'] ?? 'upcoming',
            'secondsUntil': m['seconds_until_pickup'],
            'collectorConfirmed': m['collector_confirmed'] ?? false,
            'dayName':      pickupDt != null ? _dayName(pickupDt) : (m['dayName'] ?? ''),
            'date':         pickupDt != null ? _formatDate(pickupDt) : (m['date'] ?? ''),
            'time':         pickupDt != null ? _timeOnly(pickupDt)   : (m['time'] ?? ''),
          };
          final st = mapped['scheduleStatus'] as String;
          if (st == 'active') {
            _activeSchedules.add(mapped);
          } else if (st == 'completed') {
            _completedSchedules.add(mapped);
          }
          return mapped;
        }).toList();
        notifyListeners();
    } catch (_) {}
  }

  Future<void> confirmSchedulePickup(int scheduleId) async {
    try {
      if (_useSupabase) {
        await SupabaseService.confirmSchedulePickup(scheduleId);
      } else {
        await ApiService.post(ApiConstants.confirmSchedule(scheduleId), {});
      }
      final idx = _assignedSchedules.indexWhere((s) => s['id'] == scheduleId);
      if (idx >= 0) {
        _confirmedActiveSchedule = Map<String, dynamic>.from(_assignedSchedules[idx]);
        _assignedSchedules.removeAt(idx);
      }
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  String _dayName(DateTime dt) {
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return days[dt.weekday - 1];
  }

  String _timeOnly(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  // ── Admin — dashboard & lists ──────────────────────────────────────────────
  Map<String, dynamic>? _adminDashboard;
  Map<String, dynamic>? get adminDashboard => _adminDashboard;

  int get adminTotalCustomers => (_adminDashboard?['total_customers'] as num?)?.toInt() ?? 0;
  double get adminTotalRevenue => (_adminDashboard?['total_revenue'] as num?)?.toDouble() ?? 0.0;
  int get adminActiveCollectors => (_adminDashboard?['active_collectors'] as num?)?.toInt() ?? 0;
  int get adminPendingPickups => (_adminDashboard?['pending_pickups'] as num?)?.toInt() ?? 0;

  Future<void> fetchAdminDashboard() async {
    try {
      _adminDashboard = _useSupabase
          ? (await SupabaseService.fetchAdminDashboard())['overview'] as Map<String, dynamic>
          : await ApiService.get(ApiConstants.adminDashboard);
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _adminCustomers = [];
  List<Map<String, dynamic>> get adminCustomers => List.unmodifiable(_adminCustomers);

  Future<void> fetchAdminCustomers() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchAdminCustomers();
      } else {
        final data = await ApiService.get(ApiConstants.adminCustomers);
        raw = (data['data'] ?? data['results'] ?? data) as List<dynamic>;
      }
      _adminCustomers = raw.map((c) => c as Map<String, dynamic>).toList();
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _adminCollectors = [];
  List<Map<String, dynamic>> get adminCollectors => List.unmodifiable(_adminCollectors);

  Future<void> fetchAdminCollectors({String filter = 'all'}) async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchAdminCollectors();
      } else {
        final data = await ApiService.get('${ApiConstants.adminCollectors}?filter=$filter');
        raw = (data['data'] ?? data['results'] ?? data) as List<dynamic>;
      }
      _adminCollectors = raw.map((c) => c as Map<String, dynamic>).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> approveCollector(int profileId) async {
    try {
      if (_useSupabase) {
        await SupabaseService.approveCollector(profileId);
      } else {
        await ApiService.post(ApiConstants.approveCollector(profileId), {});
      }
      final idx = _adminCollectors.indexWhere((c) => c['id'] == profileId);
      if (idx >= 0) _adminCollectors[idx]['is_approved'] = true;
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> declineCollector(int profileId, {String? reason}) async {
    try {
      if (_useSupabase) {
        await SupabaseService.declineCollector(profileId);
      } else {
        await ApiService.post(
          ApiConstants.declineCollector(profileId),
          {'reason': reason ?? 'Your application has been declined.'},
        );
      }
      _adminCollectors.removeWhere((c) => c['id'] == profileId);
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  List<Map<String, dynamic>> _adminSchedules = [];
  List<Map<String, dynamic>> get adminAllSchedules => List.unmodifiable(_adminSchedules);

  Future<void> fetchAdminSchedules() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchAdminSchedules();
      } else {
        final data = await ApiService.get(ApiConstants.adminSchedules);
        raw = (data['data'] ?? data['results'] ?? data) as List<dynamic>;
      }
      _adminSchedules = raw.map((s) => s as Map<String, dynamic>).toList();
      notifyListeners();
    } catch (_) {}
  }

  /// [collectorUserId] must be the collector's profiles.id (uuid) when on
  /// Supabase, or their Django numeric user id otherwise — callers already
  /// have the right kind of id since adminCollectors is sourced from the
  /// matching backend.
  Future<void> assignScheduleCollector(int scheduleId, dynamic collectorUserId) async {
    try {
      if (_useSupabase) {
        await SupabaseService.assignScheduleCollector(scheduleId, collectorUserId as String);
      } else {
        await ApiService.put(ApiConstants.assignSchedule(scheduleId), {'collector_id': collectorUserId});
      }
      await fetchAdminSchedules();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }


  List<Map<String, dynamic>> _adminReports = [];
  List<Map<String, dynamic>> get adminReports => List.unmodifiable(_adminReports);

  Future<void> fetchAdminReports() async {
    try {
      final List<dynamic> raw;
      if (_useSupabase) {
        raw = await SupabaseService.fetchAdminReports();
      } else {
        final data = await ApiService.get(ApiConstants.adminReports);
        raw = (data['data'] ?? data['results'] ?? data) as List<dynamic>;
      }
      _adminReports = raw.map((r) => r as Map<String, dynamic>).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> resolveReport(int reportId) async {
    try {
      if (_useSupabase) {
        await SupabaseService.resolveReport(reportId);
      } else {
        await ApiService.post(ApiConstants.resolveReport(reportId), {});
      }
      final idx = _adminReports.indexWhere((r) => r['id'] == reportId);
      if (idx >= 0) _adminReports[idx]['status'] = 'resolved';
      notifyListeners();
    } on ApiException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatDate(DateTime date) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatApiDate(String iso) {
    try {
      return _formatDate(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  // ── Super-Admin: Branch Management ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    if (_useSupabase) return SupabaseService.fetchAdminBranchesList();
    final data = await ApiService.get(ApiConstants.superAdminBranches);
    final list = (data['data'] as List?) ?? (data['results'] as List?) ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createBranch({
    required String name,
    required String region,
    String country = 'Ghana',
    String address = '',
    required double lat,
    required double lng,
    double serviceRadiusKm = 50.0,
  }) async {
    if (_useSupabase) {
      return SupabaseService.createBranch(
        name: name, region: region, country: country, address: address,
        lat: lat, lng: lng, serviceRadiusKm: serviceRadiusKm,
      );
    }
    return await ApiService.post(ApiConstants.superAdminBranches, {
      'name': name,
      'region': region,
      'country': country,
      'address': address,
      'lat': lat,
      'lng': lng,
      'service_radius_km': serviceRadiusKm,
    });
  }

  Future<void> updateBranch(int id, Map<String, dynamic> fields) async {
    if (_useSupabase) {
      await SupabaseService.updateBranch(id, fields);
    } else {
      await ApiService.put(ApiConstants.superAdminBranch(id), fields);
    }
  }

  Future<void> deleteBranch(int id) async {
    if (_useSupabase) {
      await SupabaseService.deleteBranch(id);
    } else {
      await ApiService.delete(ApiConstants.superAdminBranch(id));
    }
  }

  Future<List<Map<String, dynamic>>> fetchAdminUsers() async {
    if (_useSupabase) return SupabaseService.fetchAdminUsers();
    final data = await ApiService.get(ApiConstants.superAdminAdmins);
    final list = data is List ? data as List : (data['results'] as List? ?? []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createAdminUser({
    required String firstName,
    required String lastName,
    required String phone,
    String email = '',
    int? branchId,
    String role = 'admin',
  }) async {
    if (_useSupabase) {
      return SupabaseService.createAdminUser(
        firstName: firstName, lastName: lastName, phone: phone,
        email: email, branchId: branchId, role: role,
      );
    }
    return await ApiService.post(ApiConstants.superAdminAdmins, {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'email': email,
      'role': role,
      if (branchId != null) 'branch_id': branchId,
    });
  }

  Future<void> assignAdminBranch(dynamic adminId, int? branchId) async {
    if (_useSupabase) {
      await SupabaseService.assignAdminBranch(adminId as String, branchId);
    } else {
      await ApiService.put(ApiConstants.superAdminAdmin(adminId as int), {
        'branch_id': branchId,
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _incomingRequestTimer?.cancel();
    super.dispose();
  }
}


typedef UserProvider = AppProvider;
