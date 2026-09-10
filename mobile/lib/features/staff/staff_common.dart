import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/staff.dart';
import '../../shared/widgets/misc.dart';

/// Presentation helpers shared across the Staff / Roles screens.
StatusTone staffStatusTone(StaffStatus s) => switch (s) {
      StaffStatus.active => StatusTone.success,
      StaffStatus.inactive => StatusTone.danger,
      StaffStatus.invited => StatusTone.warning,
    };

String staffInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.isNotEmpty ? parts.first[0] : '';
  final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
  final out = (first + last).toUpperCase();
  return out.isEmpty ? '?' : out;
}

String staffDate(String? iso) {
  if (iso == null) return '—';
  return Formatters.dateShort(DateTime.parse(iso));
}

const Map<String, String> securityEventLabels = {
  'STAFF_INVITED': 'Staff Invited',
  'STAFF_LINKED': 'Staff Linked',
  'STAFF_ACTIVATED': 'Reactivated',
  'STAFF_DEACTIVATED': 'Deactivated',
  'STAFF_ROLE_CHANGED': 'Role Updated',
  'STAFF_PROFILE_UPDATED': 'Profile Updated',
  'FACILITY_ACCESS_GRANTED': 'Facility Access',
  'FACILITY_ACCESS_REMOVED': 'Facility Access Removed',
  'ROLE_CREATED': 'Role Created',
  'ROLE_UPDATED': 'Role Updated',
  'ROLE_DELETED': 'Role Removed',
  'ROLE_PERMISSIONS_UPDATED': 'Permissions Updated',
};

/// A circular initials/photo avatar.
class StaffAvatar extends StatelessWidget {
  const StaffAvatar({super.key, required this.name, this.photoUrl, this.size = 36});

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final has = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        image: has ? DecorationImage(image: NetworkImage(photoUrl!), fit: BoxFit.cover) : null,
      ),
      child: has
          ? null
          : Text(staffInitials(name),
              style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700)),
    );
  }
}

/// A scrollable row of underlined tab buttons.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.tabs, required this.index, required this.onChanged});

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: i == index ? primary : Colors.transparent, width: 2),
                  ),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                    color: i == index ? null : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when the signed-in user lacks the permission a Users & Roles screen
/// needs. The database still enforces access regardless.
class StaffPermissionDenied extends StatelessWidget {
  const StaffPermissionDenied({super.key, required this.message, this.title = 'Users & Roles'});

  final String message;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: AppSpacing.md),
              const Text('Access restricted', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.xs),
              Text(message, textAlign: TextAlign.center, style: AppTypography.secondary(context)),
            ],
          ),
        ),
      ),
    );
  }
}
