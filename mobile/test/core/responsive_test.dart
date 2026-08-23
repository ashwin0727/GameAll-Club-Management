import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/responsive/breakpoints.dart';

void main() {
  group('Breakpoints.classify', () {
    test('classifies a narrow phone width as small', () {
      expect(Breakpoints.classify(320), ScreenSize.small);
      expect(Breakpoints.classify(359), ScreenSize.small);
    });

    test('classifies a typical phone width as medium', () {
      expect(Breakpoints.classify(360), ScreenSize.medium);
      expect(Breakpoints.classify(412), ScreenSize.medium);
      expect(Breakpoints.classify(479), ScreenSize.medium);
    });

    test('classifies a large phone/tablet width as large', () {
      expect(Breakpoints.classify(480), ScreenSize.large);
      expect(Breakpoints.classify(800), ScreenSize.large);
    });
  });
}