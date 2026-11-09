import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/coaching_enroll.dart';

/// Why joining a coaching programme could not go on, in words for the player.
class CoachingException implements Exception {
  const CoachingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the Coaching page's data comes from, and how an enrolment is started and paid. The Supabase version is the real one.
abstract class CoachingEnrollRepository {
  /// The venue's coaching programmes, or null when the venue is not open.
  Future<CoachingInfo?> info(String venueId);

  /// The signed-in player's coaching enrolments at the venue.
  Future<List<MyCoaching>> mine(String venueId);

  /// Makes (or resumes) the pending enrolment for [programId] in [batchId]. The fee is worked out by the database.
  Future<CoachingStart> start({
    required String venueId,
    required String programId,
    String? batchId,
  });

  /// The Razorpay page for the enrolment: a payment link for a one-time fee, a UPI AutoPay mandate for a monthly one.
  Future<Uri> paymentLink(String enrollmentId);
}

class SupabaseCoachingEnrollRepository implements CoachingEnrollRepository {
  SupabaseCoachingEnrollRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  bool _notInstalled(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883';

  @override
  Future<CoachingInfo?> info(String venueId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final result = await client.rpc(
        'get_public_coaching_enroll',
        params: {'p_facility_id': venueId},
      );
      if (result == null) return null;
      return CoachingInfo.fromJson((result as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (_notInstalled(e)) {
        throw const CoachingException(
          'The coaching update is not live on the database yet (migration 0176 or its schema reload is missing).',
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<MyCoaching>> mine(String venueId) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) return const [];
    try {
      final result = await client.rpc(
        'get_my_coaching_at',
        params: {'p_facility_id': venueId},
      );
      return [
        for (final m in (result as List<dynamic>? ?? const []))
          MyCoaching.fromJson((m as Map).cast<String, dynamic>()),
      ];
    } on PostgrestException catch (e) {
      if (_notInstalled(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<CoachingStart> start({
    required String venueId,
    required String programId,
    String? batchId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const CoachingException('Please sign in to join coaching.');
    }
    try {
      final r = await client.rpc(
        'player_start_coaching_enroll',
        params: {
          'p_facility_id': venueId,
          'p_program_id': programId,
          'p_batch_id': batchId,
        },
      );
      final m = (r as Map).cast<String, dynamic>();
      return CoachingStart(
        enrollmentId: m['enrollmentId'] as String,
        feeType: (m['feeType'] as String?) ?? 'ONE_TIME',
        cycles: (m['cycles'] as num?)?.toInt() ?? 1,
        chargeMinor: (m['chargeMinor'] as num?)?.toInt() ?? 0,
        totalMinor: (m['totalMinor'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      throw CoachingException(_friendly(e));
    }
  }

  @override
  Future<Uri> paymentLink(String enrollmentId) async {
    final client = _client;
    if (client == null) {
      throw const CoachingException('Please sign in to join coaching.');
    }
    try {
      final res = await client.functions.invoke(
        'create-player-coaching-billing',
        body: {'enrollmentId': enrollmentId},
      );
      final data = res.data;
      final url = data is Map ? data['shortUrl'] as String? : null;
      if (url == null || url.isEmpty) {
        throw const CoachingException(
          "We couldn't open the payment page. Please try again.",
        );
      }
      return Uri.parse(url);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      throw CoachingException(
        msg ?? "We couldn't set up the payment. Please try again.",
      );
    }
  }

  String _friendly(PostgrestException e) {
    final m = e.message.toLowerCase();
    // "Please choose another time: you already have coaching at this court at this time." (migration 0190)
    if (e.code == '23505' && e.message.startsWith('Please')) return e.message;
    if (m.contains('already enrolled')) {
      return 'You are already enrolled in this programme.';
    }
    if (m.contains('full')) {
      return 'That batch is full. Pick another time slot.';
    }
    if (m.contains('closed')) return 'Enrolment for this programme has closed.';
    if (m.contains('not available')) {
      return 'That programme or time slot is no longer available.';
    }
    // our own plain-language messages (sign in, enrolled at the club ...) pass through
    if (e.code == '42501' || e.code == '23514') return e.message;
    return "We couldn't start your enrolment. Please try again.";
  }
}
