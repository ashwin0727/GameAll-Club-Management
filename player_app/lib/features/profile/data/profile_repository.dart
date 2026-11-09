import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/profile_models.dart';

/// Something to tell the player in plain words.
class ProfileFailure implements Exception {
  const ProfileFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The profile's data. The Supabase version is the real one (migration 0187); tests supply a fake.
abstract class ProfileRepository {
  /// The full profile, or null when the database does not have migration 0187 yet (the caller shows the basic profile).
  Future<ProfileDetails?> details();

  /// Saves the form and returns the saved profile.
  Future<ProfileDetails> update(ProfileEdit edit);

  /// GameAll's sports a player can mark as preferred (empty when it cannot be read).
  Future<List<SportOption>> sports();

  /// Uploads the ID proof (a private file) and saves it on the profile; returns the saved profile.
  Future<ProfileDetails> uploadDocument(
    Uint8List bytes,
    String extension,
    String fileName,
    String docType,
  );

  /// Removes the saved ID proof; returns the saved profile.
  Future<ProfileDetails> removeDocument(String path);

  /// A short-lived link to open the private ID proof.
  Future<Uri?> documentLink(String path);

  /// Uploads a new photo and saves its address on the profile; returns the saved profile.
  Future<ProfileDetails> uploadAvatar(Uint8List bytes, String extension);

  Future<ProfileStats?> stats();

  Future<List<PaymentRecord>> payments();
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  SupabaseClient get _need {
    final c = _client;
    if (c == null || c.auth.currentUser == null) {
      throw const ProfileFailure('Please sign in first.');
    }
    return c;
  }

  /// Migration 0187 not applied yet.
  bool _missing(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883' || e.code == '42703';

  @override
  Future<ProfileDetails?> details() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return null;
    try {
      final r = await client.rpc('get_my_player_profile');
      if (r == null) return null;
      return ProfileDetails.fromJson((r as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  Future<ProfileDetails> _saveInfo(Map<String, dynamic> patch) async {
    final client = _need;
    try {
      final r = await client.rpc('update_my_player_info', params: {'p_patch': patch});
      return ProfileDetails.fromJson((r as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (_missing(e)) {
        throw const ProfileFailure('Saving is not available yet. Please try again a little later.');
      }
      if (e.code == '22023') throw ProfileFailure(e.message);
      throw const ProfileFailure("We couldn't save that. Please try again.");
    } catch (_) {
      throw const ProfileFailure("We couldn't reach GameAll. Check your connection and try again.");
    }
  }

  @override
  Future<List<SportOption>> sports() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final r = await client.rpc('list_platform_sports');
      return [
        for (final s in (r as List<dynamic>? ?? const []))
          if (s is Map) SportOption(s['key'] as String, s['name'] as String),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<ProfileDetails> uploadDocument(
    Uint8List bytes,
    String extension,
    String fileName,
    String docType,
  ) async {
    final client = _need;
    final ext = switch (extension.toLowerCase()) {
      'png' => 'png',
      'webp' => 'webp',
      'pdf' => 'pdf',
      _ => 'jpg',
    };
    if (bytes.length > 5 * 1024 * 1024) {
      throw const ProfileFailure('Please choose a file under 5 MB.');
    }
    final uid = client.auth.currentUser!.id;
    final path = '$uid/id-${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await client.storage.from('player-documents').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: switch (ext) {
            'jpg' => 'image/jpeg',
            'pdf' => 'application/pdf',
            _ => 'image/$ext',
          },
          upsert: true,
        ),
      );
    } catch (_) {
      throw const ProfileFailure("We couldn't upload the document. Please try again.");
    }
    return _saveInfo({'idDocType': docType, 'idDocPath': path, 'idDocName': fileName});
  }

  @override
  Future<ProfileDetails> removeDocument(String path) async {
    final client = _need;
    final saved = await _saveInfo({'idDocType': '', 'idDocPath': '', 'idDocName': ''});
    try {
      await client.storage.from('player-documents').remove([path]);
    } catch (_) {
      // the profile no longer points at it; a leftover file is harmless
    }
    return saved;
  }

  @override
  Future<Uri?> documentLink(String path) async {
    final client = _need;
    try {
      final url = await client.storage.from('player-documents').createSignedUrl(path, 300);
      return Uri.parse(url);
    } catch (_) {
      return null;
    }
  }

  Future<ProfileDetails> _save(Map<String, dynamic> params) async {
    final client = _need;
    try {
      final r = await client.rpc('update_my_player_profile', params: params);
      return ProfileDetails.fromJson((r as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (_missing(e)) {
        throw const ProfileFailure(
          'Saving is not available yet. Please try again a little later.',
        );
      }
      // the database's own sentences ("Please enter a valid email address") are meant to be read
      if (e.code == '22023') throw ProfileFailure(e.message);
      throw const ProfileFailure("We couldn't save that. Please try again.");
    } catch (_) {
      throw const ProfileFailure(
        "We couldn't reach GameAll. Check your connection and try again.",
      );
    }
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<ProfileDetails> update(ProfileEdit edit) {
    if (edit.full) {
      return _saveInfo({
        'fullName': edit.fullName.trim(),
        'email': edit.email.trim(),
        'dob': edit.dob == null ? '' : _date(edit.dob!),
        'gender': edit.gender?.wire ?? '',
        'city': edit.city ?? '',
        'bloodGroup': edit.bloodGroup,
        'tshirtSize': edit.tshirtSize,
        'preferredSports': edit.preferredSports,
        'playingLevel': edit.playingLevel,
        'about': edit.about.trim(),
        'altPhone': edit.altPhone.trim(),
        'emergencyName': edit.emergencyName.trim(),
        'emergencyRelation': edit.emergencyRelation.trim(),
        'emergencyPhone': edit.emergencyPhone.trim(),
        'addressLine1': edit.addressLine1.trim(),
        'addressLine2': edit.addressLine2.trim(),
        'state': edit.state,
        'pincode': edit.pincode.trim(),
        'idDocType': edit.idDocType,
      });
    }
    return _basics(edit);
  }

  Future<ProfileDetails> _basics(ProfileEdit edit) => _save({
    'p_full_name': edit.fullName.trim(),
    'p_email': edit.email.trim(),
    'p_dob': edit.dob == null ? null : _date(edit.dob!),
    'p_clear_dob': edit.clearDob,
    'p_gender': edit.gender?.wire ?? '',
    'p_city': edit.city ?? '',
  });

  @override
  Future<ProfileDetails> uploadAvatar(Uint8List bytes, String extension) async {
    final client = _need;
    final ext = switch (extension.toLowerCase()) {
      'png' => 'png',
      'webp' => 'webp',
      _ => 'jpg',
    };
    if (bytes.length > 3 * 1024 * 1024) {
      throw const ProfileFailure('Please choose a photo under 3 MB.');
    }
    final uid = client.auth.currentUser!.id;
    // a new file name each time, so the new photo shows at once instead of the cached old one
    final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: ext == 'jpg' ? 'image/jpeg' : 'image/$ext',
              upsert: true,
            ),
          );
    } catch (_) {
      throw const ProfileFailure("We couldn't upload the photo. Please try again.");
    }
    final url = client.storage.from('avatars').getPublicUrl(path);
    return _save({'p_avatar_url': url});
  }

  @override
  Future<ProfileStats?> stats() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return null;
    try {
      final r = await client.rpc('get_my_profile_stats');
      if (r == null) return null;
      return ProfileStats.fromJson((r as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  @override
  Future<List<PaymentRecord>> payments() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return const [];
    try {
      final r = await client.rpc(
        'get_my_payment_history',
        params: {'p_limit': 100},
      );
      return [
        for (final e in (r as List<dynamic>? ?? const []))
          if (e is Map) PaymentRecord.fromJson(e.cast<String, dynamic>()),
      ];
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }
}
