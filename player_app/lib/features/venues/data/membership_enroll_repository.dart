import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/membership_enroll.dart';

/// Why joining could not go on, in words for the player.
class EnrollException implements Exception {
  const EnrollException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the Enroll page's data comes from, and how a membership is started and paid. The Supabase version is the real one.
abstract class MembershipEnrollRepository {
  /// The venue's time slots and plans, or null when the venue is not open.
  Future<EnrollInfo?> info(String venueId);

  /// Memberships the signed-in player's phone number already has at the venue.
  Future<List<ExistingMembership>> myMemberships(String venueId);

  /// Makes (or resumes) the pending membership for [planId] in [batchId].
  Future<EnrollStart> start({
    required String venueId,
    required String planId,
    String? batchId,
  });

  /// The Razorpay page where the player sets up UPI AutoPay (GPay, PhonePe or any UPI app) and pays the first amount.
  Future<Uri> autopayLink(String membershipId);
}

class SupabaseMembershipEnrollRepository implements MembershipEnrollRepository {
  SupabaseMembershipEnrollRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  bool _notInstalled(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883';

  @override
  Future<EnrollInfo?> info(String venueId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final result = await client.rpc(
        'get_public_membership_enroll',
        params: {'p_facility_id': venueId},
      );
      if (result == null) return null;
      return EnrollInfo.fromJson((result as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (_notInstalled(e)) {
        throw const EnrollException(
          'The memberships update is not live on the database yet (migration 0175 or its schema reload is missing).',
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<ExistingMembership>> myMemberships(String venueId) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) return const [];
    try {
      final result = await client.rpc(
        'get_my_memberships_at',
        params: {'p_facility_id': venueId},
      );
      return [
        for (final m in (result as List<dynamic>? ?? const []))
          ExistingMembership.fromJson((m as Map).cast<String, dynamic>()),
      ];
    } on PostgrestException catch (e) {
      if (_notInstalled(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<EnrollStart> start({
    required String venueId,
    required String planId,
    String? batchId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const EnrollException('Please sign in to join a membership.');
    }
    try {
      final r = await client.rpc(
        'player_start_membership_enroll',
        params: {
          'p_facility_id': venueId,
          'p_plan_id': planId,
          'p_batch_id': batchId,
        },
      );
      final m = (r as Map).cast<String, dynamic>();
      return EnrollStart(
        membershipId: m['membershipId'] as String,
        amountInr: (m['amountInr'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      throw EnrollException(_friendly(e));
    }
  }

  @override
  Future<Uri> autopayLink(String membershipId) async {
    final client = _client;
    if (client == null) {
      throw const EnrollException('Please sign in to join a membership.');
    }
    try {
      final res = await client.functions.invoke(
        'create-membership-subscription',
        body: {'membershipId': membershipId},
      );
      final data = res.data;
      final url = data is Map ? data['shortUrl'] as String? : null;
      if (url == null || url.isEmpty) {
        throw const EnrollException(
          "We couldn't open the payment page. Please try again.",
        );
      }
      return Uri.parse(url);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      throw EnrollException(
        msg ?? "We couldn't set up AutoPay. Please try again.",
      );
    }
  }

  String _friendly(PostgrestException e) {
    if (e.code == '23503' && e.message.contains('slot')) {
      return 'That time slot is no longer available. Pick another.';
    }
    if (e.message.toLowerCase().contains('full')) {
      return 'That time slot is full. Pick another.';
    }
    if (e.code == '42501') return e.message;
    return "We couldn't start your membership. Please try again.";
  }
}
