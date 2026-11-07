import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';

UpcomingBooking booking(
  String id, {
  required DateTime start,
  String status = 'confirmed',
  String sport = 'Badminton',
  int hours = 1,
}) => UpcomingBooking(
  id: id,
  venueName: 'PlayZone Sports Arena',
  sportName: sport,
  courtName: 'Court 2',
  startTime: start,
  endTime: start.add(Duration(hours: hours)),
  status: status,
);

PlayerHomeData data({
  List<UpcomingBooking> bookings = const [],
  bool history = false,
  String? name,
}) => PlayerHomeData(
  fullName: name,
  unreadNotifications: 0,
  hasActiveMembership: false,
  hasActiveCoaching: false,
  hasBookingHistory: history,
  upcomingBookings: bookings,
);

void main() {
  final now = DateTime(2026, 11, 1, 10);

  group('resolveNextGame', () {
    test('a brand-new player has no bookings yet', () {
      final next = resolveNextGame(data(), now);
      expect(next.kind, NextGameKind.empty);
      expect(next.booking, isNull);
    });

    test(
      'with booking history but nothing coming up: "ready for your next game"',
      () {
        expect(
          resolveNextGame(data(history: true), now).kind,
          NextGameKind.readyForNext,
        );
      },
    );

    test('shows the nearest confirmed booking and counts the rest', () {
      final later = booking('later', start: now.add(const Duration(days: 3)));
      final soon = booking('soon', start: now.add(const Duration(hours: 5)));
      final next = resolveNextGame(
        data(bookings: [later, soon], history: true),
        now,
      );
      expect(next.kind, NextGameKind.upcoming);
      expect(next.booking!.id, 'soon');
      expect(next.moreCount, 1);
    });

    test('a cancelled booking is never shown as confirmed', () {
      final cancelled = booking(
        'x',
        start: now.add(const Duration(hours: 5)),
        status: 'cancelled',
      );
      final next = resolveNextGame(
        data(bookings: [cancelled], history: true),
        now,
      );
      expect(next.kind, NextGameKind.readyForNext);
      expect(next.booking, isNull);
    });

    test('a booking that has already finished is not upcoming', () {
      final done = booking(
        'done',
        start: now.subtract(const Duration(hours: 3)),
      );
      expect(
        resolveNextGame(data(bookings: [done], history: true), now).kind,
        NextGameKind.readyForNext,
      );
    });

    test('a booking in progress still counts', () {
      final playing = booking(
        'now',
        start: now.subtract(const Duration(minutes: 20)),
      );
      expect(
        resolveNextGame(
          data(bookings: [playing], history: true),
          now,
        ).booking!.id,
        'now',
      );
    });

    test('the sport filter only considers that sport', () {
      final football = booking(
        'f',
        start: now.add(const Duration(hours: 2)),
        sport: 'Football',
      );
      final badminton = booking('b', start: now.add(const Duration(hours: 4)));
      final all = data(bookings: [football, badminton], history: true);
      expect(resolveNextGame(all, now).booking!.id, 'f');
      expect(
        resolveNextGame(all, now, sportName: 'Badminton').booking!.id,
        'b',
      );
      expect(
        resolveNextGame(all, now, sportName: 'Tennis').kind,
        NextGameKind.readyForNext,
      );
    });
  });

  group('PlayerHomeData', () {
    test('first name', () {
      expect(data(name: 'Alex Kumar').firstName, 'Alex');
      expect(data(name: '  Priya  ').firstName, 'Priya');
      expect(data().firstName, 'there');
      expect(data(name: '').firstName, 'there');
    });

    test('is read from the database function result', () {
      final parsed = PlayerHomeData.fromJson({
        'fullName': 'Alex Kumar',
        'unreadNotifications': 3,
        'hasActiveMembership': true,
        'hasActiveCoaching': false,
        'hasBookingHistory': true,
        'upcomingBookings': [
          {
            'id': 'b1',
            'startTime': '2026-11-02T12:30:00+00:00',
            'endTime': '2026-11-02T13:30:00+00:00',
            'status': 'confirmed',
            'venueName': 'PlayZone Sports Arena',
            'venueLogo': null,
            'courtName': 'Court 2',
            'sportName': 'Badminton',
          },
        ],
      });
      expect(parsed.firstName, 'Alex');
      expect(parsed.unreadNotifications, 3);
      expect(parsed.hasActiveMembership, isTrue);
      expect(parsed.hasActiveCoaching, isFalse);
      expect(parsed.upcomingBookings.single.venueName, 'PlayZone Sports Arena');
      expect(
        parsed.upcomingBookings.single.endTime.difference(
          parsed.upcomingBookings.single.startTime,
        ),
        const Duration(hours: 1),
      );
    });

    test('a guest has nothing enrolled or booked', () {
      const guest = PlayerHomeData.guest();
      expect(guest.hasActiveMembership, isFalse);
      expect(guest.hasActiveCoaching, isFalse);
      expect(guest.upcomingBookings, isEmpty);
    });
  });
}
