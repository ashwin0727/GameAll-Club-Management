import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_common.dart';

/// Coaching → Overview — mirrors src/features/coaching/components/overview-page.tsx.
class CoachingOverviewScreen extends ConsumerStatefulWidget {
  const CoachingOverviewScreen({super.key});

  @override
  ConsumerState<CoachingOverviewScreen> createState() => _CoachingOverviewScreenState();
}

class _CoachingOverviewScreenState extends ConsumerState<CoachingOverviewScreen> {
  CoachingOverview? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    setState(() => _error = null);
    try {
      final data = await ref.read(coachingRepositoryProvider).getOverview(fid);
      if (mounted) setState(() => _data = data);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(
        title: 'Coaching',
        message: "You don't have permission to view coaching.",
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coaching'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_open),
            onSelected: (r) => context.push(r),
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppRoutes.coachingCoaches, child: Text('Coaches')),
              PopupMenuItem(value: AppRoutes.coachingPrograms, child: Text('Programs')),
              PopupMenuItem(value: AppRoutes.coachingSchedule, child: Text('Schedule')),
              PopupMenuItem(value: AppRoutes.coachingSessions, child: Text('Sessions')),
              PopupMenuItem(value: AppRoutes.coachingEnrollments, child: Text('Enrollments')),
              PopupMenuItem(value: AppRoutes.coachingReports, child: Text('Reports')),
            ],
          ),
        ],
      ),
      floatingActionButton: session.can('COACHING_CREATE_SESSION')
          ? FloatingActionButton.extended(
              onPressed: () async {
                final ok = await context.push<bool>(AppRoutes.coachingSessionNew);
                if (ok == true) _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('New Session'),
            )
          : null,
      body: SafeArea(
        child: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _data == null
                ? const LoadingView(message: 'Loading overview…')
                : RefreshIndicator(onRefresh: _load, child: _body(_data!)),
      ),
    );
  }

  Widget _body(CoachingOverview d) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.8,
          children: [
            CoachingKpi(label: 'Active Students', value: '${d.activeStudents}'),
            CoachingKpi(label: 'Active Programs', value: '${d.activePrograms}'),
            CoachingKpi(
                label: 'Coaches',
                value: '${d.activeCoaches}',
                hint: d.coachesOnLeave > 0 ? '${d.coachesOnLeave} on leave' : null),
            CoachingKpi(label: 'Sessions / Month', value: '${d.sessionsThisMonth}'),
            CoachingKpi(label: 'Upcoming', value: '${d.upcomingSessionsCount}'),
            CoachingKpi(label: 'Revenue / Month', value: coachMoney(d.revenueThisMonthMinor), hint: 'collected'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Upcoming Sessions', style: Theme.of(context).textTheme.titleSmall)),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.coachingSchedule),
                    child: const Text('Schedule'),
                  ),
                ],
              ),
              if (d.upcomingSessions.isEmpty)
                Text('No sessions scheduled.', style: AppTypography.secondary(context))
              else
                ...d.upcomingSessions.map(
                  (s) => InkWell(
                    onTap: () => context.push('/coaching/sessions/${s.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.programName, style: AppTypography.rowTitle(context)),
                                Text(
                                  '${coachDateTime(s.startAt)} · ${s.coachName} · ${s.courtName} · ${s.enrolled}/${s.capacity}',
                                  style: AppTypography.caption(context),
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(label: s.status.label, tone: sessionTone(s.status)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Active Programs', style: Theme.of(context).textTheme.titleSmall)),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.coachingPrograms),
                    child: const Text('All'),
                  ),
                ],
              ),
              if (d.programs.isEmpty)
                Text('No coaching programs yet.', style: AppTypography.secondary(context))
              else
                ...d.programs.map(
                  (p) => InkWell(
                    onTap: () => context.push('/coaching/programs/${p.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(p.name, style: AppTypography.rowTitle(context))),
                          Text('${p.level} · ${p.studentCount} students', style: AppTypography.caption(context)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (d.studentsByProgram.isNotEmpty) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Students by Program', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                ...() {
                  final total = d.studentsByProgram.fold<int>(0, (s, p) => s + p.students);
                  return d.studentsByProgram.map((p) {
                    final pct = total > 0 ? p.students / total : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(p.programName)),
                              Text('${p.students} (${(pct * 100).round()}%)', style: AppTypography.caption(context)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: pct.clamp(0, 1)),
                        ],
                      ),
                    );
                  });
                }(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent Enrollments', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              if (d.recentEnrollments.isEmpty)
                Text('No active enrollments.', style: AppTypography.secondary(context))
              else
                ...d.recentEnrollments.map(
                  (e) => InkWell(
                    onTap: () => context.push('/coaching/enrollments/${e.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.studentName, style: AppTypography.rowTitle(context)),
                                Text('${e.programName} · ${Formatters.dateShort(e.enrolledAt)}',
                                    style: AppTypography.caption(context)),
                              ],
                            ),
                          ),
                          StatusBadge(label: e.status.label, tone: enrollmentTone(e.status)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl * 2),
      ],
    );
  }
}
