import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import 'register_vehicle_page.dart';
import 'vehicle_detail_page.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF0F7F0);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

/// Read-only list of registered vehicles — tap to view details.
class CollectorVehicleDetailsPage extends StatefulWidget {
  const CollectorVehicleDetailsPage({super.key});

  @override
  State<CollectorVehicleDetailsPage> createState() =>
      _CollectorVehicleDetailsPageState();
}

class _CollectorVehicleDetailsPageState extends State<CollectorVehicleDetailsPage> {
  List<dynamic> _vehicles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<dynamic> vehicles;
      if (SupabaseService.isLoggedIn) {
        vehicles = await SupabaseService.fetchMyVehicles();
      } else {
        final data = await ApiService.get(ApiConstants.collectorVehicles);
        vehicles = (data['vehicles'] as List?) ?? [];
      }
      if (mounted) {
        setState(() {
          _vehicles = vehicles;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: _kTextDark,
        elevation: 0,
        title: const Text('Vehicle Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const RegisterVehiclePage()),
          );
          if (ok == true) _load();
        },
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Register vehicle',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading && _vehicles.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _vehicles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text('No vehicles registered',
                          style: TextStyle(color: _kTextGray, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('Tap Register vehicle to add one',
                          style: TextStyle(color: _kTextGray, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _vehicles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final v = _vehicles[i] as Map<String, dynamic>;
                    final id = v['id'] as int;
                    return InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VehicleDetailPage(vehicleId: id),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE8E8E8)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.local_shipping,
                                  color: _kPrimary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    v['name'] as String? ??
                                        v['vehicle_type'] as String? ??
                                        'Vehicle',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _kTextDark),
                                  ),
                                  Text(
                                    '${v['vehicle_type']} · ${v['vehicle_number'] ?? ''}',
                                    style: const TextStyle(
                                        color: _kTextGray, fontSize: 12),
                                  ),
                                  if (v['needs_admin_approval'] == true)
                                    const Text('Pending approval',
                                        style: TextStyle(
                                            color: Colors.orange, fontSize: 11)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: _kTextGray),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
