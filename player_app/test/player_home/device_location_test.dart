import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/device_location.dart';
import 'package:gameall_player/features/player_home/presentation/widgets/player_search_bar.dart';

class _Fake implements DeviceLocation {
  @override
  Future<(double, double)?> currentPosition() async => null;
  _Fake(this.outcome);
  final LocationOutcome outcome;
  int settingsOpened = 0;
  @override
  Future<LocationOutcome> detectCity() async => outcome;
  @override
  Future<void> openSettings() async => settingsOpened++;
}

Future<ProviderContainer> _open(WidgetTester tester, _Fake fake) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [deviceLocationProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showCityPicker(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  group('nearestCity', () {
    test('a position in a city picks that city', () {
      expect(nearestCity(13.05, 80.25), 'Chennai, Tamil Nadu');
      expect(nearestCity(12.93, 77.62), 'Bangalore, Karnataka');
      expect(nearestCity(19.12, 72.85), 'Mumbai, Maharashtra');
    });

    test('a suburb a little way out still belongs to the city', () {
      // Tambaram, about 25 km from the Chennai centre
      expect(nearestCity(12.9249, 80.1), 'Chennai, Tamil Nadu');
    });

    test('far from every city is not matched', () {
      expect(nearestCity(27.1767, 78.0081), isNull); // Agra
      expect(nearestCity(0, 0), isNull);
    });

    test('every picker city has a centre', () {
      for (final c in playerCities) {
        expect(cityCentres.containsKey(c), isTrue, reason: c);
      }
    });
  });

  group('Use my current location', () {
    testWidgets('picks the detected city and closes the picker', (
      tester,
    ) async {
      final c = await _open(tester, _Fake(const LocationFound('Pune, Maharashtra')));
      await tester.tap(find.byKey(const ValueKey('city-use-location')));
      await tester.pumpAndSettle();
      expect(c.read(selectedCityProvider), 'Pune, Maharashtra');
      expect(find.text('Choose your city'), findsNothing);
    });

    testWidgets('outside the service area says so and keeps the list', (
      tester,
    ) async {
      final c = await _open(tester, _Fake(const LocationOutsideService()));
      await tester.tap(find.byKey(const ValueKey('city-use-location')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('city-location-note')), findsOneWidget);
      expect(find.text('Choose your city'), findsOneWidget);
      expect(c.read(selectedCityProvider), playerCities.first);
    });

    testWidgets('a blocked permission offers the settings', (tester) async {
      final fake = _Fake(const LocationBlocked());
      await _open(tester, fake);
      await tester.tap(find.byKey(const ValueKey('city-use-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('city-open-settings')));
      expect(fake.settingsOpened, 1);
    });
  });
}
