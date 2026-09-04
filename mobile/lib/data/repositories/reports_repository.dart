import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/analytics.dart';

/// Reports & Analytics — Flutter port (Phase 9). Mirrors
/// src/services/reports/supabase-reports.service.ts.
///
/// A pure read layer over the analytics RPCs (migrations 0056–0063), plus
/// the four Finance RPCs the Revenue report reuses verbatim
/// (`get_finance_summary`, `get_revenue_trend`, `get_revenue_breakdown`,
/// `get_payment_method_breakdown`) so Reports revenue == Finance revenue.
///
/// The one rule this file enforces: **it never does analytics math**. There
/// is no method here that counts, sums or averages a record — every number
/// returned is an RPC response field (web spec §32 "Data Architecture").
///
/// Date ranges are never resolved here: the client sends a preset name (plus
/// explicit CUSTOM dates) and resolve_finance_date_range turns it into real
/// timestamps in the FACILITY's timezone.
class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  /// The full arg map every analytics RPC shares — date range + sport/court
  /// scope, built one way so a summary, a trend and a table for one filter
  /// can never disagree about what that filter is. Mirrors the web service's
  /// `dateRangeArgs` + `scopeArgs`.
  Map<String, dynamic> _scopedArgs(String facilityId, AnalyticsFilter f) => {
        'p_facility_id': facilityId,
        'p_preset': f.preset.toJson(),
        'p_start_date': f.startDate,
        'p_end_date': f.endDate,
        'p_facility_sport_id': f.facilitySportId,
        'p_court_id': f.courtId,
      };

  /// The date-only subset — for the Finance RPCs the Revenue report reuses,
  /// which take no sport/court.
  Map<String, dynamic> _dateArgs(String facilityId, AnalyticsFilter f) => {
        'p_facility_id': facilityId,
        'p_preset': f.preset.toJson(),
        'p_start_date': f.startDate,
        'p_end_date': f.endDate,
      };

  /// Mirrors the web service's `mapError`. A facility-isolation rejection is
  /// its own code — the UI must show a denial, never a fabricated zero.
  AppException _mapError(Object error) {
    if (error is AppException) return error;
    final message = error is PostgrestException ? error.message : error.toString();
    if (message.contains('Not authorized')) return AppException(AppErrorCode.reportsAccessDenied);
    if (message.contains('valid start and end date')) return AppException(AppErrorCode.invalidDateRange);
    return AppException(AppErrorCode.reportsDataError);
  }

  /// `returns table (...)` single-row aggregates always have exactly one row.
  /// An empty result means the call did not produce what it promised.
  Map<String, dynamic> _firstRow(dynamic data) {
    if (data is List && data.isNotEmpty) {
      return (data.first as Map).cast<String, dynamic>();
    }
    throw AppException(AppErrorCode.reportsDataError);
  }

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List<dynamic>)
      .map((row) => (row as Map).cast<String, dynamic>())
      .toList();

  // ─── Overview ─────────────────────────────────────────────────────────

  Future<AnalyticsOverview> getAnalyticsOverview(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_analytics_overview', params: _scopedArgs(facilityId, filter));
      return AnalyticsOverview.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─── Bookings ─────────────────────────────────────────────────────────

  Future<BookingAnalytics> getBookingAnalytics(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_booking_analytics', params: _scopedArgs(facilityId, filter));
      return BookingAnalytics.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<BookingTrendPoint>> getBookingTrend(
    String facilityId,
    AnalyticsFilter filter,
    RevenueTrendGranularity granularity,
  ) async {
    try {
      final data = await _client.rpc(
        'get_booking_trend',
        params: {..._scopedArgs(facilityId, filter), 'p_granularity': granularity.toJson()},
      );
      return _rows(data).map(BookingTrendPoint.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<BookingsBySportRow>> getBookingsBySport(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_bookings_by_sport', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(BookingsBySportRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<BookingSourceRow>> getBookingSourceSplit(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_booking_source_split', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(BookingSourceRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─── Court Utilization ────────────────────────────────────────────────

  Future<OverallUtilization> getOverallUtilization(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_overall_utilization', params: _scopedArgs(facilityId, filter));
      return OverallUtilization.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<CourtUtilizationRow>> getCourtUtilization(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_court_utilization', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(CourtUtilizationRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<SportUtilizationRow>> getSportUtilization(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_sport_utilization', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(SportUtilizationRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<PeakHourRow>> getPeakHours(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_peak_hours', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(PeakHourRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<HeatmapCell>> getDemandHeatmap(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_demand_heatmap', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(HeatmapCell.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─── Revenue — the four Finance RPCs reused verbatim (date args only) ──

  Future<RevenueSummary> getRevenueSummary(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_finance_summary', params: _dateArgs(facilityId, filter));
      return RevenueSummary.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<RevenueTrendPoint>> getRevenueTrend(
    String facilityId,
    AnalyticsFilter filter,
    RevenueTrendGranularity granularity,
  ) async {
    try {
      final data = await _client.rpc(
        'get_revenue_trend',
        params: {..._dateArgs(facilityId, filter), 'p_granularity': granularity.toJson()},
      );
      return _rows(data).map(RevenueTrendPoint.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<ReportRevenueBreakdown> getRevenueBreakdown(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_revenue_breakdown', params: _dateArgs(facilityId, filter));
      return ReportRevenueBreakdown.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<PaymentMethodSlice>> getPaymentMethodBreakdown(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_payment_method_breakdown', params: _dateArgs(facilityId, filter));
      return _rows(data).map(PaymentMethodSlice.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─── Revenue — the two new cuts (scoped args) ─────────────────────────

  Future<List<RevenueBySportRow>> getRevenueBySport(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_revenue_by_sport', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(RevenueBySportRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<RevenueByCourtRow>> getRevenueByCourt(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_revenue_by_court', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(RevenueByCourtRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─── Memberships ──────────────────────────────────────────────────────

  Future<MembershipAnalytics> getMembershipAnalytics(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_membership_analytics', params: _dateArgs(facilityId, filter));
      return MembershipAnalytics.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<MembershipTypeRow>> getMembershipsByType(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_memberships_by_type', params: _dateArgs(facilityId, filter));
      return _rows(data).map(MembershipTypeRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<MembershipSessionAnalytics> getMembershipSessionAnalytics(
    String facilityId,
    AnalyticsFilter filter,
  ) async {
    try {
      final data = await _client.rpc('get_membership_session_analytics', params: _scopedArgs(facilityId, filter));
      return MembershipSessionAnalytics.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<GuestReleaseAnalytics> getGuestReleaseAnalytics(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_guest_release_analytics', params: _scopedArgs(facilityId, filter));
      return GuestReleaseAnalytics.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  // ─── Guest Bookings ───────────────────────────────────────────────────

  Future<GuestBookingAnalytics> getGuestBookingAnalytics(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_guest_booking_analytics', params: _scopedArgs(facilityId, filter));
      return GuestBookingAnalytics.fromJson(_firstRow(data));
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<GuestBookingsBySportRow>> getGuestBookingsBySport(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_guest_bookings_by_sport', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(GuestBookingsBySportRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<GuestBookingsByCourtRow>> getGuestBookingsByCourt(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_guest_bookings_by_court', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(GuestBookingsByCourtRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<GuestPeakHourRow>> getGuestPeakHours(String facilityId, AnalyticsFilter filter) async {
    try {
      final data = await _client.rpc('get_guest_peak_hours', params: _scopedArgs(facilityId, filter));
      return _rows(data).map(GuestPeakHourRow.fromJson).toList();
    } catch (e) {
      throw _mapError(e);
    }
  }
}
