import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import '../utils/parse_utils.dart';
import 'register_vehicle_page.dart';
import 'vehicle_detail_page.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kLight = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class CollectorVehiclesPage extends StatefulWidget {
  const CollectorVehiclesPage({super.key});

  @override
  State<CollectorVehiclesPage> createState() => _CollectorVehiclesPageState();
}

class _CollectorVehiclesPageState extends State<CollectorVehiclesPage> {
  List<dynamic> _vehicles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final List<dynamic> vehicles;
      if (SupabaseService.isLoggedIn) {
        vehicles = await SupabaseService.fetchMyVehicles();
      } else {
        final data = await ApiService.get(ApiConstants.collectorVehicles);
        vehicles = (data['vehicles'] as List?) ?? (data['data'] as List? ?? []);
      }
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _setDefault(int id) async {
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.setDefaultVehicle(id);
      } else {
        await ApiService.post(ApiConstants.collectorVehicleSetDefault(id), {});
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  void _openRegister() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterVehiclePage()),
    );
    if (ok == true) _load();
  }

  void _openDetail(int id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VehicleDetailPage(vehicleId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: const Text('My Vehicles',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRegister,
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Register a new vehicle',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading && _vehicles.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _buildError()
              : _vehicles.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: _kTextGray),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _kTextGray)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, elevation: 0),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: _kLight, shape: BoxShape.circle),
            child: const Icon(Icons.local_shipping_outlined, size: 48, color: _kPrimary),
          ),
          const SizedBox(height: 16),
          const Text('No vehicles registered',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kTextDark)),
          const SizedBox(height: 8),
          const Text('Tap Register to add your first vehicle',
              style: TextStyle(color: _kTextGray)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _vehicles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final v = _vehicles[i] as Map<String, dynamic>;
        final isDefault = v['is_default'] as bool? ?? false;
        final id = v['id'] as int;
        return InkWell(
          onTap: () => _openDetail(id),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDefault ? _kPrimary : const Color(0xFFE8E8E8),
                width: isDefault ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDefault ? _kLight : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.local_shipping,
                          color: isDefault ? _kPrimary : _kTextGray, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v['name'] as String? ?? v['vehicle_type'] as String? ?? 'Vehicle',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14, color: _kTextDark),
                          ),
                          if ((v['vehicle_number'] as String? ?? '').isNotEmpty)
                            Text(v['vehicle_number'] as String,
                                style: const TextStyle(color: _kTextGray, fontSize: 12)),
                          if (v['needs_admin_approval'] == true)
                            const Text('Pending admin approval',
                                style: TextStyle(color: Colors.orange, fontSize: 11)),
                        ],
                      ),
                    ),
                    if (!isDefault)
                      IconButton(
                        icon: const Icon(Icons.star_outline, color: _kPrimary, size: 20),
                        onPressed: () => _setDefault(id),
                        tooltip: 'Set default',
                      ),
                    const Icon(Icons.chevron_right, color: _kTextGray),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.check_circle_outline,
                      label: '${v['total_collections'] ?? 0} collections',
                      color: _kPrimary,
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.account_balance_wallet_outlined,
                      label: money(v['total_earnings'], prefix: 'GHS', fallback: 'GHS 0.00'),
                      color: const Color(0xFF1976D2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
