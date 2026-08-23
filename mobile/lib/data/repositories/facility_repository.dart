import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/facility.dart';

/// Mirrors src/services/facility/supabase-facility.service.ts — same RPC
/// (`create_facility_with_owner`) and table, so a facility created on
/// mobile is immediately visible on web and vice versa.
class FacilityRepository {
  FacilityRepository(this._client);

  final SupabaseClient _client;

  Future<Facility> createFacility({
    required String name,
    required FacilityType type,
    String? customType,
    required String businessEmail,
    required String businessPhone,
    required FacilityAddress address,
    String? logoUrl,
    String? description,
  }) async {
    try {
      final row = await _client.rpc(
        'create_facility_with_owner',
        params: {
          'p_name': name,
          'p_facility_type': type.toDb(),
          'p_custom_facility_type': type == FacilityType.other ? customType : null,
          'p_business_email': businessEmail,
          'p_business_phone': businessPhone,
          'p_address_line_1': address.line1,
          'p_address_line_2': null,
          'p_area': address.area,
          'p_city': address.city,
          'p_state': address.state,
          'p_country': address.country,
          'p_postal_code': address.pinCode,
          'p_latitude': null,
          'p_longitude': null,
          'p_timezone': 'Asia/Kolkata',
          'p_logo_url': logoUrl,
          'p_description': description,
        },
      );
      return Facility.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Facility?> getFacility() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AppException(AppErrorCode.unauthenticated);

    try {
      final row = await _client
          .from('facilities')
          .select()
          .eq('owner_id', userId)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();
      return row == null ? null : Facility.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> updateOnboardingStep(String facilityId, OnboardingStep step) async {
    try {
      await _client
          .from('facilities')
          .update({'onboarding_step': step.toDb()})
          .eq('id', facilityId);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}