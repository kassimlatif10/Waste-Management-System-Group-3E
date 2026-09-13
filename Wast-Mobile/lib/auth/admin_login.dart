import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import 'auth_utils.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and password')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      // Admin accounts are Supabase-native now — try there first (a real
      // "wrong password" error from Supabase should still be shown, not
      // silently swallowed into a Django fallback attempt).
      try {
        final sb = await SupabaseService.checkEmailExists(email);
        if (sb['exists'] != true) throw Exception('not in supabase');
      } catch (_) {
        // Not a Supabase account (or the probe itself failed) — fall
        // through to Django below, unchanged.
        final data = await ApiService.post(
          ApiConstants.adminLogin,
          {'email': email, 'password': password},
          authenticated: false,
        );
        if (!mounted) return;
        await navigateAfterLogin(context, data);
        return;
      }
      final data = await SupabaseService.loginAdminWithEmail(email, password);
      if (!mounted) return;
      await navigateAfterLogin(context, {'user': data});
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kTextDark),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Text('Admin Login',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _kTextDark)),
            const SizedBox(height: 6),
            const Text('Sign in with your admin email and password',
                style: TextStyle(color: _kTextGray, fontSize: 14)),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kTextDark)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: _kTextDark),
                    decoration: InputDecoration(
                      hintText: 'admin@wastepick.com',
                      hintStyle: const TextStyle(color: _kTextGray),
                      prefixIcon: const Icon(Icons.email_outlined, size: 20, color: _kTextGray),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kTextDark)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    onSubmitted: (_) => _login(),
                    style: const TextStyle(color: _kTextDark),
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      hintStyle: const TextStyle(color: _kTextGray),
                      prefixIcon: const Icon(Icons.lock_outline, size: 20, color: _kTextGray),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _kTextGray),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        disabledBackgroundColor: _kPrimary.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Sign In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
