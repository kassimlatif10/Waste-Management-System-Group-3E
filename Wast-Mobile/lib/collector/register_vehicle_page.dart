import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../constants/api_constants.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../widgets/file_image.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF0F7F0);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class RegisterVehiclePage extends StatefulWidget {
  const RegisterVehiclePage({super.key});

  @override
  State<RegisterVehiclePage> createState() => _RegisterVehiclePageState();
}

class _RegisterVehiclePageState extends State<RegisterVehiclePage> {
  int _step = 0;
  bool _saving = false;
  bool _assignSelf = true;

  final _nameCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _vehiclePhoneCtrl = TextEditingController();
  final _driverNameCtrl = TextEditingController();
  final _driverPhoneCtrl = TextEditingController();
  final _driverAddressCtrl = TextEditingController();
  final _ghanaCardCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  File? _vehiclePhoto;
  File? _ghanaFront;
  File? _ghanaBack;
  File? _licenseFront;
  File? _licenseBack;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _typeCtrl.dispose();
    _numberCtrl.dispose();
    _vehiclePhoneCtrl.dispose();
    _driverNameCtrl.dispose();
    _driverPhoneCtrl.dispose();
    _driverAddressCtrl.dispose();
    _ghanaCardCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<File?> _pickImage(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    return x != null ? File(x.path) : null;
  }

  Future<void> _choosePhoto(void Function(File?) setFile) async {
    final source = await showModalBottomSheet<ImageSource>(
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
    if (source == null) return;
    final f = await _pickImage(source);
    if (f != null) setState(() => setFile(f));
  }

  bool _validateStep() {
    if (_step == 0) {
      if (_nameCtrl.text.trim().isEmpty ||
          _typeCtrl.text.trim().isEmpty ||
          _numberCtrl.text.trim().isEmpty) {
        _snack('Name, type and registration number are required');
        return false;
      }
      if (_vehiclePhoto == null) {
        _snack('Vehicle photo is required');
        return false;
      }
    }
    if (_step == 1 && !_assignSelf) {
      if (_driverNameCtrl.text.trim().isEmpty || _driverPhoneCtrl.text.trim().isEmpty) {
        _snack('Driver name and phone are required');
        return false;
      }
      if (_ghanaCardCtrl.text.trim().isEmpty || _licenseCtrl.text.trim().isEmpty) {
        _snack('Ghana card and license numbers are required');
        return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_validateStep()) return;
    setState(() => _saving = true);
    try {
      final fields = <String, String>{
        'name': _nameCtrl.text.trim(),
        'vehicle_type': _typeCtrl.text.trim(),
        'vehicle_number': _numberCtrl.text.trim(),
        if (_vehiclePhoneCtrl.text.trim().isNotEmpty)
          'phone': _vehiclePhoneCtrl.text.trim(),
        'assign_self': _assignSelf.toString(),
      };
      if (!_assignSelf) {
        fields['driver_name'] = _driverNameCtrl.text.trim();
        fields['driver_phone'] = _driverPhoneCtrl.text.trim();
        fields['driver_address'] = _driverAddressCtrl.text.trim();
        fields['ghana_card_number'] = _ghanaCardCtrl.text.trim();
        fields['license_number'] = _licenseCtrl.text.trim();
      }
      final files = <String, File>{'vehicle_photo': _vehiclePhoto!};
      if (!_assignSelf) {
        if (_ghanaFront != null) files['ghana_card_front'] = _ghanaFront!;
        if (_ghanaBack != null) files['ghana_card_back'] = _ghanaBack!;
        if (_licenseFront != null) files['license_front'] = _licenseFront!;
        if (_licenseBack != null) files['license_back'] = _licenseBack!;
      }
      final Map<String, dynamic> data;
      if (SupabaseService.isLoggedIn) {
        final driverDocs = <String, Uint8List>{};
        for (final entry in files.entries) {
          if (entry.key == 'vehicle_photo') continue;
          driverDocs[entry.key] = await readFileBytes(entry.value);
        }
        data = await SupabaseService.registerVehicle(
          name: fields['name']!,
          vehicleType: fields['vehicle_type']!,
          vehicleNumber: fields['vehicle_number']!,
          phone: fields['phone'],
          assignSelf: _assignSelf,
          vehiclePhoto: await readFileBytes(_vehiclePhoto!),
          driverName: fields['driver_name'],
          driverPhone: fields['driver_phone'],
          driverAddress: fields['driver_address'],
          ghanaCardNumber: fields['ghana_card_number'],
          licenseNumber: fields['license_number'],
          driverDocs: driverDocs,
        );
      } else {
        data = await ApiService.postMultipart(
          ApiConstants.collectorRegisterVehicle,
          fields,
          files,
        );
      }
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Success'),
          content: Text(data['message'] as String? ?? 'Vehicle registered.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: const Text('Register a new vehicle',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: Colors.white,
            color: _kPrimary,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _step == 0
                  ? _buildVehicleStep()
                  : _step == 1
                      ? _buildAssignStep()
                      : _buildReviewStep(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (!_validateStep()) return;
                            if (_step < 2) {
                              setState(() => _step++);
                            } else {
                              _submit();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(_step < 2 ? 'Continue' : 'Register vehicle',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Vehicle information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextDark)),
        const SizedBox(height: 16),
        _field('Vehicle name', _nameCtrl, 'e.g. Green Pickup 1'),
        _field('Vehicle type', _typeCtrl, 'e.g. Pickup Truck'),
        _field('Registration number', _numberCtrl, 'e.g. GT-1234-24'),
        _field('Contact phone (optional)', _vehiclePhoneCtrl, 'e.g. 0240000000',
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        const Text('Vehicle photo (required)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _photoTile(_vehiclePhoto, () => _choosePhoto((f) => _vehiclePhoto = f)),
      ],
    );
  }

  Widget _buildAssignStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Assign collector',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextDark)),
        RadioListTile<bool>(
          value: true,
          groupValue: _assignSelf,
          onChanged: (v) => setState(() => _assignSelf = true),
          title: const Text('Assign to myself'),
          fillColor: WidgetStateProperty.resolveWith<Color?>(
              (_) => _kPrimary),
        ),
        RadioListTile<bool>(
          value: false,
          groupValue: _assignSelf,
          onChanged: (v) => setState(() => _assignSelf = false),
          title: const Text('Register a new collector for this vehicle'),
          fillColor: WidgetStateProperty.resolveWith<Color?>(
              (_) => _kPrimary),
        ),
        if (!_assignSelf) ...[
          _field('Collector name', _driverNameCtrl, 'Full name'),
          _field('Phone number', _driverPhoneCtrl, '0240000000'),
          _field('Location address', _driverAddressCtrl, 'Address in Sekondi-Takoradi'),
          _field('Ghana card number', _ghanaCardCtrl, 'GHA-XXXXXXXX-X'),
          _field('License number', _licenseCtrl, 'License number'),
          const SizedBox(height: 8),
          const Text('Ghana card (front & back)', style: TextStyle(fontWeight: FontWeight.w600)),
          Row(children: [
            Expanded(child: _photoTile(_ghanaFront, () => _choosePhoto((f) => _ghanaFront = f), label: 'Front')),
            const SizedBox(width: 8),
            Expanded(child: _photoTile(_ghanaBack, () => _choosePhoto((f) => _ghanaBack = f), label: 'Back')),
          ]),
          const SizedBox(height: 12),
          const Text('License (front & back)', style: TextStyle(fontWeight: FontWeight.w600)),
          Row(children: [
            Expanded(child: _photoTile(_licenseFront, () => _choosePhoto((f) => _licenseFront = f), label: 'Front')),
            const SizedBox(width: 8),
            Expanded(child: _photoTile(_licenseBack, () => _choosePhoto((f) => _licenseBack = f), label: 'Back')),
          ]),
        ],
      ],
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Review & submit',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextDark)),
        const SizedBox(height: 12),
        Text('${_nameCtrl.text} · ${_typeCtrl.text} · ${_numberCtrl.text}',
            style: const TextStyle(color: _kTextGray)),
        Text(_assignSelf ? 'Assigned to: Yourself' : 'New collector: ${_driverNameCtrl.text}',
            style: const TextStyle(color: _kTextGray)),
        const SizedBox(height: 12),
        const Text(
          'After registration, new collectors must be approved by admin before they can log in.',
          style: TextStyle(color: _kTextGray, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint,
      {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _photoTile(File? file, VoidCallback onTap, {String label = 'Add photo'}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        margin: const EdgeInsets.only(top: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: file != null
            ? FileImageView(file, fit: BoxFit.cover, width: double.infinity, height: 100)
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_a_photo_outlined, color: _kPrimary),
                    Text(label, style: const TextStyle(color: _kTextGray, fontSize: 12)),
                  ],
                ),
              ),
      ),
    );
  }
}
