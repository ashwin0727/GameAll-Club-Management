import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/sport.dart';

/// Mirrors src/services/sports/supabase-sports.service.ts — same
/// `sync_facility_sports` RPC (preserves id/created_at on re-save so a
/// playing area's facility_sport_id FK never orphans).
class SportsRepository {
  SportsRepository(this._client);

  final SupabaseClient _client;

  Future<List<Sport>> getActiveSports() async {
    try {
      final rows = await _client
          .from('sports')
          .select('id, key, name, is_active, sort_order')
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Sport.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<FacilitySport>> getFacilitySports(String facilityId) async {
    try {
      final rows = await _client
          .from('facility_sports')
          .select()
          .eq('facility_id', facilityId)
          .eq('is_active', true);
      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(FacilitySport.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<FacilitySport>> saveFacilitySports(
    String facilityId,
    List<String> sportIds, {
    String? customSportName,
  }) async {
    try {
      final rows = await _client.rpc(
        'sync_facility_sports',
        params: {
          'p_facility_id': facilityId,
          'p_sport_ids': sportIds,
          'p_custom_sport_name': customSportName,
        },
      );
      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(FacilitySport.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, duplicate: AppErrorCode.duplicateFacilitySport);
    }
  }
}