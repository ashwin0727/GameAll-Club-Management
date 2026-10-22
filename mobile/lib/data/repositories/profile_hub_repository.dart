import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/profile_hub.dart';

/// The Profile hub's reads and writes — mirrors the web `SupabaseProfileService`
/// (src/services/profile). The plan / payout / support tables arrive with
/// migration 0148; the headline numbers come from the same Finance and Reports
/// repositories the other screens use (composed in the provider, not here).
class ProfileHubRepository {
  ProfileHubRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw AppException(AppErrorCode.unauthenticated);
    return id;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    } on StorageException catch (_) {
      throw AppException(AppErrorCode.databaseError, 'Could not upload this photo. Please try again.');
    }
  }

  Future<HubProfile> getProfile() => _guard(() async {
        final row = await _client.from('profiles').select().eq('id', _uid).single();
        return HubProfile.fromJson(row);
      });

  Future<void> updateProfile({required String fullName, String? phone, String? avatarUrl, bool setAvatar = false}) =>
      _guard(() async {
        final patch = <String, dynamic>{
          'full_name': fullName.trim(),
          'phone': (phone?.trim().isEmpty ?? true) ? null : phone!.trim(),
          if (setAvatar) 'avatar_url': avatarUrl,
        };
        await _client.from('profiles').update(patch).eq('id', _uid);
      });

  /// Uploads to the public `avatars` bucket under the user's own folder and returns the public URL.
  Future<String> uploadAvatar(Uint8List bytes, String fileName, String contentType) => _guard(() async {
        final safe = fileName.replaceAll(RegExp(r'[^\w.-]'), '_');
        final path = '$_uid/${DateTime.now().microsecondsSinceEpoch}-$safe';
        await _client.storage.from('avatars').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
        return _client.storage.from('avatars').getPublicUrl(path);
      });

  Future<FacilityPlan?> getPlan(String facilityId) => _guard(() async {
        final row = await _client.from('facility_subscriptions').select().eq('facility_id', facilityId).maybeSingle();
        return row == null ? null : FacilityPlan.fromJson(row);
      });

  Future<int> countActiveMembers(String facilityId) => _guard(() async {
        final rows = await _client.from('members').select('id').eq('facility_id', facilityId).eq('status', 'ACTIVE');
        return (rows as List<dynamic>).length;
      });

  Future<int> countCourts(String facilityId) => _guard(() async {
        final rows = await _client.from('courts').select('id').eq('facility_id', facilityId).eq('archived', false);
        return (rows as List<dynamic>).length;
      });

  Future<NotificationPrefs> getNotificationPrefs() => _guard(() async {
        final row = await _client.from('profiles').select('notification_prefs').eq('id', _uid).single();
        return NotificationPrefs.fromJson((row['notification_prefs'] as Map?)?.cast<String, dynamic>());
      });

  Future<void> saveNotificationPrefs(NotificationPrefs prefs) => _guard(() async {
        await _client.from('profiles').update({'notification_prefs': prefs.toJson()}).eq('id', _uid);
      });

  /// Only the address and description can be changed by the owner; the name, type and contact number stay as set up.
  Future<void> updateFacilityAddress(
    String facilityId, {
    required String line1,
    required String area,
    required String city,
    required String state,
    required String pinCode,
    String? description,
  }) =>
      _guard(() async {
        await _client.from('facilities').update({
          'address_line_1': line1.trim(),
          'area': area.trim(),
          'city': city.trim(),
          'state': state.trim(),
          'postal_code': pinCode.trim(),
          'description': (description?.trim().isEmpty ?? true) ? null : description!.trim(),
        }).eq('id', facilityId);
      });

  Future<List<SupportTicket>> listTickets(String facilityId) => _guard(() async {
        final rows = await _client
            .from('support_tickets')
            .select()
            .eq('facility_id', facilityId)
            .order('created_at', ascending: false)
            .limit(20);
        return (rows as List<dynamic>).map((r) => SupportTicket.fromJson((r as Map).cast<String, dynamic>())).toList();
      });

  Future<void> createTicket(
    String facilityId, {
    required String category,
    required String subject,
    required String message,
  }) =>
      _guard(() async {
        await _client.from('support_tickets').insert({
          'facility_id': facilityId,
          'category': category,
          'subject': subject.trim(),
          'message': message.trim(),
        });
      });

  Future<void> changePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AppException(AppErrorCode.unauthenticated, e.message);
    }
  }
}
