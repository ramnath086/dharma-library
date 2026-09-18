import 'package:dharma_library/core/locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('firstRunLocale', () {
    test('saved preference always wins', () {
      expect(firstRunLocale('ml', 'en'), 'ml');
      expect(firstRunLocale('en', 'ml'), 'en');
    });
    test('unsupported saved values reseed from the device', () {
      expect(firstRunLocale('de', 'ml'), 'ml');
      expect(firstRunLocale('de', 'de'), 'en');
    });
    test('Malayalam-first: ml device without a preference starts Malayalam', () {
      expect(firstRunLocale(null, 'ml'), 'ml');
    });
    test('other devices fall back to English', () {
      expect(firstRunLocale(null, 'en'), 'en');
      expect(firstRunLocale(null, 'hi'), 'en');
      expect(firstRunLocale(null, 'ta'), 'en');
    });
  });
}
