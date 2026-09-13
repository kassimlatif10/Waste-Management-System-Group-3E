import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../utils/parse_utils.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF0F7F0);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class VehicleDetailPage extends StatefulWidget {
  final int vehicleId;
  const VehicleDetailPage({super.key, required this.vehicleId});

  @override
  State<VehicleDetailPage> createState() => _VehicleDetailPageState();
}

class _VehicleDetailPageState extends State<VehicleDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = SupabaseService.isLoggedIn
          ? await SupabaseService.fetchVehicleDetail(widget.vehicleId)
          : await ApiService.get(ApiConstants.collectorVehicleDetail(widget.vehicleId));
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEdit() {
    final d = _data;
    if (d == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditVehicleSheet(
        vehicleId: widget.vehicleId,
        initial: {
          'name': d['name'] as String? ?? '',
          'vehicle_type': d['vehicle_type'] as String? ?? '',
          'vehicle_number': d['vehicle_number'] as String? ?? '',
          'phone': d['phone'] as String? ?? '',
        },
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final driver = d?['driver'] as Map<String, dynamic>?;
    final reg = d?['driver_registration'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: Text(d?['name'] as String? ?? 'Vehicle Details',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (!_loading && d != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit vehicle info',
              onPressed: _openEdit,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : d == null
              ? const Center(child: Text('Vehicle not found'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Vehicle photo
                    if ((d['vehicle_photo'] as String?)?.isNotEmpty == true)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: d['vehicle_photo'] as String,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            height: 180,
                            color: const Color(0xFFE0E0E0),
                            child: const Center(
                                child: CircularProgressIndicator(
                                    color: _kPrimary)),
                          ),
                          errorWidget: (_, _, _) => Container(
                            height: 180,
                            color: const Color(0xFFE0E0E0),
                            child: const Icon(Icons.local_shipping,
                                size: 64, color: _kTextGray),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Edit banner
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _kLightGreen,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _kPrimary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: _kPrimary, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Tap the edit icon at the top right to update this vehicle\'s information.',
                              style: TextStyle(
                                  color: _kPrimary,
                                  fontSize: 12,
                                  height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Vehicle info card
                    _card([
                      _sectionLabel('Vehicle Information'),
                      _row('Name', d['name'] as String? ?? '—'),
                      _row('Type', d['vehicle_type'] as String? ?? '—'),
                      _row('Registration',
                          d['vehicle_number'] as String? ?? '—'),
                      if ((d['phone'] as String?)?.isNotEmpty == true)
                        _row('Contact Phone', d['phone'] as String),
                      _row('Collections',
                          '${d['total_collections'] ?? 0}'),
                      _row('Earnings',
                          money(d['total_earnings'], prefix: 'GH₵', fallback: 'GH₵ 0.00')),
                      if (d['is_default'] == true)
                        _row('Status', 'Default vehicle'),
                      if (d['needs_admin_approval'] == true)
                        _row('Approval', 'Pending admin approval'),
                    ]),

                    // Assigned collector
                    if (driver != null) ...[
                      const SizedBox(height: 12),
                      _card([
                        _sectionLabel('Assigned Collector'),
                        _row('Name', driver['name'] as String? ?? '—'),
                        _row('Phone', driver['phone'] as String? ?? '—'),
                        _row(
                          'Account',
                          (driver['approved'] as bool? ?? false)
                              ? 'Approved — can log in'
                              : 'Pending admin approval',
                        ),
                      ]),
                    ],

                    // Registration docs
                    if (reg != null) ...[
                      const SizedBox(height: 12),
                      _card([
                        _sectionLabel('Documentation'),
                        _row('Ghana Card',
                            reg['ghana_card_number'] as String? ?? '—'),
                        _row('License',
                            reg['license_number'] as String? ?? '—'),
                        _row('Address', reg['address'] as String? ?? '—'),
                      ]),
                    ],

                    // Pending info banner
                    if (driver != null &&
                        (driver['approved'] as bool? ?? false) == false) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFFFCC80)),
                        ),
                        child: Text(
                          'The new collector (${driver['phone']}) can log in '
                          'with their phone once an admin approves their account.',
                          style: const TextStyle(
                              color: Color(0xFF6D4C00),
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: _kPrimary)),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(label,
                    style: const TextStyle(
                        color: _kTextGray, fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _kTextDark,
                        fontSize: 14))),
          ],
        ),
      );
}

// ── Edit vehicle bottom sheet ──────────────────────────────────────────────────
class _EditVehicleSheet extends StatefulWidget {
  final int vehicleId;
  final Map<String, String> initial;
  final VoidCallback onSaved;

  const _EditVehicleSheet({
    required this.vehicleId,
    required this.initial,
    required this.onSaved,
  });

  @override
  State<_EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends State<_EditVehicleSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _typeCtrl;
  late final TextEditingController _numberCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial['name']);
    _typeCtrl = TextEditingController(text: widget.initial['vehicle_type']);
    _numberCtrl = TextEditingController(text: widget.initial['vehicle_number']);
    _phoneCtrl = TextEditingController(text: widget.initial['phone']);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _typeCtrl.dispose();
    _numberCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final type = _typeCtrl.text.trim();
    final number = _numberCtrl.text.trim();
    if (name.isEmpty || type.isEmpty || number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name, type and registration number are required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final fields = {
        'name': name,
        'vehicle_type': type,
        'vehicle_number': number,
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
      };
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.updateVehicle(widget.vehicleId, fields);
      } else {
        await ApiService.patch(ApiConstants.collectorVehicle(widget.vehicleId), fields);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Vehicle information updated.'),
        backgroundColor: _kPrimary,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kLightGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.edit_outlined, color: _kPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Edit Vehicle Info',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: _kTextDark),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _field('Vehicle Name', _nameCtrl, 'e.g. Green Pickup 1',
                Icons.local_shipping_outlined),
            _field('Vehicle Type', _typeCtrl, 'e.g. Pickup Truck',
                Icons.category_outlined),
            _field('Registration Number', _numberCtrl, 'e.g. GT-1234-24',
                Icons.badge_outlined),
            _field('Contact Phone', _phoneCtrl, 'e.g. 0240000000',
                Icons.phone_outlined,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
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
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: _kPrimary, size: 20),
            filled: true,
            fillColor: const Color(0xFFF8F8F8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          ),
        ),
      );
}
