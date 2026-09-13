import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import '../widgets/file_image.dart';

const _kPrimary = Color(0xFF2E7D32);
const _kBg = Color(0xFFF1F8F1);
const _kCard = Colors.white;
const _kTextGray = Color(0xFF757575);
const _kTextDark = Color(0xFF1A1A1A);

/// Full KYC registration wizard for collectors.
class CollectorKycPage extends StatefulWidget {
  const CollectorKycPage({super.key});
  @override
  State<CollectorKycPage> createState() => _CollectorKycPageState();
}

class _CollectorKycPageState extends State<CollectorKycPage> {
  final _pageController = PageController();
  int _step = 0;
  bool _loading = false;

  // Personal
  final _middleName = TextEditingController();
  final _ghanaCard = TextEditingController();
  final _email = TextEditingController();
  final _licenseNum = TextEditingController();
  final _vehiclePlate = TextEditingController();
  final _vehicleDetails = TextEditingController();

  // Documents
  File? _ghanaCardFront;
  File? _ghanaCardBack;
  File? _selfie;
  File? _proofOfAddress;
  File? _vehiclePhoto;
  File? _licenseFront;
  File? _licenseBack;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final res = SupabaseService.isLoggedIn
          ? await SupabaseService.fetchMyKyc() ?? {}
          : await ApiService.get(ApiConstants.collectorKyc);
      setState(() {
        _middleName.text = res['middle_name'] as String? ?? '';
        _ghanaCard.text = res['ghana_card_number'] as String? ?? '';
        _email.text = res['email'] as String? ?? '';
        _licenseNum.text = res['license_number'] as String? ?? '';
        _vehiclePlate.text = res['vehicle_number_plate'] as String? ?? '';
        _vehicleDetails.text = res['vehicle_details'] as String? ?? '';
      });
    } catch (_) {}
  }

  Future<void> _pickImage(String field) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() {
      final f = File(picked.path);
      switch (field) {
        case 'ghana_card_front': _ghanaCardFront = f;
        case 'ghana_card_back': _ghanaCardBack = f;
        case 'selfie': _selfie = f;
        case 'proof_of_address': _proofOfAddress = f;
        case 'vehicle_photo': _vehiclePhoto = f;
        case 'license_front': _licenseFront = f;
        case 'license_back': _licenseBack = f;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final fields = <String, String>{
        'middle_name': _middleName.text,
        'ghana_card_number': _ghanaCard.text,
        'email': _email.text,
        'license_number': _licenseNum.text,
        'vehicle_number_plate': _vehiclePlate.text,
        'vehicle_details': _vehicleDetails.text,
      };

      final files = <String, File>{};
      if (_ghanaCardFront != null) files['ghana_card_front'] = _ghanaCardFront!;
      if (_ghanaCardBack != null) files['ghana_card_back'] = _ghanaCardBack!;
      if (_selfie != null) files['selfie'] = _selfie!;
      if (_proofOfAddress != null) files['proof_of_address'] = _proofOfAddress!;
      if (_vehiclePhoto != null) files['vehicle_photo'] = _vehiclePhoto!;
      if (_licenseFront != null) files['license_front'] = _licenseFront!;
      if (_licenseBack != null) files['license_back'] = _licenseBack!;

      if (SupabaseService.isLoggedIn) {
        final byteFiles = <String, Uint8List>{};
        for (final entry in files.entries) {
          byteFiles[entry.key] = await readFileBytes(entry.value);
        }
        await SupabaseService.submitKyc(fields: fields, files: byteFiles);
      } else {
        await ApiService.postMultipart(ApiConstants.collectorKyc, fields, files);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('KYC submitted for review!'),
            backgroundColor: _kPrimary,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // The step widgets mark these fields `required: true` visually, but
  // nothing previously stopped Continue/Submit from proceeding with them
  // left empty — a submission could reach the backend missing its core
  // identity documents entirely.
  String? _stepError() {
    switch (_step) {
      case 0:
        if (_ghanaCard.text.trim().isEmpty) return 'Ghana Card Number is required.';
        return null;
      case 1:
        if (_ghanaCardFront == null || _ghanaCardBack == null || _selfie == null) {
          return 'Ghana Card (front, back) and a selfie are required.';
        }
        return null;
      default:
        return null;
    }
  }

  void _next() {
    final error = _stepError();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
      return;
    }
    if (_step < 3) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('KYC Verification', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                Row(
                  children: List.generate(4, (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: i <= _step ? _kPrimary : const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  )),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Personal', style: TextStyle(fontSize: 10, color: _kTextGray)),
                    Text('Identity', style: TextStyle(fontSize: 10, color: _kTextGray)),
                    Text('Vehicle', style: TextStyle(fontSize: 10, color: _kTextGray)),
                    Text('License', style: TextStyle(fontSize: 10, color: _kTextGray)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _PersonalStep(
                  middleName: _middleName,
                  ghanaCard: _ghanaCard,
                  email: _email,
                ),
                _IdentityStep(
                  frontFile: _ghanaCardFront,
                  backFile: _ghanaCardBack,
                  selfieFile: _selfie,
                  proofFile: _proofOfAddress,
                  onPick: _pickImage,
                ),
                _VehicleStep(
                  vehiclePlate: _vehiclePlate,
                  vehicleDetails: _vehicleDetails,
                  vehiclePhoto: _vehiclePhoto,
                  onPick: _pickImage,
                ),
                _LicenseStep(
                  licenseNum: _licenseNum,
                  licenseFront: _licenseFront,
                  licenseBack: _licenseBack,
                  onPick: _pickImage,
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _back,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : Text(
                            _step == 3 ? 'Submit KYC' : 'Continue',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
}

// ── Step 1: Personal Information ──────────────────────────────────────────────
class _PersonalStep extends StatelessWidget {
  final TextEditingController middleName, ghanaCard, email;
  const _PersonalStep({required this.middleName, required this.ghanaCard, required this.email});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Personal Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kTextDark)),
        const SizedBox(height: 6),
        const Text('Fill in your personal details for verification.',
            style: TextStyle(color: _kTextGray, fontSize: 13)),
        const SizedBox(height: 24),
        _KycField(middleName, 'Middle Name (optional)', Icons.person_outline, required: false),
        const SizedBox(height: 14),
        _KycField(ghanaCard, 'Ghana Card Number', Icons.badge_outlined),
        const SizedBox(height: 14),
        _KycField(email, 'Email Address', Icons.email_outlined, type: TextInputType.emailAddress, required: false),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: _kPrimary, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Your information is encrypted and only used for identity verification.',
              style: TextStyle(fontSize: 12, color: _kTextDark),
            )),
          ]),
        ),
      ],
    ),
  );
}

// ── Step 2: Identity Verification ────────────────────────────────────────────
class _IdentityStep extends StatelessWidget {
  final File? frontFile, backFile, selfieFile, proofFile;
  final Function(String) onPick;
  const _IdentityStep({required this.frontFile, required this.backFile,
    required this.selfieFile, required this.proofFile, required this.onPick});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Identity Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Upload clear photos of your identity documents.', style: TextStyle(color: _kTextGray, fontSize: 13)),
        const SizedBox(height: 24),
        _DocUpload(
          label: 'Ghana Card — Front',
          icon: Icons.credit_card,
          file: frontFile,
          onTap: () => onPick('ghana_card_front'),
          required: true,
        ),
        const SizedBox(height: 12),
        _DocUpload(
          label: 'Ghana Card — Back',
          icon: Icons.credit_card_outlined,
          file: backFile,
          onTap: () => onPick('ghana_card_back'),
          required: true,
        ),
        const SizedBox(height: 12),
        _DocUpload(
          label: 'Selfie Verification',
          icon: Icons.face_outlined,
          file: selfieFile,
          onTap: () => onPick('selfie'),
          required: true,
        ),
        const SizedBox(height: 12),
        _DocUpload(
          label: 'Proof of Address (Bank Statement / Utility Bill)',
          icon: Icons.home_outlined,
          file: proofFile,
          onTap: () => onPick('proof_of_address'),
          required: false,
        ),
      ],
    ),
  );
}

// ── Step 3: Vehicle ───────────────────────────────────────────────────────────
class _VehicleStep extends StatelessWidget {
  final TextEditingController vehiclePlate, vehicleDetails;
  final File? vehiclePhoto;
  final Function(String) onPick;
  const _VehicleStep({required this.vehiclePlate, required this.vehicleDetails,
    required this.vehiclePhoto, required this.onPick});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Vehicle Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Provide your vehicle details for verification.', style: TextStyle(color: _kTextGray, fontSize: 13)),
        const SizedBox(height: 24),
        _KycField(vehiclePlate, 'Vehicle Number Plate', Icons.directions_car_outlined),
        const SizedBox(height: 14),
        _KycField(vehicleDetails, 'Vehicle Details (make, model, year)', Icons.info_outline,
            type: TextInputType.multiline, required: false),
        const SizedBox(height: 14),
        _DocUpload(
          label: 'Vehicle Photo',
          icon: Icons.photo_camera_outlined,
          file: vehiclePhoto,
          onTap: () => onPick('vehicle_photo'),
          required: false,
        ),
      ],
    ),
  );
}

// ── Step 4: Driver License ────────────────────────────────────────────────────
class _LicenseStep extends StatelessWidget {
  final TextEditingController licenseNum;
  final File? licenseFront, licenseBack;
  final Function(String) onPick;
  const _LicenseStep({required this.licenseNum, required this.licenseFront,
    required this.licenseBack, required this.onPick});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Driver License', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Upload your valid driver license for verification.', style: TextStyle(color: _kTextGray, fontSize: 13)),
        const SizedBox(height: 24),
        _KycField(licenseNum, 'License Number', Icons.badge_outlined, required: false),
        const SizedBox(height: 14),
        _DocUpload(
          label: 'License — Front',
          icon: Icons.article_outlined,
          file: licenseFront,
          onTap: () => onPick('license_front'),
          required: false,
        ),
        const SizedBox(height: 12),
        _DocUpload(
          label: 'License — Back',
          icon: Icons.article_outlined,
          file: licenseBack,
          onTap: () => onPick('license_back'),
          required: false,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Review Before Submitting', style: TextStyle(fontWeight: FontWeight.w700, color: _kTextDark)),
              SizedBox(height: 6),
              Text(
                '• All documents will be reviewed within 24–48 hours.\n'
                '• You will be notified once your account is approved.\n'
                '• Approved collectors can go online and accept collections.',
                style: TextStyle(fontSize: 12, color: _kTextGray, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Shared KYC Widgets ────────────────────────────────────────────────────────

class _KycField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType type;
  final bool required;

  const _KycField(this.controller, this.label, this.icon,
      {this.type = TextInputType.text, this.required = true});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: type,
    maxLines: type == TextInputType.multiline ? 3 : 1,
    decoration: InputDecoration(
      labelText: required ? label : '$label (optional)',
      prefixIcon: Icon(icon, size: 20, color: _kTextGray),
      filled: true,
      fillColor: _kCard,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEEEEEE))),
    ),
  );
}

class _DocUpload extends StatelessWidget {
  final String label;
  final IconData icon;
  final File? file;
  final VoidCallback onTap;
  final bool required;

  const _DocUpload({
    required this.label, required this.icon, required this.file,
    required this.onTap, this.required = true,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: file != null ? const Color(0xFFE8F5E9) : _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: file != null ? _kPrimary.withValues(alpha: 0.4) : const Color(0xFFDDDDDD),
          style: file != null ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          if (file != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FileImageView(file!, width: 50, height: 50, fit: BoxFit.cover),
            )
          else
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _kPrimary, size: 24),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  required ? label : '$label (optional)',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  file != null ? '✓ Uploaded — tap to change' : 'Tap to upload',
                  style: TextStyle(
                    fontSize: 11,
                    color: file != null ? _kPrimary : _kTextGray,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            file != null ? Icons.check_circle : Icons.upload_outlined,
            color: file != null ? _kPrimary : _kTextGray,
            size: 20,
          ),
        ],
      ),
    ),
  );
}
