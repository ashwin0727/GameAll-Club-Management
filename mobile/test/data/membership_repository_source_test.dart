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
    // Normalise line endings — git may check this file out with CRLF on
    // Windows, and these are LF-based `contains` assertions.
    source = File('lib/data/repositories/membership_repository.dart').readAsStringSync().replaceAll('\r\n', '\n');
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

  group('Full Create Membership page write path (web Phase 4 parity)', () {
    test('createMembershipFull calls the create_membership_full RPC', () {
      expect(source, contains("_client.rpc(\n                'create_membership_full'"));
    });

    test('sends every param name the web service sends', () {
      for (final param in const [
        'p_facility_id',
        'p_full_name',
        'p_phone',
        'p_email',
        'p_date_of_birth',
        'p_gender',
        'p_address',
        'p_name',
        'p_membership_type',
        'p_max_family_members',
        'p_start_date',
        'p_duration_days',
        'p_description',
        'p_membership_fee_inr',
        'p_registration_fee_inr',
        'p_gst_percent',
        'p_payment_mode',
        'p_payment_methods',
        'p_payment_reference',
        'p_referral_member_id',
        'p_discovery_source',
        'p_notes',
        'p_monthly_price_inr',
      ]) {
        expect(source, contains("'$param':"), reason: 'missing $param');
      }
    });

    test('payment methods are comma-joined, matching the web service', () {
      expect(source, contains(".join(', ')"));
    });

    test('listMemberships / summary call the shared RPCs', () {
      expect(source, contains("'list_memberships'"));
      expect(source, contains("'get_membership_page_summary'"));
    });

    test('deleteMember calls the guarded delete_member RPC and surfaces its 23514 verbatim', () {
      expect(source, contains("'delete_member'"));
      expect(source, contains("e.code == '23514'"));
    });

    test('recurring subscription goes through the create-membership-subscription Edge Function', () {
      expect(source, contains("'create-membership-subscription'"));
      expect(source, contains('_client.functions.invoke'));
    });
  });
}