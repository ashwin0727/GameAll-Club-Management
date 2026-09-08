import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Maintenance & Court Operations.
///
/// Same precedent as reports_repository_source_test.dart: no fake Supabase
/// client, no mocking dependency added, so RPC-contract checks are static
/// assertions on the repository source. Model mapping is covered by
/// maintenance_models_test.dart.
///
/// Mirrors src/services/maintenance/supabase-maintenance.service.ts:
///   (a) every write goes through its exact RPC name — never a table update;
///   (b) 42501 -> maintenanceAccessDenied; P0002 -> maintenanceNotFound;
///       23514/23503/23P01 -> the rule message passed through verbatim.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/data/repositories/maintenance_repository.dart').readAsStringSync();
  });

  test('every lifecycle action calls its exact RPC name', () {
    const rpcs = [
      'get_maintenance_overview',
      'list_maintenance_issue_categories',
      'create_maintenance_issue_category',
      'update_maintenance_issue_category',
      'list_maintenance_tickets',
      'get_maintenance_ticket_detail',
      'create_maintenance_ticket',
      'assign_maintenance_ticket',
      'schedule_maintenance',
      'start_maintenance_ticket',
      'add_maintenance_note',
      'update_maintenance_cost',
      'resolve_maintenance_ticket',
      'reopen_maintenance_ticket',
      'close_maintenance_ticket',
      'detect_maintenance_affected_bookings',
      'list_facility_staff',
      'add_maintenance_attachment',
    ];
    for (final rpc in rpcs) {
      expect(source.contains("_client.rpc('$rpc'"), isTrue, reason: '$rpc must be called by name');
    }
  });

  test('status is never written directly — no bookings/tickets table update', () {
    expect(source.contains(".from('maintenance_tickets').update"), isFalse);
    expect(source.contains(".update({'status'"), isFalse);
  });

  test('actual cost posts through the RPC, which reuses Finance create_expense', () {
    // The web/DB side (update_maintenance_cost + 0068) owns the Finance
    // integration; the repo only forwards p_post_to_expenses.
    expect(source.contains("'p_post_to_expenses'"), isTrue);
  });

  test('error mapping: access denied / not found / rule message', () {
    expect(source.contains("'42501'") && source.contains('maintenanceAccessDenied'), isTrue);
    expect(source.contains("'P0002'") && source.contains('maintenanceNotFound'), isTrue);
    expect(source.contains("'23514'") && source.contains('error.message'), isTrue);
  });

  test('attachments upload to the shared maintenance-attachments bucket', () {
    expect(source.contains("'maintenance-attachments'"), isTrue);
    expect(source.contains('add_maintenance_attachment'), isTrue);
  });
}
