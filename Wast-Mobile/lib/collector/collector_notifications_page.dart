import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

const Color _kPrimary    = Color(0xFF2E7D32);
const Color _kBg         = Color(0xFFF0F7F0);
const Color _kTextDark   = Color(0xFF1A1A1A);
const Color _kTextGray   = Color(0xFF757575);
const Color _kLightGreen = Color(0xFFE8F5E9);

class CollectorNotificationsPage extends StatefulWidget {
  const CollectorNotificationsPage({super.key});

  @override
  State<CollectorNotificationsPage> createState() =>
      _CollectorNotificationsPageState();
}

class _CollectorNotificationsPageState
    extends State<CollectorNotificationsPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await context.read<AppProvider>().fetchCollectorNotifications();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p      = context.watch<AppProvider>();
    final items  = p.collectorNotifications;
    final unread = p.collectorUnreadNotifications;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kTextDark,
        elevation: 0,
        title: Column(
          children: [
            const Text('Notifications',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            if (unread > 0)
              Text('$unread unread',
                  style: const TextStyle(color: _kPrimary, fontSize: 11)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () =>
                  context.read<AppProvider>().markAllCollectorNotificationsRead(),
              child: const Text('Mark all read',
                  style: TextStyle(color: _kPrimary, fontSize: 12)),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPrimary))
          : items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 14),
                      const Text('No notifications yet',
                          style: TextStyle(
                              color: _kTextGray, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: _kPrimary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _NotificationCard(
                          item: items[i],
                          onTap: () async {
                            final id = items[i]['id'] as int?;
                            if (id != null) {
                              await context.read<AppProvider>().markCollectorNotificationRead(id);
                            }
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text(items[i]['title'] as String? ?? ''),
                                content: Text(items[i]['message'] as String? ?? ''),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                  ),
                ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  const _NotificationCard({required this.item, this.onTap});

  IconData _icon() {
    switch (item['type'] as String? ?? '') {
      case 'request':  return Icons.local_shipping_outlined;
      case 'payment':  return Icons.payments_outlined;
      case 'schedule': return Icons.calendar_today_outlined;
      default:         return Icons.notifications_outlined;
    }
  }

  Color _iconColor() {
    switch (item['type'] as String? ?? '') {
      case 'request':  return _kPrimary;
      case 'payment':  return const Color(0xFF1565C0);
      case 'schedule': return const Color(0xFF6A1B9A);
      default:         return _kTextGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = item['read'] as bool? ?? false;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : _kLightGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRead
              ? const Color(0xFFE0E0E0)
              : const Color(0xFFA5D6A7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _iconColor().withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon(), color: _iconColor(), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item['title'] as String? ?? '',
                          style: TextStyle(
                              fontWeight: isRead
                                  ? FontWeight.w500
                                  : FontWeight.bold,
                              fontSize: 14,
                              color: _kTextDark)),
                    ),
                    if (!isRead)
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: _kPrimary, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(item['message'] as String? ?? '',
                    style: const TextStyle(
                        color: _kTextGray, fontSize: 13, height: 1.4)),
                const SizedBox(height: 6),
                Text(item['time'] as String? ?? '',
                    style: const TextStyle(
                        color: _kTextGray, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}
