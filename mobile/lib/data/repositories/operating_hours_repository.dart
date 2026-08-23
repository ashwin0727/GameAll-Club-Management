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
}