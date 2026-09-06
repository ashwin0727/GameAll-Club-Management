import 'package:flutter/material.dart';
import '../../data/models/maintenance.dart';
import '../../shared/widgets/misc.dart';

/// Semantic colour + label together — never colour alone (spec §25).
Widget priorityBadge(MaintenancePriority p) {
  final tone = switch (p) {
    MaintenancePriority.low => StatusTone.success,
    MaintenancePriority.medium => StatusTone.warning,
    MaintenancePriority.high => StatusTone.danger,
    MaintenancePriority.critical => StatusTone.danger,
  };
  return StatusBadge(label: p.label, tone: tone);
}

Widget maintenanceStatusBadge(MaintenanceStatus s) {
  final tone = switch (s) {
    MaintenanceStatus.reported => StatusTone.danger,
    MaintenanceStatus.assigned => StatusTone.info,
    MaintenanceStatus.scheduled => StatusTone.warning,
    MaintenanceStatus.inProgress => StatusTone.info,
    MaintenanceStatus.resolved => StatusTone.success,
    MaintenanceStatus.closed => StatusTone.neutral,
  };
  return StatusBadge(label: s.label, tone: tone);
}

Widget courtStatusBadge(CourtMaintenanceStatus s) {
  final tone = switch (s) {
    CourtMaintenanceStatus.available => StatusTone.success,
    CourtMaintenanceStatus.inUse => StatusTone.info,
    CourtMaintenanceStatus.underMaintenance => StatusTone.danger,
    CourtMaintenanceStatus.blocked => StatusTone.neutral,
  };
  return StatusBadge(label: s.label, tone: tone);
}
