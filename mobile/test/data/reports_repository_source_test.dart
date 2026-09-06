import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reports & Analytics — Phase 9.1.
///
/// This project has no fake/mock Supabase client (see
/// finance_repository_source_test.dart for the precedent), and this phase
/// adds no mocking dependency, so the RPC-contract cases are static checks
/// on the repository source itself. Model row-mapping is covered separately
/// by analytics_models_test.dart.
///
/// Mirrors src/services/reports/supabase-reports.service.test.ts:
///   (a) each RPC is called by its exact name;
///   (b) analytics RPCs get the full scoped arg map (date + sport + court);
///   (c) the four reused Finance RPCs get the date-only subset;
///   (d) "Not authorized" -> reportsAccessDenied, never a fabricated zero;
///       "valid start and end date" -> invalidDateRange; else reportsDataError;
///   (e) the repository does no analytics math.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/reports_repository.dart').readAsStringSync();
  });

  group('scoped args', () {
    test('every analytics RPC uses the shared _scopedArgs helper', () {
      const scoped = [
        'get_analytics_overview',
        'get_booking_analytics',
        'get_booking_trend',
        'get_bookings_by_sport',
        'get_booking_source_split',
        'get_overall_utilization',
        'get_court_utilization',
        'get_sport_utilization',
        'get_peak_hours',
        'get_demand_heatmap',
        'get_revenue_by_sport',
        'get_revenue_by_court',
        'get_membership_session_analytics',
        'get_guest_release_analytics',
        'get_guest_booking_analytics',
        'get_guest_bookings_by_sport',
        'get_guest_bookings_by_court',
        'get_guest_peak_hours',
      ];
      for (final rpc in scoped) {
        // Direct `params: _scopedArgs(...)` OR spread `params: {..._scopedArgs(...)`
        // (the trend RPCs add p_granularity).
        final direct = source.contains("'$rpc', params: _scopedArgs(facilityId, filter)");
        final spread = source.contains("'$rpc',\n        params: {..._scopedArgs(facilityId, filter)");
        expect(direct || spread, isTrue, reason: '$rpc must pass the full scoped args');
      }
    });

    test('_scopedArgs is exactly the six p_-prefixed keys', () {
      final match = RegExp(r'_scopedArgs\(String facilityId, AnalyticsFilter f\) => \{([\s\S]*?)\};').firstMatch(source);
      expect(match, isNotNull);
      final keys = RegExp(r"'(p_\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(keys, {
        'p_facility_id',
        'p_preset',
        'p_start_date',
        'p_end_date',
        'p_facility_sport_id',
        'p_court_id',
      });
    });

    test('the trend RPCs also pass p_granularity', () {
      expect(source, contains("'get_booking_trend',\n        params: {..._scopedArgs(facilityId, filter), 'p_granularity': granularity.toJson()}"));
      expect(source, contains("'get_revenue_trend',\n        params: {..._dateArgs(facilityId, filter), 'p_granularity': granularity.toJson()}"));
    });
  });

  group('reused Finance RPCs use the date-only args', () {
    test('get_finance_summary / _revenue_trend / _revenue_breakdown / _payment_method_breakdown use _dateArgs', () {
      for (final rpc in [
        'get_finance_summary',
        'get_revenue_breakdown',
        'get_payment_method_breakdown',
        'get_membership_analytics',
        'get_memberships_by_type',
      ]) {
        expect(
          source.contains("'$rpc', params: _dateArgs(facilityId, filter)"),
          isTrue,
          reason: '$rpc must use date-only args',
        );
      }
      // get_revenue_trend adds p_granularity to the date-only args.
      expect(source, contains("'get_revenue_trend',\n        params: {..._dateArgs(facilityId, filter)"));
    });

    test('_dateArgs is exactly the four date keys (no sport/court)', () {
      final match = RegExp(r'_dateArgs\(String facilityId, AnalyticsFilter f\) => \{([\s\S]*?)\};').firstMatch(source);
      final keys = RegExp(r"'(p_\w+)':").allMatches(match!.group(1)!).map((m) => m.group(1)).toSet();
      expect(keys, {'p_facility_id', 'p_preset', 'p_start_date', 'p_end_date'});
    });
  });

  group('error mapping', () {
    test('"Not authorized" -> reportsAccessDenied', () {
      expect(source, contains("message.contains('Not authorized')"));
      expect(source, contains('AppErrorCode.reportsAccessDenied'));
    });
    test('"valid start and end date" -> invalidDateRange', () {
      expect(source, contains("message.contains('valid start and end date')"));
      expect(source, contains('AppErrorCode.invalidDateRange'));
    });
    test('the fallback is reportsDataError', () {
      expect(source, contains('return AppException(AppErrorCode.reportsDataError);'));
    });
  });

  test('the repository does no analytics math', () {
    // No fold/reduce/sum over amounts or counts anywhere in the repo — every
    // figure returned is an RPC response field mapped straight through.
    expect(source, isNot(contains('.fold(')));
    expect(source, isNot(matches(RegExp(r'\.reduce\('))));
  });
}
