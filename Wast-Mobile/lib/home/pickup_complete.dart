import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../utils/parse_utils.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);
const String _kCurrency = 'GH₵';

class PickupCompletePage extends StatefulWidget {
  const PickupCompletePage({super.key});

  @override
  State<PickupCompletePage> createState() => _PickupCompletePageState();
}

class _PickupCompletePageState extends State<PickupCompletePage> {
  int _selectedRating = 0;
  bool _submitting = false;

  Future<void> _goHome() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final provider = context.read<AppProvider>();
    if (_selectedRating > 0) {
      await provider.rateCompletedPickup(_selectedRating);
    }
    provider.clearCompletedRequest();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final req = provider.activeRequest;
    final collectorName = (req?['collector_name'] as String?) ?? 'Collector';
    final profile = req?['collector_profile'] as Map<String, dynamic>?;
    final vehicle = (profile?['vehicle_type'] as String?) ?? 'Vehicle';
    final amount = provider.proposedPrice;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    color: _kLightGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: _kPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Pickup Complete!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _kTextDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your waste has been collected. Thank you for keeping the environment clean!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _kTextGray),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: _kTextGray, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collectorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kTextDark,
                            ),
                          ),
                          Text(
                            vehicle,
                            style: const TextStyle(fontSize: 12, color: _kTextGray),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final filled = i < _selectedRating;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedRating = i + 1),
                          child: Icon(
                            filled ? Icons.star : Icons.star_border,
                            color: filled ? Colors.amber : Colors.orange,
                            size: 22,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Text(
                      'Total charged',
                      style: TextStyle(fontSize: 14, color: _kTextGray),
                    ),
                    const Spacer(),
                    Text(
                      money(amount, prefix: _kCurrency),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _goHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Back to Home',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
