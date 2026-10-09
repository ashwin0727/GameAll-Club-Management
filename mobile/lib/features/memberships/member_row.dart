import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership.dart';
import '../../shared/widgets/app_avatar.dart';

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// One member in a list — avatar, name, their plan and renewal date, and a status pill. Shared by the
/// Memberships → Members tab and the Members tab of a plan's details.
class MemberRow extends StatelessWidget {
  const MemberRow({super.key, required this.row, required this.onTap});

  final MembershipListRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (label, color) = switch (row.status) {
      MembershipListStatus.active => ('Active', tokens.primary),
      MembershipListStatus.paymentIncomplete => ('Unpaid', tokens.warning),
      MembershipListStatus.inactive => ('Inactive', tokens.textSecondary),
    };
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Row(
            children: [
              AppAvatar(name: row.memberName, size: AppAvatarSize.medium),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${row.planName} · renews ${_date(row.endDate)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) => '${d.day} ${_monthShort[d.month - 1]}';
}
