import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:typed_data';
import '../constants/api_constants.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../utils/parse_utils.dart';
import '../widgets/file_image.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kTextGray = Color(0xFF757575);

class InvestorFleetTab extends StatefulWidget {
  const InvestorFleetTab({super.key});

  @override
  State<InvestorFleetTab> createState() => _InvestorFleetTabState();
}

class _InvestorFleetTabState extends State<InvestorFleetTab> {
  List<dynamic> _rides = [];
  List<dynamic> _collectors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      List<dynamic> rides;
      List<dynamic> cols;
      if (SupabaseService.isLoggedIn) {
        final profile = await SupabaseService.fetchMyInvestorProfile();
        rides = profile == null ? [] : await SupabaseService.fetchInvestorFleetRides(profile['id'] as int);
        cols = await SupabaseService.fetchInvestorRegisteredCollectors();
      } else {
        final ridesData = await ApiService.get(ApiConstants.investorRides);
        final colsData = await ApiService.get(ApiConstants.investorCollectors);
        rides = (ridesData['rides'] as List?) ?? [];
        cols = (colsData['collectors'] as List?) ?? [];
      }
      if (!mounted) return;
      setState(() {
        _rides = rides;
        _collectors = cols;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerRide() async {
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    var management = 'bola_aba';
    int? collectorId;
    var saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Register Ride', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Ride name')),
              TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Vehicle type')),
              TextField(controller: numberCtrl, decoration: const InputDecoration(labelText: 'Plate number')),
              SwitchListTile(
                title: const Text('Managed by Bɔla Aba'),
                subtitle: Text(
                  management == 'bola_aba'
                      ? 'Bɔla Aba assigns collectors & charges 10% service fee'
                      : 'You manage collections yourself',
                ),
                value: management == 'bola_aba',
                activeThumbColor: _kPrimary,
                onChanged: (v) => setSheet(() => management = v ? 'bola_aba' : 'self'),
              ),
              if (management == 'self' && _collectors.isNotEmpty)
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Assign collector'),
                  items: _collectors
                      .where((c) => c['is_approved'] == true)
                      .map((c) => DropdownMenuItem(
                            value: c['id'] as int,
                            child: Text(c['full_name'] as String? ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) => collectorId = v,
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty ||
                              typeCtrl.text.trim().isEmpty ||
                              numberCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Fill in all the fields above')),
                            );
                            return;
                          }
                          setSheet(() => saving = true);
                          // Don't pop until we know it worked — closing the
                          // sheet first meant a failed submission lost
                          // everything the investor had just typed.
                          try {
                            if (SupabaseService.isLoggedIn) {
                              await SupabaseService.registerInvestorRide(
                                name: nameCtrl.text.trim(),
                                vehicleType: typeCtrl.text.trim(),
                                vehicleNumber: numberCtrl.text.trim(),
                                managementMode: management,
                                assignedCollectorProfileId: collectorId,
                              );
                            } else {
                              await ApiService.post(ApiConstants.investorRides, {
                                'name': nameCtrl.text.trim(),
                                'vehicle_type': typeCtrl.text.trim(),
                                'vehicle_number': numberCtrl.text.trim(),
                                'management_mode': management,
                                if (collectorId != null) 'assigned_collector_id': collectorId,
                              });
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
                          } catch (e) {
                            setSheet(() => saving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
                  child: saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Register Ride'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCollector() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _AddCollectorPage(onSubmitted: () { _load(); })),
    );
  }

  void _openRideDetail(Map<String, dynamic> ride) async {
    final id = ride['id'] as int;
    try {
      final data = SupabaseService.isLoggedIn
          ? await SupabaseService.fetchInvestorRideDetail(id)
          : await ApiService.get(ApiConstants.investorRide(id));
      if (!mounted) return;
      final detail = data['ride'] as Map<String, dynamic>? ?? ride;
      final collections = (data['collections'] as List?) ?? [];
      final lat = (detail['current_lat'] as num?)?.toDouble();
      final lng = (detail['current_lng'] as num?)?.toDouble();

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Text(detail['vehicle_type'] as String? ?? 'Ride',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              if ((detail['assignment_label'] as String? ?? '').isNotEmpty)
                Chip(
                  label: Text(detail['assignment_label'] as String),
                  backgroundColor: _kPrimary.withValues(alpha: 0.1),
                ),
              Text('Management: ${detail['management_label'] ?? ''}'),
              if (detail['assigned_collector'] != null) ...[
                const SizedBox(height: 8),
                Text('Collector: ${detail['assigned_collector']['full_name']}'),
              ],
              if (lat != null && lng != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(lat, lng),
                      zoom: 14,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('ride'),
                        position: LatLng(lat, lng),
                      ),
                    },
                    zoomControlsEnabled: false,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Collections (${collections.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              ...collections.map((c) => ListTile(
                    dense: true,
                    title: Text(c['pickup_address'] as String? ?? ''),
                    subtitle: Text(money(c['price'], prefix: 'GHS')),
                  )),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Rides', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                TextButton(onPressed: _addCollector, child: const Text('+ Collector')),
              ],
            ),
            if (_rides.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No rides registered yet.', style: TextStyle(color: _kTextGray)),
              )
            else
              ..._rides.map((r) {
                final ride = r as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(ride['vehicle_type'] as String? ?? 'Ride'),
                    subtitle: Text(
                      '${ride['management_label'] ?? ''} · ${ride['vehicle_number'] ?? ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openRideDetail(ride),
                  ),
                );
              }),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: _registerRide,
            backgroundColor: _kPrimary,
            icon: const Icon(Icons.add),
            label: const Text('Register Ride'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Collector Page — full KYC form
// ─────────────────────────────────────────────────────────────────────────────

class _AddCollectorPage extends StatefulWidget {
  final VoidCallback onSubmitted;
  const _AddCollectorPage({required this.onSubmitted});

  @override
  State<_AddCollectorPage> createState() => _AddCollectorPageState();
}

class _AddCollectorPageState extends State<_AddCollectorPage> {
  final _picker = ImagePicker();
  bool _loading = false;

  static const _vehicleTypes = ['Pickup Truck', 'Tricycle', 'Motorcycle', 'Van', 'Mini Van', 'Mini Truck', 'Large Van', 'Tipper Truck'];

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ghanaCardCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _vehicleNameCtrl = TextEditingController();
  final _vehicleNumberCtrl = TextEditingController();
  String _vehicleType = 'Pickup Truck';
  File? _ghanaFront;
  File? _ghanaBack;
  File? _licenseFront;
  File? _licenseBack;
  File? _vehiclePhoto;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _ghanaCardCtrl.dispose();
    _licenseCtrl.dispose(); _vehicleNameCtrl.dispose(); _vehicleNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(void Function(File) onPicked) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
      ])),
    );
    if (src == null) return;
    final x = await _picker.pickImage(source: src, maxWidth: 1600, imageQuality: 85);
    if (x != null && mounted) setState(() => onPicked(File(x.path)));
  }

  Widget _photoTile(File? file, VoidCallback onTap, {required String label}) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: file != null ? _kPrimary : Colors.grey.shade300, width: 1.5),
      ),
      child: file != null
          ? ClipRRect(borderRadius: BorderRadius.circular(11), child: FileImageView(file, fit: BoxFit.cover, width: double.infinity))
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.camera_alt_outlined, color: file != null ? _kPrimary : Colors.grey, size: 28),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11, color: _kTextGray)),
            ]),
    ),
  );

  Widget _field(String label, TextEditingController c, {TextInputType? type}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    ),
  );

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and phone are required.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final fields = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'vehicle_type': _vehicleType,
        if (_ghanaCardCtrl.text.isNotEmpty) 'ghana_card_number': _ghanaCardCtrl.text.trim(),
        if (_licenseCtrl.text.isNotEmpty) 'license_number': _licenseCtrl.text.trim(),
        if (_vehicleNameCtrl.text.isNotEmpty) 'vehicle_name': _vehicleNameCtrl.text.trim(),
        if (_vehicleNumberCtrl.text.isNotEmpty) 'vehicle_number': _vehicleNumberCtrl.text.trim(),
      };
      final images = <String, File>{};
      if (_ghanaFront != null) images['ghana_card_front'] = _ghanaFront!;
      if (_ghanaBack != null) images['ghana_card_back'] = _ghanaBack!;
      if (_licenseFront != null) images['license_front'] = _licenseFront!;
      if (_licenseBack != null) images['license_back'] = _licenseBack!;
      if (_vehiclePhoto != null) images['vehicle_photo'] = _vehiclePhoto!;

      if (SupabaseService.isLoggedIn) {
        final byteImages = <String, Uint8List>{};
        for (final entry in images.entries) {
          byteImages[entry.key] = await readFileBytes(entry.value);
        }
        await SupabaseService.investorRegisterCollector(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          vehicleType: _vehicleType,
          ghanaCardNumber: _ghanaCardCtrl.text.trim().isEmpty ? null : _ghanaCardCtrl.text.trim(),
          licenseNumber: _licenseCtrl.text.trim().isEmpty ? null : _licenseCtrl.text.trim(),
          vehicleName: _vehicleNameCtrl.text.trim().isEmpty ? null : _vehicleNameCtrl.text.trim(),
          vehicleNumber: _vehicleNumberCtrl.text.trim().isEmpty ? null : _vehicleNumberCtrl.text.trim(),
          images: byteImages,
        );
      } else if (images.isNotEmpty) {
        await ApiService.postMultipart(ApiConstants.investorCollectors, fields, images);
      } else {
        await ApiService.post(ApiConstants.investorCollectors, fields);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collector submitted for admin approval.')),
      );
      widget.onSubmitted();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Add Collector', style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800)),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _field('Full Name', _nameCtrl),
        _field('Phone', _phoneCtrl, type: TextInputType.phone),
        _field('Ghana Card Number', _ghanaCardCtrl),
        const Text('Ghana Card (front & back)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _photoTile(_ghanaFront, () => _pickPhoto((f) => _ghanaFront = f), label: 'Front')),
          const SizedBox(width: 10),
          Expanded(child: _photoTile(_ghanaBack, () => _pickPhoto((f) => _ghanaBack = f), label: 'Back')),
        ]),
        const SizedBox(height: 12),
        _field('License Number', _licenseCtrl),
        const Text('Driver License (front & back)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _photoTile(_licenseFront, () => _pickPhoto((f) => _licenseFront = f), label: 'Front')),
          const SizedBox(width: 10),
          Expanded(child: _photoTile(_licenseBack, () => _pickPhoto((f) => _licenseBack = f), label: 'Back')),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Vehicle Type',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _vehicleType,
                isExpanded: true,
                items: _vehicleTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) { if (v != null) setState(() => _vehicleType = v); },
              ),
            ),
          ),
        ),
        _field('Vehicle Name (optional)', _vehicleNameCtrl),
        _field('Registration Number', _vehicleNumberCtrl),
        const Text('Vehicle Photo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        _photoTile(_vehiclePhoto, () => _pickPhoto((f) => _vehiclePhoto = f), label: 'Vehicle'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Submit for Approval', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}
