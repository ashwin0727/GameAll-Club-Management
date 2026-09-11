import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/coaching.dart';

/// Real fromJson mapping over the payload shapes migrations 0082-0086's RPCs
/// return. Money fields are integer minor units (paise).
void main() {
  test('enums round-trip through the DB spellings', () {
    expect(SessionStatus.fromJson('IN_PROGRESS'), SessionStatus.inProgress);
    expect(SessionStatus.inProgress.label, 'In Progress');
    expect(SessionStatus.confirmed.isLive, isTrue);
    expect(SessionStatus.completed.isLive, isFalse);
    expect(CoachStatus.fromJson('ON_LEAVE'), CoachStatus.onLeave);
    expect(CoachStatus.onLeave.toJson(), 'ON_LEAVE');
    expect(EnrollmentStatus.fromJson('PAUSED'), EnrollmentStatus.paused);
    expect(EnrollmentPaymentStatus.fromJson('PARTIAL').label, 'Partially Paid');
    expect(ProgressStatus.fromJson('AT_RISK').toJson(), 'AT_RISK');
  });

  test('CoachPage maps a list_coaches row and carries total_count', () {
    final page = CoachPage.fromRows([
      {
        'id': 'c1',
        'user_id': 'u1',
        'full_name': 'Rahul Mehta',
        'email': 'rahul@x.com',
        'phone': null,
        'avatar_url': null,
        'specialization': 'Beginner, Intermediate',
        'experience_years': 5,
        'status': 'ACTIVE',
        'program_count': 2,
        'session_count': 18,
        'student_count': 42,
        'total_count': 6,
      }
    ]);
    expect(page.totalCount, 6);
    expect(page.coaches.single.fullName, 'Rahul Mehta');
    expect(page.coaches.single.studentCount, 42);
    expect(page.coaches.single.experienceYears, 5.0);
  });

  test('CoachPage.fromRows is empty-safe', () {
    final page = CoachPage.fromRows(const []);
    expect(page.coaches, isEmpty);
    expect(page.totalCount, 0);
  });

  test('SessionPage maps a list_coaching_sessions row', () {
    final page = SessionPage.fromRows([
      {
        'id': 's1',
        'program_id': 'p1',
        'program_name': 'Beginner Group',
        'coach_id': 'c1',
        'coach_name': 'Rahul',
        'court_id': 'ct1',
        'court_name': 'Court 1',
        'start_at': '2026-09-08T03:30:00Z',
        'end_at': '2026-09-08T04:30:00Z',
        'capacity': 10,
        'enrolled_count': 8,
        'status': 'CONFIRMED',
        'total_count': 1,
      }
    ]);
    final s = page.sessions.single;
    expect(s.programName, 'Beginner Group');
    expect(s.enrolledCount, 8);
    expect(s.capacity, 10);
    expect(s.status, SessionStatus.confirmed);
  });

  test('SessionDetail maps the get_coaching_session jsonb shape (progress gated)', () {
    final d = SessionDetail.fromJson({
      'id': 's1',
      'facilityId': 'f1',
      'programId': 'p1',
      'programName': 'Beginner Group',
      'programLevel': 'Beginner',
      'coachId': 'c1',
      'coachName': 'Rahul',
      'courtId': 'ct1',
      'courtName': 'Court 1',
      'startAt': '2026-09-08T03:30:00Z',
      'endAt': '2026-09-08T04:30:00Z',
      'capacity': 10,
      'status': 'SCHEDULED',
      'notes': null,
      'objective': 'Footwork drills',
      'objectiveResult': null,
      'cancelReason': null,
      'enrolledCount': 1,
      'students': [
        {'enrollmentId': 'e1', 'memberId': 'm1', 'name': 'Arun', 'phone': '9', 'status': 'ENROLLED', 'enrollmentStatus': 'ACTIVE'}
      ],
      'progressNotes': null, // caller lacks COACHING_VIEW_PROGRESS
      'events': [
        {'id': 'ev1', 'event': 'SESSION_CREATED', 'summary': 'Session scheduled', 'actorName': 'Priya', 'createdAt': '2026-09-01T09:00:00Z'}
      ],
    });
    expect(d.objective, 'Footwork drills');
    expect(d.students.single.name, 'Arun');
    expect(d.canViewProgress, isFalse);
    expect(d.progressNotes, isEmpty);
    expect(d.events.single.summary, 'Session scheduled');
  });

  test('EnrollmentDetail computes outstanding and membership-included flag', () {
    final e = EnrollmentDetail.fromJson({
      'id': 'e1',
      'facilityId': 'f1',
      'studentName': 'Arun Sharma',
      'studentPhone': '9',
      'programId': 'p1',
      'programName': 'Beginner',
      'programLevel': 'Beginner',
      'coachName': null,
      'startDate': '2026-09-01',
      'endDate': '2026-10-26',
      'sessionsTotal': 8,
      'priceMinor': 300000,
      'paidMinor': 100000,
      'outstandingMinor': 200000,
      'pricingType': 'STANDARD',
      'status': 'ACTIVE',
      'notes': null,
      'cancelReason': null,
      'createdAt': '2026-09-01T10:15:00Z',
      'sessions': const [],
      'payments': [
        {'id': 'pay1', 'amountMinor': 100000, 'paidAt': '2026-09-01T11:00:00Z', 'method': 'UPI', 'reference': null}
      ],
      'progressNotes': const [],
    });
    expect(e.outstandingMinor, 200000);
    expect(e.isMembershipIncluded, isFalse);
    expect(e.payments.single.amountMinor, 100000);
    expect(e.canViewProgress, isTrue);
  });

  test('CoachingOverview maps kpis', () {
    final o = CoachingOverview.fromJson({
      'kpis': {
        'activeStudents': 24,
        'activePrograms': 6,
        'activeCoaches': 4,
        'coachesOnLeave': 1,
        'sessionsThisMonth': 72,
        'upcomingSessions': 5,
        'revenueThisMonthMinor': 4500000,
      },
      'upcomingSessions': const [],
      'activePrograms': const [],
      'studentsByProgram': const [],
      'studentGrowth': const [],
      'recentEnrollments': const [],
    });
    expect(o.activeStudents, 24);
    expect(o.coachesOnLeave, 1);
    expect(o.revenueThisMonthMinor, 4500000);
  });
}
