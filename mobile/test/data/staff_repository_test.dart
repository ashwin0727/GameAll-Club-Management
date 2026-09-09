import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/staff.dart';

/// Staff / Roles / Permissions (migrations 0072-0077) — model mapping + the
/// repository's RPC contract (this project has no fake Supabase client, so
/// contract cases are static checks on the repository source).
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/staff_repository.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
  });

  group('StaffRow.fromJson', () {
    test('maps a list_staff row including the facility count', () {
      final r = StaffRow.fromJson({
        'assignment_id': 'a1',
        'user_id': 'u1',
        'full_name': 'Priya Sharma',
        'email': 'priya@x.com',
        'phone': null,
        'avatar_url': null,
        'role_id': null,
        'role_name': 'Manager',
        'base_role': 'manager',
        'status': 'ACTIVE',
        'is_primary': true,
        'title': null,
        'facility_count': 2,
        'last_login_at': null,
        'joined_at': '2024-03-05',
        'total_count': 12,
      });
      expect(r.fullName, 'Priya Sharma');
      expect(r.status, StaffStatus.active);
      expect(r.facilityCount, 2);
    });

    test('a pending invitation maps to StaffStatus.invited', () {
      expect(
        StaffRow.fromJson(_minRow('INVITED')).status,
        StaffStatus.invited,
      );
    });
  });

  group('StaffPage', () {
    test('totalCount is the server row total_count, not staff.length', () {
      final p = StaffPage.fromRows([_minRow('ACTIVE', total: 40), _minRow('ACTIVE', total: 40)]);
      expect(p.staff.length, 2);
      expect(p.totalCount, 40);
    });
    test('an empty result is a real zero', () {
      expect(StaffPage.fromRows(const []).totalCount, 0);
    });
  });

  group('StaffDetail.fromJson', () {
    test('flattens the assignment and lists permissions + facility access', () {
      final d = StaffDetail.fromJson({
        'userId': 'u1',
        'fullName': 'Priya',
        'email': 'priya@x.com',
        'phone': '900',
        'avatarUrl': null,
        'assignment': {
          'roleId': 'r1',
          'roleName': 'Manager',
          'baseRole': 'manager',
          'status': 'ACTIVE',
          'isPrimary': true,
          'title': null,
          'notes': 'trial',
          'joinedAt': '2024-03-05',
          'lastLoginAt': null,
        },
        'facilityAccess': [
          {'facilityId': 'f1', 'facilityName': 'Champz Turf', 'roleName': 'Manager', 'baseRole': 'manager', 'status': 'ACTIVE', 'isPrimary': true}
        ],
        'permissions': ['BOOKINGS_VIEW', 'FINANCE_VIEW'],
        'recentActivity': [
          {'id': 'e1', 'event': 'STAFF_ROLE_CHANGED', 'summary': 'Role changed to Manager', 'actorName': 'Arun', 'createdAt': '2024-03-06'}
        ],
      });
      expect(d.roleName, 'Manager');
      expect(d.notes, 'trial');
      expect(d.permissions, contains('FINANCE_VIEW'));
      expect(d.facilityAccess.single.facilityName, 'Champz Turf');
      expect(d.recentActivity.single.summary, 'Role changed to Manager');
    });
  });

  group('RoleRow.fromJson', () {
    test('carries staff_count and permission_count', () {
      final r = RoleRow.fromJson({
        'id': 'r1', 'key': 'manager', 'name': 'Manager', 'description': 'Ops',
        'is_system': true, 'is_custom': false, 'is_active': true, 'version': 1,
        'staff_count': 3, 'permission_count': 20,
      });
      expect(r.isSystem, true);
      expect(r.staffCount, 3);
    });
  });

  group('StaffRepository — RPC contract', () {
    test('calls the 0075/0076 RPCs by name', () {
      for (final rpc in const [
        "'list_staff'", "'get_staff'", "'list_roles'", "'get_role'",
        "'list_role_templates'", "'list_permissions'", "'list_security_events'",
        "'create_role'", "'update_role'", "'delete_role'",
        "'assign_staff_role'", "'set_staff_status'", "'update_staff_profile'",
        "'remove_facility_access'", "'my_facility_permissions'",
        "'mark_password_reset_complete'", "'record_my_login'",
      ]) {
        expect(source, contains(rpc), reason: 'missing $rpc');
      }
    });

    test('creating a new staff account goes through the create-staff edge function', () {
      expect(source, contains("functions.invoke('create-staff'"));
    });

    test('update_role forwards the optimistic-lock version', () {
      expect(source, contains("'p_expected_version': expectedVersion"));
    });

    test('a permission / last-owner / concurrency rejection maps to its own code', () {
      expect(source, contains('AppErrorCode.unauthorized'));
      expect(source, contains('AppErrorCode.lastActiveOwner'));
      expect(source, contains('AppErrorCode.staffConcurrentUpdate'));
      expect(source, contains('AppErrorCode.roleInUse'));
    });

    test('the repository does no authorization of its own — every check is an RPC', () {
      expect(source, isNot(contains('facility_users')), reason: 'no direct role table reads');
      expect(source, isNot(contains('has_permission(')), reason: 'the RPCs enforce, not the client');
    });
  });
}

Map<String, dynamic> _minRow(String status, {int total = 1}) => {
      'assignment_id': 'a',
      'user_id': 'u',
      'full_name': 'X',
      'email': 'x@x.com',
      'phone': null,
      'avatar_url': null,
      'role_id': null,
      'role_name': 'Staff',
      'base_role': 'staff',
      'status': status,
      'is_primary': true,
      'title': null,
      'facility_count': 1,
      'last_login_at': null,
      'joined_at': '2024-01-01',
      'total_count': total,
    };
