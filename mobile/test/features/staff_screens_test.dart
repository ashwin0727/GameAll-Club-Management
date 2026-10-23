import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/staff.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/data/repositories/staff_repository.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/staff/access_history_screen.dart';
import 'package:gameall_club_mobile/features/staff/roles_screen.dart';
import 'package:gameall_club_mobile/features/staff/staff_details_screen.dart';
import 'package:gameall_club_mobile/features/staff/staff_list_screen.dart';

Facility _facility() => Facility(
      id: 'facility-1',
      ownerId: 'owner-1',
      name: 'Champz Turf',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '900',
      address: const FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'd', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.completed,
    );

class _FakeSession extends SessionController {
  @override
  SessionState build() => SessionState(facility: _facility(), baseRole: 'owner', isLoading: false);
}

final _staffRow = <String, dynamic>{
  'assignment_id': 'a1',
  'user_id': 'u1',
  'full_name': 'Ravi Kumar',
  'email': 'ravi@x.com',
  'login_email': 'ravi23102026153045@gameall.co',
  'first_name': 'Ravi',
  'last_name': 'Kumar',
  'phone': '9876543210',
  'avatar_url': null,
  'role_id': null,
  'role_name': 'Staff',
  'base_role': 'staff',
  'status': 'INVITED',
  'is_primary': true,
  'title': null,
  'facility_count': 1,
  'last_login_at': null,
  'joined_at': '2026-10-23T10:00:45+00:00',
  'total_count': 1,
};

class _FakeStaffRepository implements StaffRepository {
  @override
  Future<StaffPage> listStaff({
    required String facilityId,
    String? search,
    StaffStatus? status,
    String? roleId,
    int limit = 20,
    int offset = 0,
  }) async =>
      StaffPage.fromRows([_staffRow]);

  @override
  Future<List<RoleRow>> listRoles(String facilityId) async => [
        RoleRow.fromJson({'id': 'r1', 'key': 'staff', 'name': 'Staff', 'is_system': true, 'staff_count': 1, 'permission_count': 5}),
      ];

  @override
  Future<List<Permission>> listPermissions() async => const [];

  @override
  Future<List<RoleTemplate>> listRoleTemplates() async => const [];

  @override
  Future<SecurityEventPage> listSecurityEvents({required String facilityId, String? event, int limit = 25, int offset = 0}) async =>
      SecurityEventPage.fromRows([
        {
          'id': 'e1',
          'event': 'STAFF_INVITED',
          'summary': 'Ravi Kumar invited',
          'actor_name': 'Owner',
          'target_name': 'Ravi Kumar',
          'detail': <String, dynamic>{},
          'created_at': '2026-10-23T10:00:45+00:00',
          'total_count': 1,
        }
      ]);

  @override
  Future<StaffDetail> getStaff(String facilityId, String userId) async => StaffDetail.fromJson({
        'userId': 'u1',
        'fullName': 'Ravi Kumar',
        'email': 'ravi@x.com',
        'loginEmail': 'ravi23102026153045@gameall.co',
        'firstName': 'Ravi',
        'lastName': 'Kumar',
        'hasGeneratedLogin': true,
        'phone': '9876543210',
        'avatarUrl': null,
        'mustResetPassword': true,
        'assignment': {
          'assignmentId': 'a1',
          'roleId': null,
          'roleName': 'Staff',
          'baseRole': 'staff',
          'status': 'INVITED',
          'isPrimary': true,
          'title': null,
          'notes': null,
          'joinedAt': '2026-10-23T10:00:45+00:00',
          'invitedAt': '2026-10-23T10:00:45+00:00',
          'activatedAt': null,
          'lastLoginAt': null,
        },
        'facilityAccess': <dynamic>[],
        'permissions': <dynamic>[],
        'recentActivity': <dynamic>[],
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        staffRepositoryProvider.overrideWithValue(_FakeStaffRepository()),
        sessionControllerProvider.overrideWith(_FakeSession.new),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => screen)]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Staff list loads and shows the login email', (tester) async {
    await _pump(tester, const StaffListScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.textContaining('ravi23102026153045@gameall.co'), findsOneWidget);
  });

  testWidgets('Roles loads', (tester) async {
    await _pump(tester, const RolesScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Staff'), findsWidgets);
  });

  testWidgets('Access history loads', (tester) async {
    await _pump(tester, const AccessHistoryScreen());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Ravi Kumar invited'), findsOneWidget);
  });

  testWidgets('Staff details loads with the login email and Reset Password', (tester) async {
    await _pump(tester, const StaffDetailsScreen(userId: 'u1'));
    expect(tester.takeException(), isNull);
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(find.textContaining('ravi23102026153045@gameall.co'), findsWidgets);
    expect(find.text('Reset Password'), findsOneWidget);
  });
}
