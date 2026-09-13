import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    final oldPass = _oldCtrl.text;
    final newPass = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (oldPass.isEmpty) { _snack('Enter your current password'); return; }
    if (newPass.length < 6) { _snack('New password must be at least 6 characters'); return; }
    if (newPass != confirm) { _snack('New passwords do not match'); return; }

    setState(() => _loading = true);
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.changePassword(oldPass, newPass);
      } else {
        await ApiService.post(ApiConstants.changePassword, {
          'old_password': oldPass,
          'new_password': newPass,
          'confirm_password': confirm,
        });
      }
      if (!mounted) return;
      _snack('Password changed successfully');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } on AuthException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      _snack('Unable to connect. Check your connection.');
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
        title: const Text('Change Password',
            style: TextStyle(color: _kTextDark, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Current Password', _oldCtrl, _obscureOld,
                () => setState(() => _obscureOld = !_obscureOld)),
            const SizedBox(height: 16),
            _field('New Password', _newCtrl, _obscureNew,
                () => setState(() => _obscureNew = !_obscureNew)),
            const SizedBox(height: 16),
            _field('Confirm New Password', _confirmCtrl, _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm)),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  disabledBackgroundColor: _kPrimary.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(height: 22, width: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Update Password',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, bool obscure, VoidCallback toggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kTextDark)),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          obscureText: obscure,
          style: const TextStyle(color: _kTextDark),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _kTextGray),
              onPressed: toggle,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          ),
        ),
      ],
    );
  }
}
