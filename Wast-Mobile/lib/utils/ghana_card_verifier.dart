import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Matches a Ghana Card number in the form GHA-123456789-0, tolerating the
/// spacing/dash variations OCR commonly produces (e.g. "GHA 123456789 0").
final RegExp ghanaCardNumberPattern = RegExp(r'GHA[\s\-]?(\d{9})[\s\-]?(\d)');

/// Returns the canonical GHA-XXXXXXXXX-X form, or null if [raw] doesn't
/// contain a recognizable Ghana Card number.
String? normalizeGhanaCardNumber(String raw) {
  final match = ghanaCardNumberPattern.firstMatch(raw.toUpperCase());
  if (match == null) return null;
  return 'GHA-${match.group(1)}-${match.group(2)}';
}

bool isValidGhanaCardFormat(String raw) => normalizeGhanaCardNumber(raw) != null;

class GhanaCardVerification {
  /// True when the typed number was found in the scanned photo, OR when
  /// OCR isn't available on this platform (see [supported]) — in which case
  /// the check is skipped rather than blocking registration.
  final bool matched;
  /// False on platforms without on-device text recognition (web/desktop).
  final bool supported;
  const GhanaCardVerification({required this.matched, required this.supported});
}

bool get _ocrSupportedPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Runs on-device OCR (Google ML Kit) over the Ghana Card photo and checks
/// whether the number the collector typed actually appears on the card.
Future<GhanaCardVerification> verifyGhanaCardPhoto(File cardPhoto, String typedNumber) async {
  if (!_ocrSupportedPlatform) {
    // No OCR engine on this platform (e.g. desktop) — don't block registration.
    return const GhanaCardVerification(matched: true, supported: false);
  }

  final typedNormalized = normalizeGhanaCardNumber(typedNumber);
  if (typedNormalized == null) {
    return const GhanaCardVerification(matched: false, supported: true);
  }

  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFile(cardPhoto));
    final foundNumbers = ghanaCardNumberPattern
        .allMatches(result.text.toUpperCase())
        .map((m) => 'GHA-${m.group(1)}-${m.group(2)}');
    return GhanaCardVerification(
      matched: foundNumbers.contains(typedNormalized),
      supported: true,
    );
  } finally {
    await recognizer.close();
  }
}
