import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wastmobile/auth/login.dart';
import 'package:wastmobile/auth/customer_signup.dart';
import 'package:wastmobile/auth/collector_signup.dart';
import 'package:wastmobile/home/home_screen.dart';
import 'package:wastmobile/home/request.dart';
import 'package:wastmobile/home/schedule_pickup.dart';
import 'package:wastmobile/home/tracking_page.dart';
import 'package:wastmobile/home/confirm_request.dart';
import 'package:wastmobile/home/pickup_complete.dart';
import 'package:wastmobile/collector/collector_home.dart';
import 'package:wastmobile/admin/admin_home.dart';
import 'package:wastmobile/investor/investor_home.dart';
import 'package:wastmobile/providers/user_provider.dart';
import 'package:wastmobile/services/notification_service.dart';
import 'package:wastmobile/services/sound_service.dart';
import 'package:wastmobile/services/app_config.dart';
import 'package:wastmobile/dev/supabase_auth_dev_page.dart';

/// Centralized color configuration for the application theme.
class _AppColors {
  static const primary = Color(0xFF2E7D32);
  static const background = Color(0xFFF0F7F0);
  static const textSecondary = Color(0xFF757575);
}

Future<void> main() async {
  // Ensure Flutter engine is ready before any async initialization.
  WidgetsFlutterBinding.ensureInitialized();
  // Load .env config (API_HOST, API_PORT, etc.)
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env missing in some build flavors — AppConfig falls back to hardcoded values
  }
  try {
    await NotificationService.initialize();
    await SoundService.initialize();
  } catch (e) {
    debugPrint('Service initialization error: $e');
  }
  // Supabase (Phase 0 of the Django->Supabase migration) — initialized
  // alongside the existing Django-backed ApiService, not replacing it yet.
  // Only used today by the dev-gated SupabaseAuthDevPage.
  try {
    if (AppConfig.supabaseUrl.isNotEmpty && AppConfig.supabasePublishableKey.isNotEmpty) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
      );
    }
  } catch (e) {
    debugPrint('Supabase initialization error: $e');
  }
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppProvider())],
      child: const WasteApp(),
    ),
  );
}

class WasteApp extends StatelessWidget {
  const WasteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WastePick',
      theme: ThemeData(
        primaryColor: _AppColors.primary,
        useMaterial3: true,
        scaffoldBackgroundColor: _AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _AppColors.primary,
          surface: _AppColors.background,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/customer-signup': (context) => const CustomerSignupPage(),
        '/collector-signup': (context) => const CollectorSignupPage(),
        '/home': (context) => const HomeScreen(),
        '/request': (context) => const RequestPickupPage(),
        '/schedule': (context) => const SchedulePickupPage(),
        '/tracking': (context) => const TrackingPage(),
        '/confirm-request': (context) => const ConfirmRequestPage(),
        '/pickup-complete': (context) => const PickupCompletePage(),
        '/collector-home': (context) => const CollectorHomePage(),
        '/admin-home': (context) => const AdminHomePage(),
        '/investor-home': (context) => const InvestorHomePage(),
        '/dev-supabase-auth': (context) => const SupabaseAuthDevPage(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Safe execution of initialization logic after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    try {
      // Use a timeout to prevent the splash screen from hanging if a network call stalls
      await provider.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) return;

      _navigateBasedOnAuth(provider);
    } catch (e) {
      debugPrint('Initialization error: $e');
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _navigateBasedOnAuth(AppProvider provider) {
    if (!provider.isAuthenticated) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    if (provider.isAdmin) {
      Navigator.pushReplacementNamed(context, '/admin-home');
    } else if (provider.isCollector) {
      Navigator.pushReplacementNamed(context, '/collector-home');
    } else if (provider.isInvestor) {
      Navigator.pushReplacementNamed(context, '/investor-home');
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppLogo(),
            SizedBox(height: 40),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: _AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/bolaaba_logo.png',
          width: 120,
          height: 120,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        const Text(
          'Bɔla Aba',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: _AppColors.primary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'On-demand waste collection',
          style: TextStyle(color: _AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}
