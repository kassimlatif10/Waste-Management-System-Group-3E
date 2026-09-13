import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();

  /// Call once from main() before runApp:  await AppConfig.load();
  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
  }

  // ── Read from .env (with fallback defaults) ───────────────────────────────
  static String get googleMapsApiKey =>
      dotenv.get('GOOGLE_MAPS_KEY', fallback: 'AIzaSyAXsy2RejZOhEsDPBhEGO0tyvHH-W_vjsE');

  // ── Supabase (Phase 0+ of the Django->Supabase migration) ─────────────────
  static String get supabaseUrl => dotenv.get('SUPABASE_URL', fallback: '');
  static String get supabasePublishableKey => dotenv.get('SUPABASE_PUBLISHABLE_KEY', fallback: '');

  // ── Base URL — supports both http://host:port and https://host formats ────
  static String get baseUrl {
    // If API_BASE_URL is set directly, use it as-is
    final direct = dotenv.maybeGet('API_BASE_URL');
    if (direct != null && direct.isNotEmpty) return direct;
    // Otherwise compose from host + port
    final host = dotenv.get('API_HOST', fallback: '54.172.240.192');
    final port = dotenv.get('API_PORT', fallback: '443');
    final scheme = port == '443' ? 'https' : 'http';
    return port == '443' || port == '80'
        ? '$scheme://$host'
        : '$scheme://$host:$port';
  }

  static String get wsUrl {
    final base = baseUrl;
    // Convert https:// → wss:// and http:// → ws://
    return base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
  }
}
