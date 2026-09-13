import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import 'customer_signup.dart';
import 'password_screen.dart';
import 'forgot_password.dart';
import 'admin_login.dart';

const Color _kBg         = Color(0xFFF0F7F0);
const Color _kPrimary     = Color(0xFF2E7D32);
const Color _kCard        = Colors.white;
const Color _kLightGreen  = Color(0xFFE8F5E9);
const Color _kTextDark    = Color(0xFF1A1A1A);
const Color _kTextGray    = Color(0xFF757575);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      // Check Supabase first for any role — a phone Supabase doesn't know
      // about falls through to the unchanged Django check below, which
      // still covers accounts not yet migrated during the staged cutover.
      try {
        final sb = await SupabaseService.checkPhoneExists(phone);
        final sbRole = sb['role'] as String?;
        if (sb['exists'] == true && sbRole != null) {
          final hasPassword = sb['has_password'] == true;
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PasswordScreen(
                phone: phone,
                role: sbRole,
                mode: hasPassword ? PasswordScreenMode.login : PasswordScreenMode.setPassword,
                useSupabase: true,
              ),
            ),
          );
          return;
        }
      } catch (_) {
        // Supabase probe failing must never block the existing Django flow.
      }

      Map<String, dynamic>? data;
      try {
        data = await ApiService.post(
          ApiConstants.checkPhone,
          {'phone': phone},
          authenticated: false,
        );
      } catch (_) {
        // Django unreachable AND Supabase already said this phone doesn't
        // exist — treat it as a new number rather than blocking login
        // entirely, since account creation itself is Supabase-native.
      }
      if (!mounted) return;

      final exists = data?['exists'] == true;
      if (!exists) {
        // New user — go to sign up with phone pre-filled
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerSignupPage(initialPhone: phone),
          ),
        );
        return;
      }

      final hasPassword = data!['has_password'] == true;
      final role = data['role'] as String? ?? 'customer';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PasswordScreen(
            phone: phone,
            role: role,
            mode: hasPassword
                ? PasswordScreenMode.login
                : PasswordScreenMode.setPassword,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to connect. Check your connection.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 52),

                  Column(
                    children: [
                      Image.asset(
                        'assets/bolaaba_logo.png',
                        width: 110,
                        height: 110,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Bɔla Aba',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: _kPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'On-demand waste collection',
                        style: TextStyle(color: _kTextGray, fontSize: 14),
                      ),
                    ],
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
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kTextDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter your phone number to continue',
                          style: TextStyle(color: _kTextGray, fontSize: 14),
                        ),
                        const SizedBox(height: 24),

                        const Text('Phone Number',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: _kTextDark)),
                        const SizedBox(height: 8),

                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: _kTextDark),
                          onSubmitted: (_) => _continue(),
                          decoration: InputDecoration(
                            hintText: '+233 24 000 0000',
                            hintStyle: const TextStyle(color: _kTextGray),
                            prefixIcon: const Icon(Icons.phone_outlined,
                                size: 20, color: _kTextGray),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE0E0E0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: _kPrimary, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'First-time users will create a password, then sign in',
                          style: TextStyle(color: _kTextGray, fontSize: 12),
                        ),

                        const SizedBox(height: 28),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _continue,
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
                                    height: 22, width: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordPage()),
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: _kPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('New customer? ',
                                style: TextStyle(
                                    color: _kTextGray, fontSize: 14)),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(
                                  context, '/customer-signup'),
                              child: const Text(
                                'Sign up',
                                style: TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, '/collector-signup'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: _kPrimary.withValues(alpha: 0.35)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: _kLightGreen,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.local_shipping_outlined,
                                color: _kPrimary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Want to collect waste?',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: _kTextDark)),
                                SizedBox(height: 2),
                                Text('Register as a Collector',
                                    style: TextStyle(
                                        color: _kTextGray, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              size: 14, color: _kPrimary),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminLoginPage()),
                      ),
                      child: const Text(
                        'Admin login',
                        style: TextStyle(
                          color: _kTextGray,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
