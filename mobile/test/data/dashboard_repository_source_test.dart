import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// This repository has no fake/mock Supabase client set up anywhere in this
/// project (see test/data/membership_repository_source_test.dart for the
/// precedent this follows), so this is a static, dependency-free check on
/// the source itself rather than a call-through test. It guards the thing
/// most likely to silently drift: that confirmed membership sessions keep
/// counting as booked court time. Booked time is now added up by the
/// database (`dashboard_booked_minutes`, migration 0166), which reads
/// `get_membership_utilization_sessions` (migration 0015) itself, while
/// today's timeline and the no-migration fallback still call that RPC here.
void main() {
  late String source;
  late String migration;

  setUpAll(() {
    source = File('lib/data/repositories/dashboard_repository.dart').readAsStringSync().replaceAll('\r\n', '\n');
    migration = File('../supabase/migrations/0166_dashboard_utilization_revenue.sql').readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('getDashboardSummary calls get_membership_utilization_sessions (today\'s timeline)', () {
    expect(source, contains("'get_membership_utilization_sessions'"));
  });

  test('booked court time comes from dashboard_booked_minutes, with the downloaded-rows fallback kept', () {
    expect(source, contains("'dashboard_booked_minutes'"));
    expect(source, contains('_functionMissing'));
  });

  test('the database function counts membership sessions as booked time', () {
    expect(migration, contains('get_membership_utilization_sessions(p_facility_id, p_cur_from_date, p_cur_to_date)'));
    expect(migration, contains('get_membership_utilization_sessions(p_facility_id, p_prev_from_date, p_prev_to_date)'));
  });
}
