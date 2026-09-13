import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/user_provider.dart';
import '../utils/parse_utils.dart';
import 'profile_screen.dart';

const Color kBg = Color(0xFFF0F7F0);
const Color kPrimary = Color(0xFF2E7D32);
const Color kCard = Colors.white;
const Color kLightGreen = Color(0xFFE8F5E9);
const Color kTextDark = Color(0xFF1A1A1A);
const Color kTextGray = Color(0xFF757575);
const String kCurrency = 'GH₵';

class ServiceHistoryPage extends StatefulWidget {
  const ServiceHistoryPage({super.key});

  @override
  State<ServiceHistoryPage> createState() => _ServiceHistoryPageState();
}

class _ServiceHistoryPageState extends State<ServiceHistoryPage> {
  String selectedFilter = 'All';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => _loading = true);
      await context.read<AppProvider>().fetchHistory(force: true);
      if (mounted) setState(() => _loading = false);
    });
  }

  final List<String> _filters = [
    'All',
    'Completed',
    'Active',
    'Scheduled',
    'Cancelled',
  ];

  Color _wasteTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'recyclable':
        return const Color(0xFF1565C0);
      case 'organic':
        return const Color(0xFF2E7D32);
      case 'hazardous':
        return const Color(0xFFE65100);
      default:
        return const Color(0xFF757575);
    }
  }

  IconData _wasteTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'recyclable':
        return Icons.recycling;
      case 'organic':
        return Icons.eco;
      case 'hazardous':
        return Icons.science_outlined;
      default:
        return Icons.delete_outline;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'active':
        return const Color(0xFF1565C0);
      case 'cancelled':
        return Colors.red;
      case 'scheduled':
        return const Color(0xFFE65100);
      default:
        return kTextGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final filteredList = provider.getFilteredHistory(selectedFilter);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Service History',
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Service History',
                  style: TextStyle(
                    color: kTextDark,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${filteredList.length} requests total',
                  style: const TextStyle(color: kTextGray, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _filters
                  .map((f) => _filterChip(f))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : filteredList.isEmpty
                ? const Center(
                    child: Text(
                      'No records found',
                      style: TextStyle(color: kTextGray, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final item = filteredList[index];
                      return _historyCard(item);
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _filterChip(String label) {
    final isSelected = selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => selectedFilter = label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? kPrimary : kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? kPrimary : const Color(0xFFBDBDBD),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : kTextGray,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  void _onCardTap(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? '';
    if (status == 'Active') {
      final active = context.read<AppProvider>().activeRequest;
      if (active == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request details unavailable')),
        );
        return;
      }
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ActiveDetailSheet(
          active: active,
          rawStatus: active['status'] as String? ?? '',
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _RequestSummarySheet(item: item),
      );
    }
  }

  Widget _historyCard(Map<String, dynamic> item) {
    final wasteType = item['wasteType']?.toString() ?? 'General';
    final status = item['status']?.toString() ?? 'Unknown';
    final address = item['address']?.toString() ?? '12 Cantonments Road, Accra';
    final date = item['date']?.toString() ?? '';
    final amount = item['amount'] ?? 0;

    final typeColor = _wasteTypeColor(wasteType);
    final typeIcon = _wasteTypeIcon(wasteType);
    final statusColor = _statusColor(status);

    return GestureDetector(
      onTap: () => _onCardTap(item),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Waste type badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, color: typeColor, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      wasteType,
                      style: TextStyle(
                        color: typeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            address,
            style: const TextStyle(
              color: kTextDark,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date,
                style: const TextStyle(color: kTextGray, fontSize: 13),
              ),
              Row(
                children: [
                  Text(
                    money(amount, prefix: kCurrency),
                    style: const TextStyle(
                      color: kTextDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      color: kTextGray, size: 20),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: kCard,
      selectedItemColor: kPrimary,
      unselectedItemColor: kTextGray,
      currentIndex: 1,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == 0) {
          Navigator.pop(context);
        } else if (index == 1) {
          // already here
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          );
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ACTIVE REQUEST DETAIL SHEET
// Shown when customer taps an Active/Searching/Proposed history card.
// ══════════════════════════════════════════════════════════════════════════════
class _ActiveDetailSheet extends StatelessWidget {
  final Map<String, dynamic> active;
  final String rawStatus;
  const _ActiveDetailSheet({required this.active, required this.rawStatus});

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final profile = active['collector_profile'] as Map<String, dynamic>?;
    final name    = (active['collector_name']  as String?) ?? 'Collector';
    final phone   = (active['collector_phone'] as String?) ?? '';
    final vehicle = (profile?['vehicle_type']  as String?) ?? 'Vehicle';
    final rating  = parseDouble(profile?['rating']);
    final address = (active['pickup_address']  as String?) ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';

    final hasCollector = rawStatus == 'assigned' ||
        rawStatus == 'on_way' ||
        rawStatus == 'arrived' ||
        rawStatus == 'proposed';

    final (statusLabel, statusColor) = switch (rawStatus) {
      'finding'  => ('Awaiting admin assignment', kTextGray),
      'proposed' => ('Collector Proposed',      const Color(0xFF9C27B0)),
      'assigned' => ('Collector Assigned',      kPrimary),
      'on_way'   => ('En Route to You',         const Color(0xFF1A73E8)),
      'arrived'  => ('Collector Arrived!',      Colors.orange),
      _          => ('Active',                  kPrimary),
    };

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ─────────────────────────────────────────────────
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),

            // ── Status badge ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7, height: 7,
                  decoration:
                      BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Collector card ──────────────────────────────────────────
            if (hasCollector)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kLightGreen.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFA5D6A7)),
                ),
                child: Row(children: [
                  // Avatar
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: kTextDark)),
                        const SizedBox(height: 3),
                        Text(vehicle,
                            style: const TextStyle(
                                fontSize: 13, color: kTextGray)),
                        if (rating > 0) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 14),
                            const SizedBox(width: 3),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: kTextDark,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ],
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(phone,
                              style: const TextStyle(
                                  fontSize: 12, color: kTextGray)),
                        ],
                      ],
                    ),
                  ),
                  // Call button
                  if (phone.isNotEmpty)
                    GestureDetector(
                      onTap: () => _call(phone),
                      child: Container(
                        width: 46, height: 46,
                        decoration: const BoxDecoration(
                            color: kPrimary, shape: BoxShape.circle),
                        child: const Icon(Icons.call,
                            color: Colors.white, size: 22),
                      ),
                    ),
                ]),
              )
            else
              // Searching spinner
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: kPrimary, strokeWidth: 2.5),
                    ),
                    SizedBox(width: 12),
                    Text('Awaiting admin assignment…',
                        style: TextStyle(color: kTextGray, fontSize: 14)),
                  ],
                ),
              ),

            const SizedBox(height: 14),

            // ── Pickup address ──────────────────────────────────────────
            if (address.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.location_on_outlined,
                      color: kPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(address,
                        style: const TextStyle(
                            fontSize: 13, color: kTextDark),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),

            const SizedBox(height: 20),

            // ── Track Live button ───────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.gps_fixed,
                    color: Colors.white, size: 20),
                label: const Text('Track Live',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
                    (_) => false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Request summary sheet (Completed / Cancelled) ─────────────────────────────
class _RequestSummarySheet extends StatelessWidget {
  final Map<String, dynamic> item;
  const _RequestSummarySheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final wasteType = item['wasteType']?.toString() ?? 'General';
    final status    = item['status']?.toString()    ?? 'Unknown';
    final address   = item['address']?.toString()   ?? '';
    final date      = item['date']?.toString()      ?? '';
    final amount    = item['amount'] ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Request Details',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: kTextDark)),
            const SizedBox(height: 16),
            _SummaryRow(
                icon: Icons.delete_outline,
                label: 'Waste Type', value: wasteType),
            _SummaryRow(
                icon: Icons.location_on_outlined,
                label: 'Address', value: address),
            _SummaryRow(
                icon: Icons.calendar_today_outlined,
                label: 'Date', value: date),
            _SummaryRow(
                icon: Icons.payments_outlined,
                label: 'Amount', value: money(amount, prefix: kCurrency)),
            _SummaryRow(
                icon: Icons.info_outline,
                label: 'Status', value: status),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _SummaryRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: kPrimary, size: 18),
            const SizedBox(width: 10),
            Text('$label: ',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: kTextDark)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, color: kTextGray),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}
