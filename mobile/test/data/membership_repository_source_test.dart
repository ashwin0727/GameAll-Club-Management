import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/repositories/membership_repository.dart';

/// This repository has no fake/mock Supabase client set up anywhere in this
/// project (see the rest of test/ — every other repository is exercised
/// only indirectly, via its models), so these are static, dependency-free
/// checks on the source itself rather than a call-through test. They exist
/// to guard the specific regression this file fixes: a "member" used to be
/// a Supabase Auth account created via `admin.auth.admin.createUser()`
/// (through a now-deleted `/api/members` HTTP route); a member is now a
/// plain facility customer record written directly via RLS, exactly like
/// `GuestRepository` does for guest players. See
/// supabase/migrations/0013_facility_members.sql for the authoritative
/// contract.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/membership_repository.dart').readAsStringSync();
  });

  group('Member creation is a plain customer record', () {
    test('createMember calls the create_member RPC', () {
      expect(source, contains("_client.rpc(\n        'create_member'"));
    });

    test('updateMember calls the update_member RPC', () {
      expect(source, contains("_client.rpc(\n        'update_member'"));
    });

    test('createMember/updateMember never touch Supabase Auth or an HTTP API', () {
      expect(source, isNot(contains('.auth.admin')));
      expect(source, isNot(contains('createUser(')));
      expect(source, isNot(contains('http.post')));
      expect(source, isNot(contains('http.patch')));
      expect(source, isNot(contains("import 'package:http")));
    });

    test('MemberAlreadyExistsException carries the existing member id for duplicate-phone handling', () {
      expect(MemberAlreadyExistsException('existing-id').existingMemberId, 'existing-id');
      expect(source, contains('class MemberAlreadyExistsException implements Exception'));
    });
  });
}