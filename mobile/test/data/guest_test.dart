import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/guest.dart';

void main() {
  group('GuestPlayer.fromJson', () {
    test('parses a full guest_players row, matching the web app column names', () {
      final guest = GuestPlayer.fromJson({
        'id': 'guest-1',
        'facility_id': 'facility-1',
        'name': 'Arun',
        'phone': '9876543210',
        'email': null,
        'notes': 'Prefers evening slots',
        'status': 'ACTIVE',
        'created_at': '2026-08-01T10:00:00Z',
        'updated_at': '2026-08-20T10:00:00Z',
      });

      expect(guest.name, 'Arun');
      expect(guest.phone, '9876543210');
      expect(guest.status, GuestStatus.active);
      expect(guest.notes, 'Prefers evening slots');
    });

    test('defaults status to ACTIVE when the column is missing', () {
      final guest = GuestPlayer.fromJson({
        'id': 'guest-1',
        'facility_id': 'facility-1',
        'name': 'Arun',
        'created_at': '2026-08-01T10:00:00Z',
        'updated_at': '2026-08-01T10:00:00Z',
      });
      expect(guest.status, GuestStatus.active);
    });
  });

  group('guestStatusToDb', () {
    test('round-trips both statuses', () {
      expect(guestStatusToDb(GuestStatus.active), 'ACTIVE');
      expect(guestStatusToDb(GuestStatus.inactive), 'INACTIVE');
    });
  });

  group('GuestStats.fromJson', () {
    test('parses a full get_guest_stats row', () {
      final stats = GuestStats.fromJson({
        'total_visits': 12,
        'total_bookings': 14,
        'last_visit': '2026-08-24T10:00:00Z',
        'total_amount_minor': 600000,
        'pending_amount_minor': 50000,
        'sports': [
          {'sportId': 'sport-1', 'sportName': 'Badminton'},
        ],
      });

      expect(stats.totalVisits, 12);
      expect(stats.totalBookings, 14);
      expect(stats.lastVisit, isNotNull);
      expect(stats.totalAmountMinor, 600000);
      expect(stats.pendingAmountMinor, 50000);
      expect(stats.sports.single.sportName, 'Badminton');
    });

    test('a guest with no bookings has zeroed stats and no last visit', () {
      final stats = GuestStats.fromJson({
        'total_visits': 0,
        'total_bookings': 0,
        'last_visit': null,
        'total_amount_minor': 0,
        'pending_amount_minor': 0,
        'sports': <dynamic>[],
      });

      expect(stats.totalVisits, 0);
      expect(stats.lastVisit, isNull);
      expect(stats.sports, isEmpty);
    });
  });
}