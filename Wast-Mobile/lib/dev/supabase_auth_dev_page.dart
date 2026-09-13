import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wastmobile/services/supabase_service.dart';

/// Dev-only screen to prove the Phase 0 Supabase auth foundation works
/// end-to-end, without touching any of the real (Django-backed) screens.
/// Reachable via /dev-supabase-auth. Not linked from any production UI.
class SupabaseAuthDevPage extends StatefulWidget {
  const SupabaseAuthDevPage({super.key});

  @override
  State<SupabaseAuthDevPage> createState() => _SupabaseAuthDevPageState();
}

class _SupabaseAuthDevPageState extends State<SupabaseAuthDevPage> {
  final _phone = TextEditingController(text: '+233555000${DateTime.now().second}');
  final _password = TextEditingController(text: 'TestPass123!');
  String _role = 'customer';
  String _log = '';
  bool _busy = false;
  RealtimeChannel? _channel;
  int? _activeRequestId;

  void _append(String s) => setState(() => _log = '$_log\n$s');

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _append('ERROR: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supabase Auth (dev)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: _password, decoration: const InputDecoration(labelText: 'Password')),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Customer'),
                    value: 'customer',
                    groupValue: _role,
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Collector'),
                    value: 'collector',
                    groupValue: _role,
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        final res = _role == 'customer'
                            ? await SupabaseService.registerCustomer(
                                phone: _phone.text, password: _password.text, firstName: 'Test')
                            : await SupabaseService.registerCollector(
                                phone: _phone.text, password: _password.text, vehicleType: 'tricycle', firstName: 'Test');
                        _append('Registered: $res');
                      }),
                  child: const Text('Register'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        final profile = await SupabaseService.loginWithPhone(_phone.text, _password.text);
                        _append('Logged in: $profile');
                      }),
                  child: const Text('Login'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        final profile = await SupabaseService.fetchCurrentProfile();
                        _append('Current profile: $profile');
                      }),
                  child: const Text('Fetch profile'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        final res = await SupabaseService.sendOtp(_phone.text, purpose: 'password_reset');
                        _append('OTP sent: $res');
                      }),
                  child: const Text('Send OTP'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        await SupabaseService.logout();
                        _channel?.unsubscribe();
                        _channel = null;
                        _append('Logged out');
                      }),
                  child: const Text('Logout'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        final types = await SupabaseService.fetchWasteTypes();
                        _append('Waste types: ${types.length} (e.g. ${types.first['label']})');
                      }),
                  child: const Text('Fetch waste types'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        final req = await SupabaseService.createPickupRequest(
                          binTypeId: 2, price: 35, basePrice: 35, pickupAddress: 'Dev test address',
                        );
                        _activeRequestId = req['id'] as int;
                        _append('Created pickup request: $req');
                        _channel?.unsubscribe();
                        _channel = SupabaseService.subscribeToPickupRequest(
                          _activeRequestId!,
                          (row) => _append('REALTIME UPDATE: status=${row['status']}'),
                        );
                        _append('Subscribed to realtime updates for request $_activeRequestId. '
                            'Go change its status in the Supabase table editor to see a live update here.');
                      }),
                  child: const Text('Create pickup request'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _run(() async {
                        final req = await SupabaseService.fetchActivePickupRequest();
                        _append('Active request: $req');
                      }),
                  child: const Text('Fetch active request'),
                ),
                ElevatedButton(
                  onPressed: _busy || _activeRequestId == null ? null : () => _run(() async {
                        await SupabaseService.cancelPickupRequest(_activeRequestId!);
                        _append('Cancelled request $_activeRequestId');
                        _channel?.unsubscribe();
                        _channel = null;
                        _activeRequestId = null;
                      }),
                  child: const Text('Cancel active request'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_log.isEmpty ? '(log appears here)' : _log,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
