import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import 'access_days.dart';

/// Sets which weekdays memberships grant court access — mirrors
/// src/features/memberships/components/membership-access-days-dialog.tsx.
/// Returns the saved list via `Navigator.pop`, or null if dismissed.
class MembershipAccessDaysSheet extends ConsumerStatefulWidget {
  const MembershipAccessDaysSheet({
    super.key,
    required this.facilityId,
    required this.currentDays,
  });

  final String facilityId;
  final List<int> currentDays;

  @override
  ConsumerState<MembershipAccessDaysSheet> createState() => _MembershipAccessDaysSheetState();
}

class _MembershipAccessDaysSheetState extends ConsumerState<MembershipAccessDaysSheet> {
  late List<int> _days = widget.currentDays.toList()..sort();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_days.isEmpty) {
      setState(() => _error = 'Select at least one day.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(membershipRepositoryProvider)
          .setMembershipAccessDays(widget.facilityId, _days);
      if (mounted) Navigator.of(context).pop(saved);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Membership Access Days', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Which days can members use the court? This pre-fills every new membership's time slot.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final d in allDays)
                  FilterChip(
                    label: Text(dayLabel(d)),
                    selected: _days.contains(d),
                    onSelected: (_) => setState(() => _days = toggleDay(_days, d)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _days = allDays.toList()),
                  child: const Text('All 7'),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _days = weekdays.toList()),
                  child: const Text('Mon–Fri'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Save',
              loadingLabel: 'Saving…',
              isLoading: _saving,
              onPressed: sameDays(_days, widget.currentDays) ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
