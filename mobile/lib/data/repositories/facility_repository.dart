import 'dart:typed_data';

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
    String? locationUrl,
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
      final facility = Facility.fromJson(row as Map<String, dynamic>);

      // `create_facility_with_owner` predates the pasted-location-link field,
      // so set it in a follow-up update rather than widening the RPC.
      final link = locationUrl?.trim();
      if (link != null && link.isNotEmpty) {
        await _client
            .from('facilities')
            .update({'location_url': link})
            .eq('id', facility.id);
      }
      return facility;
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Uploads a facility logo to the public `facility-logos` bucket, keyed
  /// under the owner's user id, and returns its public URL. Called before
  /// the facility row exists, so the user id is the only stable namespace.
  Future<String> uploadFacilityLogo(Uint8List bytes, String filename) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AppException(AppErrorCode.unauthenticated);

    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 ? filename.substring(dot + 1).toLowerCase() : 'jpg';
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _client.storage.from('facility-logos').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );
      return _client.storage.from('facility-logos').getPublicUrl(path);
    } on StorageException catch (e) {
      throw AppException(AppErrorCode.databaseError, e.message);
    }
  }

  /// Updates an existing facility row — used when the owner steps back into
  /// the Facility Details screen during onboarding, so we don't create a
  /// second facility. `id`/`owner_id` are never in the payload.
  Future<Facility> updateFacility({
    required String id,
    required String name,
    required FacilityType type,
    String? customType,
    required String businessPhone,
    required FacilityAddress address,
    String? logoUrl,
    String? locationUrl,
    String? description,
  }) async {
    try {
      final row = await _client
          .from('facilities')
          .update({
            'name': name,
            'facility_type': type.toDb(),
            'custom_facility_type': type == FacilityType.other ? customType : null,
            'business_phone': businessPhone,
            'address_line_1': address.line1,
            'area': address.area,
            'city': address.city,
            'state': address.state,
            'postal_code': address.pinCode,
            'logo_url': logoUrl,
            'location_url': locationUrl,
            'description': description,
          })
          .eq('id', id)
          .select()
          .single();
      return Facility.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Facility?> getFacility() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AppException(AppErrorCode.unauthenticated);

    try {
      // Resolve via facility access, not ownership — a manager or staff member
      // has an ACTIVE facility_users row but owns nothing. RLS on `facilities`
      // (is_facility_member, which now also requires status = 'ACTIVE') scopes
      // this to the facilities the signed-in user may see; the owned one wins.
      final rows = await _client
          .from('facilities')
          .select()
          .order('created_at', ascending: true) as List<dynamic>;
      final list = rows.map((r) => (r as Map).cast<String, dynamic>()).toList();
      if (list.isEmpty) return null;
      final owned = list.where((f) => f['owner_id'] == userId);
      final row = owned.isNotEmpty ? owned.first : list.first;
      return Facility.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Marks whether the owner linked a payments account on the Connect
  /// Payments step. Full Razorpay Route onboarding is a later project; this
  /// is just the remembered flag.
  Future<void> setPaymentsConnected(String facilityId, bool connected) async {
    try {
      await _client
          .from('facilities')
          .update({'payments_connected': connected})
          .eq('id', facilityId);
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