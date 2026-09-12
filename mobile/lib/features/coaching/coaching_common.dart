import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/coaching.dart';
import '../../shared/widgets/misc.dart';

/// Presentation helpers shared across the Coaching screens — the mobile
/// counterpart of src/features/coaching/components/shared.tsx.
///
/// Nothing here computes a monetary figure: [coachMoney] only FORMATS a
/// server-provided minor-unit value.
String coachMoney(int? amountMinor) => Formatters.currencyInr(((amountMinor ?? 0) / 100).round());

String coachDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  return Formatters.dateShort(DateTime.parse(iso));
}

String coachDateTime(DateTime dt) => Formatters.dateTimeShort(dt);

String coachTime(DateTime dt) => Formatters.dateTimeShort(dt).split(', ').last;

const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

StatusTone sessionTone(SessionStatus s) => switch (s) {
      SessionStatus.scheduled => StatusTone.neutral,
      SessionStatus.confirmed => StatusTone.success,
      SessionStatus.inProgress => StatusTone.warning,
      SessionStatus.completed => StatusTone.info,
      SessionStatus.cancelled => StatusTone.danger,
    };

StatusTone coachTone(CoachStatus s) => switch (s) {
      CoachStatus.active => StatusTone.success,
      CoachStatus.inactive => StatusTone.neutral,
      CoachStatus.onLeave => StatusTone.warning,
    };

StatusTone enrollmentTone(EnrollmentStatus s) => switch (s) {
      EnrollmentStatus.active => StatusTone.success,
      EnrollmentStatus.paused => StatusTone.warning,
      EnrollmentStatus.completed => StatusTone.info,
      EnrollmentStatus.cancelled => StatusTone.danger,
    };

StatusTone paymentTone(EnrollmentPaymentStatus s) => switch (s) {
      EnrollmentPaymentStatus.paid => StatusTone.success,
      EnrollmentPaymentStatus.partial => StatusTone.warning,
      EnrollmentPaymentStatus.pending => StatusTone.warning,
      EnrollmentPaymentStatus.included => StatusTone.neutral,
    };

StatusTone progressTone(ProgressStatus s) => switch (s) {
      ProgressStatus.excelling => StatusTone.success,
      ProgressStatus.onTrack => StatusTone.neutral,
      ProgressStatus.needsWork => StatusTone.warning,
      ProgressStatus.atRisk => StatusTone.danger,
    };

/// A compact KPI tile.
class CoachingKpi extends StatelessWidget {
  const CoachingKpi({super.key, required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: tokens.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge),
          if (hint != null)
            Text(hint!, style: TextStyle(fontSize: 10, color: tokens.textSecondary)),
        ],
      ),
    );
  }
}
