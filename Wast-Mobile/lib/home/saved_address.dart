import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'location_picker.dart';

const Color _kBg       = Color(0xFFF0F7F0);
const Color _kPrimary  = Color(0xFF2E7D32);
const Color _kCard     = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class SavedAddressesPage extends StatefulWidget {
  const SavedAddressesPage({super.key});

  @override
  State<SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<SavedAddressesPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AppProvider>().fetchAddresses();
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _addAddress() async {
    final result = await showLocationPicker(context);
    if (result == null || !mounted) return;

    final labelCtrl = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Label this address',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(result['address'] as String,
                style: const TextStyle(color: _kTextGray, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: labelCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Home, Work, Mum\'s place',
                hintStyle: const TextStyle(color: _kTextGray),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _kPrimary, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: _kTextGray)),
          ),
          ElevatedButton(
            onPressed: () {
              final label = labelCtrl.text.trim();
              Navigator.pop(context, label.isEmpty ? 'Address' : label);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Save',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == null || !mounted) return;
    try {
      await context.read<AppProvider>().addAddress({
        'label': confirmed,
        'address': result['address'],
        'lat': result['lat'],
        'lng': result['lng'],
      });
    } catch (_) {}
  }

  Future<void> _delete(dynamic id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete address?',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text(
            'This address will be removed from your saved list.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: _kTextGray))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppProvider>().deleteAddress(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final addresses = provider.savedAddresses;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Saved Addresses',
            style: TextStyle(
                color: _kTextDark,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAddress,
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Address',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPrimary))
          : addresses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No saved addresses',
                          style: TextStyle(
                              color: _kTextGray, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text(
                          'Save frequently used addresses for quick pickup',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _kTextGray, fontSize: 13)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _addAddress,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Add Address',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final item = addresses[index];
                    final label =
                        (item['label'] as String?) ?? 'Address';
                    final isHome = label.toLowerCase() == 'home';
                    final isWork = label.toLowerCase() == 'work';
                    final icon = isHome
                        ? Icons.home_outlined
                        : isWork
                            ? Icons.work_outline
                            : Icons.location_on_outlined;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                              color: _kLightGreen, shape: BoxShape.circle),
                          child: Icon(icon, color: _kPrimary, size: 20),
                        ),
                        title: Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: _kTextDark)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            item['address']?.toString() ?? '',
                            style: const TextStyle(
                                color: _kTextGray, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 22),
                          onPressed: () => _delete(item['id']),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
