import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/membership_slot.dart';

/// Parity gap G3 — the membership court-time-slot / batch subsystem.
///
/// `create_membership_full` / `update_membership_full` (0029 / 0038) take
/// `p_batch_id` (join an existing batch) or `p_new_batch` jsonb
/// (`{courtId, facilitySportId, daysOfWeek, startTime, endTime, capacity}` —
/// create one). The old cosmetic `p_time_slot_start/end` args are gone.
/// Mirrors src/features/memberships/slot-form.ts + court-time-slot-section.tsx.
void main() {
  group('AssignableBatch.fromJson', () {
    test('maps a list_assignable_batches row', () {
      final b = AssignableBatch.fromJson({
        'batch_id': 'batch-1',
        'name': 'Morning Badminton',
        'plan_id': 'plan-1',
        'court_id': 'court-1',
        'court_name': 'Court 2',
        'facility_sport_id': 'fs-1',
        'sport_name': 'Badminton',
        'days_of_week': [1, 3, 5],
        'start_time': '06:00:00',
        'end_time': '07:00:00',
        'capacity': 8,
        'enrolled_count': 5,
        'spare': 3,
      });

      expect(b.batchId, 'batch-1');
      expect(b.courtId, 'court-1');
      expect(b.facilitySportId, 'fs-1');
      expect(b.daysOfWeek, [1, 3, 5]);
      expect(b.startTime, '06:00:00');
      expect(b.capacity, 8);
      expect(b.enrolledCount, 5);
      expect(b.spare, 3);
    });
  });

  group('validateSlotSelection', () {
    test('accepts "no slot"', () {
      expect(validateSlotSelection(const SlotNone()), isNull);
    });

    test('accepts an existing batch, rejects an empty batch id', () {
      expect(validateSlotSelection(const SlotExisting('batch-1')), isNull);
      expect(validateSlotSelection(const SlotExisting('')), isNotNull);
    });

    test('a new slot needs a court, at least one day, a valid time range and capacity >= 1', () {
      NewSlotDraft draft({
        String courtId = 'court-1',
        List<int> days = const [1, 2],
        String start = '06:00',
        String end = '07:00',
        int? capacity = 8,
      }) =>
          NewSlotDraft(
            facilitySportId: 'fs-1',
            courtId: courtId,
            daysOfWeek: days,
            startTime: start,
            endTime: end,
            capacity: capacity,
          );

      expect(validateSlotSelection(SlotNew(draft())), isNull);
      expect(validateSlotSelection(SlotNew(draft(courtId: ''))), contains('court'));
      expect(validateSlotSelection(SlotNew(draft(days: const []))), contains('day'));
      expect(validateSlotSelection(SlotNew(draft(start: '07:00', end: '06:00'))), contains('after'));
      expect(validateSlotSelection(SlotNew(draft(capacity: 0))), contains('capacity'));
      expect(validateSlotSelection(SlotNew(draft(capacity: null))), contains('capacity'));
    });
  });

  group('slot selection -> RPC arguments', () {
    test('SlotNone sends neither batch id nor new batch', () {
      final args = slotRpcArgs(const SlotNone());
      expect(args['p_batch_id'], isNull);
      expect(args['p_new_batch'], isNull);
    });

    test('SlotExisting sends only the batch id', () {
      final args = slotRpcArgs(const SlotExisting('batch-9'));
      expect(args['p_batch_id'], 'batch-9');
      expect(args['p_new_batch'], isNull);
    });

    test('SlotNew sends the jsonb payload the RPC destructures, camelCase keys', () {
      final args = slotRpcArgs(SlotNew(NewSlotDraft(
        facilitySportId: 'fs-1',
        courtId: 'court-1',
        daysOfWeek: const [1, 3, 5],
        startTime: '06:00',
        endTime: '07:00',
        capacity: 10,
      )));
      expect(args['p_batch_id'], isNull);
      expect(args['p_new_batch'], {
        'courtId': 'court-1',
        'facilitySportId': 'fs-1',
        'daysOfWeek': [1, 3, 5],
        'startTime': '06:00',
        'endTime': '07:00',
        'capacity': 10,
      });
    });
  });

  group('MembershipRepository — batch args on the wire', () {
    late String source;
    setUpAll(() {
      source = File('lib/data/repositories/membership_repository.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
    });

    test('listAssignableBatches calls the RPC with facility + optional plan', () {
      expect(source, contains("'list_assignable_batches'"));
      expect(source, contains("'p_facility_id':"));
      expect(source, contains("'p_plan_id':"));
    });

    test('create_membership_full sends p_batch_id / p_new_batch and no longer the dead time-slot args', () {
      expect(source, contains("'p_batch_id':"));
      expect(source, contains("'p_new_batch':"));
      expect(source, isNot(contains("'p_time_slot_start'")));
      expect(source, isNot(contains("'p_time_slot_end'")));
    });

    test('update_membership_full also carries the batch args', () {
      // both call sites reference the shared slot args
      final batchIdCount = "'p_batch_id':".allMatches(source).length;
      expect(batchIdCount, greaterThanOrEqualTo(2));
    });
  });
}
