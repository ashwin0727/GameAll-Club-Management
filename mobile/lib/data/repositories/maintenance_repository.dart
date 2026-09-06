import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/maintenance.dart';

/// Mirrors src/services/maintenance/supabase-maintenance.service.ts — same
/// RPCs (migration 0068_maintenance_module.sql), same lifecycle. Every
/// write is a single server RPC; this repository never computes status or
/// availability itself.
class MaintenanceRepository {
  MaintenanceRepository(this._client);

  final SupabaseClient _client;

  static const _bucket = 'maintenance-attachments';

  AppException _mapError(Object error, {AppErrorCode fallback = AppErrorCode.maintenanceRuleError}) {
    if (error is! PostgrestException) return AppException(AppErrorCode.network);
    if (error.code == '42501') return AppException(AppErrorCode.maintenanceAccessDenied);
    if (error.code == 'P0002') return AppException(AppErrorCode.maintenanceNotFound, error.message);
    if (error.code == '23514' || error.code == '23503' || error.code == '23P01') {
      return AppException(fallback, error.message);
    }
    return AppException(AppErrorCode.maintenanceDataError);
  }

  Future<MaintenanceOverview> getOverview(String facilityId) async {
    try {
      final data = await _client.rpc('get_maintenance_overview', params: {'p_facility_id': facilityId});
      return MaintenanceOverview.fromJson(data as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapError(e, fallback: AppErrorCode.maintenanceDataError);
    }
  }

  Future<List<MaintenanceIssueCategory>> listIssueCategories(String facilityId, {bool includeInactive = true}) async {
    try {
      final rows = await _client.rpc('list_maintenance_issue_categories', params: {
        'p_facility_id': facilityId,
        'p_include_inactive': includeInactive,
      });
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MaintenanceIssueCategory.fromJson).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, fallback: AppErrorCode.maintenanceDataError);
    }
  }

  Future<MaintenanceIssueCategory> createIssueCategory({
    required String facilityId,
    required String name,
    required String icon,
    String? description,
    int sortOrder = 0,
  }) async {
    try {
      final row = await _client.rpc('create_maintenance_issue_category', params: {
        'p_facility_id': facilityId,
        'p_name': name,
        'p_icon': icon,
        'p_description': description,
        'p_sort_order': sortOrder,
      });
      return MaintenanceIssueCategory.fromJson({...row as Map<String, dynamic>, 'issue_count': 0});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<MaintenanceIssueCategory> updateIssueCategory({
    required String categoryId,
    required String name,
    required String icon,
    String? description,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    try {
      final row = await _client.rpc('update_maintenance_issue_category', params: {
        'p_category_id': categoryId,
        'p_name': name,
        'p_icon': icon,
        'p_description': description,
        'p_sort_order': sortOrder,
        'p_is_active': isActive,
      });
      return MaintenanceIssueCategory.fromJson({...row as Map<String, dynamic>, 'issue_count': 0});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<({List<MaintenanceTicketListRow> tickets, int totalCount})> listTickets(
    String facilityId, {
    String? search,
    String? status,
    String? priority,
    String? courtId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_maintenance_tickets', params: {
        'p_facility_id': facilityId,
        'p_search': (search == null || search.isEmpty) ? null : search,
        'p_status': status,
        'p_priority': priority,
        'p_court_id': courtId,
        'p_sort': 'NEWEST',
        'p_limit': limit,
        'p_offset': offset,
      });
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      final total = list.isEmpty ? 0 : (list.first['total_count'] as num).toInt();
      return (tickets: list.map(MaintenanceTicketListRow.fromJson).toList(), totalCount: total);
    } on PostgrestException catch (e) {
      throw _mapError(e, fallback: AppErrorCode.maintenanceDataError);
    }
  }

  Future<MaintenanceTicketDetail> getTicketDetail(String ticketId) async {
    try {
      final data = await _client.rpc('get_maintenance_ticket_detail', params: {'p_ticket_id': ticketId});
      return MaintenanceTicketDetail.fromJson(data as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<String> createTicket({
    required String facilityId,
    required String courtId,
    required String issueCategoryId,
    required MaintenancePriority priority,
    required String title,
    required String description,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    String? assignedTo,
    int? estimatedCostMinor,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('create_maintenance_ticket', params: {
        'p_facility_id': facilityId,
        'p_court_id': courtId,
        'p_issue_category_id': issueCategoryId,
        'p_priority': priority.toJson(),
        'p_title': title,
        'p_description': description,
        'p_scheduled_start': scheduledStart?.toIso8601String(),
        'p_scheduled_end': scheduledEnd?.toIso8601String(),
        'p_assigned_to': assignedTo,
        'p_estimated_cost_minor': estimatedCostMinor,
        'p_notes': notes,
      });
      return (row as Map<String, dynamic>)['id'] as String;
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> assignTicket(String ticketId, String assignedTo) async {
    try {
      await _client.rpc('assign_maintenance_ticket', params: {'p_ticket_id': ticketId, 'p_assigned_to': assignedTo});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> scheduleMaintenance(String ticketId, DateTime start, DateTime end) async {
    try {
      await _client.rpc('schedule_maintenance', params: {
        'p_ticket_id': ticketId,
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> startMaintenance(String ticketId) async {
    try {
      await _client.rpc('start_maintenance_ticket', params: {'p_ticket_id': ticketId});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> addNote(String ticketId, String note) async {
    try {
      await _client.rpc('add_maintenance_note', params: {'p_ticket_id': ticketId, 'p_note': note});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> updateCost({
    required String ticketId,
    int? estimatedCostMinor,
    int? actualCostMinor,
    bool postToExpenses = false,
  }) async {
    try {
      await _client.rpc('update_maintenance_cost', params: {
        'p_ticket_id': ticketId,
        'p_estimated_cost_minor': estimatedCostMinor,
        'p_actual_cost_minor': actualCostMinor,
        'p_post_to_expenses': postToExpenses,
      });
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> resolveTicket(String ticketId) async {
    try {
      await _client.rpc('resolve_maintenance_ticket', params: {'p_ticket_id': ticketId});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> reopenTicket(String ticketId) async {
    try {
      await _client.rpc('reopen_maintenance_ticket', params: {'p_ticket_id': ticketId});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> closeTicket(String ticketId, {String? reason}) async {
    try {
      await _client.rpc('close_maintenance_ticket', params: {'p_ticket_id': ticketId, 'p_reason': reason});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<AffectedBooking>> detectAffectedBookings(String courtId, DateTime start, DateTime end, {String? excludeTicketId}) async {
    try {
      final rows = await _client.rpc('detect_maintenance_affected_bookings', params: {
        'p_court_id': courtId,
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
        'p_exclude_ticket_id': excludeTicketId,
      });
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(AffectedBooking.fromJson).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, fallback: AppErrorCode.maintenanceDataError);
    }
  }

  Future<List<FacilityStaffOption>> listAssignableStaff(String facilityId) async {
    try {
      final rows = await _client.rpc('list_facility_staff', params: {'p_facility_id': facilityId});
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(FacilityStaffOption.fromJson).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, fallback: AppErrorCode.maintenanceDataError);
    }
  }

  /// Uploads directly to the maintenance-attachments Storage bucket
  /// (0068) and records it — same bucket/path convention the web uses.
  Future<void> uploadAttachment(String facilityId, String ticketId, String fileName, Uint8List bytes, {String? contentType}) async {
    final path = '$facilityId/$ticketId/${DateTime.now().microsecondsSinceEpoch}-$fileName';
    try {
      await _client.storage.from(_bucket).uploadBinary(path, bytes);
      await _client.rpc('add_maintenance_attachment', params: {
        'p_ticket_id': ticketId,
        'p_storage_path': path,
        'p_file_name': fileName,
        'p_content_type': contentType,
        'p_size_bytes': bytes.length,
      });
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } on StorageException catch (_) {
      throw AppException(AppErrorCode.maintenanceDataError, 'Could not upload this file. Please try again.');
    }
  }
}
