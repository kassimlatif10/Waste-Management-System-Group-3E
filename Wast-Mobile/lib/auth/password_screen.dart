import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import 'auth_utils.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

enum PasswordScreenMode { login, setPassword }

/// Password entry for existing users.
/// - [PasswordScreenMode.login] — user already has a password
/// - [PasswordScreenMode.setPassword] — first-time password setup
class PasswordScreen extends StatefulWidget {
  final String phone;
  final PasswordScreenMode mode;
  final String? role;
  /// True for phones resolved via Supabase (currently: customer accounts) —
  /// routes login through SupabaseService instead of the Django endpoint.
  final bool useSupabase;

  const PasswordScreen({
    super.key,
    required this.phone,
    required this.mode,
    this.role,
    this.useSupabase = false,
  });

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _otpSent = false;

  bool get _isSetMode => widget.mode == PasswordScreenMode.setPassword;
  // Supabase accounts (currently collector, occasionally) can reach
  // setPassword mode without ever having had a real password (e.g. they
  // backed out of the post-registration "set your password" dialog) — that
  // needs an OTP-verified reset since there's no old password to check.
  bool get _needsOtp => widget.useSupabase && _isSetMode;

  @override
  void initState() {
    super.initState();
    if (_needsOtp) _sendOtp();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.sendOtp(widget.phone, purpose: 'password_reset');
      setState(() => _otpSent = true);
      if (!mounted) return;
      final devCode = res['otp_code'] as String?;
      if (devCode != null) _snack('Dev mode — your code is $devCode');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final password = _passwordCtrl.text;
    if (password.length < 6) {
      _snack('Password must be at least 6 characters');
      return;
    }
    if (_isSetMode) {
      if (password != _confirmCtrl.text) {
        _snack('Passwords do not match');
        return;
      }
    }
    if (_needsOtp && _otpCtrl.text.trim().isEmpty) {
      _snack('Enter the code we sent you');
      return;
    }

    setState(() => _loading = true);
    try {
      final Map<String, dynamic> data;
      if (widget.useSupabase && _needsOtp) {
        await SupabaseService.resetPassword(widget.phone, _otpCtrl.text.trim(), password);
        data = await SupabaseService.loginWithPhone(widget.phone, password);
      } else if (widget.useSupabase) {
        data = await SupabaseService.loginWithPhone(widget.phone, password);
      } else if (_isSetMode) {
        data = await ApiService.post(
          ApiConstants.setPassword,
          {
            'phone': widget.phone,
            'password': password,
            'confirm_password': _confirmCtrl.text,
          },
          authenticated: false,
        );
      } else {
        data = await ApiService.post(
          ApiConstants.phoneLogin,
          {'phone': widget.phone, 'password': password},
          authenticated: false,
        );
      }
      if (!mounted) return;
      await navigateAfterLogin(context, data);
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (widget.role) {
      'collector' => 'collector',
      'investor' => 'investor',
      'admin' => 'admin',
      _ => 'account',
    };
    final title = _isSetMode ? 'Create your password' : 'Enter your password';
    final subtitle = _isSetMode
        ? 'Your $roleLabel was created by admin. Set a password for ${widget.phone}, then you will be signed in.'
        : 'Welcome back! Enter the password for ${widget.phone}';

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_kLightGreen, _kBg, _kBg],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        size: 20, color: _kTextDark),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            _isSetMode ? Icons.lock_outline : Icons.lock_open_outlined,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _kTextDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: _kTextGray, fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_needsOtp) ...[
                                Text(_otpSent ? 'Code sent to your phone' : 'Sending code…',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: _kTextDark)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _otpCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: _fieldDecoration(hint: '6-digit code'),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _loading ? null : _sendOtp,
                                      child: const Text('Resend'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              const Text('Password',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: _kTextDark)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                onSubmitted: (_) => _isSetMode ? null : _submit(),
                                decoration: _fieldDecoration(
                                  hint: 'At least 6 characters',
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: _kTextGray,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                              ),
                              if (_isSetMode) ...[
                                const SizedBox(height: 16),
                                const Text('Confirm Password',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: _kTextDark)),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _confirmCtrl,
                                  obscureText: _obscureConfirm,
                                  onSubmitted: (_) => _submit(),
                                  decoration: _fieldDecoration(
                                    hint: 'Re-enter password',
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscureConfirm
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: _kTextGray,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(
                                          () => _obscureConfirm = !_obscureConfirm),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _kPrimary,
                                    disabledBackgroundColor:
                                        _kPrimary.withValues(alpha: 0.6),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : Text(
                                          _isSetMode ? 'Set Password & Login' : 'Login',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _kTextGray),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kPrimary, width: 1.5),
      ),
    );
  }
}
