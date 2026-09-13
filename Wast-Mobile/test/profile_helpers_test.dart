import 'package:flutter_test/flutter_test.dart';
import 'package:wastmobile/home/location_picker.dart';

void main() {
  group('looksLikeCoordinates', () {
    test('detects lat,lng pairs', () {
      expect(looksLikeCoordinates('4.90123, -1.75740'), isTrue);
      expect(looksLikeCoordinates('-1.75740,4.90123'), isTrue);
    });

    test('allows normal addresses', () {
      expect(looksLikeCoordinates('Market Circle, Takoradi'), isFalse);
      expect(looksLikeCoordinates('Sekondi-Takoradi, Ghana'), isFalse);
    });
  });
}
