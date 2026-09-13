import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

const Color _kBg      = Color(0xFFF0F7F0);
const Color _kCard    = Colors.white;
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBlue    = Color(0xFF1565C0);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AppProvider>().fetchNotifications();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final notifications = provider.notifications;

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
          'Notifications',
          style: TextStyle(
              color: _kTextDark, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (notifications.any((n) => n['read'] != true))
            TextButton(
              onPressed: () => provider.markAllNotificationsRead(),
              child: const Text('Mark all read',
                  style: TextStyle(
                      color: _kPrimary, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPrimary))
          : notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No notifications yet',
                          style:
                              TextStyle(color: _kTextGray, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text('We\'ll notify you about your pickups here',
                          style: TextStyle(
                              color: _kTextGray, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final item = notifications[index];
                    final isRead = item['read'] == true;
                    final type = (item['type'] as String?) ?? 'general';
                    final icon = _iconFor(type);
                    final iconColor = _colorFor(type);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isRead
                            ? _kCard
                            : _kBlue.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isRead
                              ? Colors.transparent
                              : _kBlue.withValues(alpha: 0.15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
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
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: iconColor, size: 20),
                        ),
                        title: Text(
                          item['title']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                            fontSize: 14,
                            color: _kTextDark,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 3),
                            Text(
                              item['message']?.toString() ?? '',
                              style: const TextStyle(
                                  color: _kTextGray, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['time']?.toString() ?? '',
                              style: const TextStyle(
                                  color: _kTextGray, fontSize: 11),
                            ),
                          ],
                        ),
                        trailing: isRead
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: _kBlue, shape: BoxShape.circle),
                              ),
                      ),
                    );
                  },
                ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'request': return Icons.local_shipping_outlined;
      case 'payment': return Icons.payments_outlined;
      case 'system':  return Icons.info_outline;
      default:        return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'request': return _kPrimary;
      case 'payment': return Colors.orange;
      case 'system':  return _kBlue;
      default:        return _kTextGray;
    }
  }
}
