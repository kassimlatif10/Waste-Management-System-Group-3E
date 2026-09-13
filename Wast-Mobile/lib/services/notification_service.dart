import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wastmobile/services/sound_service.dart';

/// Handles local (on-device) push notifications with normal and loud alarm channels.
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static Completer<void>? _initCompleter;

  static const _channelId = 'wastepick_main';
  static const _channelName = 'WastePick Alerts';
  static const _channelDesc = 'Pickup status and account notifications';

  static const _alarmChannelId = 'wastepick_collector_alarm';
  static const _alarmChannelName = 'Collector Request Alarm';
  static const _alarmChannelDesc = 'Loud alerts when a new pickup request arrives';

  static String? _lastRequestStatus;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      // Allow notifications to appear (banner + sound) while app is in the foreground.
      // Without these three flags, iOS silently drops every local notification the
      // moment the app is active — which is exactly when our polling fires them.
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );

    try {
      await _plugin
          .initialize(settings: const InitializationSettings(android: android, iOS: ios))
          .timeout(const Duration(seconds: 5));

      if (Platform.isAndroid) {
        final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('notification'),
            enableVibration: true,
          ),
        );

        await androidPlugin?.createNotificationChannel(
          AndroidNotificationChannel(
            _alarmChannelId,
            _alarmChannelName,
            description: _alarmChannelDesc,
            importance: Importance.max,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('alarm'),
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800, 400, 800]),
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );

        await androidPlugin?.requestNotificationsPermission().timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
      }
    } catch (e) {
      debugPrint('NotificationService failed to initialize: $e');
    } finally {
      _initialized = true;
      _initCompleter?.complete();
      _initCompleter = null;
    }
  }

  static Future<void> show(String title, String body, {int id = 0}) async {
    SoundService.playNotification();
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Loud alarm notification for collectors — high priority + looping in-app audio.
  static Future<void> showCollectorAlarm(String title, String body, {int id = 10}) async {
    await SoundService.playCollectorAlarm();
    if (!_initialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: _alarmChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800, 400, 800]),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      ticker: 'New pickup request',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  static void onRequestStatusChanged(
    String? newStatus, {
    String? collectorName,
  }) {
    if (newStatus == null || newStatus == _lastRequestStatus) return;
    final previous = _lastRequestStatus;
    _lastRequestStatus = newStatus;

    switch (newStatus) {
      case 'proposed':
        show(
          'Collector Found!',
          collectorName != null
              ? '$collectorName has been matched to your request. Please confirm.'
              : 'A collector has been matched to your request. Please confirm.',
          id: 1,
        );
      case 'assigned':
        if (previous == 'proposed') {
          show('Confirmed!', 'Your collector is heading to you.', id: 2);
        }
      case 'on_way':
        show(
          'Collector On the Way',
          '${collectorName ?? "Your collector"} is heading to your location.',
          id: 3,
        );
      case 'arrived':
        show(
          'Collector Has Arrived',
          '${collectorName ?? "Your collector"} is at your location.',
          id: 4,
        );
      case 'completed':
        show(
          'Pickup Completed!',
          'Your waste has been collected. Please rate your experience.',
          id: 5,
        );
      case 'cancelled':
        show('Pickup Cancelled', 'Your pickup request was cancelled.', id: 6);
    }
  }

  static void onIncomingRequestChanged({
    bool hasNew = false,
    String? customerName,
  }) {
    if (hasNew) {
      showCollectorAlarm(
        'New Pickup Request!',
        customerName != null
            ? 'New request from $customerName near you. Tap to accept.'
            : 'A new pickup request is near your location. Tap to accept.',
        id: 10,
      );
    } else {
      SoundService.stopAlarm();
      _plugin.cancel(id: 10);
    }
  }

  static void reset() {
    _lastRequestStatus = null;
    SoundService.stopAlarm();
  }

  // ── Permission helpers ──────────────────────────────────────────────────────

  static Future<bool> _checkPermissions() async {
    try {
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final status = await ios?.checkPermissions();
        return status?.isEnabled == true;
      } else if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? true;
      }
    } catch (_) {}
    return true;
  }

  static Future<void> _requestSystemPermissions() async {
    try {
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      } else if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      }
    } catch (_) {}
  }

  /// Show a one-time notification permission prompt after login.
  /// On first call: explains the benefit then triggers the system dialog.
  /// If the user previously denied: offers a "Open Settings" shortcut.
  static Future<void> promptIfNeeded(BuildContext context) async {
    if (!_initialized) await initialize();

    final hasPermission = await _checkPermissions();
    if (hasPermission) return;

    if (!context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool('_notif_permission_prompted') ?? false;

    if (!context.mounted) return;

    if (alreadyAsked) {
      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(Icons.notifications_off_outlined, color: Colors.orange[700]),
            const SizedBox(width: 10),
            const Text('Notifications Off'),
          ]),
          content: const Text(
            'Enable notifications in Settings so you never miss a pickup alert or status update.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (goToSettings == true) {
        final uri = Uri.parse(Platform.isIOS ? 'app-settings:' : 'package:com.wastepick.app');
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      }
      return;
    }

    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.notifications_active_outlined, color: Color(0xFF2E7D32)),
          SizedBox(width: 10),
          Text('Stay Updated'),
        ]),
        content: const Text(
          'Allow notifications so we can alert you when your waste is being collected, '
          'track your collector in real-time, and send pickup status updates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    await prefs.setBool('_notif_permission_prompted', true);

    if (allow == true) {
      await _requestSystemPermissions();
    }
  }
}
