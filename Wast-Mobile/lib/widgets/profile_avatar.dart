import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../services/app_config.dart';
import 'file_image.dart';

/// Loads images from the production API host, trusting its TLS certificate.
class SslImageLoader {
  SslImageLoader._();

  static final Map<String, Uint8List> _cache = {};

  static http.Client _client() {
    final apiHost = Uri.tryParse(AppConfig.baseUrl)?.host ?? '';
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        if (apiHost.isEmpty) return false;
        return host == apiHost;
      };
    return IOClient(inner);
  }

  static Future<Uint8List?> loadBytes(String url) async {
    final key = url.split('?').first;
    if (_cache.containsKey(key)) return _cache[key];

    final client = _client();
    try {
      final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _cache[key] = response.bodyBytes;
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('SslImageLoader failed for $url: $e');
    } finally {
      client.close();
    }
    return null;
  }

  static void bustCache(String url) {
    _cache.remove(url.split('?').first);
  }
}

class SslNetworkImageProvider extends ImageProvider<SslNetworkImageProvider> {
  final String url;

  const SslNetworkImageProvider(this.url);

  @override
  Future<SslNetworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    SslNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key.url, decode),
      scale: 1.0,
    );
  }

  static Future<ui.Codec> _loadCodec(String url, ImageDecoderCallback decode) async {
    final bytes = await SslImageLoader.loadBytes(url);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Could not load image: $url');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is SslNetworkImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Profile photo that loads correctly on production HTTPS (self-signed cert).
class ProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final File? localFile;
  final double radius;
  final String fallbackInitial;
  final Color backgroundColor;
  final Color foregroundColor;

  const ProfileAvatar({
    super.key,
    this.imageUrl,
    this.localFile,
    required this.radius,
    required this.fallbackInitial,
    this.backgroundColor = const Color(0x332E7D32),
    this.foregroundColor = const Color(0xFF2E7D32),
  });

  @override
  Widget build(BuildContext context) {
    if (localFile != null) {
      return FileCircleAvatar(
        file: localFile,
        radius: radius,
        backgroundColor: backgroundColor,
      );
    }

    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: SslNetworkImageProvider(url),
        onBackgroundImageError: (_, _) {},
        child: null,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Text(
        fallbackInitial.isNotEmpty ? fallbackInitial[0].toUpperCase() : 'U',
        style: TextStyle(
          color: foregroundColor,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

ImageProvider? profileImageProvider(String? imageUrl) {
  final url = imageUrl?.trim();
  if (url == null || url.isEmpty) return null;
  return SslNetworkImageProvider(url);
}
