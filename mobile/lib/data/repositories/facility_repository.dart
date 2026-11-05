import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/facility.dart';
import '../models/facility_image.dart';

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
    VenueType? venueType,
    FacilityAmenities amenities = const FacilityAmenities(),
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
          'p_description': null,
        },
      );
      final facility = Facility.fromJson(row as Map<String, dynamic>);

      // `create_facility_with_owner` predates the map link, venue type and amenities, so they are set in a follow-up update
      // rather than widening the RPC.
      final link = locationUrl?.trim();
      final updated = await _client
          .from('facilities')
          .update({
            if (link != null && link.isNotEmpty) 'location_url': link,
            if (venueType != null) 'venue_type': venueType.toDb(),
            ...amenities.toDb(),
          })
          .eq('id', facility.id)
          .select()
          .single();
      return Facility.fromJson(updated);
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
    VenueType? venueType,
    FacilityAmenities amenities = const FacilityAmenities(),
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
            if (venueType != null) 'venue_type': venueType.toDb(),
            ...amenities.toDb(),
          })
          .eq('id', id)
          .select()
          .single();
      return Facility.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Uploads one facility photo to the public `facility-photos` bucket, in the owner's own folder, and returns its public URL.
  Future<String> uploadFacilityPhoto(Uint8List bytes, String filename) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AppException(AppErrorCode.unauthenticated);
    final dot = filename.lastIndexOf('.');
    var ext = dot >= 0 ? filename.substring(dot + 1).toLowerCase() : 'jpg';
    if (!const ['jpg', 'jpeg', 'png', 'webp'].contains(ext)) ext = 'jpg';
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}-${bytes.length}.$ext';
    try {
      await _client.storage.from('facility-photos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: false, contentType: ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg')),
          );
      return _client.storage.from('facility-photos').getPublicUrl(path);
    } on StorageException catch (e) {
      throw AppException(AppErrorCode.databaseError, e.message);
    }
  }

  /// Attaches uploaded photos to the facility. They start waiting for GameAll's check; the first one is the cover.
  Future<void> addFacilityImages(String facilityId, List<String> urls, {int firstSortOrder = 0}) async {
    if (urls.isEmpty) return;
    try {
      await _client.from('facility_images').insert([
        for (var i = 0; i < urls.length; i++) {'facility_id': facilityId, 'url': urls[i], 'sort_order': firstSortOrder + i},
      ]);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<FacilityImage>> listFacilityImages(String facilityId) async {
    try {
      final rows = await _client
          .from('facility_images')
          .select()
          .eq('facility_id', facilityId)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true) as List<dynamic>;
      return rows.map((r) => FacilityImage.fromJson((r as Map).cast<String, dynamic>())).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> removeFacilityImage(String imageId) async {
    try {
      await _client.from('facility_images').delete().eq('id', imageId);
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