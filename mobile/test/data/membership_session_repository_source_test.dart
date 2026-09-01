import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// This repository has no fake/mock Supabase client set up anywhere in this
/// project (see test/data/membership_repository_source_test.dart for the
/// precedent this follows), so these are static, dependency-free checks on
/// the source itself rather than a call-through test. They guard the two
/// things most likely to silently drift from the authoritative contract in
/// supabase/migrations/0014_membership_sessions.sql: which RPC each write
/// path calls, and that every 23514 business-rule violation is surfaced to
/// the UI verbatim (the exact DB message, not a generic string) — mirroring
/// the web service's `mapCapacityError` in
/// supabase-membership-session.service.ts.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/membership_session_repository.dart').readAsStringSync();
  });

  group('MembershipSessionRepository calls the contract RPCs', () {
    test('createBatch calls create_membership_batch', () {
      expect(source, contains("'create_membership_batch'"));
    });

    test('updateBatch calls update_membership_batch', () {
      expect(source, contains("'update_membership_batch'"));
    });

    test('assignBatchMember calls assign_batch_member', () {
      expect(source, contains("'assign_batch_member'"));
    });

    test('removeBatchMember calls remove_batch_member', () {
      expect(source, contains("'remove_batch_member'"));
    });

    test('listSessionsForDate calls list_membership_sessions_for_date', () {
      expect(source, contains("'list_membership_sessions_for_date'"));
    });

    test('getOrCreateSession calls get_or_create_membership_session', () {
      expect(source, contains("'get_or_create_membership_session'"));
    });

    test('getSessionCapacity calls get_membership_session_capacity', () {
      expect(source, contains("'get_membership_session_capacity'"));
    });

    test('bookMembershipSlot calls book_membership_slot', () {
      expect(source, contains("'book_membership_slot'"));
    });

    test('releaseCapacity calls release_membership_capacity', () {
      expect(source, contains("'release_membership_capacity'"));
    });

    test('restoreCapacity calls restore_membership_capacity', () {
      expect(source, contains("'restore_membership_capacity'"));
    });

    test('bookGuestSlot calls book_guest_slot', () {
      expect(source, contains("'book_guest_slot'"));
    });

    test('cancelSlotBooking calls cancel_membership_slot_booking', () {
      expect(source, contains("'cancel_membership_slot_booking'"));
    });
  });

  group('Capacity-rule violations (23514) are surfaced verbatim', () {
    test('the capacity error mapper passes the raw Postgres message through, not a generic string', () {
      expect(source, contains("if (error.code == '23514') return AppException(AppErrorCode.membershipCapacityError, error.message);"));
    });

    test('write paths route errors through the capacity mapper, not the generic one', () {
      // createBatch, updateBatch's rpc call, assignBatchMember,
      // removeBatchMember, getOrCreateSession, bookMembershipSlot,
      // releaseCapacity, restoreCapacity, bookGuestSlot, cancelSlotBooking,
      // plus the dashboard writes: getSessionDetail, setSessionNotes,
      // blockDate, unblockDate, duplicateSession.
      const expectedCapacitySensitiveWrites = 15;
      final capacityErrorThrows = RegExp(r'throw _mapCapacityError\(e\);').allMatches(source).length;
      expect(capacityErrorThrows, expectedCapacitySensitiveWrites);
    });
  });
}