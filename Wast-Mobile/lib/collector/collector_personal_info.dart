import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/profile_avatar.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

const Color _kPrimary    = Color(0xFF2E7D32);
const Color _kBg         = Color(0xFFF0F7F0);
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark   = Color(0xFF1A1A1A);
const Color _kTextGray   = Color(0xFF757575);

class CollectorPersonalInfoPage extends StatefulWidget {
  const CollectorPersonalInfoPage({super.key});

  @override
  State<CollectorPersonalInfoPage> createState() =>
      _CollectorPersonalInfoPageState();
}

class _CollectorPersonalInfoPageState extends State<CollectorPersonalInfoPage> {
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _emailCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppProvider>();
    final profile = p.collectorProfile;
    _firstNameCtrl = TextEditingController(
        text: (profile?['first_name'] as String?) ??
            (p.currentUser?['first_name'] as String?) ?? '');
    _lastNameCtrl = TextEditingController(
        text: (profile?['last_name'] as String?) ??
            (p.currentUser?['last_name'] as String?) ?? '');
    _emailCtrl = TextEditingController(
        text: (p.currentUser?['email'] as String?) ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName  = _lastNameCtrl.text.trim();
    if (firstName.isEmpty) {
      _snack('First name cannot be empty');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppProvider>().updateCollectorProfile({
        'first_name': firstName,
        'last_name':  lastName,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: _kPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
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
    final picked = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<AppProvider>().uploadCollectorProfilePhoto(picked.path);
      if (!mounted) return;
      _snack('Profile photo updated');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p    = context.watch<AppProvider>();
    final phone = (p.currentUser?['phone'] as String?) ?? '';
    final name = p.displayName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final photoUrl = p.profileImageUrl;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kTextDark,
        elevation: 0,
        title: const Text('Personal Information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kPrimary))
                : const Text('Save',
                    style: TextStyle(
                        color: _kPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _saving ? null : _pickPhoto,
                    child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: _kPrimary,
                      borderRadius: BorderRadius.circular(20),
                      image: photoUrl != null
                          ? DecorationImage(
                              image: profileImageProvider(photoUrl)!,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: photoUrl == null
                        ? Center(
                      child: Text(initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 32)),
                    )
                        : null,
                  ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap to change photo',
                      style: TextStyle(color: _kTextGray, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 28),

            _buildField('First Name', _firstNameCtrl,
                icon: Icons.person_outline, hint: 'Enter first name'),
            const SizedBox(height: 14),
            _buildField('Last Name', _lastNameCtrl,
                icon: Icons.person_outline, hint: 'Enter last name'),
            const SizedBox(height: 14),
            _buildField('Email Address', _emailCtrl,
                icon: Icons.email_outlined,
                hint: 'Enter email',
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),

            // Phone — read-only
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Phone Number',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _kTextDark)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 20, color: _kTextGray),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(phone,
                            style: const TextStyle(
                                color: _kTextGray, fontSize: 15)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kLightGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Verified',
                            style: TextStyle(
                                color: _kPrimary, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Phone number cannot be changed',
                    style: TextStyle(color: _kTextGray, fontSize: 11)),
              ],
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  disabledBackgroundColor: _kPrimary.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    required IconData icon,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: _kTextDark)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(color: _kTextDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _kTextGray),
            prefixIcon: Icon(icon, size: 20, color: _kTextGray),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          ),
        ),
      ],
    );
  }
}
