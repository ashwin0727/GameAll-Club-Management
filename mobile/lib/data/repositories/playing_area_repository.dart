import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/playing_area.dart';

/// Mirrors src/services/playing-areas/supabase-playing-areas.service.ts —
/// same `courts` table, same soft-delete-via-archived semantics.
class PlayingAreaRepository {
  PlayingAreaRepository(this._client);

  final SupabaseClient _client;

  Future<List<PlayingArea>> getPlayingAreas(String facilityId) async {
    try {
      final rows = await _client
          .from('courts')
          .select()
          .eq('facility_id', facilityId)
          .eq('archived', false)
          .order('display_order', ascending: true);
      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PlayingArea.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<PlayingArea> createPlayingArea(PlayingArea input) async {
    try {
      final row = await _client
          .from('courts')
          .insert(input.toInsertJson())
          .select()
          .single();
      return PlayingArea.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(
        e,
        duplicate: AppErrorCode.duplicatePlayingArea,
        notFound: AppErrorCode.facilitySportNotFound,
        invalid: AppErrorCode.invalidPlayingArea,
      );
    }
  }

  Future<PlayingArea> updatePlayingArea(
    String id, {
    String? name,
    String? areaType,
    String? status,
    bool? bookingEnabled,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (areaType != null) patch['area_type'] = areaType;
    if (status != null) patch['status'] = status;
    if (bookingEnabled != null) patch['booking_enabled'] = bookingEnabled;

    try {
      final row = await _client
          .from('courts')
          .update(patch)
          .eq('id', id)
          .select()
          .maybeSingle();
      if (row == null) throw AppException(AppErrorCode.playingAreaNotFound);
      return PlayingArea.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, duplicate: AppErrorCode.duplicatePlayingArea);
    }
  }

  Future<void> removePlayingArea(String id) async {
    try {
      await _client.from('courts').update({'archived': true}).eq('id', id);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}