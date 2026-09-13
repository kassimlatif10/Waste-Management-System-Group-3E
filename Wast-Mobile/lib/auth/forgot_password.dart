import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';

const _kBg      = Color(0xFFF0F7F0);
const _kPrimary = Color(0xFF2E7D32);
const _kCard    = Colors.white;
const _kDark    = Color(0xFF1A1A1A);
const _kGray    = Color(0xFF757575);

/// Three-step password reset: enter phone → enter OTP → set new password.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  // step 0 = phone, step 1 = otp, step 2 = new password
  int _step = 0;
  bool _loading = false;
  bool _useSupabase = false;

  final _phoneCtrl   = TextEditingController();
  final _otpCtrl     = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass    = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : _kPrimary,
    ));
  }

  // Step 0 → send OTP
  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) { _snack('Enter your phone number', error: true); return; }
    setState(() => _loading = true);
    try {
      // Check Supabase first (customer/collector accounts are Supabase-
      // native now); fall back to Django unchanged for anyone else.
      bool sentViaSupabase = false;
      try {
        final sb = await SupabaseService.checkPhoneExists(phone);
        if (sb['exists'] == true) {
          await SupabaseService.sendOtp(phone, purpose: 'password_reset');
          sentViaSupabase = true;
        }
      } catch (_) {}

      if (sentViaSupabase) {
        setState(() { _step = 1; _loading = false; _useSupabase = true; });
        return;
      }

      await ApiService.post(
        ApiConstants.forgotPassword,
        {'phone': phone},
        authenticated: false,
      );
      setState(() { _step = 1; _loading = false; _useSupabase = false; });
    } on ApiException catch (e) {
      _snack(e.message, error: true);
      setState(() => _loading = false);
    } catch (_) {
      _snack('Unable to connect. Check your connection.', error: true);
      setState(() => _loading = false);
    }
  }

  // Step 1 → verify OTP and move to set-password
  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) { _snack('Enter the 4-digit OTP', error: true); return; }
    // We don't call the API here — the OTP is validated server-side with the password in step 2.
    setState(() => _step = 2);
  }

  // Step 2 → reset password
  Future<void> _resetPassword() async {
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.length < 6) { _snack('Password must be at least 6 characters', error: true); return; }
    if (pass != confirm)  { _snack('Passwords do not match', error: true); return; }
    setState(() => _loading = true);
    try {
      if (_useSupabase) {
        await SupabaseService.resetPassword(_phoneCtrl.text.trim(), _otpCtrl.text.trim(), pass);
      } else {
        await ApiService.post(
          ApiConstants.resetPassword,
          {
            'phone':            _phoneCtrl.text.trim(),
            'otp_code':         _otpCtrl.text.trim(),
            'new_password':     pass,
            'confirm_password': confirm,
          },
          authenticated: false,
        );
      }
      if (!mounted) return;
      _snack('Password reset! Please log in with your new password.');
      Navigator.pop(context);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
      // If OTP was wrong/expired, send them back to step 1
      if (e.message.toLowerCase().contains('otp') ||
          e.message.toLowerCase().contains('expired')) {
        setState(() { _step = 1; _otpCtrl.clear(); });
      }
      setState(() => _loading = false);
    } catch (e) {
      final msg = _useSupabase ? e.toString().replaceFirst('Exception: ', '') : 'Unable to connect. Check your connection.';
      _snack(msg, error: true);
      if (_useSupabase && (msg.toLowerCase().contains('otp') || msg.toLowerCase().contains('expired'))) {
        setState(() { _step = 1; _otpCtrl.clear(); });
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: BackButton(color: _kPrimary),
        title: const Text(
          'Reset Password',
          style: TextStyle(color: _kDark, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIndicator(current: _step),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _step == 0
                    ? _PhoneStep(
                        key: const ValueKey(0),
                        ctrl: _phoneCtrl,
                        loading: _loading,
                        onSubmit: _sendOtp,
                      )
                    : _step == 1
                        ? _OtpStep(
                            key: const ValueKey(1),
                            phone: _phoneCtrl.text.trim(),
                            ctrl: _otpCtrl,
                            loading: _loading,
                            onSubmit: _verifyOtp,
                            onResend: () {
                              _otpCtrl.clear();
                              setState(() => _step = 0);
                            },
                          )
                        : _NewPasswordStep(
                            key: const ValueKey(2),
                            passCtrl: _passCtrl,
                            confirmCtrl: _confirmCtrl,
                            obscurePass: _obscurePass,
                            obscureConfirm: _obscureConfirm,
                            onTogglePass: () => setState(() => _obscurePass = !_obscurePass),
                            onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            loading: _loading,
                            onSubmit: _resetPassword,
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final labels = ['Phone', 'OTP', 'New Password'];
    return Row(
      children: List.generate(labels.length, (i) {
        final done   = i < current;
        final active = i == current;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 4,
                      decoration: BoxDecoration(
                        color: done || active ? _kPrimary : const Color(0xFFDDDDDD),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: active ? _kPrimary : done ? _kPrimary : _kGray,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < labels.length - 1) const SizedBox(width: 8),
            ],
          ),
        );
      }),
    );
  }
}

// ── Step 0: Phone ─────────────────────────────────────────────────────────────

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    super.key,
    required this.ctrl,
    required this.loading,
    required this.onSubmit,
  });
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter your phone number',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 6),
          const Text('We will send a one-time code to verify it\'s you.',
              style: TextStyle(color: _kGray, fontSize: 14)),
          const SizedBox(height: 24),
          _FieldLabel('Phone Number'),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.phone,
            onSubmitted: (_) => onSubmit(),
            decoration: _fieldDeco(hint: '+233 24 000 0000', icon: Icons.phone_outlined),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Send OTP', loading: loading, onTap: onSubmit),
        ],
      ),
    );
  }
}

// ── Step 1: OTP ───────────────────────────────────────────────────────────────

class _OtpStep extends StatelessWidget {
  const _OtpStep({
    super.key,
    required this.phone,
    required this.ctrl,
    required this.loading,
    required this.onSubmit,
    required this.onResend,
  });
  final String phone;
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter the OTP',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 6),
          Text('A 4-digit code was sent to $phone',
              style: const TextStyle(color: _kGray, fontSize: 14)),
          const SizedBox(height: 24),
          _FieldLabel('OTP Code'),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            onSubmitted: (_) => onSubmit(),
            decoration: _fieldDeco(hint: '----', icon: Icons.lock_outline),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Verify OTP', loading: loading, onTap: onSubmit),
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              onTap: onResend,
              child: const Text(
                'Didn\'t receive it? Re-send',
                style: TextStyle(color: _kPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 2: New Password ──────────────────────────────────────────────────────

class _NewPasswordStep extends StatelessWidget {
  const _NewPasswordStep({
    super.key,
    required this.passCtrl,
    required this.confirmCtrl,
    required this.obscurePass,
    required this.obscureConfirm,
    required this.onTogglePass,
    required this.onToggleConfirm,
    required this.loading,
    required this.onSubmit,
  });
  final TextEditingController passCtrl;
  final TextEditingController confirmCtrl;
  final bool obscurePass;
  final bool obscureConfirm;
  final VoidCallback onTogglePass;
  final VoidCallback onToggleConfirm;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Set a new password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 6),
          const Text('Choose a password at least 6 characters long.',
              style: TextStyle(color: _kGray, fontSize: 14)),
          const SizedBox(height: 24),
          _FieldLabel('New Password'),
          const SizedBox(height: 8),
          TextField(
            controller: passCtrl,
            obscureText: obscurePass,
            decoration: _fieldDeco(
              hint: 'Enter new password',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility,
                    color: _kGray, size: 20),
                onPressed: onTogglePass,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel('Confirm Password'),
          const SizedBox(height: 8),
          TextField(
            controller: confirmCtrl,
            obscureText: obscureConfirm,
            onSubmitted: (_) => onSubmit(),
            decoration: _fieldDeco(
              hint: 'Repeat new password',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    color: _kGray, size: 20),
                onPressed: onToggleConfirm,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Reset Password', loading: loading, onTap: onSubmit),
        ],
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kDark));
  }
}

InputDecoration _fieldDeco({required String hint, required IconData icon, Widget? suffixIcon}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _kGray),
    prefixIcon: Icon(icon, size: 20, color: _kGray),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF5F5F5),
    contentPadding: const EdgeInsets.symmetric(vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.loading, required this.onTap});
  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimary,
          disabledBackgroundColor: _kPrimary.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                height: 22, width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
