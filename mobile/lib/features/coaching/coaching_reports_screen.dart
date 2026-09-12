import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';

/// Coaching → Reports — mirrors src/features/coaching/components/reports-page.tsx.
/// Read-only analytics over sessions / enrollments / payments / availability.
class CoachingReportsScreen extends ConsumerStatefulWidget {
  const CoachingReportsScreen({super.key});

  @override
  ConsumerState<CoachingReportsScreen> createState() => _CoachingReportsScreenState();
}

class _CoachingReportsScreenState extends ConsumerState<CoachingReportsScreen> {
  static const _presets = [
    (value: 'THIS_MONTH', label: 'This Month'),
    (value: 'LAST_MONTH', label: 'Last Month'),
    (value: 'THIS_QUARTER', label: 'This Quarter'),
    (value: 'THIS_YEAR', label: 'This Year'),
  ];

  String _preset = 'THIS_MONTH';
  CoachingReports? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    setState(() {
      _error = null;
      _data = null;
    });
    try {
      final d = await ref.read(coachingRepositoryProvider).getReports(fid, preset: _preset);
      if (mounted) setState(() => _data = d);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Reports', message: "You don't have permission to view coaching.");
    }
    final presetLabel = _presets.firstWhere((p) => p.value == _preset).label;

    return Scaffold(
      appBar: AppBar(title: const Text('Coaching Reports')),
      body: SafeArea(
        child: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _data == null
                ? const LoadingView(message: 'Loading reports…')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        PickerChip(
                          label: presetLabel,
                          onSelect: () async {
                            final picked = await showPickerSheet<String>(
                              context: context,
                              selected: _preset,
                              options: _presets.map((p) => (value: p.value, label: p.label)).toList(),
                            );
                            if (picked != null) {
                              setState(() => _preset = picked);
                              _load();
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _body(_data!),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _body(CoachingReports d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 2.0,
          children: [
            CoachingKpi(label: 'Active Students', value: '${d.activeStudents}'),
            CoachingKpi(label: 'Active Programs', value: '${d.activePrograms}'),
            CoachingKpi(
                label: 'Sessions',
                value: '${d.sessionsInRange}',
                hint: '${d.completedSessionsInRange} completed'),
            CoachingKpi(label: 'Coaching Revenue', value: coachMoney(d.coachingRevenueMinor)),
            CoachingKpi(label: 'Avg Utilization', value: '${d.avgCapacityUtilization.toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Program Performance', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              if (d.programPerformance.isEmpty)
                Text('No programs yet.', style: AppTypography.secondary(context))
              else
                ...d.programPerformance.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.programName, style: AppTypography.rowTitle(context)),
                                Text(
                                  '${p.activeStudents} students · ${p.sessions} sessions · ${p.capacityUtilization.toStringAsFixed(0)}%',
                                  style: AppTypography.caption(context),
                                ),
                              ],
                            ),
                          ),
                          Text(coachMoney(p.revenueMinor), style: AppTypography.body(context)),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coach Utilization', style: Theme.of(context).textTheme.titleSmall),
              Text('Scheduled hours vs. weekly recurring available hours.', style: AppTypography.caption(context)),
              const SizedBox(height: AppSpacing.xs),
              if (d.coachUtilization.isEmpty)
                Text('No coaches yet.', style: AppTypography.secondary(context))
              else
                ...d.coachUtilization.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(c.coachName)),
                          Text(
                            '${c.sessions} sessions · ${c.scheduledHours.toStringAsFixed(1)} / ${c.weeklyAvailableHours.toStringAsFixed(1)} h',
                            style: AppTypography.caption(context),
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Student Growth', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              ...() {
                final max = d.studentGrowth.fold<int>(1, (m, g) => g.students > m ? g.students : m);
                return d.studentGrowth.map((g) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(g.month)),
                              Text('${g.students}', style: AppTypography.caption(context)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: (g.students / max).clamp(0.02, 1)),
                        ],
                      ),
                    ));
              }(),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
