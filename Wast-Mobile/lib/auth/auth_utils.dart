import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';

/// Navigate to the correct home screen after a successful login.
///
/// `data` is either Django's shape ({tokens: {...}, user: {...}} — tokens
/// saved into ApiService's storage) or a Supabase login's ({user: {...}},
/// no tokens key — supabase_flutter already persisted its own session).
Future<void> navigateAfterLogin(BuildContext context, Map<String, dynamic> data) async {
  final tokens = data['tokens'] as Map<String, dynamic>?;
  if (tokens != null) {
    await ApiService.saveTokens(
      access: tokens['access'] as String,
      refresh: tokens['refresh'] as String,
    );
  }
  if (!context.mounted) return;

  final provider = Provider.of<AppProvider>(context, listen: false);
  provider.setCurrentUser(Map<String, dynamic>.from(data['user'] as Map));

  final role = data['user']['role'] as String? ?? 'customer';
  String route;
  switch (role) {
    case 'admin':
    case 'super_admin':
    case 'staff':
      route = '/admin-home';
      break;
    case 'collector':
      route = '/collector-home';
      break;
    case 'investor':
      route = '/investor-home';
      break;
    default:
      route = '/home';
  }
  Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
}
