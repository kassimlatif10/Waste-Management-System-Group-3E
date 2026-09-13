import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/sound_service.dart';
import '../services/notification_service.dart';
import '../utils/parse_utils.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class ScheduledPickupsPage extends StatefulWidget {
  const ScheduledPickupsPage({super.key});

  @override
  State<ScheduledPickupsPage> createState() => _ScheduledPickupsPageState();
}

class _ScheduledPickupsPageState extends State<ScheduledPickupsPage> {
  Timer? _ticker;
  final Set<int> _triggeredIds = {};
  final Set<int> _paymentAlertedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AppProvider>().fetchSchedules();
      if (mounted) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() {});
            _checkDue();
            _checkPaymentAlerts();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration? _remaining(Map<String, dynamic> item) {
    final dtStr = item['pickup_datetime'] as String?;
    if (dtStr == null || dtStr.isEmpty) return null;
    try {
      final dt = DateTime.parse(dtStr).toLocal();
      return dt.difference(DateTime.now());
    } catch (_) {
      return null;
    }
  }

  void _checkDue() {
    final items = context.read<AppProvider>().scheduledPickups;
    for (final item in items) {
      final id = (item['id'] as num?)?.toInt() ?? 0;
      if (_triggeredIds.contains(id)) continue;
      final status = (item['status'] as String?) ?? 'pending';
      if (status != 'pending') continue;
      final rem = _remaining(item);
      if (rem == null) continue;
      if (rem.inSeconds <= 0) {
        _triggeredIds.add(id);
        _triggerRequestPlacement(id, item);
      }
    }
  }

  Future<void> _triggerRequestPlacement(
      int id, Map<String, dynamic> item) async {
    final provider = context.read<AppProvider>();
    try {
      await provider.triggerSchedule(id);
    } catch (e) {
      // Let it be retried on the next tick instead of pretending it worked.
      _triggeredIds.remove(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not place this pickup: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await SoundService.playNotification();
    await NotificationService.show(
      'Scheduled Pickup Active',
      'Your ${item['wasteType']} pickup request has been placed. An admin will assign a collector.',
      id: 300 + id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your ${item['wasteType']} pickup request has been placed. An admin will assign a collector.',
          ),
          backgroundColor: _kPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _checkPaymentAlerts() {
    final items = context.read<AppProvider>().scheduledPickups;
    for (final item in items) {
      final id = (item['id'] as num?)?.toInt() ?? 0;
      if (_paymentAlertedIds.contains(id)) continue;
      final dueStr = item['next_payment_due'] as String?;
      if (dueStr == null || dueStr.isEmpty) continue;
      try {
        final due = DateTime.parse(dueStr).toLocal();
        final diff = due.difference(DateTime.now());
        // Alert within 1 hour of next payment due
        if (!diff.isNegative && diff.inHours < 1) {
          _paymentAlertedIds.add(id);
          _showPaymentAlert(id, item);
        }
        // Also alert if overdue by less than 24 hours (missed alert)
        if (diff.isNegative && diff.inHours.abs() < 24) {
          _paymentAlertedIds.add(id);
          _showPaymentAlert(id, item, overdue: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _showPaymentAlert(int id, Map<String, dynamic> item,
      {bool overdue = false}) async {
    await SoundService.playCollectorAlarm(
        duration: const Duration(seconds: 10));
    await NotificationService.show(
      overdue ? 'Payment Overdue!' : 'Payment Reminder',
      'Complete payment for your ${item['wasteType']} recurring pickup.',
      id: 400 + id,
    );
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3E0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                overdue ? Icons.alarm_off : Icons.alarm,
                color: const Color(0xFFF57C00),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              overdue ? 'Payment Overdue!' : 'Payment Due Soon!',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overdue
                  ? 'Your recurring payment for ${item['wasteType']} pickup is overdue.'
                  : 'Your recurring payment for ${item['wasteType']} pickup is due within the hour.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kLightGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      color: _kPrimary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Amount: ${money(item['price'], prefix: 'GH₵', fallback: 'GH₵ 0.00')}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _kPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please complete payment to keep your collection schedule active.',
              style: TextStyle(
                  color: _kTextGray, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              SoundService.stopAlarm();
            },
            child: const Text('Dismiss',
                style: TextStyle(color: _kTextGray)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              SoundService.stopAlarm();
              // Navigate to payment screen (home → active request)
              Navigator.pop(context);
            },
            child: const Text('Pay Now',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDateLabel(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      const days = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday'
      ];
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final pickups = provider.scheduledPickups;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Schedules',
          style: TextStyle(
              color: _kTextDark,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _kPrimary),
            onPressed: () => context.read<AppProvider>().fetchSchedules(),
          ),
        ],
      ),
      body: pickups.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 64, color: _kTextGray),
                  SizedBox(height: 16),
                  Text(
                    'No scheduled pickups yet',
                    style:
                        TextStyle(color: _kTextGray, fontSize: 16),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Schedule a pickup to see it here',
                    style:
                        TextStyle(color: _kTextGray, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: pickups.length,
              itemBuilder: (context, index) =>
                  _ScheduleCard(
                    item: pickups[index],
                    remaining: _remaining(pickups[index]),
                    formattedDate:
                        _formatDateLabel(pickups[index]['date'] as String?),
                  ),
            ),
    );
  }
}

// ── Individual schedule card with live countdown ───────────────────────────────
class _ScheduleCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Duration? remaining;
  final String formattedDate;

  const _ScheduleCard({
    required this.item,
    required this.remaining,
    required this.formattedDate,
  });

  Color _countdownColor() {
    if (remaining == null) return _kTextGray;
    if (remaining!.isNegative) return Colors.red;
    if (remaining!.inMinutes < 15) return Colors.red;
    if (remaining!.inMinutes < 60) return const Color(0xFFF57C00);
    return _kPrimary;
  }

  String _countdownText() {
    if (remaining == null) return '—';
    if (remaining!.isNegative) return 'NOW!';
    final d = remaining!;
    if (d.inDays > 0) {
      return '${d.inDays}d ${d.inHours.remainder(24)}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _frequencyLabel(String freq) {
    switch (freq.toLowerCase()) {
      case 'daily':
        return 'Daily';
      case 'every_3_days':
        return 'Every 3 Days';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'once':
        return 'One-time';
      default:
        return freq;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Scheduled';
      case 'finding':
        return 'Awaiting Admin Assignment';
      case 'assigned':
        return 'Collector Assigned';
      case 'on_way':
        return 'Collector On Way';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this schedule?'),
        content: const Text('This recurring pickup will stop. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Schedule', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppProvider>().cancelSchedule(id);
      messenger.showSnackBar(const SnackBar(content: Text('Schedule cancelled')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not cancel: ${e.toString().replaceFirst('Exception: ', '')}'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return _kPrimary;
      case 'cancelled':
        return Colors.red;
      case 'finding':
        return const Color(0xFFF57C00);
      case 'assigned':
      case 'on_way':
        return const Color(0xFF1565C0);
      default:
        return _kTextGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _countdownColor();
    final status = (item['status'] as String?) ?? 'pending';
    final isRecurring = (item['isRecurring'] as bool?) ?? false;
    final freq = (item['frequency'] as String?) ?? 'once';
    final price = item['price'];
    final binTypeName = (item['binTypeName'] as String?) ?? '';
    final wasteType = (item['wasteType'] as String?) ?? 'General';
    final time = (item['time'] as String?) ?? '';
    final paymentPeriod = (item['payment_period'] as String?) ?? '';
    final isNow =
        remaining != null && remaining!.isNegative;
    final isUrgent =
        remaining != null && !remaining!.isNegative && remaining!.inMinutes < 15;

    // Day chip data
    String shortDay = '';
    final dateStr = item['date'] as String?;
    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateStr);
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        shortDay = days[dt.weekday - 1];
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isNow
            ? const Color(0xFFFFF3E0)
            : isUrgent
                ? const Color(0xFFFFF8F8)
                : _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isNow
              ? const Color(0xFFFFCC80)
              : isUrgent
                  ? const Color(0xFFFFCDD2)
                  : const Color(0xFFE8F5E9),
          width: isNow || isUrgent ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (shortDay.isNotEmpty)
                      Text(
                        shortDay,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    Icon(Icons.calendar_month,
                        color: color, size: 20),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wasteType,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _kTextDark),
                    ),
                    if (binTypeName.isNotEmpty)
                      Text(
                        binTypeName,
                        style: const TextStyle(
                            color: _kTextGray, fontSize: 12),
                      ),
                    Text(
                      formattedDate.isNotEmpty
                          ? '$formattedDate  ·  $time'
                          : time,
                      style: const TextStyle(
                          color: _kTextGray, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(price, prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _kPrimary),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Countdown row
          if (status == 'pending' || status == 'finding') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    isNow
                        ? Icons.alarm_on_outlined
                        : Icons.timer_outlined,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isNow
                        ? 'Request placed — awaiting admin assignment!'
                        : isUrgent
                            ? 'Due very soon — '
                            : 'Pickup in: ',
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                  if (!isNow)
                    Text(
                      _countdownText(),
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Active pickup — let the customer track the collector live
          if (status == 'assigned' || status == 'on_way' || status == 'arrived') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/home', (route) => false,
                ),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Track on Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (status == 'pending') ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmCancel(context),
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                label: const Text('Cancel Schedule', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Recurring + payment info
          if (isRecurring) ...[
            Row(
              children: [
                const Icon(Icons.refresh,
                    size: 14, color: _kTextGray),
                const SizedBox(width: 6),
                Text(
                  'Recurring: ${_frequencyLabel(freq)}',
                  style: const TextStyle(
                      color: _kTextGray, fontSize: 12),
                ),
                if (paymentPeriod.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.payments_outlined,
                      size: 14, color: _kTextGray),
                  const SizedBox(width: 4),
                  Text(
                    _paymentPeriodLabel(paymentPeriod),
                    style: const TextStyle(
                        color: _kTextGray, fontSize: 12),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _paymentPeriodLabel(String period) {
    switch (period.toLowerCase()) {
      case 'per_pickup':
        return 'Pay per pickup';
      case 'weekly':
        return 'Weekly payment';
      case 'monthly':
        return 'Monthly payment';
      default:
        return period;
    }
  }
}
