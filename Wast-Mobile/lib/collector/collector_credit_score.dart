import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF0F7F0);
const Color _kTextDark = Color(0xFF1A1A1A);

class CollectorCreditScorePage extends StatefulWidget {
  const CollectorCreditScorePage({super.key});

  @override
  State<CollectorCreditScorePage> createState() =>
      _CollectorCreditScorePageState();
}

class _CollectorCreditScorePageState extends State<CollectorCreditScorePage> {
  int _score = 100;
  List<Map<String, dynamic>> _actions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = SupabaseService.isLoggedIn
          ? await SupabaseService.fetchCreditScoreActions()
          : await ApiService.get(ApiConstants.collectorCreditScore);
      if (!mounted) return;
      setState(() {
        _score = (data['credit_score'] as num?)?.toInt() ?? 100;
        _actions = (data['actions'] as List?)
                ?.map((a) => a as Map<String, dynamic>)
                .toList() ??
            [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claim(String action, {bool copyShare = false}) async {
    if (copyShare) {
      const shareText =
          'Join Bɔla Aba for waste collection in Sekondi-Takoradi — download the app today!';
      await Clipboard.setData(const ClipboardData(text: shareText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share link copied — paste to share')),
        );
      }
    }
    try {
      final data = SupabaseService.isLoggedIn
          ? await SupabaseService.claimCreditScoreAction(action)
          : await ApiService.post(ApiConstants.collectorCreditScore, {'action': action});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message'] as String? ?? 'Credit added'),
          backgroundColor: _kPrimary,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: const Text('Credit Score',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kPrimary, Color(0xFF1B5E20)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text('$_score',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.bold)),
                      const Text('/ 100',
                          style: TextStyle(color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(
                        _score >= 80
                            ? 'Excellent standing'
                            : _score >= 50
                                ? 'Good standing'
                                : 'Needs improvement',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Earn credit score',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _kTextDark)),
                const SizedBox(height: 12),
                ..._actions.map((a) {
                  final done = a['done'] as bool? ?? false;
                  final type = a['type'] as String? ?? '';
                  final pts = a['points'] as num? ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: done ? Colors.grey.shade300 : _kPrimary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a['label'] as String? ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _kTextDark)),
                              Text('+$pts credit',
                                  style: const TextStyle(
                                      color: _kPrimary, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (done)
                          const Icon(Icons.check_circle, color: _kPrimary)
                        else
                          TextButton(
                            onPressed: () {
                              if (type == 'rate_app') {
                                _claim(type);
                              } else {
                                _claim(type, copyShare: true);
                              }
                            },
                            child: const Text('Claim',
                                style: TextStyle(color: _kPrimary)),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
