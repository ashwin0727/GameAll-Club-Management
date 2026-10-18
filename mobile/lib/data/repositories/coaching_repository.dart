import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import 'dart:typed_data';

import '../../features/coaching/coaching_hub.dart' show ProgramCardStats, StudentCardStats, todaysActiveCount;
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

  /// The sports list the database functions take: null (All Sports) unless a real subset is given.
  List<String>? _sports(List<String>? ids) => (ids == null || ids.isEmpty) ? null : ids;

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List<dynamic>? ?? const []).map((r) => (r as Map).cast<String, dynamic>()).toList();
  Map<String, dynamic> _obj(dynamic data) => (data as Map).cast<String, dynamic>();

  // ── Overview / reports ──────────────────────────────────────────────────
  /// Programs tab cards (migration 0122). Null when the function is not there yet — the tab shows dashes.
  Future<ProgramCardStats?> getProgramCardStats(String facilityId, {List<String>? sportIds}) async {
    try {
      return ProgramCardStats.fromJson(_obj(await _client.rpc('get_program_card_stats', params: {'p_facility_id': facilityId, 'p_facility_sport_ids': _sports(sportIds)})));
    } catch (_) {
      return null;
    }
  }

  /// Students tab cards (migration 0123). Null when the function is not there yet — the tab shows dashes.
  Future<StudentCardStats?> getStudentCardStats(String facilityId, {List<String>? sportIds}) async {
    try {
      return StudentCardStats.fromJson(_obj(await _client.rpc('get_student_card_stats', params: {'p_facility_id': facilityId, 'p_facility_sport_ids': _sports(sportIds)})));
    } catch (_) {
      return null;
    }
  }

  Future<CoachingOverview> getOverview(String facilityId, {List<String>? sportIds}) async {
    try {
      final data = await _client.rpc('get_coaching_overview', params: {'p_facility_id': facilityId, 'p_facility_sport_ids': _sports(sportIds)});
      final json = _obj(data);
      var overview = CoachingOverview.fromJson(json);

      // Active Sessions is the current day's session count, taken from the session list so it follows the
      // same rules as the Sessions page.
      try {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final today = await listSessions(facilityId: facilityId, from: start, to: start.add(const Duration(days: 1)), limit: 500, sportIds: sportIds);
        overview = overview.withActiveSessions(todaysActiveCount(today.sessions));
      } catch (_) {
        overview = overview.withActiveSessions(0);
      }

      // Overall revenue (migration 0115). Missing leaves it null, shown as a dash — never this month's
      // figure passed off as the total.
      try {
        final total = await _client.rpc('get_coaching_total_revenue', params: {'p_facility_id': facilityId, 'p_facility_sport_ids': _sports(sportIds)});
        if (total is num) overview = overview.withRevenueTotal(total.toInt());
      } catch (_) {
        // leave it null
      }
      // Total Coaches + this month's Coaching Expense (migration 0121). Missing leaves both null (a dash).
      try {
        final stats = _obj(await _client.rpc('get_coaching_card_stats', params: {'p_facility_id': facilityId, 'p_facility_sport_ids': _sports(sportIds)}));
        overview = overview.withCardStats(
          totalCoaches: (stats['totalCoaches'] as num?)?.toInt(),
          coachingExpenseMinor: (stats['coachingExpenseMinor'] as num?)?.toInt(),
        );
      } catch (_) {
        // leave both null
      }
      return overview;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<CoachingReports> getReports(String facilityId, {String? preset, List<String>? sportIds}) async {
    try {
      final data = await _client.rpc('get_coaching_reports', params: {
        'p_facility_id': facilityId,
        'p_preset': preset ?? 'THIS_MONTH',
        'p_start_date': null,
        'p_end_date': null,
        'p_facility_sport_ids': _sports(sportIds),
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
    List<String>? sportIds,
  }) async {
    try {
      final rows = await _client.rpc('list_coaches', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_status': status?.toJson(),
        'p_specialization': null,
        'p_limit': limit,
        'p_offset': offset,
        // The full argument list, like the web sends: with only the first six, Postgres can match both
        // this and an older six-argument copy of the function and refuse to pick one.
        'p_sport_id': null,
        'p_sort': 'name_asc',
        'p_facility_sport_ids': _sports(sportIds),
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
    List<String>? sportIds,
    List<String>? expertiseLevels,
    int? defaultSessionDurationMinutes,
    String? dateOfBirth,
  }) async {
    try {
      // Every parameter is sent (like the web does), so the call can only ever match the one add_coach.
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
        'p_sport_ids': sportIds,
        'p_expertise_levels': expertiseLevels,
        'p_default_session_duration_minutes': defaultSessionDurationMinutes,
        'p_date_of_birth': dateOfBirth,
      });
      return _obj(row)['id'] as String;
    } catch (e) {
      throw _map(e);
    }
  }

  /// Removes a student's enrollment while no payment has been received on it (migration 0127).
  Future<void> deleteEnrollment(String enrollmentId) async {
    try {
      await _client.rpc('delete_coaching_enrollment', params: {'p_enrollment_id': enrollmentId});
    } catch (e) {
      throw _map(e);
    }
  }

  /// Removes a program nobody has joined (migration 0126); the database refuses one with any enrollment.
  Future<void> deleteProgram(String programId) async {
    try {
      await _client.rpc('delete_coaching_program', params: {'p_program_id': programId});
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
    List<String>? sportIds,
  }) async {
    try {
      final rows = await _client.rpc('list_coaching_programs', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_status': status?.toJson(),
        'p_limit': limit,
        'p_offset': offset,
        'p_facility_sport_ids': _sports(sportIds),
      });
      return ProgramPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<ProgramDetail> getProgram(String programId) async {
    try {
      final data = await _client.rpc('get_coaching_program', params: {'p_program_id': programId});
      // get_coaching_program predates fee_type (0110) — read it straight from the row.
      final fee = await _client.from('coaching_programs').select('fee_type').eq('id', programId).maybeSingle();
      return ProgramDetail.fromJson({..._obj(data), 'feeType': fee?['fee_type'] ?? 'ONE_TIME'});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<List<ProgramOption>> listProgramOptions(String facilityId) async {
    try {
      final rows = await _client.rpc('list_coaching_program_options', params: {'p_facility_id': facilityId});
      // list_coaching_program_options predates fee_type / end_date (0110) — merge them in from the table.
      final extra = _rows(await _client.from('coaching_programs').select('id, fee_type, start_date, end_date, payment_mode, early_bird_discount_minor, tax_percent').eq('facility_id', facilityId));
      final byId = {for (final r in extra) r['id'] as String: r};
      return _rows(rows).map((r) => ProgramOption.fromJson({...r, ...?byId[r['id']]})).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<List<ProgramBatch>> listProgramBatches(String programId) async {
    try {
      final rows = await _client.rpc('list_coaching_program_batches', params: {'p_program_id': programId});
      return _rows(rows).map(ProgramBatch.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  /// ONE_TIME or MONTHLY. A monthly program needs a start and end date (the database enforces it).
  Future<void> setProgramFeeType(String programId, String feeType) async {
    try {
      await _client.rpc('set_coaching_program_fee_type', params: {'p_program_id': programId, 'p_fee_type': feeType});
    } catch (e) {
      throw _map(e);
    }
  }

  /// Uploads a program picture to the program-images bucket (under the signed-in user's folder) and returns its
  /// public URL — the wizard's optional Program Image.
  Future<String> uploadProgramImage(List<int> bytes, String fileName, String contentType) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw StateError('not signed in');
      final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$uid/${DateTime.now().microsecondsSinceEpoch}-$safe';
      await _client.storage.from('program-images').uploadBinary(path, Uint8List.fromList(bytes), fileOptions: FileOptions(contentType: contentType));
      return _client.storage.from('program-images').getPublicUrl(path);
    } catch (_) {
      throw AppException(AppErrorCode.databaseError, 'Could not upload this image. Please try again.');
    }
  }

  /// A program together with its first batch, atomically — what the web Create Program wizard submits.
  /// [batch] keys: courtId, coachId (nullable), name, daysOfWeek, startTime, endTime, capacity.
  Future<String> createProgramFull({
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
    int? sessionsPerWeek,
    String? startDate,
    String? endDate,
    String paymentMode = 'BOTH',
    int? earlyBirdDiscountMinor,
    String? discountValidTill,
    double? taxPercent,
    String feeType = 'ONE_TIME',
    List<Map<String, dynamic>> batches = const [],
    // What the web wizard also sets — all optional so the older one-screen form keeps working.
    String? facilitySportId,
    String programType = 'GROUP',
    int? minCapacity,
    List<String> programStructure = const [],
    String? sessionFormat,
    String? imageUrl,
    String? paymentNotes,
    bool allowWaitlist = true,
    bool allowTrialSession = false,
    bool autoEnrollNextBatch = false,
    bool sendNotifications = true,
    bool visibleInBooking = false,
    String? enrollmentDeadline,
    String status = 'ACTIVE',
  }) async {
    try {
      final row = await _client.rpc('create_coaching_program_full', params: {
        'p_facility_id': facilityId,
        'p_name': name,
        'p_level': level,
        'p_age_group': ageGroup,
        'p_category': category,
        'p_description': description,
        'p_facility_sport_id': facilitySportId,
        'p_default_duration_minutes': defaultDurationMinutes,
        'p_default_capacity': defaultCapacity,
        'p_session_count': sessionCount,
        'p_default_price_minor': defaultPriceMinor,
        'p_is_membership_included': isMembershipIncluded,
        'p_image_url': imageUrl,
        'p_program_type': programType,
        'p_min_capacity': minCapacity,
        'p_program_structure': programStructure,
        'p_session_format': sessionFormat,
        'p_sessions_per_week': sessionsPerWeek,
        'p_start_date': startDate,
        'p_end_date': endDate,
        'p_payment_mode': paymentMode,
        'p_early_bird_discount_minor': earlyBirdDiscountMinor,
        'p_discount_valid_till': discountValidTill,
        'p_tax_percent': taxPercent,
        'p_payment_notes': paymentNotes,
        'p_allow_waitlist': allowWaitlist,
        'p_allow_trial_session': allowTrialSession,
        'p_auto_enroll_next_batch': autoEnrollNextBatch,
        'p_send_notifications': sendNotifications,
        'p_visible_in_booking': visibleInBooking,
        'p_enrollment_deadline': enrollmentDeadline,
        'p_status': status,
        'p_batches': batches,
      });
      final id = _obj(row)['id'] as String;
      if (feeType != 'ONE_TIME') await setProgramFeeType(id, feeType);
      return id;
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
    int? sessionsPerWeek,
    String? startDate,
    String? endDate,
    String? paymentMode,
    int? earlyBirdDiscountMinor,
    String? discountValidTill,
    double? taxPercent,
    String? feeType,
  }) async {
    try {
      await _client.rpc('update_coaching_program', params: {
        'p_sessions_per_week': sessionsPerWeek,
        'p_start_date': startDate,
        'p_end_date': endDate,
        'p_payment_mode': paymentMode,
        'p_early_bird_discount_minor': earlyBirdDiscountMinor,
        'p_discount_valid_till': discountValidTill,
        'p_tax_percent': taxPercent,
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
      if (feeType != null) await setProgramFeeType(programId, feeType);
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
    List<String>? sportIds,
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
        'p_facility_sport_ids': _sports(sportIds),
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
    String? coachId,
    String? level,
    List<String>? sportIds,

    /// Overrides [status] with a raw filter key — 'NOT_ACTIVE' groups every non-ACTIVE enrollment
    /// (the Manage Students "Inactive" tab).
    String? statusKey,
  }) async {
    try {
      final rows = await _client.rpc('list_coaching_enrollments', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_program_id': programId,
        'p_status': statusKey ?? status?.toJson(),
        'p_limit': limit,
        'p_offset': offset,
        'p_coach_id': coachId,
        'p_level': level,
        'p_facility_sport_ids': _sports(sportIds),
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
    String? batchId,
  }) async {
    try {
      final row = await _client.rpc('create_coaching_enrollment', params: {
        'p_batch_id': batchId,
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
    // A cancelled student must not keep being charged: stop any live Razorpay link/subscription.
    // Best-effort — the status change above already succeeded and the billing card can cancel it again.
    if (status == 'CANCELLED') {
      try {
        await cancelEnrollmentBilling(enrollmentId);
      } on AppException {
        // swallowed on purpose, see above
      }
    }
  }

  // ── Online billing (Razorpay payment link / monthly subscription) ──────
  /// Monthly charges between an enrollment start and a program end. Computed by the database
  /// (coaching_billing_cycles) so the total shown here always equals what the enrollment stores.
  Future<int> getBillingCycles(String startDate, String? endDate) async {
    try {
      final data = await _client.rpc('coaching_billing_cycles', params: {'p_start': startDate, 'p_end': endDate});
      return (data as num).toInt();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<EnrollmentBilling?> getEnrollmentBilling(String enrollmentId) async {
    try {
      final row = await _client
          .from('coaching_enrollment_billing')
          .select('kind, status, amount_minor, total_cycles, charge_count, short_url, current_end')
          .eq('enrollment_id', enrollmentId)
          .maybeSingle();
      return row == null ? null : EnrollmentBilling.fromJson(row);
    } catch (e) {
      throw _map(e);
    }
  }

  /// Creates (or returns the existing) Razorpay link / AutoPay subscription for the enrollment. The
  /// amount is decided server-side from the enrollment — nothing money-related is sent from here.
  Future<void> createEnrollmentBilling(String enrollmentId) =>
      _invokeBilling('create-coaching-enrollment-billing', enrollmentId);

  Future<void> cancelEnrollmentBilling(String enrollmentId) =>
      _invokeBilling('cancel-coaching-enrollment-billing', enrollmentId);

  /// Asks Razorpay directly whether the link / subscription has been paid and records it (idempotent
  /// with the webhook), so the screen reflects a payment immediately instead of waiting on the webhook.
  Future<void> reconcileEnrollmentBilling(String enrollmentId) =>
      _invokeBilling('reconcile-coaching-enrollment-billing', enrollmentId);

  Future<void> _invokeBilling(String function, String enrollmentId) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(function, body: {'enrollmentId': enrollmentId});
    } on FunctionsHttpException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw AppException(AppErrorCode.paymentGatewayError, details['error'] as String);
      }
      throw AppException(AppErrorCode.paymentGatewayError);
    } on FunctionException {
      throw AppException(AppErrorCode.paymentGatewayError);
    }
    final data = response.data;
    if (data is! Map || data['error'] != null) throw AppException(AppErrorCode.paymentGatewayError);
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
