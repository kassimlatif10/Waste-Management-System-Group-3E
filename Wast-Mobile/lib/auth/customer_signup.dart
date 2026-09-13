import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

/// Customer sign-up flow:
/// Step 1 — enter phone → check if registered
/// Step 2 — set password → create account → auto-login
class CustomerSignupPage extends StatefulWidget {
  /// When provided (from OTP new-user flow), skip the phone step and go
  /// straight to the password step with the number pre-filled.
  final String? initialPhone;
  const CustomerSignupPage({super.key, this.initialPhone});

  @override
  State<CustomerSignupPage> createState() => _CustomerSignupPageState();
}

enum _Step { phone, password }

class _CustomerSignupPageState extends State<CustomerSignupPage> {
  _Step _step = _Step.phone;
  String _phone = '';

  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null && widget.initialPhone!.isNotEmpty) {
      _phone = widget.initialPhone!;
      _phoneCtrl.text = widget.initialPhone!;
      _step = _Step.password;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPhone() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showSnack('Please enter your phone number');
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Supabase is authoritative for the duplicate-phone check now (new
      // signups land there) — check it first, and only fall back to
      // Django if Supabase doesn't know the phone either (still catches
      // numbers already registered as a Django-only collector/admin/
      // investor). Supabase itself also enforces phone uniqueness at the
      // database level, so this is a UX nicety, not the only safety net.
      try {
        final sb = await SupabaseService.checkPhoneExists(phone);
        if (sb['exists'] == true) {
          if (!mounted) return;
          _showSnack('Phone already registered. Please login instead.');
          return;
        }
      } catch (_) {
        // Supabase probe failing must never block signup — fall through.
      }

      final data = await ApiService.post(
        ApiConstants.checkPhone,
        {'phone': phone},
        authenticated: false,
      );
      if (!mounted) return;
      if (data['exists'] == true) {
        _showSnack('Phone already registered. Please login instead.');
      } else {
        setState(() {
          _phone = phone;
          _step = _Step.password;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (_) {
      // Django unreachable AND Supabase said this phone doesn't exist —
      // proceed anyway, since account creation itself is Supabase-native
      // and doesn't need Django at all.
      if (!mounted) return;
      setState(() {
        _phone = phone;
        _step = _Step.password;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createAccount() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      _showSnack('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Customer accounts are created directly in Supabase now (see the
      // Django->Supabase migration) — no ApiService/Django involved for
      // new customer signups. supabase_flutter persists its own session,
      // so there's no token-saving step here.
      final data = await SupabaseService.registerCustomer(phone: _phone, password: password);
      if (!mounted) return;

      final provider = Provider.of<AppProvider>(context, listen: false);
      provider.setCurrentUser(Map<String, dynamic>.from(data['user'] as Map));

      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
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
                stops: [0.0, 0.40, 1.0],
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
                    onPressed: () {
                      if (_step == _Step.password) {
                        setState(() => _step = _Step.phone);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _step == _Step.phone
                          ? _buildPhoneStep()
                          : _buildPasswordStep(),
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

  Widget _buildPhoneStep() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Create account',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: _kTextDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter your phone number to get started',
          style: TextStyle(color: _kTextGray, fontSize: 14),
        ),
        const SizedBox(height: 28),
        _card(
          children: [
            _label('Phone Number'),
            const SizedBox(height: 8),
            _field(
              controller: _phoneCtrl,
              hint: '+233 24 000 0000',
              icon: Icons.phone_android_outlined,
              type: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            const Text(
              'We\'ll check if this number is already registered',
              style: TextStyle(color: _kTextGray, fontSize: 12),
            ),
            const SizedBox(height: 28),
            _primaryButton(
              label: 'Continue',
              onPressed: _isLoading ? null : _checkPhone,
              isLoading: _isLoading,
            ),
            const SizedBox(height: 20),
            _centeredLink(
              prefix: 'Already have an account? ',
              linkText: 'Sign in',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      key: const ValueKey('password'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Set your password',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: _kTextDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Creating account for $_phone',
          style: const TextStyle(color: _kTextGray, fontSize: 14),
        ),
        const SizedBox(height: 28),
        _card(
          children: [
            _label('Password'),
            const SizedBox(height: 8),
            _passwordField(
              controller: _passwordCtrl,
              hint: 'Min. 6 characters',
              obscure: _obscurePassword,
              onToggle: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            const SizedBox(height: 16),
            _label('Confirm Password'),
            const SizedBox(height: 8),
            _passwordField(
              controller: _confirmCtrl,
              hint: 'Re-enter your password',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            const SizedBox(height: 28),
            _primaryButton(
              label: 'Create Account',
              onPressed: _isLoading ? null : _createAccount,
              isLoading: _isLoading,
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _card({required List<Widget> children}) => Container(
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
          children: children,
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: _kTextDark,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
  }) =>
      TextField(
        controller: controller,
        keyboardType: type,
        style: const TextStyle(color: _kTextDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _kTextGray),
          prefixIcon: Icon(icon, size: 20, color: _kTextGray),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
        ),
      );

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: _kTextDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _kTextGray),
          prefixIcon:
              const Icon(Icons.lock_outline, size: 20, color: _kTextGray),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              size: 20,
              color: _kTextGray,
            ),
            onPressed: onToggle,
          ),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
        ),
      );

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isLoading,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            disabledBackgroundColor: _kPrimary.withValues(alpha: 0.6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
        ),
      );

  Widget _centeredLink({
    required String prefix,
    required String linkText,
    required VoidCallback onTap,
  }) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(prefix, style: const TextStyle(color: _kTextGray, fontSize: 14)),
          GestureDetector(
            onTap: onTap,
            child: Text(
              linkText,
              style: const TextStyle(
                color: _kPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      );
}
