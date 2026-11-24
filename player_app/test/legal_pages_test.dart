import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/utils/legal_links.dart';

// Google Play opens these pages and compares them with the app: they must exist, be about the GameAll player app only, and be served from the
// Play site (play.gameall.co), not the venue website.
void main() {
  const pages = {
    'privacy': 'Privacy Policy',
    'terms': 'Terms & Conditions',
    'refund-policy': 'Cancellation & Refund Policy',
    'delete-account': 'Delete your account',
  };

  for (final e in pages.entries) {
    test('web/${e.key}.html is a GameAll player page', () {
      final html = File('web/${e.key}.html').readAsStringSync();
      expect(html, contains('<h1>${e.value}</h1>'));
      expect(html, contains('GameAll'));
      expect(html, isNot(contains('club.gameall.co')));
      expect(html, isNot(contains('Venue app')));
    });
  }

  test('the refund table keeps 5% at 12 hours or more and 100% under an hour', () {
    final html = File('web/refund-policy.html').readAsStringSync();
    expect(RegExp(r'<tr><td>').allMatches(html).length, 13);
    expect(html, contains('<td>12 hours or more before the start</td><td>5%</td><td>95%</td>'));
    expect(html, contains('<td>Less than 1 hour, or after the start</td><td>100%</td><td>0%</td>'));
  });

  test('the app links to the Play site', () {
    for (final p in LegalPage.values) {
      expect(legalUri(p).host, 'play.gameall.co');
    }
  });
}
