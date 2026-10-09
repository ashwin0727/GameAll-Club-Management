import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/add_member_wizard.dart';

AssignableBatch batch(String id, String plan, String court, String start, {List<int> days = const [3, 1, 2]}) => AssignableBatch(
      batchId: id,
      name: 'b',
      planId: plan,
      courtId: court,
      courtName: court == 'c1' ? 'Court 1' : 'Court 2',
      facilitySportId: 'fs',
      sportName: 'Badminton',
      daysOfWeek: days,
      startTime: '$start:00',
      endTime: '08:00:00',
      capacity: 999,
      enrolledCount: 0,
      spare: 999,
    );

AddMemberDraft valid() => AddMemberDraft()
  ..fullName = 'Arun Kumar'
  ..phone = '9876543210'
  ..planId = 'p1'
  ..planName = 'Monthly'
  ..durationDays = 30
  ..membershipFeeInr = 2500
  ..paymentAmount = 2500
  ..receivedFrom = 'Arun'
  ..collectedBy = 'Staff';

void main() {
  test('addMemberSplitPhone reverses the stored form', () {
    expect(addMemberSplitPhone('9876543210'), (code: '+91', number: '9876543210'));
    expect(addMemberSplitPhone('+44 7700900123'), (code: '+44', number: '7700900123'));
  });

  test('four steps, no playing schedule', () {
    expect(addMemberSteps.map((s) => s.title), ['Personal Information', 'Select Plan', 'Review & Confirm', 'Payment']);
  });

  group('step 1', () {
    test('name and phone required', () {
      final e = addMemberFieldErrors(0, AddMemberDraft());
      expect(e['fullName'], 'Full name is required.');
      expect(e['phone'], 'Phone number is required.');
    });
    test('indian mobile rules', () {
      expect(addMemberFieldErrors(0, valid()..phone = '12345')['phone'], 'Phone number is invalid.');
      expect(addMemberFieldErrors(0, valid()..phone = '+91 98765 43210'), isEmpty);
    });
    test('pincode and email', () {
      expect(addMemberFieldErrors(0, valid()..pincode = '6000')['pincode'], isNotNull);
      expect(addMemberFieldErrors(0, valid()..email = 'nope')['email'], isNotNull);
    });
  });

  test('step 2 needs a plan, caps GST at 28', () {
    expect(addMemberFieldErrors(1, AddMemberDraft())['planId'], 'Membership plan is required.');
    expect(addMemberFieldErrors(1, valid()..gstPercent = 29)['gstPercent'], isNotNull);
    expect(addMemberFieldErrors(1, valid()), isEmpty);
  });

  group('payment step', () {
    test('amount required on every tab', () {
      expect(addMemberFieldErrors(3, valid()..paymentAmount = 0)['paymentAmount'], isNotNull);
    });
    test('link tab needs nothing else', () {
      expect(addMemberFieldErrors(3, valid()..receivedFrom = ''), isEmpty);
    });
    test('offline needs received/collected and a reference for UPI', () {
      final d = valid()
        ..paymentTab = AddMemberPaymentTab.offline
        ..receivedFrom = ''
        ..collectedBy = ''
        ..paymentMethod = 'UPI';
      expect(addMemberFieldErrors(3, d).keys, containsAll(['receivedFrom', 'collectedBy', 'paymentReference']));
    });
  });

  test('furthest step stops at first invalid one', () {
    expect(addMemberFurthestStep(AddMemberDraft()), 0);
    expect(addMemberFurthestStep(valid()..planId = ''), 1);
    expect(addMemberFurthestStep(valid()), 3);
  });

  group('plan slots', () {
    test('only the plan\'s slots, sorted and trimmed', () {
      final slots = planSlotsFor([batch('a', 'p1', 'c2', '06:00'), batch('b', 'p1', 'c1', '09:00'), batch('c', 'other', 'c1', '07:00'), batch('d', 'p1', 'c1', '07:00')], 'p1');
      expect(slots.map((s) => s.batchId), ['d', 'b', 'a']);
      expect(slots.first.daysOfWeek, [1, 2, 3]);
      expect(slots.first.startTime, '07:00');
    });
    test('empty without a plan', () => expect(planSlotsFor([batch('a', 'p1', 'c1', '07:00')], ''), isEmpty));
  });

  test('address, notes and phone composition', () {
    final d = valid()
      ..address = '12 MG Road'
      ..city = 'Chennai'
      ..pincode = '600040'
      ..emergencyName = 'Suresh'
      ..emergencyPhone = '9876512345';
    expect(addMemberComposeAddress(d), '12 MG Road, Chennai - 600040');
    expect(addMemberComposeNotes(d), 'Emergency contact: Suresh — +91 9876512345');
    expect(addMemberComposePhone('+91', '98765 43210'), '9876543210');
    expect(addMemberComposePhone('+44', '7700 900123'), '+44 7700900123');
  });

  test('payment notes only for offline tabs', () {
    final d = valid()
      ..paymentTab = AddMemberPaymentTab.offline
      ..paymentDate = DateTime(2026, 10, 9)
      ..paymentAmount = 125000;
    expect(addMemberComposePaymentNotes(d), startsWith('Payment: ₹1,25,000 on 2026-10-09 via Cash.'));
    expect(addMemberComposePaymentNotes(d..paymentTab = AddMemberPaymentTab.link), isNull);
  });

  test('splitPlanName', () {
    expect(splitPlanName('Batch 1(5 A.M to 6 A.M)'), (main: 'Batch 1', detail: '(5 A.M to 6 A.M)'));
    expect(splitPlanName('Monthly').detail, isNull);
  });
}
