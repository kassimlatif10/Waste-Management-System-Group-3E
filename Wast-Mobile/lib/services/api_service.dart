import 'dart:convert';
import 'dart:io' as dart_io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import 'app_config.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  ApiService._();

  static const _kAccess  = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _timeout  = Duration(seconds: 20);

  // ── HTTP client ────────────────────────────────────────────────────────────
  // Uses an IOClient so we can accept the self-signed / IP-based TLS cert on
  // the production server.  All cert validation is bypassed only for the
  // configured API host; this is intentional for IP-based HTTPS deployments.
  //
  // dart:io.HttpClient does not exist on Flutter Web — instantiating it there
  // throws at runtime (before any real network call is ever made), which a
  // generic catch-all then mislabels as "can't connect". The browser's own
  // http.Client already validates certificates against its trusted CA store,
  // so there's no equivalent bad-cert override needed there anyway.
  static http.Client _buildClient() {
    if (kIsWeb) return http.Client();
    final apiHost = Uri.tryParse(AppConfig.baseUrl)?.host ?? '';
    final inner = dart_io.HttpClient()
      ..badCertificateCallback = (dart_io.X509Certificate cert, String host, int port) {
        if (apiHost.isEmpty) return false;
        return host == apiHost;
      };
    return IOClient(inner);
  }

  // ── Token storage ──────────────────────────────────────────────────────────

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccess, access);
    await p.setString(_kRefresh, refresh);
  }

  static Future<String?> getAccessToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAccess);
  }

  static Future<String?> getRefreshToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kRefresh);
  }

  static Future<void> clearTokens() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAccess);
    await p.remove(_kRefresh);
  }

  static Future<bool> hasTokens() async {
    final t = await getAccessToken();
    return t != null && t.isNotEmpty;
  }

  // ── Token refresh ──────────────────────────────────────────────────────────

  static Future<bool> _refresh() async {
    final refresh = await getRefreshToken();
    if (refresh == null) return false;
    try {
      final client = _buildClient();
      final res = await client
          .post(
            Uri.parse(ApiConstants.tokenRefresh),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(_timeout);
      client.close();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final p = await SharedPreferences.getInstance();
        await p.setString(_kAccess, data['access'] as String);
        if (data.containsKey('refresh')) {
          await p.setString(_kRefresh, data['refresh'] as String);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await getAccessToken();
      if (token != null) h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  static String? _firstFieldError(Map<String, dynamic> body) {
    for (final v in body.values) {
      if (v is List && v.isNotEmpty) return v.first?.toString();
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return {};
    try {
      final d = jsonDecode(res.body);
      return d is Map<String, dynamic> ? d : {'data': d};
    } catch (_) {
      return {'raw': res.body};
    }
  }

  static Future<Map<String, dynamic>> _handle(
    http.Response res,
    Future<http.Response> Function() retry,
  ) async {
    if (res.statusCode == 401) {
      final ok = await _refresh();
      if (ok) {
        final r2 = await retry();
        if (r2.statusCode < 300) return _decode(r2);
      }
      await clearTokens();
      throw ApiException('Session expired. Please log in again.', statusCode: 401);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res);

    final body = _decode(res);
    final msg = body['error'] ??
        body['detail'] ??
        body['message'] ??
        _firstFieldError(body) ??
        'Request failed (${res.statusCode})';
    throw ApiException(msg.toString(), statusCode: res.statusCode);
  }

  // ── Public HTTP methods ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> get(String url) async {
    final client = _buildClient();
    try {
      final h = await _headers();
      final res = await client.get(Uri.parse(url), headers: h).timeout(_timeout);
      return _handle(res, () async {
        final c2 = _buildClient();
        final h2 = await _headers();
        final r2 = await c2.get(Uri.parse(url), headers: h2).timeout(_timeout);
        c2.close();
        return r2;
      });
    } finally { client.close(); }
  }

  static Future<List<dynamic>> getList(String url) async {
    final client = _buildClient();
    try {
      final h = await _headers(auth: false);
      final res = await client.get(Uri.parse(url), headers: h).timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = jsonDecode(res.body);
        return d is List ? d : [];
      }
      return [];
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> post(
    String url,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    final client = _buildClient();
    try {
      final h = await _headers(auth: authenticated);
      final encoded = jsonEncode(body);
      final res = await client
          .post(Uri.parse(url), headers: h, body: encoded)
          .timeout(_timeout);
      return _handle(res, () async {
        final c2 = _buildClient();
        final h2 = await _headers(auth: authenticated);
        final r2 = await c2.post(Uri.parse(url), headers: h2, body: encoded).timeout(_timeout);
        c2.close();
        return r2;
      });
    } finally { client.close(); }
  }

  static Future<Map<String, dynamic>> put(
    String url,
    Map<String, dynamic> body,
  ) async {
    final client = _buildClient();
    try {
      final h = await _headers();
      final encoded = jsonEncode(body);
      final res = await client
          .put(Uri.parse(url), headers: h, body: encoded)
          .timeout(_timeout);
      return _handle(res, () async {
        final c2 = _buildClient();
        final h2 = await _headers();
        final r2 = await c2.put(Uri.parse(url), headers: h2, body: encoded).timeout(_timeout);
        c2.close();
        return r2;
      });
    } finally { client.close(); }
  }

  static Future<Map<String, dynamic>> delete(String url) async {
    final client = _buildClient();
    try {
      final h = await _headers();
      final res = await client.delete(Uri.parse(url), headers: h).timeout(_timeout);
      if (res.statusCode == 204) return {};
      return _handle(res, () async {
        final c2 = _buildClient();
        final h2 = await _headers();
        final r2 = await c2.delete(Uri.parse(url), headers: h2).timeout(_timeout);
        c2.close();
        return r2;
      });
    } finally { client.close(); }
  }

  static Future<Map<String, dynamic>> patch(String url, Map<String, dynamic> body) async {
    final client = _buildClient();
    try {
      final h = await _headers();
      final encoded = jsonEncode(body);
      final res = await client
          .patch(Uri.parse(url), headers: h, body: encoded)
          .timeout(_timeout);
      return _handle(res, () async {
        final c2 = _buildClient();
        final h2 = await _headers();
        final r2 = await c2.patch(Uri.parse(url), headers: h2, body: encoded).timeout(_timeout);
        c2.close();
        return r2;
      });
    } finally { client.close(); }
  }

  /// Multipart PATCH for profile image uploads.
  static Future<Map<String, dynamic>> patchMultipart(
    String url,
    Map<String, String> fields, {
    dart_io.File? imageFile,
    String imageField = 'profile_image',
  }) async {
    return _sendMultipart(() async {
      final request = http.MultipartRequest('PATCH', Uri.parse(url));
      final token = await getAccessToken();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(fields);
      if (imageFile != null) {
        request.files.add(await _multipartImageFile(imageField, imageFile));
      }
      return request;
    });
  }

  /// Multipart POST for KYC document uploads.
  static Future<Map<String, dynamic>> postMultipart(
    String url,
    Map<String, String> fields,
    Map<String, dart_io.File> files,
  ) async {
    final token = await getAccessToken();
    final client = _buildClient();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(fields);
      for (final entry in files.entries) {
        request.files.add(await http.MultipartFile.fromPath(entry.key, entry.value.path));
      }
      final streamed = await client.send(request).timeout(_timeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) return {};
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      throw Exception('Upload failed: ${res.statusCode} ${res.body}');
    } finally { client.close(); }
  }

  /// Multipart PUT for profile / vehicle uploads.
  static Future<Map<String, dynamic>> putMultipart(
    String url,
    Map<String, String> fields, {
    dart_io.File? imageFile,
    String imageField = 'profile_image',
    Map<String, dart_io.File> files = const {},
  }) async {
    return _sendMultipart(() async {
      final request = http.MultipartRequest('PUT', Uri.parse(url));
      final token = await getAccessToken();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(fields);
      if (imageFile != null) {
        request.files.add(await _multipartImageFile(imageField, imageFile));
      }
      for (final entry in files.entries) {
        request.files.add(await _multipartImageFile(entry.key, entry.value));
      }
      return request;
    });
  }

  static Future<http.MultipartFile> _multipartImageFile(
    String field,
    dart_io.File file,
  ) async {
    final path = file.path;
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg';
    final normalizedExt = (ext == 'heic' || ext == 'heif') ? 'jpg' : ext;
    final mime = normalizedExt == 'png' ? 'image/png' : 'image/jpeg';
    return http.MultipartFile.fromPath(
      field,
      path,
      filename: 'upload.$normalizedExt',
      contentType: MediaType.parse(mime),
    );
  }

  static Future<Map<String, dynamic>> _sendMultipart(
    Future<http.MultipartRequest> Function() buildRequest,
  ) async {
    Future<http.Response> sendOnce() async {
      final client = _buildClient();
      try {
        final request = await buildRequest();
        final streamed = await client.send(request).timeout(_timeout);
        return http.Response.fromStream(streamed);
      } finally {
        client.close();
      }
    }

    var res = await sendOnce();
    if (res.statusCode == 401) {
      final ok = await _refresh();
      if (ok) {
        res = await sendOnce();
      } else {
        await clearTokens();
        throw ApiException('Session expired. Please log in again.', statusCode: 401);
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _decode(res);
    }

    final body = _decode(res);
    final msg = body['error'] ??
        body['detail'] ??
        body['message'] ??
        'Upload failed (${res.statusCode})';
    throw ApiException(msg.toString(), statusCode: res.statusCode);
  }
}
