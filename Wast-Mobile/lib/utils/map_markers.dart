import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Shared helpers for Google Maps-style custom markers and polyline styling.
class MapMarkers {
  MapMarkers._();

  static const Color _kBlue = Color(0xFF1A73E8);
  static const Color _kGreen = Color(0xFF2E7D32);

  // ── Blue location dot (user's current GPS position) ───────────────────────
  //
  // Renders:  shadow → white ring (r=20) → colored fill (r=14) → white centre
  static Future<BitmapDescriptor> buildLocationDot({
    Color color = _kBlue,
    int size = 36,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(size / 2.0, size / 2.0);

    // drop shadow
    canvas.drawCircle(
      Offset(c.dx, c.dy + 1.5),
      14,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // white ring
    canvas.drawCircle(c, 14, Paint()..color = Colors.white);
    // colored fill
    canvas.drawCircle(c, 10, Paint()..color = color);
    // inner white highlight
    canvas.drawCircle(c, 3.5, Paint()..color = Colors.white.withValues(alpha: 0.45));

    final img = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  // ── Navigation arrow (collector heading indicator) ────────────────────────
  //
  // Drawn pointing UP; set Marker.rotation = bearing so it faces the right way.
  static Future<BitmapDescriptor> buildNavArrow({
    Color color = _kBlue,
    int size = 40,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cx = size / 2.0;
    final cy = size / 2.0;

    final path = Path()
      ..moveTo(cx, 3)
      ..lineTo(cx + 13, cy + 15)
      ..lineTo(cx, cy + 9)
      ..lineTo(cx - 13, cy + 15)
      ..close();

    // shadow
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // white stroke outline
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    // coloured fill
    canvas.drawPath(path, Paint()..color = color);

    final img = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  // ── Destination pin (teardrop shape) ─────────────────────────────────────
  static Future<BitmapDescriptor> buildDestinationPin({
    Color color = _kGreen,
    int size = 44,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cx = size / 2.0;

    // shadow
    canvas.drawCircle(
      Offset(cx, 17),
      14,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // white border circle
    canvas.drawCircle(Offset(cx, 15), 14, Paint()..color = Colors.white);
    // coloured circle
    canvas.drawCircle(Offset(cx, 15), 10, Paint()..color = color);
    // white inner dot
    canvas.drawCircle(Offset(cx, 15), 3.5, Paint()..color = Colors.white);

    // teardrop tail
    final tail = Path()
      ..moveTo(cx - 5, 26)
      ..quadraticBezierTo(cx, 40, cx, 40)
      ..quadraticBezierTo(cx, 40, cx + 5, 26)
      ..close();
    canvas.drawPath(tail, Paint()..color = color);

    final img = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  // ── Google Maps-style route polylines ────────────────────────────────────
  //
  // Two layers: white shadow (width 10) behind the coloured route (width 6).
  // Both use Cap.roundCap + JointType.round for a smooth, modern look.
  static Set<Polyline> routePolylines({
    required List<LatLng> points,
    Color color = _kBlue,
    String suffix = '',
  }) {
    return {
      Polyline(
        polylineId: PolylineId('route_shadow$suffix'),
        points: points,
        color: Colors.white,
        width: 10,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 0,
      ),
      Polyline(
        polylineId: PolylineId('route$suffix'),
        points: points,
        color: color,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1,
      ),
    };
  }

  // ── Dashed fallback (when Directions API is unavailable) ─────────────────
  static Set<Polyline> fallbackPolylines({
    required List<LatLng> points,
    Color color = _kBlue,
    String suffix = '',
  }) {
    return {
      Polyline(
        polylineId: PolylineId('route$suffix'),
        points: points,
        color: color,
        width: 4,
        patterns: [PatternItem.dash(16), PatternItem.gap(8)],
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 1,
      ),
    };
  }
}
