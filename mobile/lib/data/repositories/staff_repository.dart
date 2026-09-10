import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/staff.dart';

/// Staff / Roles / Permissions — mirrors src/services/staff/supabase-staff.service.ts.
///
/// A read/write layer over the RBAC RPCs (0075/0076) and the create-staff edge
/// function. Every RPC self-enforces the caller's permission (has_permission),
/// the last-owner guard and the escalation guard — this class never re-checks
/// authorization, it only maps rows and errors.
class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient _client;

  AppException _map(Object e) {
    if (e is AppException) return e;
    final msg = e is PostgrestException
        ? e.message
        : e is FunctionException
            ? (e.details is Map ? (e.details as Map)['error']?.toString() ?? e.toString() : e.toString())
            : e.toString();
    if (msg.contains('permission') || msg.contains('Not authorized')) {
      return AppException(AppErrorCode.unauthorized, msg);
    }
    if (msg.contains('Another administrator')) return AppException(AppErrorCode.staffConcurrentUpdate, msg);
    if (msg.contains('last active owner')) return AppException(AppErrorCode.lastActiveOwner, msg);
    if (msg.contains('assigned to')) return AppException(AppErrorCode.roleInUse, msg);
    if (msg.contains('already has access')) return AppException(AppErrorCode.staffDuplicate, msg);
    return AppException(AppErrorCode.databaseError, msg);
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List<dynamic>? ?? const []).map((r) => (r as Map).cast<String, dynamic>()).toList();

  // ── my permissions (session bootstrap) ─────────────────────────────────

  Future<List<String>> myFacilityPermissions(String facilityId) async {
    try {
      final rows = await _client.rpc('my_facility_permissions', params: {'p_facility': facilityId});
      return (rows as List<dynamic>? ?? const []).map((e) => e as String).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> markPasswordResetComplete() async {
    try {
      await _client.rpc('mark_password_reset_complete');
    } catch (_) {}
  }

  Future<void> recordMyLogin() async {
    try {
      await _client.rpc('record_my_login');
    } catch (_) {}
  }

  // ── staff ─────────────────────────────────────────────────────────────

  Future<StaffPage> listStaff({
    required String facilityId,
    String? search,
    StaffStatus? status,
    String? roleId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_staff', params: {
        'p_facility_id': facilityId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_status': status?.toJson(),
        'p_role_id': roleId,
        'p_limit': limit,
        'p_offset': offset,
      });
      return StaffPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }

  Future<StaffDetail> getStaff(String facilityId, String userId) async {
    try {
      final data = await _client.rpc('get_staff', params: {'p_facility_id': facilityId, 'p_user_id': userId});
      return StaffDetail.fromJson((data as Map).cast<String, dynamic>());
    } catch (e) {
      throw _map(e);
    }
  }

  Future<CreateStaffResult> createStaff({
    required String facilityId,
    required String fullName,
    required String email,
    String? phone,
    required String roleId,
    bool isPrimary = false,
    String? title,
    String? notes,
  }) async {
    try {
      final res = await _client.functions.invoke('create-staff', body: {
        'facilityId': facilityId,
        'fullName': fullName,
        'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'roleId': roleId,
        'isPrimary': isPrimary,
        if (title != null && title.isNotEmpty) 'title': title,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });
      final data = (res.data as Map).cast<String, dynamic>();
      return CreateStaffResult(
        userId: data['userId'] as String,
        linked: data['linked'] as bool? ?? false,
        temporaryPassword: data['temporaryPassword'] as String?,
      );
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> assignRole(String facilityId, String userId, String roleId) async {
    try {
      await _client.rpc('assign_staff_role',
          params: {'p_facility_id': facilityId, 'p_user_id': userId, 'p_role_id': roleId});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> setStatus(String facilityId, String userId, StaffStatus status) async {
    try {
      await _client.rpc('set_staff_status',
          params: {'p_facility_id': facilityId, 'p_user_id': userId, 'p_status': status.toJson()});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateProfile(String facilityId, String userId, {String? title, String? notes}) async {
    try {
      await _client.rpc('update_staff_profile',
          params: {'p_facility_id': facilityId, 'p_user_id': userId, 'p_title': title, 'p_notes': notes});
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> removeFacilityAccess(String facilityId, String userId) async {
    try {
      await _client.rpc('remove_facility_access', params: {'p_facility_id': facilityId, 'p_user_id': userId});
    } catch (e) {
      throw _map(e);
    }
  }

  // ── roles & permissions ───────────────────────────────────────────────

  Future<List<RoleRow>> listRoles(String facilityId) async {
    try {
      final rows = await _client.rpc('list_roles', params: {'p_facility_id': facilityId});
      return _rows(rows).map(RoleRow.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<RoleDetail> getRole(String roleId) async {
    try {
      final data = await _client.rpc('get_role', params: {'p_role_id': roleId});
      return RoleDetail.fromJson((data as Map).cast<String, dynamic>());
    } catch (e) {
      throw _map(e);
    }
  }

  Future<List<RoleTemplate>> listRoleTemplates() async {
    try {
      final rows = await _client.rpc('list_role_templates');
      return _rows(rows).map(RoleTemplate.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<List<Permission>> listPermissions() async {
    try {
      final rows = await _client.rpc('list_permissions');
      return _rows(rows).map(Permission.fromJson).toList();
    } catch (e) {
      throw _map(e);
    }
  }

  Future<String> createRole({
    required String facilityId,
    required String name,
    String? description,
    required List<String> permissionKeys,
    String? fromTemplateId,
  }) async {
    try {
      final id = await _client.rpc('create_role', params: {
        'p_facility_id': facilityId,
        'p_name': name,
        'p_description': description,
        'p_permission_keys': permissionKeys,
        'p_from_template_id': fromTemplateId,
      });
      return id as String;
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateRole({
    required String roleId,
    required String facilityId,
    String? name,
    String? description,
    bool? isActive,
    List<String>? permissionKeys,
    int? expectedVersion,
  }) async {
    try {
      await _client.rpc('update_role', params: {
        'p_role_id': roleId,
        'p_facility_id': facilityId,
        'p_name': name,
        'p_description': description,
        'p_is_active': isActive,
        'p_permission_keys': permissionKeys,
        'p_expected_version': expectedVersion,
      });
    } catch (e) {
      throw _map(e);
    }
  }

  Future<void> deleteRole(String roleId, String facilityId) async {
    try {
      await _client.rpc('delete_role', params: {'p_role_id': roleId, 'p_facility_id': facilityId});
    } catch (e) {
      throw _map(e);
    }
  }

  // ── access history ────────────────────────────────────────────────────

  Future<SecurityEventPage> listSecurityEvents({
    required String facilityId,
    String? event,
    int limit = 25,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_security_events', params: {
        'p_facility_id': facilityId,
        'p_event': event,
        'p_target_user_id': null,
        'p_from': null,
        'p_to': null,
        'p_limit': limit,
        'p_offset': offset,
      });
      return SecurityEventPage.fromRows(_rows(rows));
    } catch (e) {
      throw _map(e);
    }
  }
}
