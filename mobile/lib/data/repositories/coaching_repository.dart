import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/coaching.dart';

/// Coaching Management — mirrors src/services/coaching/supabase-coaching.service.ts.
///
/// A read/write layer over the RPCs in migrations 0082-0086. Every RPC
/// self-enforces the caller's permission (has_permission), the slot-conflict
/// gate (_validate_coaching_slot) and capacity — this class only maps rows
/// and errors. Money is in integer minor units (paise).
class CoachingRepository {
  CoachingRepository(this._client);

  final SupabaseClient _client;

  AppException _map(Object e) {
    if (e is AppException) return e;
    final msg = e is PostgrestException ? e.message : e.toString();
    final code = e is PostgrestException ? e.code : null;
    if (code == '42501' || msg.contains('permission')) {
      return AppException(AppErrorCode.unauthorized, msg);
    }
    if (e is PostgrestException) return AppException(AppErrorCode.databaseError, msg);
    return AppException(AppErrorCode.network);
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List<dynamic>? ?? const []).map((r) => (r as Map).cast<String, dynamic>()).toList();
  Map<String, dynamic> _obj(dynamic data) => (data as Map).cast<String, dynamic>();

  // ── Overview / reports ──────────────────────────────────────────────────
  Future<CoachingOverview> getOverview(String facilityId) async {
    try {
      final data = await _client.rpc('get_coaching_overview', params: {'p_facility_id': facilityId});
      return CoachingOverview.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<CoachingReports> getReports(String facilityId, {String? preset}) async {
    try {
      final data = await _client.rpc('get_coaching_reports', params: {
        'p_facility_id': facilityId,
        'p_preset': preset ?? 'THIS_MONTH',
        'p_start_date': null,
        'p_end_date': null,
      });
      return CoachingReports.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Coaches ─────────────────────────────────────────────────────────────
  Future<CoachPage> listCoaches({
    required String facilityId,
    String? search,
    CoachStatus? status,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_coaches', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_status': status?.toJson(),
        'p_specialization': null,
        'p_limit': limit,
        'p_offset': offset,
      });
      return CoachPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<CoachDetail> getCoach(String coachId) async {
    try {
      final data = await _client.rpc('get_coach', params: {'p_coach_id': coachId});
      return CoachDetail.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<List<CoachCandidate>> listCoachCandidates(String facilityId) async {
    try {
      final rows = await _client.rpc('list_coach_candidates', params: {'p_facility_id': facilityId});
      return _rows(rows).map(CoachCandidate.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<List<CoachOption>> listCoachOptions(String facilityId) async {
    try {
      final rows = await _client.rpc('list_coach_options', params: {'p_facility_id': facilityId});
      return _rows(rows).map(CoachOption.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> addCoach({
    required String facilityId,
    required String userId,
    String? specialization,
    double? experienceYears,
    String? certifications,
    String? bio,
    int? hourlyRateMinor,
    CoachStatus status = CoachStatus.active,
  }) async {
    try {
      final row = await _client.rpc('add_coach', params: {
        'p_facility_id': facilityId,
        'p_user_id': userId,
        'p_specialization': specialization,
        'p_experience_years': experienceYears,
        'p_certifications': certifications,
        'p_bio': bio,
        'p_hourly_rate_minor': hourlyRateMinor,
        'p_status': status.toJson(),
        'p_joined_on': null,
      });
      return _obj(row)['id'] as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateCoach({
    required String coachId,
    String? specialization,
    double? experienceYears,
    String? certifications,
    String? bio,
    int? hourlyRateMinor,
    CoachStatus? status,
  }) async {
    try {
      await _client.rpc('update_coach', params: {
        'p_coach_id': coachId,
        'p_specialization': specialization,
        'p_experience_years': experienceYears,
        'p_certifications': certifications,
        'p_bio': bio,
        'p_hourly_rate_minor': hourlyRateMinor,
        'p_status': status?.toJson(),
        'p_joined_on': null,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> setCoachAvailability(String coachId, List<AvailabilityWindow> windows) async {
    try {
      await _client.rpc('set_coach_availability', params: {
        'p_coach_id': coachId,
        'p_windows': windows.map((w) => w.toPayload()).toList(),
      });
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Programs ────────────────────────────────────────────────────────────
  Future<ProgramPage> listPrograms({
    required String facilityId,
    String? search,
    ProgramStatus? status,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_coaching_programs', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_status': status?.toJson(),
        'p_limit': limit,
        'p_offset': offset,
      });
      return ProgramPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<ProgramDetail> getProgram(String programId) async {
    try {
      final data = await _client.rpc('get_coaching_program', params: {'p_program_id': programId});
      return ProgramDetail.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<List<ProgramOption>> listProgramOptions(String facilityId) async {
    try {
      final rows = await _client.rpc('list_coaching_program_options', params: {'p_facility_id': facilityId});
      return _rows(rows).map(ProgramOption.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> createProgram({
    required String facilityId,
    required String name,
    String level = 'All Levels',
    String ageGroup = 'All Ages',
    String category = 'General',
    String? description,
    int defaultDurationMinutes = 60,
    int defaultCapacity = 1,
    int? sessionCount,
    int? defaultPriceMinor,
    bool isMembershipIncluded = false,
  }) async {
    try {
      final row = await _client.rpc('create_coaching_program', params: {
        'p_facility_id': facilityId,
        'p_name': name,
        'p_level': level,
        'p_age_group': ageGroup,
        'p_category': category,
        'p_description': description,
        'p_facility_sport_id': null,
        'p_default_duration_minutes': defaultDurationMinutes,
        'p_default_capacity': defaultCapacity,
        'p_session_count': sessionCount,
        'p_default_price_minor': defaultPriceMinor,
        'p_is_membership_included': isMembershipIncluded,
      });
      return _obj(row)['id'] as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateProgram({
    required String programId,
    String? name,
    String? level,
    String? ageGroup,
    String? category,
    String? description,
    int? defaultDurationMinutes,
    int? defaultCapacity,
    int? sessionCount,
    int? defaultPriceMinor,
    ProgramStatus? status,
  }) async {
    try {
      await _client.rpc('update_coaching_program', params: {
        'p_program_id': programId,
        'p_name': name,
        'p_level': level,
        'p_age_group': ageGroup,
        'p_category': category,
        'p_description': description,
        'p_facility_sport_id': null,
        'p_default_duration_minutes': defaultDurationMinutes,
        'p_default_capacity': defaultCapacity,
        'p_session_count': sessionCount,
        'p_default_price_minor': defaultPriceMinor,
        'p_is_membership_included': null,
        'p_status': status?.toJson(),
      });
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Sessions ────────────────────────────────────────────────────────────
  Future<SessionPage> listSessions({
    required String facilityId,
    DateTime? from,
    DateTime? to,
    String? coachId,
    String? programId,
    SessionStatus? status,
    int limit = 200,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_coaching_sessions', params: {
        'p_facility_id': facilityId,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
        'p_coach_id': coachId,
        'p_program_id': programId,
        'p_court_id': null,
        'p_status': status?.toJson(),
        'p_limit': limit,
        'p_offset': offset,
      });
      return SessionPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<SessionDetail> getSession(String sessionId) async {
    try {
      final data = await _client.rpc('get_coaching_session', params: {'p_session_id': sessionId});
      return SessionDetail.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> createSession({
    required String facilityId,
    required String programId,
    required String coachId,
    required String courtId,
    required DateTime startAt,
    required DateTime endAt,
    int? capacity,
    String? notes,
    String? objective,
    bool confirmNow = false,
    bool autoEnroll = true,
  }) async {
    try {
      final row = await _client.rpc('create_coaching_session', params: {
        'p_facility_id': facilityId,
        'p_program_id': programId,
        'p_coach_id': coachId,
        'p_court_id': courtId,
        'p_start_at': startAt.toUtc().toIso8601String(),
        'p_end_at': endAt.toUtc().toIso8601String(),
        'p_capacity': capacity,
        'p_notes': notes,
        'p_objective': objective,
        'p_status': confirmNow ? 'CONFIRMED' : 'SCHEDULED',
        'p_auto_enroll': autoEnroll,
      });
      return _obj(row)['id'] as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> rescheduleSession({
    required String sessionId,
    String? coachId,
    String? courtId,
    DateTime? startAt,
    DateTime? endAt,
    int? capacity,
  }) async {
    try {
      await _client.rpc('reschedule_coaching_session', params: {
        'p_session_id': sessionId,
        'p_coach_id': coachId,
        'p_court_id': courtId,
        'p_start_at': startAt?.toUtc().toIso8601String(),
        'p_end_at': endAt?.toUtc().toIso8601String(),
        'p_capacity': capacity,
        'p_notes': null,
        'p_objective': null,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> setSessionStatus(String sessionId, String status) async {
    try {
      await _client.rpc('set_coaching_session_status', params: {'p_session_id': sessionId, 'p_status': status});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> completeSession(String sessionId, {String? notes, String? objectiveResult}) async {
    try {
      await _client.rpc('complete_coaching_session', params: {
        'p_session_id': sessionId,
        'p_notes': notes,
        'p_objective_result': objectiveResult,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> cancelSession(String sessionId, String reason) async {
    try {
      await _client.rpc('cancel_coaching_session', params: {'p_session_id': sessionId, 'p_reason': reason});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> addSessionStudent(String sessionId, String enrollmentId) async {
    try {
      await _client.rpc('add_session_student', params: {'p_session_id': sessionId, 'p_enrollment_id': enrollmentId});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> removeSessionStudent(String sessionId, String enrollmentId) async {
    try {
      await _client.rpc('remove_session_student', params: {'p_session_id': sessionId, 'p_enrollment_id': enrollmentId});
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Enrollments ─────────────────────────────────────────────────────────
  Future<EnrollmentPage> listEnrollments({
    required String facilityId,
    String? search,
    String? programId,
    EnrollmentStatus? status,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_coaching_enrollments', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_program_id': programId,
        'p_status': status?.toJson(),
        'p_limit': limit,
        'p_offset': offset,
      });
      return EnrollmentPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<EnrollmentDetail> getEnrollment(String enrollmentId) async {
    try {
      final data = await _client.rpc('get_coaching_enrollment', params: {'p_enrollment_id': enrollmentId});
      return EnrollmentDetail.fromJson(_obj(data));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> createEnrollment({
    required String facilityId,
    required String memberId,
    required String programId,
    String? coachId,
    String? startDate,
    String? endDate,
    int? sessionsTotal,
    int? priceMinor,
    String? pricingType,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('create_coaching_enrollment', params: {
        'p_facility_id': facilityId,
        'p_member_id': memberId,
        'p_program_id': programId,
        'p_coach_id': coachId,
        'p_start_date': startDate,
        'p_end_date': endDate,
        'p_sessions_total': sessionsTotal,
        'p_price_minor': priceMinor,
        'p_pricing_type': pricingType,
        'p_notes': notes,
      });
      return _obj(row)['id'] as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateEnrollment({
    required String enrollmentId,
    String? coachId,
    String? startDate,
    String? endDate,
    int? sessionsTotal,
    int? priceMinor,
    String? notes,
  }) async {
    try {
      await _client.rpc('update_coaching_enrollment', params: {
        'p_enrollment_id': enrollmentId,
        'p_coach_id': coachId,
        'p_start_date': startDate,
        'p_end_date': endDate,
        'p_sessions_total': sessionsTotal,
        'p_price_minor': priceMinor,
        'p_notes': notes,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> setEnrollmentStatus(String enrollmentId, String status, {String? reason}) async {
    try {
      await _client.rpc('set_coaching_enrollment_status', params: {
        'p_enrollment_id': enrollmentId,
        'p_status': status,
        'p_reason': reason,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  // ── Progress ────────────────────────────────────────────────────────────
  Future<void> addProgressNote({
    required String enrollmentId,
    required String note,
    String? skillOrGoal,
    String progressStatus = 'ON_TRACK',
    String? sessionId,
  }) async {
    try {
      await _client.rpc('add_progress_note', params: {
        'p_enrollment_id': enrollmentId,
        'p_note': note,
        'p_skill_or_goal': skillOrGoal,
        'p_progress_status': progressStatus,
        'p_session_id': sessionId,
      });
    } catch (e) {
      throw _map(e);
    }
  }
}
