/// Maintenance & Court Operations — models mirroring
/// supabase/migrations/0068_maintenance_module.sql and
/// src/features/maintenance/types.ts (the web's equivalent shapes).
library;

enum MaintenancePriority { low, medium, high, critical }

extension MaintenancePriorityX on MaintenancePriority {
  String toJson() => switch (this) {
        MaintenancePriority.low => 'LOW',
        MaintenancePriority.medium => 'MEDIUM',
        MaintenancePriority.high => 'HIGH',
        MaintenancePriority.critical => 'CRITICAL',
      };

  String get label => switch (this) {
        MaintenancePriority.low => 'Low',
        MaintenancePriority.medium => 'Medium',
        MaintenancePriority.high => 'High',
        MaintenancePriority.critical => 'Critical',
      };

  static MaintenancePriority fromJson(String v) => switch (v) {
        'LOW' => MaintenancePriority.low,
        'HIGH' => MaintenancePriority.high,
        'CRITICAL' => MaintenancePriority.critical,
        _ => MaintenancePriority.medium,
      };
}

enum MaintenanceStatus { reported, assigned, scheduled, inProgress, resolved, closed }

extension MaintenanceStatusX on MaintenanceStatus {
  String toJson() => switch (this) {
        MaintenanceStatus.reported => 'REPORTED',
        MaintenanceStatus.assigned => 'ASSIGNED',
        MaintenanceStatus.scheduled => 'SCHEDULED',
        MaintenanceStatus.inProgress => 'IN_PROGRESS',
        MaintenanceStatus.resolved => 'RESOLVED',
        MaintenanceStatus.closed => 'CLOSED',
      };

  String get label => switch (this) {
        MaintenanceStatus.reported => 'Open',
        MaintenanceStatus.assigned => 'Assigned',
        MaintenanceStatus.scheduled => 'Scheduled',
        MaintenanceStatus.inProgress => 'In Progress',
        MaintenanceStatus.resolved => 'Resolved',
        MaintenanceStatus.closed => 'Closed',
      };

  static MaintenanceStatus fromJson(String v) => switch (v) {
        'ASSIGNED' => MaintenanceStatus.assigned,
        'SCHEDULED' => MaintenanceStatus.scheduled,
        'IN_PROGRESS' => MaintenanceStatus.inProgress,
        'RESOLVED' => MaintenanceStatus.resolved,
        'CLOSED' => MaintenanceStatus.closed,
        _ => MaintenanceStatus.reported,
      };
}

enum CourtMaintenanceStatus { available, inUse, underMaintenance, blocked }

extension CourtMaintenanceStatusX on CourtMaintenanceStatus {
  String get label => switch (this) {
        CourtMaintenanceStatus.available => 'Available',
        CourtMaintenanceStatus.inUse => 'In Use',
        CourtMaintenanceStatus.underMaintenance => 'Under Maintenance',
        CourtMaintenanceStatus.blocked => 'Blocked',
      };

  static CourtMaintenanceStatus fromJson(String v) => switch (v) {
        'IN_USE' => CourtMaintenanceStatus.inUse,
        'UNDER_MAINTENANCE' => CourtMaintenanceStatus.underMaintenance,
        'BLOCKED' => CourtMaintenanceStatus.blocked,
        _ => CourtMaintenanceStatus.available,
      };
}

int _int(dynamic v) => v == null ? 0 : (v is int ? v : (v as num).toInt());
int? _intOrNull(dynamic v) => v == null ? null : _int(v);
String _str(dynamic v) => v == null ? '' : v as String;
String? _strOrNull(dynamic v) => v as String?;

class MaintenanceIssueCategory {
  const MaintenanceIssueCategory({
    required this.id,
    required this.facilityId,
    required this.name,
    required this.icon,
    required this.description,
    required this.isActive,
    required this.sortOrder,
    required this.issueCount,
    required this.isShared,
  });

  final String id;
  final String? facilityId;
  final String name;
  final String icon;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final int issueCount;
  final bool isShared;

  factory MaintenanceIssueCategory.fromJson(Map<String, dynamic> json) => MaintenanceIssueCategory(
        id: _str(json['id']),
        facilityId: _strOrNull(json['facility_id']),
        name: _str(json['name']),
        icon: _str(json['icon']),
        description: _strOrNull(json['description']),
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: _int(json['sort_order']),
        issueCount: _int(json['issue_count']),
        isShared: json['is_shared'] as bool? ?? (json['facility_id'] == null),
      );
}

class MaintenanceTicketListRow {
  const MaintenanceTicketListRow({
    required this.ticketId,
    required this.code,
    required this.courtId,
    required this.courtName,
    required this.sportName,
    required this.issueCategoryId,
    required this.categoryName,
    required this.title,
    required this.priority,
    required this.status,
    required this.reportedByName,
    required this.assignedToName,
    required this.scheduledStart,
    required this.reportedAt,
    required this.actualCostMinor,
    required this.estimatedCostMinor,
  });

  final String ticketId;
  final String code;
  final String courtId;
  final String courtName;
  final String? sportName;
  final String issueCategoryId;
  final String categoryName;
  final String title;
  final MaintenancePriority priority;
  final MaintenanceStatus status;
  final String reportedByName;
  final String? assignedToName;
  final DateTime? scheduledStart;
  final DateTime reportedAt;
  final int? actualCostMinor;
  final int? estimatedCostMinor;

  factory MaintenanceTicketListRow.fromJson(Map<String, dynamic> json) => MaintenanceTicketListRow(
        ticketId: _str(json['ticket_id']),
        code: _str(json['code']),
        courtId: _str(json['court_id']),
        courtName: _str(json['court_name']),
        sportName: _strOrNull(json['sport_name']),
        issueCategoryId: _str(json['issue_category_id']),
        categoryName: _str(json['category_name']),
        title: _str(json['title']),
        priority: MaintenancePriorityX.fromJson(_str(json['priority'])),
        status: MaintenanceStatusX.fromJson(_str(json['status'])),
        reportedByName: _str(json['reported_by_name']),
        assignedToName: _strOrNull(json['assigned_to_name']),
        scheduledStart: json['scheduled_start'] == null ? null : DateTime.parse(json['scheduled_start'] as String),
        reportedAt: DateTime.parse(_str(json['reported_at'])),
        actualCostMinor: _intOrNull(json['actual_cost_minor']),
        estimatedCostMinor: _intOrNull(json['estimated_cost_minor']),
      );
}

class AffectedBooking {
  const AffectedBooking({
    required this.bookingId,
    required this.customerType,
    required this.guestName,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.paymentStatus,
    required this.amountMinor,
  });

  final String bookingId;
  final String customerType;
  final String? guestName;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String paymentStatus;
  final int? amountMinor;

  factory AffectedBooking.fromJson(Map<String, dynamic> json) => AffectedBooking(
        bookingId: _str(json['bookingId'] ?? json['booking_id']),
        customerType: _str(json['customerType'] ?? json['customer_type']),
        guestName: _strOrNull(json['guestName'] ?? json['guest_name']),
        startTime: DateTime.parse(_str(json['startTime'] ?? json['start_time'])),
        endTime: DateTime.parse(_str(json['endTime'] ?? json['end_time'])),
        status: _str(json['status']),
        paymentStatus: _str(json['paymentStatus'] ?? json['payment_status']),
        amountMinor: _intOrNull(json['amountMinor'] ?? json['amount_minor']),
      );
}

class MaintenanceActivityEntry {
  const MaintenanceActivityEntry({required this.id, required this.eventType, required this.note, required this.actorName, required this.createdAt});

  final String id;
  final String eventType;
  final String? note;
  final String? actorName;
  final DateTime createdAt;

  factory MaintenanceActivityEntry.fromJson(Map<String, dynamic> json) => MaintenanceActivityEntry(
        id: _str(json['id']),
        eventType: _str(json['eventType']),
        note: _strOrNull(json['note']),
        actorName: _strOrNull(json['actorName']),
        createdAt: DateTime.parse(_str(json['createdAt'])),
      );
}

class MaintenanceAttachment {
  const MaintenanceAttachment({required this.id, required this.storagePath, required this.fileName});

  final String id;
  final String storagePath;
  final String fileName;

  factory MaintenanceAttachment.fromJson(Map<String, dynamic> json) => MaintenanceAttachment(
        id: _str(json['id']),
        storagePath: _str(json['storagePath']),
        fileName: _str(json['fileName']),
      );
}

class MaintenanceTicketDetail {
  const MaintenanceTicketDetail({
    required this.id,
    required this.code,
    required this.facilityId,
    required this.courtId,
    required this.courtName,
    required this.sportName,
    required this.categoryName,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.reportedByName,
    required this.reportedAt,
    required this.assignedToName,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.actualStart,
    required this.actualEnd,
    required this.estimatedCostMinor,
    required this.actualCostMinor,
    required this.notes,
    required this.currency,
    required this.attachments,
    required this.activity,
    required this.affectedBookings,
  });

  final String id;
  final String code;
  final String facilityId;
  final String courtId;
  final String courtName;
  final String? sportName;
  final String categoryName;
  final String title;
  final String description;
  final MaintenancePriority priority;
  final MaintenanceStatus status;
  final String reportedByName;
  final DateTime reportedAt;
  final String? assignedToName;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final int? estimatedCostMinor;
  final int? actualCostMinor;
  final String? notes;
  final String currency;
  final List<MaintenanceAttachment> attachments;
  final List<MaintenanceActivityEntry> activity;
  final List<AffectedBooking> affectedBookings;

  factory MaintenanceTicketDetail.fromJson(Map<String, dynamic> json) {
    DateTime? dt(dynamic v) => v == null ? null : DateTime.parse(v as String);
    final court = json['court'] as Map<String, dynamic>? ?? const {};
    final category = json['category'] as Map<String, dynamic>? ?? const {};
    final reportedBy = json['reportedBy'] as Map<String, dynamic>? ?? const {};
    final assignedTo = json['assignedTo'] as Map<String, dynamic>?;
    return MaintenanceTicketDetail(
      id: _str(json['id']),
      code: _str(json['code']),
      facilityId: _str(json['facilityId']),
      courtId: _str(court['id']),
      courtName: _str(court['name']),
      sportName: _strOrNull(json['sportName']),
      categoryName: _str(category['name']),
      title: _str(json['title']),
      description: _str(json['description']),
      priority: MaintenancePriorityX.fromJson(_str(json['priority'])),
      status: MaintenanceStatusX.fromJson(_str(json['status'])),
      reportedByName: _str(reportedBy['name']),
      reportedAt: DateTime.parse(_str(json['reportedAt'])),
      assignedToName: assignedTo == null ? null : _str(assignedTo['name']),
      scheduledStart: dt(json['scheduledStart']),
      scheduledEnd: dt(json['scheduledEnd']),
      actualStart: dt(json['actualStart']),
      actualEnd: dt(json['actualEnd']),
      estimatedCostMinor: _intOrNull(json['estimatedCostMinor']),
      actualCostMinor: _intOrNull(json['actualCostMinor']),
      notes: _strOrNull(json['notes']),
      currency: _str(json['currency']).isEmpty ? 'INR' : _str(json['currency']),
      attachments: ((json['attachments'] as List?) ?? const [])
          .map((e) => MaintenanceAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      activity: ((json['activity'] as List?) ?? const [])
          .map((e) => MaintenanceActivityEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      affectedBookings: ((json['affectedBookings'] as List?) ?? const [])
          .map((e) => AffectedBooking.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CourtMaintenanceStatusRow {
  const CourtMaintenanceStatusRow({required this.courtId, required this.courtName, required this.sportName, required this.status});

  final String courtId;
  final String courtName;
  final String? sportName;
  final CourtMaintenanceStatus status;

  factory CourtMaintenanceStatusRow.fromJson(Map<String, dynamic> json) => CourtMaintenanceStatusRow(
        courtId: _str(json['courtId'] ?? json['court_id']),
        courtName: _str(json['courtName'] ?? json['court_name']),
        sportName: _strOrNull(json['sportName'] ?? json['sport_name']),
        status: CourtMaintenanceStatusX.fromJson(_str(json['status'])),
      );
}

class MaintenanceRecentTicket {
  const MaintenanceRecentTicket({
    required this.ticketId,
    required this.code,
    required this.courtName,
    required this.title,
    required this.priority,
    required this.status,
    required this.assignedToName,
  });

  final String ticketId;
  final String code;
  final String courtName;
  final String title;
  final MaintenancePriority priority;
  final MaintenanceStatus status;
  final String? assignedToName;

  factory MaintenanceRecentTicket.fromJson(Map<String, dynamic> json) => MaintenanceRecentTicket(
        ticketId: _str(json['ticketId']),
        code: _str(json['code']),
        courtName: _str(json['courtName']),
        title: _str(json['title']),
        priority: MaintenancePriorityX.fromJson(_str(json['priority'])),
        status: MaintenanceStatusX.fromJson(_str(json['status'])),
        assignedToName: _strOrNull(json['assignedToName']),
      );
}

class MaintenanceOverview {
  const MaintenanceOverview({
    required this.openIssues,
    required this.inProgress,
    required this.scheduled,
    required this.resolvedThisMonth,
    required this.courtsBlocked,
    required this.repairCostThisMonthMinor,
    required this.courtStatus,
    required this.recentTickets,
  });

  final int openIssues;
  final int inProgress;
  final int scheduled;
  final int resolvedThisMonth;
  final int courtsBlocked;
  final int repairCostThisMonthMinor;
  final List<CourtMaintenanceStatusRow> courtStatus;
  final List<MaintenanceRecentTicket> recentTickets;

  factory MaintenanceOverview.fromJson(Map<String, dynamic> json) => MaintenanceOverview(
        openIssues: _int(json['openIssues']),
        inProgress: _int(json['inProgress']),
        scheduled: _int(json['scheduled']),
        resolvedThisMonth: _int(json['resolvedThisMonth']),
        courtsBlocked: _int(json['courtsBlocked']),
        repairCostThisMonthMinor: _int(json['repairCostThisMonthMinor']),
        courtStatus: ((json['courtStatus'] as List?) ?? const [])
            .map((e) => CourtMaintenanceStatusRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        recentTickets: ((json['recentTickets'] as List?) ?? const [])
            .map((e) => MaintenanceRecentTicket.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FacilityStaffOption {
  const FacilityStaffOption({required this.userId, required this.fullName, required this.role});

  final String userId;
  final String fullName;
  final String role;

  factory FacilityStaffOption.fromJson(Map<String, dynamic> json) =>
      FacilityStaffOption(userId: _str(json['user_id']), fullName: _str(json['full_name']), role: _str(json['role']));
}
