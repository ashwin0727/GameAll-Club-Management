import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/guest_booking_dashboard.dart';
import 'package:gameall_club_mobile/features/bookings/booking_status_presentation.dart';

/// Parity gap G4 — released membership-seat guest bookings.
///
/// `list_guest_bookings_admin` (migration 0043) returns a `source` column:
/// `COURT` for an ordinary guest court booking, `SESSION` for a guest sitting
/// in capacity released from a membership session. A SESSION row has no
/// `bookings` record behind it, so the court actions (edit / reschedule /
/// cancel / duplicate / delete) don't apply — the web restricts it to Record
/// Payment (`record_session_guest_payment`) + Invoice. Flutter was ignoring
/// the column and offering every action on every row.
void main() {
  group('GuestBookingRow.source', () {
    test('maps the source column and exposes isSession', () {
      final court = GuestBookingRow.fromJson(_row(source: 'COURT'));
      final session = GuestBookingRow.fromJson(_row(source: 'SESSION'));
      expect(court.source, GuestBookingSource.court);
      expect(court.isSession, isFalse);
      expect(session.source, GuestBookingSource.session);
      expect(session.isSession, isTrue);
    });

    test('defaults to COURT when the column is absent (older list rows)', () {
      final row = GuestBookingRow.fromJson(_row()..remove('source'));
      expect(row.source, GuestBookingSource.court);
    });
  });

  group('guestBookingActions', () {
    test('a court booking offers the full set', () {
      final actions = guestBookingActions(isSession: false, status: 'confirmed', paymentStatus: 'PENDING');
      expect(actions, contains(GuestBookingAction.complete));
      expect(actions, contains(GuestBookingAction.cancel));
      expect(actions, contains(GuestBookingAction.sendReceipt));
      expect(actions, contains(GuestBookingAction.duplicate));
      expect(actions, contains(GuestBookingAction.invoice));
      expect(actions, contains(GuestBookingAction.delete));
      expect(actions, isNot(contains(GuestBookingAction.recordSessionPayment)));
    });

    test('a released membership seat offers only Record Payment and Invoice', () {
      final actions = guestBookingActions(isSession: true, status: 'confirmed', paymentStatus: 'PENDING');
      expect(actions, [GuestBookingAction.recordSessionPayment, GuestBookingAction.invoice]);
    });

    test('a paid or cancelled session seat cannot record another payment', () {
      expect(
        guestBookingActions(isSession: true, status: 'confirmed', paymentStatus: 'PAID'),
        [GuestBookingAction.invoice],
      );
      expect(
        guestBookingActions(isSession: true, status: 'cancelled', paymentStatus: 'PENDING'),
        [GuestBookingAction.invoice],
      );
    });

    test('a completed or cancelled court booking drops Complete', () {
      final done = guestBookingActions(isSession: false, status: 'completed', paymentStatus: 'PAID');
      expect(done, isNot(contains(GuestBookingAction.complete)));
      final cancelled = guestBookingActions(isSession: false, status: 'cancelled', paymentStatus: 'PENDING');
      expect(cancelled, isNot(contains(GuestBookingAction.complete)));
      expect(cancelled, isNot(contains(GuestBookingAction.cancel)));
    });
  });

  group('BookingRepository.recordSessionGuestPayment', () {
    late String source;
    setUpAll(() {
      source = File('lib/data/repositories/booking_repository.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
    });

    test('calls record_session_guest_payment with the session booking id, method and minor-unit amount', () {
      expect(source, contains("'record_session_guest_payment'"));
      expect(source, contains("'p_session_booking_id':"));
      expect(source, contains("'p_method':"));
      expect(source, contains("'p_amount_minor':"));
    });
  });
}

Map<String, dynamic> _row({String source = 'COURT'}) => {
      'booking_id': 'b-1',
      'code': 'GSB1234',
      'guest_name': 'Rahul',
      'guest_phone': null,
      'sport_name': 'Badminton',
      'court_name': 'Court 2',
      'start_time': '2026-08-14T12:30:00Z',
      'end_time': '2026-08-14T13:30:00Z',
      'party_size': 1,
      'amount_minor': 40000,
      'currency': 'INR',
      'payment_status': 'PENDING',
      'payment_method': null,
      'status': 'confirmed',
      'source': source,
      'total_count': 1,
    };
