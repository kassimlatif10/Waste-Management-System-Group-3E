import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../utils/parse_utils.dart';
import 'confirm_request.dart';
import 'location_picker.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);
const String _kCurrency = 'GH₵';

class RequestPickupPage extends StatefulWidget {
  const RequestPickupPage({super.key});

  @override
  State<RequestPickupPage> createState() => _RequestPickupPageState();
}

class _RequestPickupPageState extends State<RequestPickupPage> {
  int _wasteTypeIndex = 0;
  int _binTypeIndex = -1; // -1 = none selected
  String _address = '';
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().fetchWasteTypes();
      // Auto-open location picker if no address set yet
      if (_address.isEmpty) _openLocationPicker();
    });
  }

  Future<void> _openLocationPicker() async {
    final result = await showLocationPicker(context);
    if (result != null && mounted) {
      setState(() {
        _address = result['address'] as String;
        _lat = (result['lat'] as num).toDouble();
        _lng = (result['lng'] as num).toDouble();
      });
      context.read<AppProvider>().setCustomerLocation(
            LatLng(_lat!, _lng!),
          );
    }
  }

  void _onContinue(List<Map<String, dynamic>> wasteTypes) {
    if (_binTypeIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a bin size')),
      );
      return;
    }
    if (_lat == null || _lng == null || _address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set your pickup location')),
      );
      return;
    }

    final wt = wasteTypes[_wasteTypeIndex.clamp(0, wasteTypes.length - 1)];
    final bins = _binTypesFor(wt);
    final bin = bins[_binTypeIndex];

    context.read<AppProvider>().setPickupDetails(
          wt['name'] as String,
          parseInt(bin['price']),
          _address,
          binTypeId: bin['id'] as int?,
          binTypeName: bin['display_name'] as String? ?? '',
        );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfirmRequestPage()),
    );
  }

  List<Map<String, dynamic>> _binTypesFor(Map<String, dynamic> wt) {
    final raw = wt['bin_types'];
    if (raw is List) {
      return raw.cast<Map<String, dynamic>>();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final wasteTypes = provider.wasteTypes;
    final wtIdx = _wasteTypeIndex.clamp(0, wasteTypes.length - 1);
    final selectedWt = wasteTypes[wtIdx];
    final bins = _binTypesFor(selectedWt);
    final selectedBin = (_binTypeIndex >= 0 && _binTypeIndex < bins.length)
        ? bins[_binTypeIndex]
        : null;
    final displayPrice = selectedBin != null ? selectedBin['price'] : 0;
    final canContinue = selectedBin != null && _address.isNotEmpty;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Request Pickup',
          style: TextStyle(
            color: _kTextDark,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [

                // ── Step 1: Waste Type ────────────────────────────────
                _sectionLabel('1. Select Waste Type'),
                const SizedBox(height: 12),
                ...List.generate(wasteTypes.length, (i) {
                  final wt = wasteTypes[i];
                  final bool isSel = i == wtIdx;
                  final Color color = wt['color'] as Color;
                  final IconData icon = wt['icon'] as IconData;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _wasteTypeIndex = i;
                      _binTypeIndex = -1;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSel
                              ? _kPrimary
                              : Colors.grey.withValues(alpha: 0.2),
                          width: isSel ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  wt['label'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: _kTextDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  wt['sub'] as String,
                                  style: const TextStyle(
                                      fontSize: 12, color: _kTextGray),
                                ),
                              ],
                            ),
                          ),
                          if (isSel)
                            const Icon(Icons.check_circle,
                                color: _kPrimary, size: 22),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // ── Step 2: Bin Size ──────────────────────────────────
                _sectionLabel('2. Select Bin Size'),
                const SizedBox(height: 4),
                Text(
                  'Price is based on the bin size you choose',
                  style: TextStyle(
                      fontSize: 12,
                      color: _kTextGray.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 12),
                if (bins.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: const Center(
                      child: Text('Loading bin sizes…',
                          style: TextStyle(color: _kTextGray)),
                    ),
                  )
                else
                  ...List.generate(bins.length, (i) {
                    final bin = bins[i];
                    final bool isSel = i == _binTypeIndex;
                    final price = bin['price'];
                    return GestureDetector(
                      onTap: () => setState(() => _binTypeIndex = i),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSel ? _kLightGreen : _kCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSel
                                ? _kPrimary
                                : Colors.grey.withValues(alpha: 0.2),
                            width: isSel ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isSel
                                    ? _kPrimary.withValues(alpha: 0.15)
                                    : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _binIcon(bin['name'] as String? ?? ''),
                                color: isSel ? _kPrimary : _kTextGray,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bin['display_name'] as String,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color:
                                          isSel ? _kPrimary : _kTextDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    bin['description'] as String? ?? '',
                                    style: const TextStyle(
                                        fontSize: 12, color: _kTextGray),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  money(price, prefix: _kCurrency),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isSel ? _kPrimary : _kTextDark,
                                  ),
                                ),
                                if (isSel)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Icon(Icons.check_circle,
                                        color: _kPrimary, size: 18),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 20),

                // ── Step 3: Pickup Location ───────────────────────────
                _sectionLabel('3. Pickup Location'),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _openLocationPicker,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _address.isEmpty
                            ? Colors.orange.shade300
                            : _kPrimary.withValues(alpha: 0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _address.isEmpty
                              ? Icons.add_location_alt_outlined
                              : Icons.location_pin,
                          color: _address.isEmpty
                              ? Colors.orange
                              : _kPrimary,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _address.isEmpty
                                    ? 'Tap to set pickup location'
                                    : _address,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _address.isEmpty
                                      ? Colors.orange.shade700
                                      : _kTextDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _address.isEmpty
                                    ? 'GPS or search for your address'
                                    : 'Tap to change location',
                                style: const TextStyle(
                                    fontSize: 11, color: _kTextGray),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _kLightGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_location_alt_outlined,
                              color: _kPrimary, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // ── Bottom bar ────────────────────────────────────────────
          SafeArea(
            bottom: true,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedBin != null ? 'Est. Total' : 'Select bin',
                        style: const TextStyle(
                            fontSize: 12, color: _kTextGray),
                      ),
                      Text(
                        selectedBin != null
                            ? money(displayPrice, prefix: _kCurrency)
                            : '—',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: selectedBin != null
                              ? _kPrimary
                              : _kTextGray,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: canContinue
                            ? () => _onContinue(wasteTypes)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          disabledBackgroundColor:
                              Colors.grey.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Continue',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward,
                                color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: _kTextDark,
        ),
      );

  IconData _binIcon(String name) {
    switch (name) {
      case 'small':
        return Icons.shopping_bag_outlined;
      case 'medium':
        return Icons.inventory_2_outlined;
      case 'large':
        return Icons.delete_outline;
      case 'standard':
        return Icons.warning_amber_outlined;
      case 'special':
        return Icons.science_outlined;
      default:
        return Icons.delete_outline;
    }
  }
}
