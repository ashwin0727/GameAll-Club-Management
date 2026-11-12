import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/operating_hours.dart';

const String _scheduleSelect = '*, operating_days(*, operating_time_slots(*))';

/// Mirrors src/services/operating-hours/supabase-operating-hours.service.ts
/// — same `save_operating_schedule` RPC (get-or-create-then-replace, so
/// repeated saves never duplicate slots).
class OperatingHoursRepository {
  OperatingHoursRepository(this._client);

  final SupabaseClient _client;

  Future<OperatingSchedule?> getFacilitySchedule(String facilityId) async {
    try {
      final row = await _client
          .from('operating_schedules')
          .select(_scheduleSelect)
          .eq('facility_id', facilityId)
          .eq('scope_type', 'FACILITY')
          .maybeSingle();
      return row == null ? null : OperatingSchedule.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> saveFacilitySchedule(String facilityId, List<OperatingDay> days) async {
    try {
      await _client.rpc(
        'save_operating_schedule',
        params: {
          'p_facility_id': facilityId,
          'p_scope_type': 'FACILITY',
          'p_playing_area_id': null,
          'p_days': days.map((d) => d.toPayload()).toList(),
        },
      );
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, invalid: AppErrorCode.invalidPlayingArea);
    }
  }

  Future<OperatingSchedule?> getPlayingAreaSchedule(String playingAreaId) async {
    try {
      final row = await _client
          .from('operating_schedules')
          .select(_scheduleSelect)
          .eq('playing_area_id', playingAreaId)
          .eq('scope_type', 'PLAYING_AREA')
          .maybeSingle();
      return row == null ? null : OperatingSchedule.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> savePlayingAreaSchedule(
    String playingAreaId,
    String facilityId,
    List<OperatingDay> days,
  ) async {
    try {
      await _client.rpc(
        'save_operating_schedule',
        params: {
          'p_facility_id': facilityId,
          'p_scope_type': 'PLAYING_AREA',
          'p_playing_area_id': playingAreaId,
          'p_days': days.map((d) => d.toPayload()).toList(),
        },
      );
    } on PostgrestException catch (e) {
      throw mapSupabaseError(
        e,
        invalid: AppErrorCode.invalidPlayingArea,
        notFound: AppErrorCode.playingAreaNotFound,
      );
    }
  }

  /// The dates the venue is closed, earliest first.
  Future<List<ClosureEntry>> getClosures(String facilityId) async {
    try {
      final rows = await _client.from('facility_closures').select('id, closure_date, name').eq('facility_id', facilityId).order('closure_date', ascending: true) as List<dynamic>;
      return [
        for (final r in rows.cast<Map<String, dynamic>>()) ClosureEntry(id: r['id'] as String, date: r['closure_date'] as String, name: r['name'] as String),
      ];
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Makes the venue's closures exactly this list (adds, renames and removes as needed).
  Future<List<ClosureEntry>> replaceClosures(String facilityId, List<ClosureEntry> closures) async {
    // one row per date: if the same date is listed twice the last one wins
    final byDate = {for (final c in closures) c.date: {'facility_id': facilityId, 'closure_date': c.date, 'name': c.name.trim()}};
    try {
      final existing = await getClosures(facilityId);
      final stale = [for (final c in existing) if (!byDate.containsKey(c.date) && c.id != null) c.id!];
      if (stale.isNotEmpty) await _client.from('facility_closures').delete().inFilter('id', stale);
      if (byDate.isNotEmpty) await _client.from('facility_closures').upsert(byDate.values.toList(), onConflict: 'facility_id,closure_date');
      return await getClosures(facilityId);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> deletePlayingAreaOverride(String playingAreaId) async {
    try {
      await _client.rpc('delete_playing_area_override', params: {'p_playing_area_id': playingAreaId});
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}