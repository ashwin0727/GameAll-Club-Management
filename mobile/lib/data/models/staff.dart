// ═══════════════════════════════════════════════════════════════════════════
// Staff / Roles / Permissions — mirrors src/features/staff/types.ts.
// Backend: migrations 0072-0077. Every authorization decision is the
// database's (has_permission + RLS); these are the shapes the UI renders.
// ═══════════════════════════════════════════════════════════════════════════

enum StaffStatus {
  active,
  inactive,
  invited;

  static StaffStatus fromJson(String v) => switch (v) {
        'ACTIVE' => StaffStatus.active,
        'INACTIVE' => StaffStatus.inactive,
        _ => StaffStatus.invited,
      };

  String toJson() => switch (this) {
        StaffStatus.active => 'ACTIVE',
        StaffStatus.inactive => 'INACTIVE',
        StaffStatus.invited => 'INVITED',
      };

  String get label => switch (this) {
        StaffStatus.active => 'Active',
        StaffStatus.inactive => 'Inactive',
        StaffStatus.invited => 'Pending',
      };
}

class Permission {
  const Permission({
    required this.key,
    required this.module,
    required this.action,
    required this.label,
    required this.description,
    required this.isDangerous,
    required this.sortOrder,
  });

  final String key;
  final String module;
  final String action;
  final String label;
  final String? description;
  final bool isDangerous;
  final int sortOrder;

  factory Permission.fromJson(Map<String, dynamic> j) => Permission(
        key: j['key'] as String,
        module: j['module'] as String,
        action: j['action'] as String,
        label: j['label'] as String,
        description: j['description'] as String?,
        isDangerous: j['is_dangerous'] as bool? ?? false,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class StaffRow {
  const StaffRow({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.avatarUrl,
    required this.roleId,
    required this.roleName,
    required this.baseRole,
    required this.status,
    required this.facilityCount,
    required this.lastLoginAt,
    required this.joinedAt,
  });

  final String userId;
  final String fullName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String? roleId;
  final String roleName;
  final String baseRole;
  final StaffStatus status;
  final int facilityCount;
  final String? lastLoginAt;
  final String joinedAt;

  factory StaffRow.fromJson(Map<String, dynamic> j) => StaffRow(
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        roleId: j['role_id'] as String?,
        roleName: j['role_name'] as String,
        baseRole: j['base_role'] as String,
        status: StaffStatus.fromJson(j['status'] as String),
        facilityCount: (j['facility_count'] as num?)?.toInt() ?? 1,
        lastLoginAt: j['last_login_at'] as String?,
        joinedAt: j['joined_at'] as String,
      );
}

class StaffPage {
  const StaffPage({required this.staff, required this.totalCount});
  final List<StaffRow> staff;
  final int totalCount;
  factory StaffPage.fromRows(List<Map<String, dynamic>> rows) => StaffPage(
        staff: rows.map(StaffRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : (rows.first['total_count'] as num).toInt(),
      );
}

class StaffFacilityAccess {
  const StaffFacilityAccess({
    required this.facilityId,
    required this.facilityName,
    required this.roleName,
    required this.baseRole,
    required this.status,
    required this.isPrimary,
  });
  final String facilityId;
  final String facilityName;
  final String roleName;
  final String baseRole;
  final StaffStatus status;
  final bool isPrimary;
  factory StaffFacilityAccess.fromJson(Map<String, dynamic> j) => StaffFacilityAccess(
        facilityId: j['facilityId'] as String,
        facilityName: j['facilityName'] as String,
        roleName: j['roleName'] as String,
        baseRole: j['baseRole'] as String,
        status: StaffStatus.fromJson(j['status'] as String),
        isPrimary: j['isPrimary'] as bool? ?? false,
      );
}

class StaffActivity {
  const StaffActivity({required this.id, required this.event, required this.summary, required this.actorName, required this.createdAt});
  final String id;
  final String event;
  final String summary;
  final String? actorName;
  final String createdAt;
  factory StaffActivity.fromJson(Map<String, dynamic> j) => StaffActivity(
        id: j['id'] as String,
        event: j['event'] as String,
        summary: j['summary'] as String,
        actorName: j['actorName'] as String?,
        createdAt: j['createdAt'] as String,
      );
}

class StaffDetail {
  const StaffDetail({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.avatarUrl,
    required this.roleId,
    required this.roleName,
    required this.baseRole,
    required this.status,
    required this.title,
    required this.notes,
    required this.joinedAt,
    required this.lastLoginAt,
    required this.facilityAccess,
    required this.permissions,
    required this.recentActivity,
  });

  final String userId;
  final String fullName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String? roleId;
  final String roleName;
  final String baseRole;
  final StaffStatus status;
  final String? title;
  final String? notes;
  final String? joinedAt;
  final String? lastLoginAt;
  final List<StaffFacilityAccess> facilityAccess;
  final List<String> permissions;
  final List<StaffActivity> recentActivity;

  factory StaffDetail.fromJson(Map<String, dynamic> j) {
    final a = (j['assignment'] as Map?)?.cast<String, dynamic>();
    return StaffDetail(
      userId: j['userId'] as String,
      fullName: j['fullName'] as String,
      email: j['email'] as String,
      phone: j['phone'] as String?,
      avatarUrl: j['avatarUrl'] as String?,
      roleId: a?['roleId'] as String?,
      roleName: (a?['roleName'] as String?) ?? '—',
      baseRole: (a?['baseRole'] as String?) ?? 'staff',
      status: StaffStatus.fromJson((a?['status'] as String?) ?? 'ACTIVE'),
      title: a?['title'] as String?,
      notes: a?['notes'] as String?,
      joinedAt: a?['joinedAt'] as String?,
      lastLoginAt: a?['lastLoginAt'] as String?,
      facilityAccess: ((j['facilityAccess'] as List<dynamic>?) ?? const [])
          .map((e) => StaffFacilityAccess.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      permissions: ((j['permissions'] as List<dynamic>?) ?? const []).map((e) => e as String).toList(),
      recentActivity: ((j['recentActivity'] as List<dynamic>?) ?? const [])
          .map((e) => StaffActivity.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class RoleRow {
  const RoleRow({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.isSystem,
    required this.isCustom,
    required this.isActive,
    required this.version,
    required this.staffCount,
    required this.permissionCount,
  });
  final String id;
  final String? key;
  final String name;
  final String? description;
  final bool isSystem;
  final bool isCustom;
  final bool isActive;
  final int version;
  final int staffCount;
  final int permissionCount;
  factory RoleRow.fromJson(Map<String, dynamic> j) => RoleRow(
        id: j['id'] as String,
        key: j['key'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        isSystem: j['is_system'] as bool? ?? false,
        isCustom: j['is_custom'] as bool? ?? false,
        isActive: j['is_active'] as bool? ?? true,
        version: (j['version'] as num?)?.toInt() ?? 1,
        staffCount: (j['staff_count'] as num?)?.toInt() ?? 0,
        permissionCount: (j['permission_count'] as num?)?.toInt() ?? 0,
      );
}

class RoleDetail {
  const RoleDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.isSystem,
    required this.isActive,
    required this.version,
    required this.permissionKeys,
  });
  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final bool isActive;
  final int version;
  final List<String> permissionKeys;
  factory RoleDetail.fromJson(Map<String, dynamic> j) => RoleDetail(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        isSystem: j['isSystem'] as bool? ?? false,
        isActive: j['isActive'] as bool? ?? true,
        version: (j['version'] as num?)?.toInt() ?? 1,
        permissionKeys: ((j['permissionKeys'] as List<dynamic>?) ?? const []).map((e) => e as String).toList(),
      );
}

class RoleTemplate {
  const RoleTemplate({required this.id, required this.name, required this.description, required this.permissionKeys});
  final String id;
  final String name;
  final String? description;
  final List<String> permissionKeys;
  factory RoleTemplate.fromJson(Map<String, dynamic> j) => RoleTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        permissionKeys: ((j['permission_keys'] as List<dynamic>?) ?? const []).map((e) => e as String).toList(),
      );
}

class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.event,
    required this.summary,
    required this.actorName,
    required this.targetName,
    required this.createdAt,
  });
  final String id;
  final String event;
  final String summary;
  final String? actorName;
  final String? targetName;
  final String createdAt;
  factory SecurityEvent.fromJson(Map<String, dynamic> j) => SecurityEvent(
        id: j['id'] as String,
        event: j['event'] as String,
        summary: j['summary'] as String,
        actorName: j['actor_name'] as String?,
        targetName: j['target_name'] as String?,
        createdAt: j['created_at'] as String,
      );
}

class SecurityEventPage {
  const SecurityEventPage({required this.events, required this.totalCount});
  final List<SecurityEvent> events;
  final int totalCount;
  factory SecurityEventPage.fromRows(List<Map<String, dynamic>> rows) => SecurityEventPage(
        events: rows.map(SecurityEvent.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : (rows.first['total_count'] as num).toInt(),
      );
}

class CreateStaffResult {
  const CreateStaffResult({required this.userId, required this.linked, required this.temporaryPassword});
  final String userId;
  final bool linked;
  final String? temporaryPassword;
}
