import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed auth/data layer. Sits alongside [ApiService] (the
/// existing Django REST client) rather than replacing it — see the
/// Django->Supabase migration plan. Only methods that have actually been
/// migrated for a given phase live here; everything else still goes
/// through ApiService until its own phase lands.
class SupabaseService {
  SupabaseService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Supabase Auth identities are email+password even for phone-based
  /// login — the phone never leaves the UI as a "real" identity, this
  /// synthesized address is just what Auth stores internally. See the
  /// Phase 0 plan's Auth design section for why (avoids requiring a paid
  /// SMS provider just to have a login mechanism).
  static String _emailForPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    // GoTrue's email validator rejects some non-standard TLDs (.internal
    // was rejected in testing) — .com passes validation and is never
    // actually sent to, so the specific domain doesn't matter otherwise.
    return '$digits@phone.wastapp.com';
  }

  static bool get isLoggedIn => _client.auth.currentSession != null;
  static User? get currentUser => _client.auth.currentUser;

  /// Mirrors accounts/views.py's CheckPhoneView, scoped to Supabase-migrated
  /// accounts only (currently: customers). A phone not found here doesn't
  /// mean it doesn't exist at all — callers should fall back to the
  /// Django check for every other role during the staged cutover.
  static Future<Map<String, dynamic>> checkPhoneExists(String phone) async {
    return Map<String, dynamic>.from(await _client.rpc('check_phone_exists', params: {'p_phone': phone}));
  }

  /// Same idea as [checkPhoneExists] but for admin's email+password login.
  static Future<Map<String, dynamic>> checkEmailExists(String email) async {
    return Map<String, dynamic>.from(await _client.rpc('check_email_exists', params: {'p_email': email}));
  }

  // ── Registration ──────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> registerCustomer({
    required String phone,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final res = await _client.auth.signUp(
      email: _emailForPhone(phone),
      password: password,
    );
    final userId = res.user?.id;
    if (userId == null) throw Exception('Registration failed');

    final profile = await _client
        .from('profiles')
        .upsert({
          'id': userId,
          'phone': phone,
          'first_name': firstName,
          'last_name': lastName,
          'role': 'customer',
          'password_set': true,
        })
        .select()
        .single();

    return {'user': profile};
  }

  /// Registers a collector + their initial vehicle + a pending KYC record.
  /// [kycFiles] maps document_type (e.g. 'ghana_card_front') to raw bytes.
  static Future<Map<String, dynamic>> registerCollector({
    required String phone,
    required String password,
    required String vehicleType,
    String? firstName,
    String? lastName,
    String? ghanaCardNumber,
    String? licenseNumber,
    Map<String, Uint8List> kycFiles = const {},
  }) async {
    final res = await _client.auth.signUp(
      email: _emailForPhone(phone),
      password: password,
    );
    final userId = res.user?.id;
    if (userId == null) throw Exception('Registration failed');

    await _client.from('profiles').upsert({
      'id': userId,
      'phone': phone,
      'first_name': firstName,
      'last_name': lastName,
      'role': 'collector',
      'password_set': true,
    });

    final collectorRow = await _client
        .from('collector_profiles')
        .insert({'user_id': userId, 'vehicle_type': vehicleType, 'is_approved': false})
        .select('id')
        .single();
    final collectorId = collectorRow['id'];

    await _client.from('collector_vehicles').insert({
      'collector_id': collectorId,
      'is_default': true,
    });

    final kycRow = await _client
        .from('collector_kyc')
        .insert({
          'user_id': userId,
          'ghana_card_number': ghanaCardNumber,
          'license_number': licenseNumber,
          'kyc_status': 'pending',
        })
        .select('id')
        .single();
    final kycId = kycRow['id'];

    for (final entry in kycFiles.entries) {
      final path = '$userId/${entry.key}.jpg';
      await _client.storage.from('kyc-documents').uploadBinary(
            path,
            entry.value,
            fileOptions: const FileOptions(upsert: true),
          );
      await _client.from('kyc_documents').insert({
        'kyc_id': kycId,
        'document_type': entry.key,
        'file': path,
      });
    }

    return {'user': await fetchCurrentProfile(), 'user_id': userId, 'collector_id': collectorId};
  }

  // ── Login / session ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> loginWithPhone(String phone, String password) async {
    await _client.auth.signInWithPassword(
      email: _emailForPhone(phone),
      password: password,
    );
    return {'user': await fetchCurrentProfile()};
  }

  static Future<Map<String, dynamic>> loginAdminWithEmail(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    return fetchCurrentProfile();
  }

  static Future<Map<String, dynamic>> fetchCurrentProfile() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    return await _client.from('profiles').select().eq('id', uid).single();
  }

  static Future<void> logout() => _client.auth.signOut();

  /// Sets the real password for the currently-authenticated user (used
  /// right after collector registration, which — unlike Django's
  /// passwordless-then-set-later flow — needs Supabase Auth's
  /// password-required signUp to start with a throwaway random one).
  static Future<void> setInitialPassword(String password) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.auth.updateUser(UserAttributes(password: password));
    await _client.from('profiles').update({'password_set': true}).eq('id', uid);
  }

  // ── OTP / password reset (via Edge Functions — see supabase/functions) ──

  static Future<Map<String, dynamic>> sendOtp(String phone, {String purpose = 'password_reset'}) async {
    final res = await _client.functions.invoke('send-otp', body: {'phone': phone, 'purpose': purpose});
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otpCode, {String purpose = 'password_reset'}) async {
    final res = await _client.functions.invoke('verify-otp', body: {
      'phone': phone,
      'otp_code': otpCode,
      'purpose': purpose,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Verifies [oldPassword] (matching Django's change-password behavior,
  /// which requires the current password rather than trusting the session
  /// alone) by re-authenticating, then sets the new one.
  static Future<void> changePassword(String oldPassword, String newPassword) async {
    final email = currentUser?.email;
    if (email == null) throw Exception('Not logged in');
    await _client.auth.signInWithPassword(email: email, password: oldPassword);
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> resetPassword(String phone, String otpCode, String newPassword) async {
    final res = await _client.functions.invoke('reset-password', body: {
      'phone': phone,
      'otp_code': otpCode,
      'new_password': newPassword,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
  }

  // ── Geocoding (via Edge Function — hides the Google API key) ───────────

  static Future<String?> reverseGeocode(double lat, double lng) async {
    final res = await _client.functions.invoke('geocode', queryParameters: {
      'mode': 'reverse',
      'lat': '$lat',
      'lng': '$lng',
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['address'] as String?;
  }

  static Future<List<Map<String, dynamic>>> searchAddress(String query) async {
    final res = await _client.functions.invoke('geocode', queryParameters: {
      'mode': 'search',
      'query': query,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return List<Map<String, dynamic>>.from(data['results'] ?? []);
  }

  // ── Catalog ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchWasteTypes() async {
    final res = await _client
        .from('waste_types')
        .select('*, bin_types(*)')
        .eq('is_active', true)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Pickup requests (Phase 1) ───────────────────────────────────────────

  static Future<Map<String, dynamic>> createPickupRequest({
    required int binTypeId,
    required double price,
    required double basePrice,
    String? wasteType,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final row = await _client
        .from('pickup_requests')
        .insert({
          'customer_id': uid,
          'bin_type_id': binTypeId,
          'waste_type': wasteType,
          'price': price,
          'base_price': basePrice,
          'pickup_address': pickupAddress,
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'status': 'finding',
        })
        .select()
        .single();
    return _mapPickupRequestRow(row);
  }

  static const String _pickupRequestSelect =
      '*, collector:profiles!pickup_requests_collector_id_fkey(first_name,last_name,phone,'
      'collector_profiles(vehicle_type,rating,current_lat,current_lng))';

  /// Reshapes a raw (joined) pickup_requests row into the same shape
  /// Django's PickupRequestSerializer produces, so AppProvider's existing
  /// UI-facing getters (proposedCollector, priceBreakdown, etc.) work
  /// unchanged regardless of which backend served the data.
  static Map<String, dynamic> _mapPickupRequestRow(Map<String, dynamic> row) {
    final collector = row['collector'] as Map<String, dynamic>?;
    final collectorProfiles = collector?['collector_profiles'];
    final cp = collectorProfiles is List && collectorProfiles.isNotEmpty
        ? collectorProfiles.first as Map<String, dynamic>
        : (collectorProfiles is Map<String, dynamic> ? collectorProfiles : null);
    final mapped = Map<String, dynamic>.from(row)..remove('collector');
    if (collector != null) {
      final name = [collector['first_name'], collector['last_name']]
          .where((s) => s != null && (s as String).isNotEmpty)
          .join(' ');
      mapped['collector_name'] = name.isNotEmpty ? name : 'Collector';
      mapped['collector_phone'] = collector['phone'];
      mapped['collector_profile'] = {
        'vehicle_type': cp?['vehicle_type'],
        'rating': cp?['rating'],
        'current_lat': cp?['current_lat'],
        'current_lng': cp?['current_lng'],
      };
    }
    mapped['price_breakdown'] = {
      'base_price': row['base_price'] ?? '0',
      'distance_km': row['distance_km'] ?? 0,
      'distance_fee': row['distance_fee'] ?? '0',
      'total': row['price'] ?? '0',
    };
    return mapped;
  }

  static Future<Map<String, dynamic>?> fetchActivePickupRequest() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client
        .from('pickup_requests')
        .select(_pickupRequestSelect)
        .eq('customer_id', uid)
        .not('status', 'in', '(completed,cancelled)')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return res == null ? null : _mapPickupRequestRow(res);
  }

  static Future<void> cancelPickupRequest(int id) async {
    await _client.from('pickup_requests').update({'status': 'cancelled'}).eq('id', id);
  }

  /// Unlike [fetchActivePickupRequest], this doesn't filter out
  /// completed/cancelled rows — used to find out what a request that just
  /// dropped out of the active list actually finished as.
  static Future<Map<String, dynamic>?> fetchPickupRequestById(int id) async {
    final res = await _client
        .from('pickup_requests')
        .select(_pickupRequestSelect)
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : _mapPickupRequestRow(res);
  }

  static Future<void> ratePickupRequest(int id, int rating, {String? comment}) async {
    await _client.from('pickup_requests').update({
      'customer_rating': rating,
      if (comment != null && comment.isNotEmpty) 'rating_comment': comment,
    }).eq('id', id);
  }

  /// Live updates for one pickup request — replaces the customer's 3s poll.
  /// Re-fetches the joined/mapped row on each change (the raw Postgres
  /// Changes payload has no join info) so callers always get the same
  /// Django-serializer-compatible shape as every other fetch method here.
  /// Caller is responsible for unsubscribing (`channel.unsubscribe()`).
  static RealtimeChannel subscribeToPickupRequest(
    int id,
    void Function(Map<String, dynamic> row) onUpdate,
  ) {
    final channel = _client.channel('pickup_request_$id');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pickup_requests',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
          callback: (payload) async {
            final row = await _client.from('pickup_requests').select(_pickupRequestSelect).eq('id', id).maybeSingle();
            if (row != null) onUpdate(_mapPickupRequestRow(row));
          },
        )
        .subscribe();
    return channel;
  }

  // ── Scheduled pickups ────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchSchedules() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client
        .from('scheduled_pickups')
        .select('*, bin_type:bin_types(name, display_name, price)')
        .eq('customer_id', uid)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>> addSchedule(Map<String, dynamic> schedule) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    return await _client.from('scheduled_pickups').insert({...schedule, 'customer_id': uid}).select().single();
  }

  static Future<void> cancelSchedule(int id) async {
    await _client.from('scheduled_pickups').update({'is_active': false}).eq('id', id);
  }

  static Future<Map<String, dynamic>> triggerSchedule(int id) async {
    final row = await _client.rpc('manually_trigger_schedule', params: {'p_schedule_id': id});
    return _mapPickupRequestRow(Map<String, dynamic>.from(row));
  }

  // ── History ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchMyPickupRequests() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client.from('pickup_requests').select().eq('customer_id', uid).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Dumping reports ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchDumpingReports() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client.from('dumping_reports').select().eq('reported_by_id', uid).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>> addDumpingReport(Map<String, dynamic> report, {Uint8List? photoBytes}) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final payload = {...report, 'reported_by_id': uid};
    if (photoBytes != null) {
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _client.storage.from('dump-report-photos').uploadBinary(path, photoBytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      payload['photo'] = path;
    }
    return await _client.from('dumping_reports').insert(payload).select().single();
  }

  // ── Notifications ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client.from('notifications').select().eq('user_id', uid).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> markAllNotificationsRead() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('notifications').update({'is_read': true}).eq('user_id', uid).eq('is_read', false);
  }

  static Future<void> markNotificationRead(int id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> fetchPublicBranches() async {
    final res = await _client.from('branches').select().eq('is_active', true);
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Saved addresses ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchSavedAddresses() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client.from('saved_addresses').select().eq('user_id', uid);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>> addSavedAddress({
    required String label,
    required String address,
    double? lat,
    double? lng,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    return await _client
        .from('saved_addresses')
        .insert({'user_id': uid, 'label': label, 'address': address, 'lat': lat, 'lng': lng})
        .select()
        .single();
  }

  static Future<void> deleteSavedAddress(int id) async {
    await _client.from('saved_addresses').delete().eq('id', id);
  }

  // ── Collector: job lifecycle (Phase 2 RPCs) ─────────────────────────────

  static Future<Map<String, dynamic>> acceptPickupRequest(int requestId) async {
    await _client.rpc('accept_pickup_request', params: {'p_request_id': requestId});
    return (await fetchMyCollectorRequest())!;
  }

  static Future<Map<String, dynamic>> declinePickupRequest(int requestId) async {
    final row = await _client.rpc('decline_pickup_request', params: {'p_request_id': requestId});
    return _mapCollectorPickupRow(Map<String, dynamic>.from(row));
  }

  static Future<Map<String, dynamic>> markPickupOnWay(int requestId) async {
    await _client.rpc('mark_pickup_on_way', params: {'p_request_id': requestId});
    return (await fetchMyCollectorRequest())!;
  }

  static Future<Map<String, dynamic>> markPickupArrived(int requestId) async {
    await _client.rpc('mark_pickup_arrived', params: {'p_request_id': requestId});
    return (await fetchMyCollectorRequest())!;
  }

  static Future<Map<String, dynamic>> completePickup(int requestId) async {
    return Map<String, dynamic>.from(await _client.rpc('complete_pickup', params: {'p_request_id': requestId}));
  }

  static Future<Map<String, dynamic>> confirmProposedCollector(int requestId) async {
    await _client.rpc('confirm_proposed_collector', params: {'p_request_id': requestId});
    return (await fetchActivePickupRequest())!;
  }

  static Future<Map<String, dynamic>> skipProposedCollector(int requestId) async {
    await _client.rpc('skip_proposed_collector', params: {'p_request_id': requestId});
    return (await fetchActivePickupRequest())!;
  }

  static Future<Map<String, dynamic>> fetchCollectorProfile() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final cp = await _client.from('collector_profiles').select().eq('user_id', uid).single();
    final profile = await _client.from('profiles').select('profile_image, first_name, last_name, phone').eq('id', uid).single();
    return {...cp, ...profile};
  }

  static Future<void> updateCollectorProfile(Map<String, dynamic> fields) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('collector_profiles').update(fields).eq('user_id', uid);
  }

  static Future<void> setCollectorOnline(bool online, {double? lat, double? lng}) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('collector_profiles').update({
      'is_online': online,
      if (lat != null) 'current_lat': lat,
      if (lng != null) 'current_lng': lng,
    }).eq('user_id', uid);
  }

  static Future<void> pushCollectorLocation(double lat, double lng) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('collector_profiles').update({'current_lat': lat, 'current_lng': lng}).eq('user_id', uid);
  }

  static const String _collectorPickupRequestSelect =
      '*, customer:profiles!pickup_requests_customer_id_fkey(first_name,last_name,phone)';

  /// Mirrors the customer-side mapper, but for the collector's view of a
  /// row (joins the customer instead of the collector).
  static Map<String, dynamic> _mapCollectorPickupRow(Map<String, dynamic> row) {
    final customer = row['customer'] as Map<String, dynamic>?;
    final mapped = Map<String, dynamic>.from(row)..remove('customer');
    if (customer != null) {
      final name = [customer['first_name'], customer['last_name']]
          .where((s) => s != null && (s as String).isNotEmpty)
          .join(' ');
      mapped['customer_name'] = name.isNotEmpty ? name : 'Customer';
      mapped['customer_phone'] = customer['phone'];
    }
    mapped['price_breakdown'] = {
      'base_price': row['base_price'] ?? '0',
      'distance_km': row['distance_km'] ?? 0,
      'distance_fee': row['distance_fee'] ?? '0',
      'total': row['price'] ?? '0',
    };
    return mapped;
  }

  /// Mirrors PendingRequestsView — the open, unassigned queue (anyone can
  /// accept). Not currently wired to any screen; kept for parity.
  static Future<List<Map<String, dynamic>>> fetchFindingQueue() async {
    final res = await _client
        .from('pickup_requests')
        .select(_collectorPickupRequestSelect)
        .eq('status', 'finding')
        .order('created_at');
    return List<Map<String, dynamic>>.from(res).map(_mapCollectorPickupRow).toList();
  }

  /// Mirrors IncomingRequestsView — requests proposed to THIS collector
  /// specifically (status='proposed', collector_id=me), the shape an
  /// admin's manual assignment actually produces. This is what the 5s
  /// incoming-request poll must call: it was calling [fetchFindingQueue]
  /// instead, which only sees the open 'finding' queue and never the
  /// collector-targeted 'proposed' row an admin assignment creates — so an
  /// admin-assigned collector never saw an Accept prompt and the request
  /// stayed stuck at 'proposed', which then rejected every on_way/arrived
  /// attempt ("Cannot mark on_way/arrived from the current status").
  static Future<List<Map<String, dynamic>>> fetchIncomingProposals() async {
    final uid = currentUser?.id;
    if (uid == null) return [];
    final res = await _client
        .from('pickup_requests')
        .select(_collectorPickupRequestSelect)
        .eq('status', 'proposed')
        .eq('collector_id', uid)
        .order('created_at');
    return List<Map<String, dynamic>>.from(res).map(_mapCollectorPickupRow).toList();
  }

  static Future<Map<String, dynamic>?> fetchMyCollectorRequest() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client
        .from('pickup_requests')
        .select(_collectorPickupRequestSelect)
        .eq('collector_id', uid)
        .not('status', 'in', '(completed,cancelled)')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return res == null ? null : _mapCollectorPickupRow(res);
  }

  /// Live updates for the collector's finding queue — replaces the 5s poll.
  /// Live-updates the collector's own approval/online status (e.g. so the
  /// "Account Under Review" banner flips to the online toggle the instant
  /// an admin approves them, without needing a manual refresh).
  static RealtimeChannel subscribeToOwnCollectorProfile(void Function() onChange) {
    final uid = currentUser?.id;
    final channel = _client.channel('collector_profile_${uid ?? 'anon'}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'collector_profiles',
          filter: uid == null ? null : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  static RealtimeChannel subscribeToFindingQueue(void Function() onChange) {
    final channel = _client.channel('finding_queue');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pickup_requests',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  // ── Admin (Phase 3) ──────────────────────────────────────────────────────

  // ── Company waste bins ───────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCompanyBins({bool? isActive}) async {
    var query = _client
        .from('company_waste_bins')
        .select('*, collector:profiles!company_waste_bins_assigned_collector_id_fkey(first_name,last_name)');
    if (isActive != null) query = query.eq('is_active', isActive);
    final res = await query.order('id', ascending: false);
    return List<Map<String, dynamic>>.from(res).map((b) {
      final collector = b['collector'] as Map<String, dynamic>?;
      final mapped = Map<String, dynamic>.from(b)..remove('collector');
      if (collector != null) {
        final name = [collector['first_name'], collector['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
        mapped['assigned_collector_name'] = name.isNotEmpty ? name : null;
      }
      return mapped;
    }).toList();
  }

  static Future<void> deleteCompanyBin(int id) async {
    await _client.from('company_waste_bins').delete().eq('id', id);
  }

  static Future<void> saveCompanyBin(int? id, Map<String, dynamic> payload) async {
    if (id != null) {
      await _client.from('company_waste_bins').update(payload).eq('id', id);
    } else {
      await _client.from('company_waste_bins').insert(payload);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAllWasteTypesAdmin() async {
    final res = await _client.from('waste_types').select().order('sort_order');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> adminSaveWasteType({int? id, required String label, String? key, required String basePrice, required bool isActive}) async {
    final payload = <String, dynamic>{'label': label, 'base_price': double.parse(basePrice), 'is_active': isActive};
    if (id != null) {
      await _client.from('waste_types').update(payload).eq('id', id);
    } else {
      payload['key'] = key;
      await _client.from('waste_types').insert(payload);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAllBinTypesAdmin({int? wasteTypeId}) async {
    var query = _client.from('bin_types').select('*, waste_type:waste_types!bin_types_waste_type_id_fkey(key)');
    if (wasteTypeId != null) query = query.eq('waste_type_id', wasteTypeId);
    final res = await query.order('sort_order');
    return List<Map<String, dynamic>>.from(res).map((b) {
      final wt = b['waste_type'] as Map<String, dynamic>?;
      final mapped = Map<String, dynamic>.from(b)..remove('waste_type');
      mapped['size_label'] = b['name'];
      mapped['waste_type_key'] = wt?['key'];
      return mapped;
    }).toList();
  }

  static Future<void> adminSaveBinType({
    int? id,
    required String displayName,
    required String sizeLabel,
    required String price,
    int? wasteTypeId,
    required bool isActive,
  }) async {
    final payload = <String, dynamic>{
      'display_name': displayName,
      'name': sizeLabel,
      'price': double.parse(price),
      'is_active': isActive,
    };
    if (id != null) {
      await _client.from('bin_types').update(payload).eq('id', id);
    } else {
      payload['waste_type_id'] = wasteTypeId;
      await _client.from('bin_types').insert(payload);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchBinTypesForWasteTypeKey(String wasteTypeKey) async {
    final wt = await _client.from('waste_types').select('id').eq('key', wasteTypeKey).maybeSingle();
    if (wt == null) return [];
    final res = await _client.from('bin_types').select().eq('waste_type_id', wt['id']).order('sort_order');
    return List<Map<String, dynamic>>.from(res).map((b) => {...b, 'size_label': b['name']}).toList();
  }

  static Future<List<Map<String, dynamic>>> searchCustomersByName(String query) async {
    final res = await _client
        .from('profiles')
        .select()
        .eq('role', 'customer')
        .or('first_name.ilike.%$query%,last_name.ilike.%$query%,phone.ilike.%$query%')
        .limit(20);
    return List<Map<String, dynamic>>.from(res).map((c) {
      final name = [c['first_name'], c['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
      return {...c, 'name': name.isNotEmpty ? name : 'Customer'};
    }).toList();
  }

  static Future<void> adminCreateSchedule(Map<String, dynamic> fields) async {
    await _client.from('scheduled_pickups').insert(fields);
  }

  static Future<Map<String, dynamic>> fetchCollectorKycDetail(int collectorProfileId) async {
    final cp = await _client
        .from('collector_profiles')
        .select('*, profile:profiles!collector_profiles_user_id_fkey(first_name,last_name,phone,email,profile_image,password_set)')
        .eq('id', collectorProfileId)
        .single();
    final profile = cp['profile'] as Map<String, dynamic>?;
    final name = profile == null
        ? ''
        : [profile['first_name'], profile['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
    final collector = {
      ...cp,
      'name': name,
      'phone': profile?['phone'],
      'email': profile?['email'],
      'profile_image': profile?['profile_image'],
      'password_set': profile?['password_set'],
    }..remove('profile');

    final kycRow = await _client.from('collector_kyc').select().eq('user_id', cp['user_id']).maybeSingle();
    Map<String, dynamic>? kyc;
    if (kycRow != null) {
      final docs = await _client.from('kyc_documents').select().eq('kyc_id', kycRow['id']);
      kyc = {...kycRow, 'documents': List<Map<String, dynamic>>.from(docs)};
    }

    final vehicles = await _client.from('collector_vehicles').select().eq('collector_id', collectorProfileId);
    final scoreEvents = await _client
        .from('collector_score_events')
        .select()
        .eq('collector_id', collectorProfileId)
        .order('created_at', ascending: false)
        .limit(30);

    return {
      'collector': collector,
      'kyc': kyc,
      'vehicles': List<Map<String, dynamic>>.from(vehicles),
      'score_events': List<Map<String, dynamic>>.from(scoreEvents),
    };
  }

  static Future<Map<String, dynamic>> fetchAdminDashboard({String period = 'all', int? branchId}) async {
    final res = Map<String, dynamic>.from(await _client.rpc('get_admin_dashboard_stats', params: {
      'p_period': period,
      if (branchId != null) 'p_branch_id': branchId,
    }));
    final overview = res['overview'] as Map?;
    if (overview != null && overview['commission_rate'] != null) {
      overview['commission_rate'] = overview['commission_rate'].toString();
    }
    return res;
  }

  static Future<void> updateCommissionRate(String rate) async {
    await _client.from('system_config').update({'commission_rate': double.parse(rate)}).eq('id', 1);
  }

  static const String _adminCollectionSelect =
      '*, customer:profiles!pickup_requests_customer_id_fkey(first_name,last_name,phone),'
      'collector:profiles!pickup_requests_collector_id_fkey(first_name,last_name,phone),'
      'bin_type:bin_types(display_name),'
      'commission:collection_commissions!collection_commissions_pickup_request_id_fkey(commission_amount)';

  static Map<String, dynamic> _mapAdminCollectionRow(Map<String, dynamic> row) {
    final customer = row['customer'] as Map<String, dynamic>?;
    final collector = row['collector'] as Map<String, dynamic>?;
    final binType = row['bin_type'] as Map<String, dynamic>?;
    final commission = row['commission'];
    final commissionRow = commission is List && commission.isNotEmpty
        ? commission.first as Map<String, dynamic>
        : (commission is Map<String, dynamic> ? commission : null);
    String? nameOf(Map<String, dynamic>? p) {
      if (p == null) return null;
      final n = [p['first_name'], p['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
      return n.isNotEmpty ? n : null;
    }
    final mapped = Map<String, dynamic>.from(row)
      ..remove('customer')..remove('collector')..remove('bin_type')..remove('commission');
    mapped['customer_name'] = nameOf(customer) ?? 'Customer';
    mapped['customer_phone'] = customer?['phone'];
    mapped['collector_name'] = nameOf(collector);
    mapped['collector_phone'] = collector?['phone'];
    mapped['bin_type'] = binType?['display_name'];
    mapped['commission_amount'] = commissionRow?['commission_amount'];
    return mapped;
  }

  /// Mirrors AdminCollectionListView. Search is applied client-side over a
  /// capped recent-rows batch rather than a server-side OR-across-joins
  /// filter, since PostgREST doesn't cleanly express "match in either of two
  /// different embedded tables or the parent" in one request.
  static Future<Map<String, dynamic>> fetchAdminCollections({
    String? status,
    String search = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    var query = _client.from('pickup_requests').select(_adminCollectionSelect);
    if (status != null && status.isNotEmpty) query = query.eq('status', status);

    if (search.trim().isNotEmpty) {
      final rows = await query.order('created_at', ascending: false).limit(500);
      final q = search.trim().toLowerCase();
      final mapped = List<Map<String, dynamic>>.from(rows).map(_mapAdminCollectionRow).where((m) {
        return (m['customer_name'] as String? ?? '').toLowerCase().contains(q) ||
            (m['collector_name'] as String? ?? '').toLowerCase().contains(q) ||
            (m['pickup_address'] as String? ?? '').toLowerCase().contains(q);
      }).toList();
      final total = mapped.length;
      final start = (page - 1) * pageSize;
      final end = (start + pageSize).clamp(0, total);
      return {
        'total': total,
        'page': page,
        'page_size': pageSize,
        'results': start >= total ? <Map<String, dynamic>>[] : mapped.sublist(start, end),
      };
    }

    final countQuery = _client.from('pickup_requests').select('id');
    final countFiltered = status != null && status.isNotEmpty ? countQuery.eq('status', status) : countQuery;
    final total = (await countFiltered).length;
    final from = (page - 1) * pageSize;
    final rows = await query.order('created_at', ascending: false).range(from, from + pageSize - 1);
    return {
      'total': total,
      'page': page,
      'page_size': pageSize,
      'results': List<Map<String, dynamic>>.from(rows).map(_mapAdminCollectionRow).toList(),
    };
  }

  static Future<Map<String, dynamic>> adminAssignCollector(int requestId, String collectorUserId) async {
    return await _client.rpc('admin_assign_collector', params: {
      'p_request_id': requestId,
      'p_collector_user_id': collectorUserId,
    });
  }

  static Future<String?> _collectorUserId(int collectorProfileId) async {
    final row = await _client.from('collector_profiles').select('user_id').eq('id', collectorProfileId).maybeSingle();
    return row?['user_id'] as String?;
  }

  /// Ports ApproveCollectorView (admin_views.py:689) — flips is_approved AND
  /// syncs collector_kyc.kyc_status, which the KYC detail screen reads
  /// separately; leaving it stale made an approval look like it hadn't
  /// taken effect even though is_approved had already flipped.
  static Future<void> approveCollector(int collectorProfileId) async {
    await _client.from('collector_profiles').update({'is_approved': true}).eq('id', collectorProfileId);
    final userId = await _collectorUserId(collectorProfileId);
    if (userId != null) {
      // reviewed_by_id/reviewed_at intentionally omitted — collector_kyc has
      // no such columns in this Supabase project, and PostgREST rejects the
      // whole update if you reference one that doesn't exist.
      await _client.from('collector_kyc').update({
        'kyc_status': 'approved',
      }).eq('user_id', userId);
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': 'Account Approved',
        'body': 'Your collector account has been approved!',
        'notification_type': 'system',
      });
    }
  }

  /// Ports DeclineCollectorView (admin_views.py:708).
  static Future<void> declineCollector(int collectorProfileId, {String reason = ''}) async {
    await _client.from('collector_profiles').update({'is_approved': false}).eq('id', collectorProfileId);
    final userId = await _collectorUserId(collectorProfileId);
    if (userId != null) {
      // reviewed_by_id/reviewed_at intentionally omitted — see approveCollector.
      await _client.from('collector_kyc').update({
        'kyc_status': 'rejected',
        'rejection_reason': reason,
      }).eq('user_id', userId);
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': 'Account Declined',
        'body': 'Your collector application was declined. $reason'.trim(),
        'notification_type': 'system',
      });
    }
  }

  /// Ports SuspendCollectorView (admin_views.py:728).
  static Future<void> suspendCollector(int collectorProfileId) async {
    await _client
        .from('collector_profiles')
        .update({'is_approved': false, 'is_online': false}).eq('id', collectorProfileId);
    final userId = await _collectorUserId(collectorProfileId);
    if (userId != null) {
      await _client.from('collector_kyc').update({'kyc_status': 'suspended'}).eq('user_id', userId);
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': 'Account Suspended',
        'body': 'Your collector account has been suspended.',
        'notification_type': 'system',
      });
    }
  }

  static Future<Map<String, dynamic>> fetchAdminCustomersPaged({
    String search = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    return Map<String, dynamic>.from(await _client.rpc('get_admin_customers_paged', params: {
      'p_search': search,
      'p_page': page,
      'p_page_size': pageSize,
    }));
  }

  static Future<Map<String, dynamic>> fetchAdminCollectorsPaged({
    String search = '',
    String kycStatus = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    return Map<String, dynamic>.from(await _client.rpc('get_admin_collectors_paged', params: {
      'p_search': search,
      'p_kyc_status': kycStatus,
      'p_page': page,
      'p_page_size': pageSize,
    }));
  }

  static Future<Map<String, dynamic>> adminCreateCustomer({
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    String? password,
  }) async {
    final res = await _client.functions.invoke('admin-create-customer', body: {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (password != null && password.isNotEmpty) 'password': password,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  static Future<Map<String, dynamic>> adminCreateCollector({
    required String name,
    required String phone,
    required String ghanaCardNumber,
    required String licenseNumber,
    bool autoApprove = false,
    bool isCompanyCollector = false,
    int? existingVehicleId,
    String? vehicleType,
    String? vehicleNumber,
    String? vehicleName,
    String? password,
    int? branchId,
    Map<String, Uint8List> images = const {},
  }) async {
    final imagesB64 = <String, String>{};
    for (final entry in images.entries) {
      imagesB64[entry.key] = base64Encode(entry.value);
    }
    final res = await _client.functions.invoke('admin-create-collector', body: {
      'name': name,
      'phone': phone,
      'ghana_card_number': ghanaCardNumber,
      'license_number': licenseNumber,
      'auto_approve': autoApprove,
      'is_company_collector': isCompanyCollector,
      if (existingVehicleId != null) 'existing_vehicle_id': existingVehicleId,
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (vehicleNumber != null) 'vehicle_number': vehicleNumber,
      if (vehicleName != null) 'vehicle_name': vehicleName,
      if (password != null && password.isNotEmpty) 'password': password,
      if (branchId != null) 'branch_id': branchId,
      'images': imagesB64,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  static Future<Map<String, dynamic>> adminCreateInvestor({
    required String firstName,
    required String lastName,
    required String phone,
    required String location,
    required String investmentAmount,
    String roiPercentage = '0',
    double? locationLat,
    double? locationLng,
    String? companyName,
    String? email,
  }) async {
    final res = await _client.functions.invoke('admin-create-investor', body: {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'location': location,
      'investment_amount': investmentAmount,
      'roi_percentage': roiPercentage,
      if (locationLat != null) 'location_latitude': locationLat,
      if (locationLng != null) 'location_longitude': locationLng,
      if (companyName != null && companyName.isNotEmpty) 'company_name': companyName,
      if (email != null && email.isNotEmpty) 'email': email,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  static Future<List<Map<String, dynamic>>> fetchAllBranches() async {
    final res = await _client.from('branches').select().order('name');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> fetchAdminBranchesList() async {
    final res = await _client.rpc('get_admin_branches_list');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>> createBranch({
    required String name,
    required String region,
    String country = 'Ghana',
    String address = '',
    required double lat,
    required double lng,
    double serviceRadiusKm = 50.0,
  }) async {
    return await _client.from('branches').insert({
      'name': name, 'region': region, 'country': country, 'address': address,
      'lat': lat, 'lng': lng, 'service_radius_km': serviceRadiusKm,
    }).select().single();
  }

  static Future<void> updateBranch(int id, Map<String, dynamic> fields) async {
    await _client.from('branches').update(fields).eq('id', id);
  }

  static Future<void> deleteBranch(int id) async {
    await _client.from('branches').delete().eq('id', id);
  }

  static Future<void> updateAllBranchesRadius(double radiusKm) async {
    await _client.from('branches').update({'service_radius_km': radiusKm}).not('id', 'is', null);
  }

  static Future<List<Map<String, dynamic>>> fetchAdminUsers() async {
    final res = await _client.from('profiles').select().inFilter('role', ['staff', 'admin', 'super_admin']).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res).map((u) {
      final name = [u['first_name'], u['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
      return {...u, 'full_name': name.isNotEmpty ? name : (u['username'] ?? 'Admin')};
    }).toList();
  }

  static Future<Map<String, dynamic>> createAdminUser({
    required String firstName,
    required String lastName,
    required String phone,
    String email = '',
    int? branchId,
    String role = 'admin',
  }) async {
    final res = await _client.functions.invoke('admin-create-admin', body: {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'email': email,
      'role': role,
      if (branchId != null) 'branch_id': branchId,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  static Future<void> assignAdminBranch(String adminId, int? branchId) async {
    await _client.from('profiles').update({'branch_id': branchId}).eq('id', adminId);
  }

  static Future<List<Map<String, dynamic>>> fetchUnassignedVehicles() async {
    final res = await _client.from('collector_vehicles').select().filter('collector_id', 'is', null).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> fetchAdminInvestorsList() async {
    final res = await _client.rpc('get_admin_investors_list');
    // The RPC only sets 'full_name' — admin_home.dart's investor list row
    // reads 'name' (matching the 'name' field every other admin list RPC
    // here returns), so without this alias every investor renders blank.
    return List<Map<String, dynamic>>.from(res).map((r) => {...r, 'name': r['full_name']}).toList();
  }

  static Future<void> adminDeleteUser(String userId, {String? expectedRole}) async {
    final res = await _client.functions.invoke('admin-delete-user', body: {
      'user_id': userId,
      if (expectedRole != null) 'expected_role': expectedRole,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
  }

  static Future<List<Map<String, dynamic>>> fetchAdminCustomers() async {
    final res = await _client.from('profiles').select().eq('role', 'customer').order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res).map((c) {
      final name = [c['first_name'], c['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
      return {...c, 'name': name.isNotEmpty ? name : 'Customer'};
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchAdminCollectors() async {
    final res = await _client
        .from('collector_profiles')
        .select('*, profile:profiles!collector_profiles_user_id_fkey(first_name,last_name,phone,email)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res).map((m) {
      final profile = m['profile'] as Map<String, dynamic>?;
      final mapped = Map<String, dynamic>.from(m)..remove('profile');
      if (profile != null) {
        final name = [profile['first_name'], profile['last_name']]
            .where((s) => s != null && (s as String).isNotEmpty)
            .join(' ');
        mapped['full_name'] = name.isNotEmpty ? name : 'Collector';
        mapped['name'] = mapped['full_name'];
        mapped['phone'] = profile['phone'];
        mapped['email'] = profile['email'];
      }
      return mapped;
    }).toList();
  }

  static Future<Map<String, dynamic>> fetchAdminSchedulesPaged({
    String search = '',
    String isActive = 'true',
    String period = 'all',
    int page = 1,
    int pageSize = 20,
  }) async {
    return Map<String, dynamic>.from(await _client.rpc('get_admin_schedules_paged', params: {
      'p_search': search,
      'p_is_active': isActive,
      'p_period': period,
      'p_page': page,
      'p_page_size': pageSize,
    }));
  }

  static Future<List<Map<String, dynamic>>> fetchAdminSchedules() async {
    final res = await _client
        .from('scheduled_pickups')
        .select('*, customer:profiles!scheduled_pickups_customer_id_fkey(first_name,last_name,phone)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> fetchAdminReports() async {
    final res = await _client
        .from('dumping_reports')
        .select('*, reported_by:profiles!dumping_reports_reported_by_id_fkey(first_name,last_name,phone)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>> fetchAllTickets({
    String? category,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    var query = _client
        .from('support_tickets')
        .select('*, user:profiles!support_tickets_user_id_fkey(first_name,last_name,role), support_messages(message, created_at)');
    var countQuery = _client.from('support_tickets').select('id');
    if (category != null) {
      query = query.eq('category', category);
      countQuery = countQuery.eq('category', category);
    }
    if (status != null) {
      query = query.eq('status', status);
      countQuery = countQuery.eq('status', status);
    }
    final from = (page - 1) * pageSize;
    final res = await query.order('created_at', ascending: false).range(from, from + pageSize - 1);
    final countRes = await countQuery;
    final results = List<Map<String, dynamic>>.from(res).map((t) {
      final user = t['user'] as Map<String, dynamic>?;
      final msgs = (t['support_messages'] as List?) ?? [];
      final mapped = Map<String, dynamic>.from(t)..remove('user')..remove('support_messages');
      if (user != null) {
        final name = [user['first_name'], user['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
        mapped['user_name'] = name.isNotEmpty ? name : 'User';
        mapped['user_role'] = user['role'];
      }
      if (msgs.isNotEmpty) {
        final sorted = List<Map<String, dynamic>>.from(msgs)
          ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
        mapped['last_message'] = sorted.first['message'];
      }
      return mapped;
    }).toList();
    return {'results': results, 'total': countRes.length};
  }

  static Future<Map<String, dynamic>> fetchAdminTicketThread(int ticketId) async {
    final uid = currentUser?.id;
    final ticket = await _client
        .from('support_tickets')
        .select('status, category, user_id, user:profiles!support_tickets_user_id_fkey(first_name,last_name,role)')
        .eq('id', ticketId)
        .single();
    final user = ticket['user'] as Map<String, dynamic>?;
    final ownerId = ticket['user_id'];
    final messages = await _client
        .from('support_messages')
        .select()
        .eq('ticket_id', ticketId)
        .order('created_at');
    final mappedMessages = List<Map<String, dynamic>>.from(messages).map((m) => {
          ...m,
          'body': m['message'],
          'is_admin': m['sender_id'] != ownerId,
          'is_mine': m['sender_id'] == uid,
        }).toList();
    return {
      'status': ticket['status'],
      'category': ticket['category'],
      'user_name': user == null
          ? ''
          : [user['first_name'], user['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' '),
      'user_role': user?['role'],
      'messages': mappedMessages,
    };
  }

  static Future<void> sendAdminTicketReply(int ticketId, String message) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('support_messages').insert({'ticket_id': ticketId, 'sender_id': uid, 'message': message});
    await _client.from('support_tickets').update({'status': 'assigned', 'assigned_admin_id': uid}).eq('id', ticketId);
  }

  static Future<void> resolveTicket(int ticketId) async {
    await _client.from('support_tickets').update({'status': 'resolved'}).eq('id', ticketId);
  }

  static Future<void> resolveReport(int reportId) async {
    await _client.from('dumping_reports').update({'status': 'resolved', 'resolved_at': DateTime.now().toIso8601String()}).eq('id', reportId);
  }

  static Future<void> assignScheduleCollector(int scheduleId, String collectorUserId) async {
    await _client.from('scheduled_pickups').update({'assigned_collector_id': collectorUserId}).eq('id', scheduleId);
  }

  // ── Support tickets (shared shape for customer + collector) ────────────

  static Future<List<Map<String, dynamic>>> fetchMyTickets() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client
        .from('support_tickets')
        .select('*, support_messages(message, created_at)')
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res).map((t) {
      final msgs = (t['support_messages'] as List?) ?? [];
      final mapped = Map<String, dynamic>.from(t)..remove('support_messages');
      if (msgs.isNotEmpty) {
        final sorted = List<Map<String, dynamic>>.from(msgs)
          ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
        mapped['last_message'] = sorted.first['message'];
      }
      return mapped;
    }).toList();
  }

  static Future<Map<String, dynamic>> createTicket({required String category, required String message}) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final ticket = await _client
        .from('support_tickets')
        .insert({'user_id': uid, 'category': category, 'status': 'open'})
        .select()
        .single();
    await _client.from('support_messages').insert({
      'ticket_id': ticket['id'],
      'sender_id': uid,
      'message': message,
    });
    return {...ticket, 'ticket_id': ticket['id'], 'last_message': message};
  }

  static Future<Map<String, dynamic>> fetchTicketThread(int ticketId) async {
    final uid = currentUser?.id;
    final ticket = await _client.from('support_tickets').select('status').eq('id', ticketId).single();
    final messages = await _client
        .from('support_messages')
        .select('*, sender:profiles!support_messages_sender_id_fkey(first_name,last_name,role)')
        .eq('ticket_id', ticketId)
        .order('created_at');
    final mapped = List<Map<String, dynamic>>.from(messages).map((m) {
      final sender = m['sender'] as Map<String, dynamic>?;
      return {
        ...m,
        'body': m['message'],
        'is_mine': m['sender_id'] == uid,
        'sender_name': sender == null
            ? null
            : [sender['first_name'], sender['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' '),
        'sender_role': sender?['role'],
      };
    }).toList();
    return {'status': ticket['status'], 'messages': mapped};
  }

  static Future<Map<String, dynamic>> sendTicketMessage(int ticketId, String message) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('support_messages').insert({
      'ticket_id': ticketId,
      'sender_id': uid,
      'message': message,
    });
    return fetchTicketThread(ticketId);
  }

  // ── Investor (Phase 4) ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchCompanyStats() async {
    return await _client.rpc('get_company_stats');
  }

  static Future<num> fetchInvestorEarningsShare(int investorProfileId) async {
    return await _client.rpc('get_investor_earnings_share', params: {'p_investor_id': investorProfileId});
  }

  static Future<Map<String, dynamic>?> fetchMyInvestorProfile() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    return await _client.from('investor_profiles').select().eq('user_id', uid).maybeSingle();
  }

  static const _managementLabels = {'bola_aba': 'Managed by Bɔla Aba', 'self': 'Self Managed'};
  static const _assignmentLabels = {'bola_aba': 'Assigned by Bɔla Aba', 'investor': 'Assigned by Investor'};

  static Map<String, dynamic> _mapFleetRide(Map<String, dynamic> r) {
    final collector = r['collector'] as Map<String, dynamic>?;
    final profile = collector?['profile'] as Map<String, dynamic>?;
    final mapped = Map<String, dynamic>.from(r)..remove('collector');
    mapped['management_label'] = _managementLabels[r['management_mode']] ?? '';
    mapped['assignment_label'] = _assignmentLabels[r['assignment_source']] ?? '';
    if (profile != null) {
      final name = [profile['first_name'], profile['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
      mapped['assigned_collector'] = {
        'id': collector?['id'],
        'full_name': name.isNotEmpty ? name : 'Collector',
        'name': name.isNotEmpty ? name : 'Collector',
        'phone': profile['phone'],
        'is_approved': collector?['is_approved'],
      };
    }
    return mapped;
  }

  static Future<List<Map<String, dynamic>>> fetchInvestorFleetRides(int investorProfileId) async {
    final res = await _client
        .from('investor_fleet_rides')
        .select('*, collector:collector_profiles(id, is_approved, profile:profiles!collector_profiles_user_id_fkey(first_name,last_name,phone))')
        .eq('investor_id', investorProfileId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res).map(_mapFleetRide).toList();
  }

  static Future<Map<String, dynamic>> fetchInvestorRideDetail(int rideId) async {
    final ride = await _client
        .from('investor_fleet_rides')
        .select('*, collector:collector_profiles(id, is_approved, profile:profiles!collector_profiles_user_id_fkey(first_name,last_name,phone))')
        .eq('id', rideId)
        .single();
    final mapped = _mapFleetRide(ride);
    final collectorId = (ride['collector'] as Map<String, dynamic>?)?['id'];
    List<Map<String, dynamic>> collections = [];
    if (collectorId != null) {
      final collectorUserId = await _client.from('collector_profiles').select('user_id').eq('id', collectorId).single();
      final res = await _client
          .from('pickup_requests')
          .select('pickup_address, price')
          .eq('collector_id', collectorUserId['user_id'])
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(50);
      collections = List<Map<String, dynamic>>.from(res);
    }
    return {'ride': mapped, 'collections': collections};
  }

  static Future<Map<String, dynamic>> registerInvestorRide({
    required String name,
    required String vehicleType,
    required String vehicleNumber,
    required String managementMode,
    int? assignedCollectorProfileId,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final investorProfile = await _client.from('investor_profiles').select('id').eq('user_id', uid).single();
    final row = await _client
        .from('investor_fleet_rides')
        .insert({
          'investor_id': investorProfile['id'],
          'name': name,
          'vehicle_type': vehicleType,
          'vehicle_number': vehicleNumber,
          'management_mode': managementMode,
          'assignment_source': assignedCollectorProfileId != null ? 'investor' : '',
          'assigned_collector_id': assignedCollectorProfileId,
        })
        .select()
        .single();
    return row;
  }

  static Future<List<Map<String, dynamic>>> fetchInvestorRegisteredCollectors() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final investorProfile = await _client.from('investor_profiles').select('id').eq('user_id', uid).maybeSingle();
    if (investorProfile == null) return [];
    final res = await _client
        .from('collector_profiles')
        .select('*, profile:profiles!collector_profiles_user_id_fkey(first_name,last_name,phone)')
        .eq('investor_id', investorProfile['id'])
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res).map((c) {
      final profile = c['profile'] as Map<String, dynamic>?;
      final mapped = Map<String, dynamic>.from(c)..remove('profile');
      if (profile != null) {
        final name = [profile['first_name'], profile['last_name']].where((s) => s != null && (s as String).isNotEmpty).join(' ');
        mapped['full_name'] = name.isNotEmpty ? name : 'Collector';
        mapped['name'] = mapped['full_name'];
        mapped['phone'] = profile['phone'];
      }
      return mapped;
    }).toList();
  }

  /// Registers a brand-new collector on the investor's behalf via the
  /// investor-register-collector Edge Function (see its own doc comment
  /// for why this can't be a direct client-side signUp call).
  static Future<Map<String, dynamic>> investorRegisterCollector({
    required String name,
    required String phone,
    required String vehicleType,
    String? ghanaCardNumber,
    String? licenseNumber,
    String? vehicleName,
    String? vehicleNumber,
    Map<String, Uint8List> images = const {},
  }) async {
    final imagesB64 = <String, String>{};
    for (final entry in images.entries) {
      imagesB64[entry.key] = base64Encode(entry.value);
    }
    final res = await _client.functions.invoke('investor-register-collector', body: {
      'name': name,
      'phone': phone,
      'vehicle_type': vehicleType,
      'ghana_card_number': ghanaCardNumber,
      'license_number': licenseNumber,
      'vehicle_name': vehicleName,
      'vehicle_number': vehicleNumber,
      'images': imagesB64,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  static Future<Map<String, dynamic>> fetchInvestorDashboard() async {
    return Map<String, dynamic>.from(await _client.rpc('get_investor_dashboard'));
  }

  static Future<List<Map<String, dynamic>>> fetchInvestorEarningsList() async {
    final profile = await fetchMyInvestorProfile();
    if (profile == null) return [];
    final res = await _client
        .from('investor_earnings')
        .select()
        .eq('investor_id', profile['id'])
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> updateInvestorProfile(Map<String, dynamic> fields) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('investor_profiles').update(fields).eq('user_id', uid);
  }

  /// Updates the actual Supabase Auth login email (not just the `profiles`
  /// display column `updateOwnProfile` writes) — admin/staff log in with
  /// email+password, so leaving auth.users.email untouched meant the
  /// "update email" field never actually changed what they log in with.
  /// Supabase's default double-opt-in flow sends confirmation links to both
  /// the old and new address before the auth email actually switches.
  static Future<void> updateOwnEmail(String newEmail) async {
    await _client.auth.updateUser(UserAttributes(email: newEmail));
  }

  static Future<void> updateOwnProfile(Map<String, dynamic> fields) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    await _client.from('profiles').update(fields).eq('id', uid);
  }

  // ── Collector: history + schedules ──────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCollectorCollections({String period = 'all'}) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    var query = _client
        .from('pickup_requests')
        .select(_collectorPickupRequestSelect)
        .eq('collector_id', uid)
        .eq('status', 'completed');
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    switch (period) {
      case 'today':
        query = query.gte('completed_at', startOfToday.toIso8601String());
        break;
      case 'yesterday':
        final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
        query = query
            .gte('completed_at', startOfYesterday.toIso8601String())
            .lt('completed_at', startOfToday.toIso8601String());
        break;
      case 'week':
        final startOfWeek = startOfToday.subtract(Duration(days: today.weekday - 1));
        query = query.gte('completed_at', startOfWeek.toIso8601String());
        break;
    }
    final res = await query.order('completed_at', ascending: false);
    return List<Map<String, dynamic>>.from(res).map(_mapCollectorPickupRow).toList();
  }

  static Future<Map<String, dynamic>> fetchCollectorCollectionDetail(int id) async {
    final row = await _client.from('pickup_requests').select(_collectorPickupRequestSelect).eq('id', id).single();
    return _mapCollectorPickupRow(row);
  }

  static Future<List<Map<String, dynamic>>> fetchAssignedSchedules() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final res = await _client.rpc('get_collector_assigned_schedules');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> confirmSchedulePickup(int scheduleId) async {
    await _client.from('scheduled_pickups').update({'collector_confirmed': true}).eq('id', scheduleId);
  }

  // ── Vehicles ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchMyVehicles() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final cp = await _client.from('collector_profiles').select('id').eq('user_id', uid).single();
    final res = await _client.from('collector_vehicles').select().eq('collector_id', cp['id']).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>> fetchVehicleDetail(int vehicleId) async {
    final row = Map<String, dynamic>.from(
        await _client.from('collector_vehicles').select().eq('id', vehicleId).single());
    final driverId = row['driver_id'] as String?;
    if (driverId != null) {
      final profile = await _client
          .from('profiles')
          .select('first_name, last_name, phone')
          .eq('id', driverId)
          .maybeSingle();
      if (profile != null) {
        final name = [profile['first_name'], profile['last_name']]
            .where((s) => s != null && (s as String).isNotEmpty)
            .join(' ');
        row['driver'] = {
          'name': name.isNotEmpty ? name : 'Driver',
          'phone': profile['phone'],
          // Mirrors the vehicle-level admin approval flag — there's no
          // separate per-driver approval state in the schema.
          'approved': row['needs_admin_approval'] != true,
        };
      }
      final reg = await _client
          .from('vehicle_driver_registrations')
          .select('docs')
          .eq('vehicle_id', vehicleId)
          .maybeSingle();
      final docs = reg?['docs'] as Map<String, dynamic>?;
      if (docs != null) {
        row['driver_registration'] = {
          'ghana_card_number': docs['ghana_card_number'],
          'license_number': docs['license_number'],
          'address': docs['address'],
        };
      }
    }
    return row;
  }

  static Future<void> updateVehicle(int vehicleId, Map<String, dynamic> fields) async {
    await _client.from('collector_vehicles').update(fields).eq('id', vehicleId);
  }

  static Future<void> setDefaultVehicle(int vehicleId) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final cp = await _client.from('collector_profiles').select('id').eq('user_id', uid).single();
    await _client.from('collector_vehicles').update({'is_default': false}).eq('collector_id', cp['id']);
    await _client.from('collector_vehicles').update({'is_default': true}).eq('id', vehicleId);
  }

  /// Registers a new vehicle. When [assignSelf] is false, the driver is a
  /// separate person without their own account — their name/phone/address
  /// and KYC-lite docs are stored on the vehicle_driver_registrations row's
  /// `docs` field (there's no separate driver-identity table for this).
  static Future<Map<String, dynamic>> registerVehicle({
    required String name,
    required String vehicleType,
    required String vehicleNumber,
    String? phone,
    required bool assignSelf,
    required Uint8List vehiclePhoto,
    String? driverName,
    String? driverPhone,
    String? driverAddress,
    String? ghanaCardNumber,
    String? licenseNumber,
    Map<String, Uint8List> driverDocs = const {},
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final cp = await _client.from('collector_profiles').select('id').eq('user_id', uid).single();
    final collectorId = cp['id'];

    final photoPath = '$uid/vehicles/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('vehicle-photos').uploadBinary(photoPath, vehiclePhoto, fileOptions: const FileOptions(upsert: true));

    final vehicle = await _client
        .from('collector_vehicles')
        .insert({
          'collector_id': collectorId,
          'name': name,
          'vehicle_type': vehicleType,
          'vehicle_number': vehicleNumber,
          'phone': phone,
          'vehicle_photo': photoPath,
          'needs_admin_approval': !assignSelf,
          'driver_id': assignSelf ? uid : null,
        })
        .select()
        .single();

    if (!assignSelf) {
      final docs = <String, dynamic>{
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'driver_address': driverAddress,
        'ghana_card_number': ghanaCardNumber,
        'license_number': licenseNumber,
      };
      for (final entry in driverDocs.entries) {
        final path = '$uid/vehicles/${vehicle['id']}/${entry.key}.jpg';
        await _client.storage.from('vehicle-photos').uploadBinary(path, entry.value, fileOptions: const FileOptions(upsert: true));
        docs[entry.key] = path;
      }
      await _client.from('vehicle_driver_registrations').insert({
        'vehicle_id': vehicle['id'],
        'registered_by_id': uid,
        'docs': docs,
      });
    }

    return {'message': 'Vehicle registered.', 'vehicle': vehicle};
  }

  // ── Credit score gamification ───────────────────────────────────────────

  static const List<Map<String, dynamic>> creditScoreActionDefs = [
    {'type': 'share_collector', 'points': 5, 'label': 'Share app with another collector'},
    {'type': 'share_customer', 'points': 4, 'label': 'Share app with a customer'},
    {'type': 'rate_app', 'points': 3, 'label': 'Rate the app'},
    {'type': 'share_rate', 'points': 2, 'label': 'Share app for ratings'},
  ];

  static Future<Map<String, dynamic>> fetchCreditScoreActions() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final cp = await _client.from('collector_profiles').select('id, credit_score').eq('user_id', uid).single();
    final completedRows = await _client.from('credit_score_actions').select('action_type').eq('collector_id', cp['id']);
    final completed = List<Map<String, dynamic>>.from(completedRows).map((r) => r['action_type'] as String).toSet();
    return {
      'credit_score': cp['credit_score'],
      'actions': creditScoreActionDefs
          .map((a) => {...a, 'done': completed.contains(a['type'])})
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> claimCreditScoreAction(String action) async {
    return Map<String, dynamic>.from(await _client.rpc('claim_credit_score_action', params: {'p_action': action}));
  }

  // ── KYC ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchMyKyc() async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    return await _client.from('collector_kyc').select().eq('user_id', uid).maybeSingle();
  }

  /// Upserts the KYC record (creating one if the collector somehow doesn't
  /// have one yet) and uploads any newly-picked documents, resetting status
  /// to 'pending' so it goes back into admin review.
  static Future<void> submitKyc({
    required Map<String, String> fields,
    required Map<String, Uint8List> files,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');

    final existing = await _client.from('collector_kyc').select('id').eq('user_id', uid).maybeSingle();
    final Map<String, dynamic> kyc;
    final kycFields = {
      'middle_name': fields['middle_name'],
      'ghana_card_number': fields['ghana_card_number'],
      'email': fields['email'],
      'license_number': fields['license_number'],
      'vehicle_number_plate': fields['vehicle_number_plate'],
      'vehicle_details': fields['vehicle_details'],
      'kyc_status': 'pending',
    };
    if (existing == null) {
      kyc = await _client.from('collector_kyc').insert({'user_id': uid, ...kycFields}).select().single();
    } else {
      kyc = await _client.from('collector_kyc').update(kycFields).eq('id', existing['id']).select().single();
    }

    for (final entry in files.entries) {
      final path = '$uid/${entry.key}.jpg';
      await _client.storage.from('kyc-documents').uploadBinary(path, entry.value, fileOptions: const FileOptions(upsert: true));
      await _client.from('kyc_documents').upsert(
        {'kyc_id': kyc['id'], 'document_type': entry.key, 'file': path},
        onConflict: 'kyc_id,document_type',
      );
    }
  }

  // ── Profile image (Storage) ─────────────────────────────────────────────

  /// Uploads to the public profile-images bucket and stores the public URL
  /// on profiles.profile_image. Returns that URL.
  static Future<String> uploadProfileImage(Uint8List bytes, {String ext = 'jpg'}) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not logged in');
    final path = '$uid/avatar.$ext';
    await _client.storage.from('profile-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from('profile-images').getPublicUrl(path);
    await _client.from('profiles').update({'profile_image': url}).eq('id', uid);
    return url;
  }
}
