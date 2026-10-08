import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart';

/// Coaching rules the mobile app shares with the web: the fee a student is charged, program
/// batches, the "locked once students have joined" rule, and the richer enrollment rows.
void main() {
  ProgramOption option({int? price = 10000, int? discount, double? tax, bool included = false, String feeType = 'ONE_TIME', String? end}) =>
      ProgramOption(
        id: 'p1',
        name: 'Squad',
        defaultCapacity: 10,
        defaultDurationMinutes: 60,
        defaultPriceMinor: price,
        isMembershipIncluded: included,
        sessionCount: null,
        earlyBirdDiscountMinor: discount,
        taxPercent: tax,
        feeType: feeType,
        endDate: end,
      );

  group('ProgramOption.chargeMinor — (fee − early-bird discount) + tax, same as the web wizard', () {
    test('plain fee', () => expect(option().chargeMinor, 10000));
    test('discount comes off before tax', () => expect(option(discount: 1000).chargeMinor, 9000));
    test('tax is rounded to whole rupees (₹90 × 18% = ₹16.20 → ₹16)', () {
      expect(option(discount: 1000, tax: 18).chargeMinor, 10600);
    });
    test('a discount larger than the fee never goes negative', () => expect(option(discount: 99999).chargeMinor, 0));
    test('membership-included programs cost nothing', () => expect(option(included: true).chargeMinor, 0));
    test('a program with no price costs nothing to compute', () => expect(option(price: null).chargeMinor, 0));
  });

  group('ProgramOption payment methods', () {
    ProgramOption withMode(String mode) => ProgramOption.fromJson({
          'id': 'p1',
          'name': 'x',
          'default_capacity': 1,
          'default_duration_minutes': 60,
          'is_membership_included': false,
          'payment_mode': mode,
        });
    test('OFFLINE hides the online option', () => expect(withMode('OFFLINE').onlineAllowed, isFalse));
    test('ONLINE and BOTH allow it', () {
      expect(withMode('ONLINE').onlineAllowed, isTrue);
      expect(withMode('BOTH').onlineAllowed, isTrue);
    });
  });

  group('ProgramBatch', () {
    test('reads the embedded camelCase shape (get_coaching_program)', () {
      final b = ProgramBatch.fromJson({
        'id': 'b1',
        'name': 'Evening Batch',
        'daysOfWeek': [1, 3, 5],
        'startTime': '17:00:00',
        'endTime': '18:00:00',
        'capacity': 12,
        'status': 'ACTIVE',
        'courtId': 'c1',
        'courtName': 'Court 1',
        'coachId': 'co1',
        'coachName': 'Siva',
      });
      expect(b.scheduleLabel, 'Mon, Wed, Fri · 17:00–18:00');
      expect(b.coachName, 'Siva');
      expect(b.enrolledCount, isNull);
      expect(b.isFull, isFalse); // an unknown fill level is never treated as full
    });

    test('reads list_coaching_program_batches rows and knows when it is full', () {
      final b = ProgramBatch.fromJson({
        'id': 'b1',
        'name': 'Morning',
        'days_of_week': [6, 0],
        'start_time': '07:00:00',
        'end_time': '08:30:00',
        'capacity': 5,
        'enrolled_count': 5,
        'status': 'ACTIVE',
        'court_id': 'c1',
        'court_name': 'Court 2',
      });
      expect(b.scheduleLabel, 'Sun, Sat · 07:00–08:30');
      expect(b.isFull, isTrue);
    });
  });

  group('ProgramDetail lock', () {
    ProgramDetail detail(int activeStudents) => ProgramDetail.fromJson({
          'id': 'p1',
          'name': 'Junior SSBA',
          'stats': {'activeStudents': activeStudents, 'totalEnrollments': activeStudents},
          'feeType': 'MONTHLY',
          'startDate': '2026-11-02',
          'endDate': '2027-04-19',
          'batches': [
            {'id': 'b1', 'name': 'B', 'daysOfWeek': [1], 'startTime': '17:00', 'endTime': '18:00', 'capacity': 5},
          ],
        });

    test('free to change while nobody has joined', () {
      expect(detail(0).isLocked, isFalse);
      expect(detail(0).lockReason, isNull);
    });
    test('locked, with the web wording, once students have joined', () {
      expect(detail(1).isLocked, isTrue);
      expect(detail(1).lockReason, "1 student is enrolled in this program, so it can't be edited or deactivated.");
      expect(detail(2).lockReason, "2 students are enrolled in this program, so it can't be edited or deactivated.");
    });
    test('carries the dates, fee type and batches', () {
      final d = detail(0);
      expect(d.isMonthly, isTrue);
      expect(d.startDate, '2026-11-02');
      expect(d.endDate, '2027-04-19');
      expect(d.batches.single.id, 'b1');
    });
  });

  group('EnrollmentRow', () {
    test('keeps the roster columns the Manage Students screen shows', () {
      final r = EnrollmentRow.fromJson({
        'id': 'e1',
        'student_name': 'Vignesh',
        'student_phone': '8372403472',
        'student_age': 15,
        'program_id': 'p1',
        'program_name': 'Junior SSBA',
        'batch_name': 'Evening Batch',
        'coach_name': 'Siva Anandhan',
        'start_date': '2026-11-02',
        'end_date': '2027-04-19',
        'price_minor': 600000,
        'status': 'ACTIVE',
        'payment_status': 'PARTIAL',
      });
      expect(r.studentPhone, '8372403472');
      expect(r.studentAge, 15);
      expect(r.programId, 'p1');
      expect(r.batchName, 'Evening Batch');
      expect(r.coachName, 'Siva Anandhan');
      expect(r.paymentStatus, EnrollmentPaymentStatus.partial);
    });

    test('older payloads without the new columns still parse', () {
      final r = EnrollmentRow.fromJson({
        'id': 'e1',
        'student_name': 'A',
        'program_name': 'P',
        'start_date': '2026-01-01',
        'price_minor': 0,
        'status': 'ACTIVE',
        'payment_status': 'INCLUDED',
      });
      expect(r.programId, '');
      expect(r.batchName, isNull);
    });
  });

  test('EnrollmentDetail exposes the batch', () {
    final d = EnrollmentDetail.fromJson({
      'id': 'e1',
      'facilityId': 'f1',
      'studentName': 'V',
      'programId': 'p1',
      'programName': 'Junior SSBA',
      'batchName': 'Evening Batch',
      'startDate': '2026-11-02',
      'priceMinor': 100,
      'paidMinor': 0,
      'outstandingMinor': 100,
      'pricingType': 'STANDARD',
      'status': 'ACTIVE',
      'createdAt': '2026-10-07T00:00:00Z',
      'sessions': <dynamic>[],
      'payments': <dynamic>[],
    });
    expect(d.batchName, 'Evening Batch');
  });
}
