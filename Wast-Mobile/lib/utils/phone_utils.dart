import 'package:url_launcher/url_launcher.dart';

/// Opens the dialler for [phone]. No-op if empty or launch fails.
Future<void> callPhone(String phone) async {
  final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (cleaned.isEmpty) return;
  final uri = Uri.parse('tel:$cleaned');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}
