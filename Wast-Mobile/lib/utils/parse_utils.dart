import 'package:flutter/material.dart';

// Safe numeric parsing — handles Django's DecimalField returning strings like "4.50"

double parseDouble(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

double? parseDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int parseInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().split('.').first) ?? fallback;
}

/// Formats a raw amount (String/num/null from the API) to a fixed 2-decimal
/// money string with the given currency prefix, e.g. money('1200.5') => '1200.50'.
/// Pass includePrefix: false to get just the number (for cases with existing custom prefix text).
String money(dynamic v, {String prefix = '', String fallback = '—'}) {
  if (v == null) return fallback;
  final d = parseDoubleOrNull(v);
  if (d == null) return v.toString();
  final formatted = d.toStringAsFixed(2);
  return prefix.isEmpty ? formatted : '$prefix $formatted';
}

/// Simplifies the backend's 7-value pickup status pipeline
/// (finding/proposed/assigned/on_way/arrived/completed/cancelled) into the
/// 3 states a customer cares about: Pending, Accepted, Declined.
String bookingStatusLabel(String rawStatus) {
  switch (rawStatus.toLowerCase()) {
    case 'finding':
    case 'proposed':
      return 'Pending';
    case 'assigned':
    case 'on_way':
    case 'arrived':
    case 'completed':
      return 'Accepted';
    case 'cancelled':
      return 'Declined';
    default:
      return rawStatus;
  }
}

Color bookingStatusColor(String rawStatus) {
  switch (rawStatus.toLowerCase()) {
    case 'finding':
    case 'proposed':
      return const Color(0xFFE65100); // pending — amber
    case 'assigned':
    case 'on_way':
    case 'arrived':
    case 'completed':
      return const Color(0xFF2E7D32); // accepted — green
    case 'cancelled':
      return Colors.red; // declined
    default:
      return const Color(0xFF757575);
  }
}
