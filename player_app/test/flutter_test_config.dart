import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Manrope font for every test, so text is measured with the real typeface (the default test font has
/// much wider letters and would make layouts look like they overflow when they do not).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  await loader.load();
  await testMain();
}
