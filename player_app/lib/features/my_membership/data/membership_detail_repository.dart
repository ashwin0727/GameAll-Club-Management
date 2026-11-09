import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/resilient.dart';
import '../domain/membership_detail.dart';

/// Where the Membership Details page gets its data. The Supabase version is the real one; tests supply a fake.
abstract class MembershipDetailRepository {
  /// The signed-in player's active memberships, soonest to end first (empty when there are none).
  Future<List<MembershipDetail>> mine();
}

class SupabaseMembershipDetailRepository implements MembershipDetailRepository {
  SupabaseMembershipDetailRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<List<MembershipDetail>> mine() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final result = await retryTransient(
        () => client.rpc('get_my_membership_details'),
      );
      return [
        for (final e in (result as List<dynamic>? ?? const []))
          if (e is Map) MembershipDetail.fromJson(e.cast<String, dynamic>()),
      ];
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    }
    // Migration 0180 is not installed yet: Home's own summary still has the plan, venue, slot and whether it is paid, so show that.
    final dash = await client.rpc('get_player_dashboard');
    final list = dash is Map ? dash['memberships'] : null;
    return [
      for (final e in (list as List<dynamic>? ?? const []))
        if (e is Map) fromDashboard(e.cast<String, dynamic>()),
    ];
  }
}

/// A membership built from Home's short summary (no photo, payments, bookings or usage).
MembershipDetail fromDashboard(Map<String, dynamic> j) {
  final days = [
    for (final d in (j['daysOfWeek'] as List<dynamic>? ?? const []))
      (d as num).toInt(),
  ];
  return MembershipDetail(
    id: (j['id'] as String?) ?? '',
    ref: '',
    planName: (j['planName'] as String?) ?? 'Membership',
    venue: MembershipVenue(
      id: '',
      name: (j['venueName'] as String?) ?? 'Venue',
    ),
    endDate: j['endDate'] == null
        ? null
        : DateTime.tryParse(j['endDate'] as String),
    payState: j['paymentIncomplete'] == true ? 'PENDING' : 'PAID',
    slot: (days.isEmpty && j['startTime'] == null && j['courtName'] == null)
        ? null
        : MembershipSlot(
            batchName: j['batchName'] as String?,
            court: j['courtName'] as String?,
            days: days,
            start: j['startTime'] as String?,
            end: j['endTime'] as String?,
          ),
    limited: true,
  );
}
