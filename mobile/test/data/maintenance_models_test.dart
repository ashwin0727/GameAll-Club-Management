import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/maintenance.dart';

/// Real fromJson mapping over the exact payload shapes migration
/// 0068_maintenance_module.sql's RPCs return.
void main() {
  test('priority + status enums round-trip through the DB spellings', () {
    expect(MaintenancePriorityX.fromJson('CRITICAL'), MaintenancePriority.critical);
    expect(MaintenancePriority.high.toJson(), 'HIGH');
    expect(MaintenanceStatusX.fromJson('IN_PROGRESS'), MaintenanceStatus.inProgress);
    expect(MaintenanceStatus.inProgress.label, 'In Progress');
    expect(MaintenanceStatus.reported.label, 'Open');
    expect(CourtMaintenanceStatusX.fromJson('UNDER_MAINTENANCE'), CourtMaintenanceStatus.underMaintenance);
  });

  test('MaintenanceTicketListRow maps a list_maintenance_tickets row', () {
    final row = MaintenanceTicketListRow.fromJson({
      'ticket_id': 't1',
      'code': 'MT-ABCD',
      'court_id': 'c1',
      'court_name': 'Court 2',
      'sport_name': 'Badminton',
      'issue_category_id': 'cat1',
      'category_name': 'Net Damaged',
      'title': 'Net torn',
      'priority': 'HIGH',
      'status': 'REPORTED',
      'reported_by_name': 'Rahul',
      'assigned_to_name': null,
      'scheduled_start': null,
      'reported_at': '2026-09-01T10:30:00Z',
      'actual_cost_minor': null,
      'estimated_cost_minor': 200000,
      'total_count': 8,
    });
    expect(row.code, 'MT-ABCD');
    expect(row.priority, MaintenancePriority.high);
    expect(row.status, MaintenanceStatus.reported);
    expect(row.assignedToName, isNull);
    expect(row.estimatedCostMinor, 200000);
  });

  test('MaintenanceTicketDetail maps the aggregate jsonb payload', () {
    final detail = MaintenanceTicketDetail.fromJson({
      'id': 't1',
      'code': 'MT-ABCD',
      'facilityId': 'f1',
      'court': {'id': 'c1', 'name': 'Court 2'},
      'sportName': 'Badminton',
      'category': {'id': 'cat1', 'name': 'Net Damaged', 'icon': 'court'},
      'title': 'Net torn',
      'description': 'The net is torn in the centre.',
      'priority': 'HIGH',
      'status': 'SCHEDULED',
      'reportedBy': {'id': 'u1', 'name': 'Rahul Kumar'},
      'reportedAt': '2026-09-01T10:30:00Z',
      'assignedTo': {'id': 'u2', 'name': 'Suresh'},
      'scheduledStart': '2026-09-01T09:00:00Z',
      'scheduledEnd': '2026-09-01T13:00:00Z',
      'actualStart': null,
      'actualEnd': null,
      'estimatedCostMinor': 200000,
      'actualCostMinor': null,
      'expenseId': null,
      'notes': null,
      'currency': 'INR',
      'activeBlock': {'id': 'b1', 'startTime': '2026-09-01T09:00:00Z', 'endTime': '2026-09-01T13:00:00Z', 'status': 'ACTIVE'},
      'attachments': [
        {'id': 'a1', 'storagePath': 'f1/t1/x.jpg', 'fileName': 'x.jpg', 'contentType': 'image/jpeg', 'sizeBytes': 1234, 'createdAt': '2026-09-01T11:00:00Z'}
      ],
      'activity': [
        {'id': 'e1', 'eventType': 'CREATED', 'note': 'Ticket reported', 'metadata': {}, 'actorName': 'Rahul Kumar', 'createdAt': '2026-09-01T10:30:00Z'}
      ],
      'affectedBookings': [
        {
          'bookingId': 'bk1',
          'customerType': 'GUEST',
          'guestName': 'Neha',
          'memberId': null,
          'startTime': '2026-09-01T10:00:00Z',
          'endTime': '2026-09-01T11:00:00Z',
          'status': 'confirmed',
          'paymentStatus': 'PAID',
          'amountMinor': 30000,
        }
      ],
      'affectedSessions': [],
    });
    expect(detail.assignedToName, 'Suresh');
    expect(detail.courtName, 'Court 2');
    expect(detail.categoryName, 'Net Damaged');
    expect(detail.attachments.single.fileName, 'x.jpg');
    expect(detail.activity.single.eventType, 'CREATED');
    expect(detail.affectedBookings.single.guestName, 'Neha');
    expect(detail.status, MaintenanceStatus.scheduled);
  });

  test('MaintenanceOverview maps KPIs, court status and recent tickets', () {
    final o = MaintenanceOverview.fromJson({
      'openIssues': 6,
      'inProgress': 3,
      'scheduled': 2,
      'resolvedThisMonth': 12,
      'courtsBlocked': 2,
      'repairCostThisMonthMinor': 1850000,
      'courtStatus': [
        {'courtId': 'c1', 'courtName': 'Court 1', 'sportName': 'Badminton', 'status': 'AVAILABLE'},
        {'courtId': 'c2', 'courtName': 'Court 2', 'sportName': 'Badminton', 'status': 'UNDER_MAINTENANCE'},
      ],
      'recentTickets': [
        {'ticketId': 't1', 'code': 'MT-0001', 'courtName': 'Court 2', 'title': 'Net damaged', 'priority': 'HIGH', 'status': 'REPORTED', 'reportedAt': '2026-09-01T10:30:00Z', 'assignedToName': 'Rahul'}
      ],
      'upcomingSchedule': [],
      'recentActivity': [],
    });
    expect(o.openIssues, 6);
    expect(o.repairCostThisMonthMinor, 1850000);
    expect(o.courtStatus.last.status, CourtMaintenanceStatus.underMaintenance);
    expect(o.recentTickets.single.code, 'MT-0001');
  });
}
