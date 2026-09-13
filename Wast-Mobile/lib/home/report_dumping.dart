import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../widgets/file_image.dart';
import 'location_picker.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class ReportDumpingPage extends StatefulWidget {
  const ReportDumpingPage({super.key});

  @override
  State<ReportDumpingPage> createState() => _ReportDumpingPageState();
}

class _ReportDumpingPageState extends State<ReportDumpingPage> {
  final TextEditingController _descCtrl = TextEditingController();

  String _locationAddress = '';
  double? _locationLat;
  double? _locationLng;
  File? _photo;
  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await showLocationPicker(context, allowAnyLocation: true);
    if (result != null && mounted) {
      setState(() {
        _locationAddress = result['address'] as String? ?? '';
        _locationLat = (result['lat'] as num?)?.toDouble();
        _locationLng = (result['lng'] as num?)?.toDouble();
      });
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1200, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => _photo = File(picked.path));
    }
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    if (_locationAddress.isEmpty) {
      _snack('Please select a location.');
      return;
    }
    if (desc.isEmpty) {
      _snack('Please add a description.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await context.read<AppProvider>().addDumpingReport({
        'location': _locationAddress,
        if (_locationLat != null) 'lat': _locationLat,
        if (_locationLng != null) 'lng': _locationLng,
        'description': desc,
      }, photo: _photo);
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (mounted) _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: _kPrimary, size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'Report Submitted!',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: _kTextDark),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thank you. Our team will act on your report shortly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextGray, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('OK',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Report Illegal Dumping',
          style: TextStyle(
              color: _kTextDark, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCCBC)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Help us keep communities clean. Report illegal dumping for immediate action.',
                      style: TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Location picker
            const Text('Location / Address',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kTextDark)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickLocation,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _locationAddress.isNotEmpty
                        ? _kPrimary
                        : const Color(0xFFBDBDBD),
                    width: _locationAddress.isNotEmpty ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _locationAddress.isNotEmpty
                          ? Icons.location_on
                          : Icons.location_on_outlined,
                      color: _kPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locationAddress.isNotEmpty
                            ? _locationAddress
                            : 'Tap to pick location (GPS / map / search)',
                        style: TextStyle(
                          color: _locationAddress.isNotEmpty
                              ? _kTextDark
                              : _kTextGray,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: _kTextGray),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Description
            const Text('Description',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kTextDark)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBDBDBD)),
              ),
              child: TextField(
                controller: _descCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText:
                      'Describe what you see — type of waste, volume, hazard level, etc.',
                  hintStyle: TextStyle(color: _kTextGray, fontSize: 14),
                  border: InputBorder.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Photo upload
            const Text('Photo (optional)',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kTextDark)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _photo != null
                        ? _kPrimary
                        : const Color(0xFFBDBDBD),
                    width: _photo != null ? 1.5 : 1,
                  ),
                ),
                child: _photo != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FileImageView(_photo!, fit: BoxFit.cover),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => setState(() => _photo = null),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.camera_alt_outlined,
                              color: _kTextGray, size: 40),
                          SizedBox(height: 10),
                          Text('Tap to add a photo',
                              style: TextStyle(
                                  color: _kTextGray,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          SizedBox(height: 4),
                          Text('Clear evidence helps speed up action',
                              style:
                                  TextStyle(color: _kTextGray, fontSize: 12)),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 32),

            // Submit
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  disabledBackgroundColor: const Color(0xFFBDBDBD),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Submit Report',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
