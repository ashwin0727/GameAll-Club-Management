import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// This repository has no fake/mock Supabase client set up anywhere in this
/// project (see test/data/membership_repository_source_test.dart for the
/// precedent this follows), so this is a static, dependency-free check on
/// the source itself rather than a call-through test. It guards the thing
/// most likely to silently drift: that the dashboard summary actually calls
/// `get_membership_utilization_sessions` (see
/// supabase/migrations/0015_membership_utilization.sql) and feeds its
/// result through DashboardCalculator.toUtilizationBookings into the same
/// booking list computeUtilization/buildTodaysSchedule already consume,
/// rather than a second utilization algorithm.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/dashboard_repository.dart').readAsStringSync();
  });

  test('getDashboardSummary calls get_membership_utilization_sessions', () {
    expect(source, contains("'get_membership_utilization_sessions'"));
  });

  test('the RPC result is converted via DashboardCalculator.toUtilizationBookings', () {
    expect(source, contains('DashboardCalculator.toUtilizationBookings('));
  });

  test('the converted membership bookings are merged into the same allBookings list fed to computeUtilization', () {
    expect(source, contains('...membershipUtilizationBookings'));
  });
}