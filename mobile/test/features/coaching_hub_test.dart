import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/repositories/coaching_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/coaching/coaching_hub.dart';
import 'package:gameall_club_mobile/features/coaching/coaching_hub_screen.dart';

ProgramRow program(String id, {ProgramStatus status = ProgramStatus.active, int students = 0, int sessions = 0, int? price, bool included = false}) => ProgramRow(
      id: id,
      name: 'Prog $id',
      level: 'Beginner',
      ageGroup: 'U12',
      category: 'Badminton',
      defaultDurationMinutes: 60,
      defaultCapacity: 10,
      sessionCount: null,
      defaultPriceMinor: price,
      isMembershipIncluded: included,
      status: status,
      studentCount: students,
      scheduledSessionCount: sessions,
    );

CoachRow coach(String id, String name, {List<String> sports = const ['Badminton'], CoachStatus status = CoachStatus.active, int students = 0, double? years}) => CoachRow(
      id: id,
      userId: 'u-$id',
      fullName: name,
      email: null,
      phone: null,
      avatarUrl: null,
      specialization: null,
      experienceYears: years,
      status: status,
      programCount: 0,
      sessionCount: 0,
      studentCount: students,
      sports: sports,
    );

SessionRow sessionOf(String coachId, DateTime start, {SessionStatus status = SessionStatus.scheduled}) => SessionRow(
      id: 's-${start.millisecondsSinceEpoch}',
      programId: 'p',
      programName: 'P',
      coachId: coachId,
      coachName: 'C',
      courtId: 'c',
      courtName: 'Court',
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      capacity: 5,
      enrolledCount: 1,
      status: status,
    );

EnrollmentRow student(String id, {EnrollmentStatus status = EnrollmentStatus.active, EnrollmentPaymentStatus pay = EnrollmentPaymentStatus.paid, int price = 100000, String start = '2026-10-01'}) =>
    EnrollmentRow(
      id: id,
      studentName: 'Student $id',
      programName: 'Prog',
      startDate: start,
      endDate: null,
      priceMinor: price,
      status: status,
      paymentStatus: pay,
    );

void main() {
  group('programInsights', () {
    test('counts, sums and averages only priced programs', () {
      final i = programInsights([
        program('a', students: 4, sessions: 2, price: 200000),
        program('b', status: ProgramStatus.inactive, students: 1, sessions: 1, price: 400000, included: true),
        program('c'),
      ], total: 12);
      expect((i.total, i.active, i.inactive), (12, 2, 1));
      expect((i.students, i.scheduledSessions), (5, 3));
      expect(i.avgFeeMinor, 300000);
      expect(i.membershipIncluded, 1);
    });
    test('no priced program means no average', () => expect(programInsights([program('a')]).avgFeeMinor, isNull));
  });

  group('studentInsights', () {
    test('active, inactive, unpaid and fees', () {
      final i = studentInsights([
        student('a'),
        student('b', pay: EnrollmentPaymentStatus.pending),
        student('c', pay: EnrollmentPaymentStatus.partial, price: 50000),
        student('d', status: EnrollmentStatus.paused, pay: EnrollmentPaymentStatus.pending),
      ]);
      expect((i.total, i.active, i.inactive), (4, 3, 1));
      expect(i.paymentPending, 2); // only active students count
      expect(i.activeFeesMinor, 250000);
    });
  });

  test('ordering puts active first, then newest or busiest', () {
    final students = orderStudents([
      student('old', start: '2026-01-01'),
      student('paused', status: EnrollmentStatus.paused, start: '2026-12-01'),
      student('new', start: '2026-09-01'),
    ]);
    expect(students.map((s) => s.id), ['new', 'old', 'paused']);
    final programs = orderPrograms([program('a', students: 1), program('off', status: ProgramStatus.inactive, students: 9), program('b', students: 5)]);
    expect(programs.map((p) => p.id), ['b', 'a', 'off']);
  });

  group('coaches', () {
    final arjun = coach('a', 'Arjun Kumar', students: 32, years: 3);
    final priya = coach('p', 'Priya Nair', sports: ['Tennis'], status: CoachStatus.onLeave, students: 10, years: 7.5);
    final all = [priya, arjun];

    test('searches by name or sport', () {
      expect(filterCoaches(all, query: 'arj').map((c) => c.id), ['a']);
      expect(filterCoaches(all, query: 'tennis').map((c) => c.id), ['p']);
      expect(filterCoaches(all, query: 'zzz'), isEmpty);
    });
    test('filters by status and sport', () {
      expect(filterCoaches(all, filters: const CoachFilters(status: CoachStatus.onLeave)).map((c) => c.id), ['p']);
      expect(filterCoaches(all, filters: const CoachFilters(sport: 'Badminton')).map((c) => c.id), ['a']);
    });
    test('sorts', () {
      expect(filterCoaches(all).map((c) => c.id), ['a', 'p']); // name
      expect(filterCoaches(all, filters: const CoachFilters(sort: CoachSort.players)).map((c) => c.id), ['a', 'p']);
      expect(filterCoaches(all, filters: const CoachFilters(sort: CoachSort.experience)).map((c) => c.id), ['p', 'a']);
      expect(filterCoaches(all, filters: const CoachFilters(sort: CoachSort.sessions), perWeek: {'p': 4, 'a': 1}).map((c) => c.id), ['p', 'a']);
    });
    test('labels', () {
      expect(coachSportLabel(arjun), 'Badminton Coach');
      expect(coachSportLabel(coach('x', 'X', sports: [])), 'Coach');
      expect(experienceLabel(3), '3');
      expect(experienceLabel(7.5), '7.5');
      expect(experienceLabel(null), '—');
      expect(const CoachFilters().isActive, isFalse);
      expect(const CoachFilters(sport: 'Tennis').isActive, isTrue);
    });
    test('sessions per week counts the next seven days, not cancelled', () {
      final now = DateTime(2026, 10, 11, 11); // a Sunday: a Mon–Sun week would be almost over
      final week = weekRange(now);
      expect(week.start, DateTime(2026, 10, 11));
      expect(week.end, DateTime(2026, 10, 18));
      final counts = sessionsPerWeek([
        sessionOf('a', DateTime(2026, 10, 11, 16)), // today
        sessionOf('a', DateTime(2026, 10, 14, 9)),
        sessionOf('a', DateTime(2026, 10, 15, 9), status: SessionStatus.cancelled),
        sessionOf('a', DateTime(2026, 10, 18, 9)), // a week out: next window
        sessionOf('p', DateTime(2026, 10, 17, 23)),
      ], now);
      expect(counts, {'a': 2, 'p': 1});
    });
  });

  group('todaysActiveCount (Active Sessions)', () {
    test('counts every session the day has except cancelled ones', () {
      expect(
        todaysActiveCount([
          sessionOf('a', DateTime(2026, 10, 12, 9)),
          sessionOf('a', DateTime(2026, 10, 12, 10), status: SessionStatus.inProgress),
          sessionOf('a', DateTime(2026, 10, 12, 11), status: SessionStatus.cancelled),
          sessionOf('a', DateTime(2026, 10, 12, 12), status: SessionStatus.completed),
        ]),
        3,
      );
    });
    test('is zero when the day has none', () => expect(todaysActiveCount([]), 0));
  });

  group('upcoming sessions', () {
    UpcomingSession at(String id, DateTime t) => UpcomingSession(
          id: id,
          startAt: t,
          endAt: t.add(const Duration(hours: 1)),
          programName: 'P',
          coachName: 'C',
          courtName: 'Court',
          enrolled: 1,
          capacity: 5,
          status: SessionStatus.scheduled,
        );

    test('keeps the next two in start order', () {
      final out = nextSessions([at('c', DateTime(2026, 10, 11, 18)), at('a', DateTime(2026, 10, 11, 16)), at('b', DateTime(2026, 10, 11, 17))]);
      expect(out.map((s) => s.id), ['a', 'b']);
    });
    test('spans days when one session is left today', () {
      final out = nextSessions([at('tomorrow', DateTime(2026, 10, 12, 16)), at('today', DateTime(2026, 10, 11, 16))]);
      expect(out.map((s) => s.id), ['today', 'tomorrow']);
    });
    test('day label', () {
      final now = DateTime(2026, 10, 11, 11);
      expect(sessionDayLabel(DateTime(2026, 10, 11, 16), now: now), 'Today');
      expect(sessionDayLabel(DateTime(2026, 10, 12, 16), now: now), 'Tomorrow');
      expect(sessionDayLabel(DateTime(2026, 10, 14, 16), now: now), '14 Oct');
    });
  });

  group('hub screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionControllerProvider.overrideWith(_OwnerSession.new),
            coachingRepositoryProvider.overrideWithValue(_FakeCoaching()),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const CoachingHubScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('three tabs, each with its own create button and insights', (tester) async {
      await open(tester);
      expect(find.text('Coaching'), findsWidgets);
      expect(find.text('Programs'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('New coach'), findsOneWidget);
      expect(find.text('View More Insights'), findsOneWidget);

      // The hero speaks only about coaches.
      expect(find.text('Active Coaches'), findsWidgets);
      expect(find.text('total coaches'), findsOneWidget);
      expect(find.text('total programs'), findsOneWidget);
      expect(find.text('upcoming sessions'), findsOneWidget);
      expect(find.text('Active students'), findsNothing);

      // The coaches themselves, as in the design — no reviews or stars.
      expect(find.text('Arjun Kumar'), findsOneWidget);
      expect(find.text('Badminton Coach'), findsOneWidget);
      expect(find.text('Players'), findsWidgets);
      expect(find.text('Sessions/Week'), findsWidgets);
      expect(find.text('Years Exp.'), findsWidgets);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.text('Search coaches by name or sport...'), findsOneWidget);
      expect(find.byTooltip('Filter'), findsOneWidget);

      // Upcoming sessions start collapsed and open on tap.
      expect(find.text('Upcoming Coaching Sessions'), findsOneWidget);
      expect(find.text('Beginner Badminton'), findsNothing);
      await tester.tap(find.text('Upcoming Coaching Sessions'));
      await tester.pumpAndSettle();
      expect(find.text('Beginner Badminton'), findsOneWidget);

      await tester.tap(find.text('View More Insights'));
      await tester.pumpAndSettle();
      expect(find.text('Total Coaches'), findsWidgets);
      expect(find.text('Active Coaches'), findsWidgets);
      expect(find.text('Coaching Expense'), findsOneWidget);
      expect(find.text('Scheduled Sessions'), findsWidgets);
      expect(find.text('Active Sessions'), findsNothing);
      expect(find.text('Overall Revenue'), findsNothing);

      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();
      expect(find.text('New program'), findsOneWidget);
      expect(find.text('Total Programs'), findsWidgets);
      await tester.tap(find.text('View More Insights'));
      await tester.pumpAndSettle();
      expect(find.text('Total Programs'), findsWidgets);
      expect(find.text('Active Programs'), findsWidgets);
      expect(find.text('Enrolled Students'), findsWidgets);
      expect(find.text('Available Seats'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Average Fee'), findsNothing);

      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();
      expect(find.text('New student'), findsOneWidget);
      expect(find.text('Total Students'), findsWidgets);
      await tester.tap(find.text('View More Insights'));
      await tester.pumpAndSettle();
      expect(find.text('Total Students'), findsWidgets);
      expect(find.text('Enrolled Students'), findsWidgets);
      expect(find.text('Revenue Collected'), findsWidgets);
      expect(find.text('Payments Pending'), findsWidgets);
      expect(find.text('Payment Pending'), findsNothing);
    });
  });
}

Facility _facility() => Facility(
      id: 'facility-1',
      ownerId: 'owner-1',
      name: 'Test Arena',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '900',
      address: const FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'd', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.completed,
    );

class _OwnerSession extends SessionController {
  @override
  SessionState build() => SessionState(user: null, facility: _facility(), baseRole: 'owner', isLoading: false);
}

class _FakeCoaching implements CoachingRepository {
  @override
  Future<StudentCardStats?> getStudentCardStats(String facilityId) async =>
      const StudentCardStats(totalStudents: 8, enrolledStudents: 5, revenueMinor: 1250000, pendingMinor: 480000);

  @override
  Future<ProgramCardStats?> getProgramCardStats(String facilityId) async =>
      const ProgramCardStats(total: 4, active: 3, enrolled: 13, availableSeats: 7);

  @override
  Future<CoachingOverview> getOverview(String facilityId) async => CoachingOverview(
        activeStudents: 12,
        activePrograms: 3,
        activeCoaches: 2,
        coachesOnLeave: 1,
        sessionsThisMonth: 20,
        activeSessions: 5,
        upcomingSessionsCount: 4,
        revenueThisMonthMinor: 4500000,
        revenueTotalMinor: 91000000,
        upcomingSessions: [
          UpcomingSession(
            id: 's1',
            startAt: DateTime(2026, 10, 14, 16),
            endAt: DateTime(2026, 10, 14, 17),
            programName: 'Beginner Badminton',
            coachName: 'Arjun Kumar',
            courtName: 'Court 1',
            enrolled: 3,
            capacity: 8,
            status: SessionStatus.scheduled,
          ),
        ],
        programs: [],
        studentsByProgram: [],
        studentGrowth: [],
        recentEnrollments: [],
      );

  @override
  Future<CoachPage> listCoaches({required String facilityId, String? search, CoachStatus? status, int limit = 20, int offset = 0}) async =>
      CoachPage(coaches: [coach('a', 'Arjun Kumar', students: 32, years: 3)], totalCount: 1);

  @override
  Future<SessionPage> listSessions({
    required String facilityId,
    DateTime? from,
    DateTime? to,
    String? coachId,
    String? programId,
    SessionStatus? status,
    int limit = 200,
    int offset = 0,
  }) async =>
      const SessionPage(sessions: [], totalCount: 0);

  @override
  Future<ProgramPage> listPrograms({required String facilityId, String? search, ProgramStatus? status, int limit = 20, int offset = 0}) async =>
      ProgramPage(programs: [program('a', students: 3, price: 200000)], totalCount: 1);

  @override
  Future<EnrollmentPage> listEnrollments({
    required String facilityId,
    String? search,
    String? programId,
    EnrollmentStatus? status,
    int limit = 20,
    int offset = 0,
    String? coachId,
    String? level,
    String? statusKey,
  }) async =>
      EnrollmentPage(enrollments: [student('a')], totalCount: 1);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
