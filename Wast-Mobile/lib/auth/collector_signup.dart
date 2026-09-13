import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import '../utils/ghana_card_verifier.dart';
import '../widgets/file_image.dart';
import 'auth_utils.dart';

const Color _kBg         = Color(0xFFF0F7F0);
const Color _kPrimary     = Color(0xFF2E7D32);
const Color _kCard        = Colors.white;
const Color _kLightGreen  = Color(0xFFE8F5E9);
const Color _kTextDark    = Color(0xFF1A1A1A);
const Color _kTextGray    = Color(0xFF757575);

enum _Step { personal, document, vehicle, success }
enum _DocType { ghanaCard, license }

final RegExp _namePattern = RegExp(r"^[A-Za-z]+(?:['\-][A-Za-z]+)*(?:\s+[A-Za-z]+(?:['\-][A-Za-z]+)*)+$");
final RegExp _ghanaPhonePattern = RegExp(r'^(0[2-9]\d{8}|\+233[2-9]\d{8})$');

class CollectorSignupPage extends StatefulWidget {
  const CollectorSignupPage({super.key});

  @override
  State<CollectorSignupPage> createState() => _CollectorSignupPageState();
}

class _CollectorSignupPageState extends State<CollectorSignupPage> {
  _Step _step = _Step.personal;

  // Personal
  final _nameCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();

  // Ghana Card
  final _ghanaCardNumberCtrl = TextEditingController();
  File? _ghanaFront;
  File? _ghanaBack;

  // License
  final _licenseNumberCtrl = TextEditingController();
  File? _licenseFront;
  File? _licenseBack;

  // Vehicle
  String _vehicleType = 'Pickup Truck';
  File? _vehiclePhoto;

  static const _vehicleTypes = [
    'Pickup Truck', 'Tricycle', 'Motorcycle', 'Van',
    'Mini Van', 'Mini Truck', 'Large Van', 'Tipper Truck',
  ];

  _DocType? _docType;
  bool _loading = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _ghanaCardNumberCtrl.dispose();
    _licenseNumberCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<File?> _pickPhoto(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    return x != null ? File(x.path) : null;
  }

  Future<void> _choosePhoto(void Function(File?) onPicked) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (src == null || !mounted) return;
    final f = await _pickPhoto(src);
    if (f != null && mounted) setState(() => onPicked(f));
  }

  // ── Step advance / back ──────────────────────────────────────────────────

  void _nextFromPersonal() {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim().replaceAll(' ', '');
    if (name.isEmpty) { _snack('Enter your full name'); return; }
    if (!_namePattern.hasMatch(name)) {
      _snack('Enter your full name (first and last name, letters only)');
      return;
    }
    if (phone.isEmpty) { _snack('Enter your phone number'); return; }
    if (!_ghanaPhonePattern.hasMatch(phone)) {
      _snack('Enter a valid Ghana phone number, e.g. 024 000 0000');
      return;
    }
    setState(() => _step = _Step.document);
  }

  Future<void> _nextFromDocument() async {
    if (_docType == null) { _snack('Choose Ghana Card or Driver\'s License'); return; }

    if (_docType == _DocType.ghanaCard) {
      final number = _ghanaCardNumberCtrl.text.trim();
      if (number.isEmpty) { _snack('Enter your Ghana card number'); return; }
      if (!isValidGhanaCardFormat(number)) {
        _snack('Enter a valid Ghana Card number, e.g. GHA-123456789-0');
        return;
      }
      if (_ghanaFront == null) { _snack('Upload Ghana card front photo'); return; }
      if (_ghanaBack == null) { _snack('Upload Ghana card back photo'); return; }

      // Full-screen scan: shows the uploaded card, scans it, and blocks
      // progression until the number is confirmed to match the photo.
      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => _GhanaCardScanScreen(photo: _ghanaFront!, typedNumber: number),
        ),
      );
      if (verified != true) return; // user backed out or it failed — stay put
    } else {
      final number = _licenseNumberCtrl.text.trim();
      if (number.isEmpty) { _snack('Enter your license number'); return; }
      if (_licenseFront == null) { _snack('Upload driver license front photo'); return; }
      if (_licenseBack == null) { _snack('Upload driver license back photo'); return; }
    }

    if (!mounted) return;
    setState(() => _step = _Step.vehicle);
  }

  void _handleBack() {
    switch (_step) {
      case _Step.personal:    Navigator.pop(context);
      case _Step.document:    setState(() => _step = _Step.personal);
      case _Step.vehicle:     setState(() => _step = _Step.document);
      case _Step.success:     break;
    }
  }

  // ── Final submit ──────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_docType == null) { _snack('Choose Ghana Card or Driver\'s License'); return; }
    if (_vehiclePhoto == null) { _snack('Upload a vehicle photo'); return; }

    final phone = _phoneCtrl.text.trim();

    // Check if phone already exists
    setState(() => _loading = true);
    try {
      // Collector accounts are Supabase-native going forward — check there
      // first, same fallback-to-Django pattern used for customers.
      try {
        final sb = await SupabaseService.checkPhoneExists(phone);
        if (sb['exists'] == true) {
          if (sb['role'] != 'collector') {
            _snack('This number belongs to a ${sb['role']} account.');
            return;
          }
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _PasswordLoginScreen(
                phone: phone,
                hasPassword: sb['has_password'] == true,
                useSupabase: true,
              ),
            ),
          );
          return;
        }
      } catch (_) {
        // Supabase probe failing must never block the existing Django flow.
      }

      try {
        final check = await ApiService.post(
          ApiConstants.checkPhone,
          {'phone': phone},
          authenticated: false,
        );
        if (!mounted) return;

        if (check['exists'] == true) {
          final role = check['role'] as String? ?? '';
          if (role == 'collector') {
            final hasPassword = check['has_password'] == true;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PasswordLoginScreen(phone: phone, hasPassword: hasPassword),
              ),
            );
            return;
          }
          _snack('This number belongs to a ${role.isEmpty ? 'another' : role} account.');
          return;
        }
      } catch (_) {
        // Django unreachable AND Supabase already said this phone doesn't
        // exist — proceed anyway, since collector registration itself is
        // Supabase-native and doesn't need Django at all.
      }

      // KYC doc bytes, keyed by document_type (matches the storage bucket
      // convention used by SupabaseService.registerCollector).
      final kycFiles = <String, Uint8List>{
        'vehicle_photo': await readFileBytes(_vehiclePhoto!),
      };
      if (_docType == _DocType.ghanaCard) {
        kycFiles['ghana_card_front'] = await readFileBytes(_ghanaFront!);
        kycFiles['ghana_card_back'] = await readFileBytes(_ghanaBack!);
      } else {
        kycFiles['license_front'] = await readFileBytes(_licenseFront!);
        kycFiles['license_back'] = await readFileBytes(_licenseBack!);
      }

      // Supabase Auth requires a password at signUp (unlike Django, which
      // defers it) — generate a throwaway one now, then immediately prompt
      // to set the real one while the fresh session is still valid.
      final tempPassword = _randomPassword();
      final regData = await SupabaseService.registerCollector(
        phone: phone,
        password: tempPassword,
        vehicleType: _vehicleType,
        firstName: _nameCtrl.text.trim(),
        ghanaCardNumber: _docType == _DocType.ghanaCard ? _ghanaCardNumberCtrl.text.trim() : null,
        licenseNumber: _docType == _DocType.license ? _licenseNumberCtrl.text.trim() : null,
        kycFiles: kycFiles,
      );
      if (!mounted) return;

      final provider = Provider.of<AppProvider>(context, listen: false);
      provider.setCurrentUser(Map<String, dynamic>.from(regData['user'] as Map));

      setState(() => _step = _Step.success);
      if (!mounted) return;
      await _promptSetRealPassword();
    } on ApiException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _randomPassword() {
    final rnd = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    return List.generate(20, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _promptSetRealPassword() async {
    final passCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool submitting = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Set your password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Choose a password so you can log back in next time.'),
                const SizedBox(height: 16),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (min. 6 characters)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (passCtrl.text.length < 6) {
                          setDialogState(() => error = 'Password must be at least 6 characters');
                          return;
                        }
                        if (passCtrl.text != confCtrl.text) {
                          setDialogState(() => error = 'Passwords do not match');
                          return;
                        }
                        setDialogState(() => submitting = true);
                        try {
                          await SupabaseService.setInitialPassword(passCtrl.text);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                        } catch (e) {
                          setDialogState(() {
                            submitting = false;
                            error = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

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
                if (_step != _Step.success)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: _kTextDark),
                      onPressed: _handleBack,
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _buildStep(),
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

  Widget _buildStep() {
    switch (_step) {
      case _Step.personal: return _buildPersonal();
      case _Step.document: return _buildDocument();
      case _Step.vehicle:  return _buildVehicle();
      case _Step.success:  return _buildSuccess();
    }
  }

  // ── Step 1 – Personal Info ───────────────────────────────────────────────

  Widget _buildPersonal() {
    return Column(
      key: const ValueKey('personal'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _stepBar(1, 3),
        const SizedBox(height: 16),
        const Text('Register as Collector',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _kTextDark, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        const Text('Step 1 of 3 — Personal Information',
            style: TextStyle(color: _kTextGray, fontSize: 14)),
        const SizedBox(height: 24),
        _card(children: [
          _label('Full Name'),
          const SizedBox(height: 8),
          _field(_nameCtrl, 'e.g. Kofi Mensah', Icons.person_outline, TextInputType.name),
          const SizedBox(height: 16),
          _label('Phone Number'),
          const SizedBox(height: 8),
          _field(_phoneCtrl, '+233 24 000 0000', Icons.phone_android_outlined, TextInputType.phone),
          const SizedBox(height: 10),
          const Text(
            'Your application will be reviewed by an admin before activation.',
            style: TextStyle(color: _kTextGray, fontSize: 12),
          ),
          const SizedBox(height: 28),
          _btn('Next', _nextFromPersonal, false),
          const SizedBox(height: 12),
          _link('Already registered? ', 'Login',
              () => Navigator.pushReplacementNamed(context, '/login')),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Step 2 – Identity document (Ghana Card OR Driver's License) ──────────

  Widget _buildDocument() {
    return Column(
      key: const ValueKey('document'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _stepBar(2, 3),
        const SizedBox(height: 16),
        const Text('Identity Verification',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _kTextDark, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        const Text('Step 2 of 3 — Choose one document to verify your identity',
            style: TextStyle(color: _kTextGray, fontSize: 14)),
        const SizedBox(height: 24),
        _card(children: [
          _label('Document Type'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _docTypeChip('Ghana Card', Icons.credit_card_outlined, _DocType.ghanaCard)),
            const SizedBox(width: 12),
            Expanded(child: _docTypeChip('Driver\'s License', Icons.badge_outlined, _DocType.license)),
          ]),
          if (_docType == _DocType.ghanaCard) ...[
            const SizedBox(height: 20),
            _label('Ghana Card Number'),
            const SizedBox(height: 8),
            _field(_ghanaCardNumberCtrl, 'GHA-123456789-0', Icons.credit_card_outlined, TextInputType.text),
            const SizedBox(height: 20),
            _label('Ghana Card Photo — Front & Back'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _photoSlot(_ghanaFront, 'Front', () => _choosePhoto((f) => _ghanaFront = f))),
              const SizedBox(width: 12),
              Expanded(child: _photoSlot(_ghanaBack, 'Back', () => _choosePhoto((f) => _ghanaBack = f))),
            ]),
            const SizedBox(height: 8),
            const Text(
              'We scan the front photo to confirm it matches the number above.',
              style: TextStyle(color: _kTextGray, fontSize: 12),
            ),
          ] else if (_docType == _DocType.license) ...[
            const SizedBox(height: 20),
            _label('License Number'),
            const SizedBox(height: 8),
            _field(_licenseNumberCtrl, 'e.g. B1234567', Icons.badge_outlined, TextInputType.text),
            const SizedBox(height: 20),
            _label('Driver License Photo — Front & Back'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _photoSlot(_licenseFront, 'Front', () => _choosePhoto((f) => _licenseFront = f))),
              const SizedBox(width: 12),
              Expanded(child: _photoSlot(_licenseBack, 'Back', () => _choosePhoto((f) => _licenseBack = f))),
            ]),
          ],
          const SizedBox(height: 28),
          _btn('Next', _nextFromDocument, false),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _docTypeChip(String label, IconData icon, _DocType type) {
    final selected = _docType == type;
    return GestureDetector(
      onTap: () => setState(() => _docType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _kLightGreen : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kPrimary : const Color(0xFFE0E0E0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(children: [
          Icon(icon, color: selected ? _kPrimary : _kTextGray, size: 22),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? _kPrimary : _kTextDark,
              )),
        ]),
      ),
    );
  }

  // ── Step 3 – Vehicle Registration ───────────────────────────────────────

  Widget _buildVehicle() {
    return Column(
      key: const ValueKey('vehicle'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _stepBar(3, 3),
        const SizedBox(height: 16),
        const Text('Vehicle Registration',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _kTextDark, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        const Text('Step 3 of 3 — Vehicle Details',
            style: TextStyle(color: _kTextGray, fontSize: 14)),
        const SizedBox(height: 24),
        _card(children: [
          _label('Vehicle Type'),
          const SizedBox(height: 8),
          _vehicleDrop(),
          const SizedBox(height: 20),
          _label('Vehicle Photo'),
          const SizedBox(height: 10),
          _photoSlot(_vehiclePhoto, 'Vehicle Photo', () => _choosePhoto((f) => _vehiclePhoto = f)),
          const SizedBox(height: 28),
          _btn('Submit Application', _loading ? null : _submit, _loading),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Success ──────────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      children: [
        const SizedBox(height: 60),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(color: _kLightGreen, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_outline, color: _kPrimary, size: 56),
        ),
        const SizedBox(height: 24),
        const Text('Application Submitted!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _kTextDark)),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Your application is under review.\nYou will be notified once your account is approved.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTextGray, fontSize: 14, height: 1.5),
          ),
        ),
        const SizedBox(height: 36),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _btn('Go to Collector Dashboard',
              () => Navigator.pushNamedAndRemoveUntil(context, '/collector-home', (_) => false),
              false),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Reusable widgets ─────────────────────────────────────────────────────

  Widget _stepBar(int current, int total) => Row(
        children: List.generate(total, (i) {
          final done = i < current;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: done ? _kPrimary : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      );

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _label(String t) =>
      Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kTextDark));

  Widget _field(TextEditingController c, String hint, IconData icon, TextInputType type) =>
      TextField(
        controller: c,
        keyboardType: type,
        style: const TextStyle(color: _kTextDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _kTextGray),
          prefixIcon: Icon(icon, size: 20, color: _kTextGray),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
        ),
      );

  Widget _vehicleDrop() => DropdownButtonFormField<String>(
        initialValue: _vehicleType,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.local_shipping_outlined, size: 20, color: _kTextGray),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
        ),
        items: _vehicleTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) { if (v != null) setState(() => _vehicleType = v); },
      );

  Widget _photoSlot(File? file, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
          ),
          child: file != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FileImageView(file, fit: BoxFit.cover, width: double.infinity),
                )
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo_outlined, color: _kPrimary.withValues(alpha: 0.7)),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(fontSize: 11, color: _kTextGray)),
                ]),
        ),
      );

  Widget _btn(String label, VoidCallback? onPressed, bool loading) => SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            disabledBackgroundColor: _kPrimary.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      );

  Widget _link(String prefix, String linkText, VoidCallback onTap) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(prefix, style: const TextStyle(color: _kTextGray, fontSize: 14)),
          GestureDetector(
            onTap: onTap,
            child: Text(linkText, style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      );
}

// ── Ghana Card scan & verify screen ───────────────────────────────────────────
// Shows the uploaded card, scans it on-device, and only lets the collector
// proceed once the typed number is confirmed to match what's on the card.

enum _ScanState { scanning, matched, mismatched, unsupported }

class _GhanaCardScanScreen extends StatefulWidget {
  final File photo;
  final String typedNumber;
  const _GhanaCardScanScreen({required this.photo, required this.typedNumber});

  @override
  State<_GhanaCardScanScreen> createState() => _GhanaCardScanScreenState();
}

class _GhanaCardScanScreenState extends State<_GhanaCardScanScreen>
    with SingleTickerProviderStateMixin {
  _ScanState _state = _ScanState.scanning;
  late final AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _runScan();
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  Future<void> _runScan() async {
    setState(() => _state = _ScanState.scanning);
    final result = await verifyGhanaCardPhoto(widget.photo, widget.typedNumber);
    if (!mounted) return;
    setState(() {
      if (!result.supported) {
        _state = _ScanState.unsupported;
      } else if (result.matched) {
        _state = _ScanState.matched;
      } else {
        _state = _ScanState.mismatched;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kTextDark),
        title: const Text('Verify Ghana Card',
            style: TextStyle(color: _kTextDark, fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // The uploaded card, with a scanning sweep while checking.
              Expanded(
                flex: 5,
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FileImageView(widget.photo, fit: BoxFit.cover),
                      if (_state == _ScanState.scanning)
                        AnimatedBuilder(
                          animation: _scanCtrl,
                          builder: (_, _) => Align(
                            alignment: Alignment(0, -1 + 2 * _scanCtrl.value),
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _kPrimary.withValues(alpha: 0.0),
                                    _kPrimary,
                                    _kPrimary.withValues(alpha: 0.0),
                                  ],
                                ),
                                boxShadow: [BoxShadow(color: _kPrimary.withValues(alpha: 0.6), blurRadius: 8)],
                              ),
                            ),
                          ),
                        ),
                      if (_state != _ScanState.scanning)
                        Container(color: Colors.black.withValues(alpha: 0.35)),
                      if (_state != _ScanState.scanning)
                        Center(child: _resultIcon()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Expanded(flex: 3, child: _resultBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultIcon() {
    switch (_state) {
      case _ScanState.matched:
        return Container(
          width: 72, height: 72,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle, color: _kPrimary, size: 64),
        );
      case _ScanState.mismatched:
        return Container(
          width: 72, height: 72,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.error, color: Colors.red, size: 64),
        );
      case _ScanState.unsupported:
        return Container(
          width: 72, height: 72,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.info, color: Colors.orange, size: 64),
        );
      case _ScanState.scanning:
        return const SizedBox.shrink();
    }
  }

  Widget _resultBody() {
    switch (_state) {
      case _ScanState.scanning:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 32, height: 32,
              child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            const Text('Scanning your Ghana Card…',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _kTextDark)),
            const SizedBox(height: 6),
            Text('Checking that it matches ${widget.typedNumber}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextGray, fontSize: 13)),
          ],
        );

      case _ScanState.matched:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Verified!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kPrimary)),
            const SizedBox(height: 6),
            const Text('Your Ghana Card number matches the photo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kTextGray, fontSize: 13)),
            const SizedBox(height: 22),
            _actionBtn('Continue', _kPrimary, () => Navigator.pop(context, true)),
          ],
        );

      case _ScanState.mismatched:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Number doesn\'t match',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 6),
            const Text(
              'We couldn\'t find this number on the card photo. Double-check the number, or re-upload a clearer photo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextGray, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 22),
            _actionBtn('Try Scanning Again', _kPrimary, _runScan),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kTextDark,
                  side: const BorderSide(color: Color(0xFFBDBDBD)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Edit Number / Photo'),
              ),
            ),
          ],
        );

      case _ScanState.unsupported:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Verification unavailable',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
            const SizedBox(height: 6),
            const Text(
              'Photo scanning isn\'t supported on this device. Your application will still be reviewed manually by an admin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextGray, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 22),
            _actionBtn('Continue', _kPrimary, () => Navigator.pop(context, true)),
          ],
        );
    }
  }

  Widget _actionBtn(String label, Color color, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      );
}

// ── Password login / set for existing collector accounts ────────────────────

class _PasswordLoginScreen extends StatefulWidget {
  final String phone;
  final bool hasPassword;
  final bool useSupabase;
  const _PasswordLoginScreen({required this.phone, required this.hasPassword, this.useSupabase = false});

  @override
  State<_PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<_PasswordLoginScreen> {
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _otpSent = false;

  @override
  void dispose() { _passCtrl.dispose(); _confCtrl.dispose(); _otpCtrl.dispose(); super.dispose(); }

  bool get _needsOtp => widget.useSupabase && !widget.hasPassword;

  Future<void> _sendOtp() async {
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.sendOtp(widget.phone, purpose: 'password_reset');
      setState(() => _otpSent = true);
      if (!mounted) return;
      final devCode = res['otp_code'] as String?;
      if (devCode != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dev mode — your code is $devCode')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_passCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters')));
      return;
    }
    if ((!widget.hasPassword || _needsOtp) && _passCtrl.text != _confCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    if (_needsOtp && _otpCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the code we sent you')));
      return;
    }
    setState(() => _loading = true);
    try {
      if (widget.useSupabase) {
        if (_needsOtp) {
          await SupabaseService.resetPassword(widget.phone, _otpCtrl.text.trim(), _passCtrl.text);
        }
        final data = await SupabaseService.loginWithPhone(widget.phone, _passCtrl.text);
        if (!mounted) return;
        await navigateAfterLogin(context, data);
        return;
      }
      final Map<String, dynamic> data;
      if (widget.hasPassword) {
        data = await ApiService.post(ApiConstants.phoneLogin, {'phone': widget.phone, 'password': _passCtrl.text}, authenticated: false);
      } else {
        data = await ApiService.post(ApiConstants.setPassword, {'phone': widget.phone, 'password': _passCtrl.text, 'confirm_password': _confCtrl.text}, authenticated: false);
      }
      if (!mounted) return;
      await navigateAfterLogin(context, data);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.useSupabase ? e.toString().replaceFirst('Exception: ', '') : 'Unable to connect.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_needsOtp) _sendOtp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(backgroundColor: _kBg, elevation: 0, iconTheme: const IconThemeData(color: _kTextDark)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.hasPassword ? 'Enter your password' : 'Set your password',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kTextDark)),
            const SizedBox(height: 6),
            Text(widget.phone, style: const TextStyle(color: _kTextGray, fontSize: 14)),
            if (_needsOtp) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _otpSent ? 'Code sent to your phone' : 'Sending code…',
                        filled: true, fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _sendOtp,
                    child: const Text('Resend'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _kTextGray),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
              ),
            ),
            if (!widget.hasPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _confCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        widget.hasPassword ? 'Login' : 'Set Password & Login',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
