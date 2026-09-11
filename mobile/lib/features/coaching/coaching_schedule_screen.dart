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

/// Coaching → Schedule — a day view with date navigation. Mirrors
/// src/features/coaching/components/schedule-page.tsx (mobile = one day at a
/// time rather than a 7-column grid).
class CoachingScheduleScreen extends ConsumerStatefulWidget {
  const CoachingScheduleScreen({super.key});

  @override
  ConsumerState<CoachingScheduleScreen> createState() => _CoachingScheduleScreenState();
}

class _CoachingScheduleScreenState extends ConsumerState<CoachingScheduleScreen> {
  DateTime _day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  List<SessionRow>? _rows;
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
      _rows = null;
    });
    try {
      final from = _day;
      final to = _day.add(const Duration(days: 1));
      final page = await ref.read(coachingRepositoryProvider).listSessions(
            facilityId: fid,
            from: from,
            to: to,
            limit: 200,
          );
      if (mounted) setState(() => _rows = page.sessions);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _rows = const [];
        });
      }
    }
  }

  void _shift(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Schedule', message: "You don't have permission to view coaching.");
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coaching Schedule'),
        actions: [
          if (session.can('COACHING_CREATE_SESSION'))
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add session',
              onPressed: () async {
                final ok = await context.push<bool>(AppRoutes.coachingSessionNew);
                if (ok == true) _load();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                  Expanded(
                    child: Center(
                      child: TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _day,
                            firstDate: DateTime(_day.year - 1),
                            lastDate: DateTime(_day.year + 2),
                          );
                          if (picked != null) {
                            setState(() => _day = DateTime(picked.year, picked.month, picked.day));
                            _load();
                          }
                        },
                        child: Text(
                          Formatters.dateShort(_day),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : _rows == null
                      ? const LoadingView(message: 'Loading…')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: _rows!.isEmpty
                              ? ListView(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(AppSpacing.xl),
                                      child: Text('No sessions scheduled.', style: AppTypography.secondary(context)),
                                    ),
                                  ],
                                )
                              : ListView(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  children: _rows!
                                      .map((s) => Padding(
                                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                            child: AppCard(
                                              padding: const EdgeInsets.all(AppSpacing.md),
                                              onTap: () => context.push('/coaching/sessions/${s.id}'),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text('${coachTime(s.startAt)} · ${s.programName}',
                                                            style: AppTypography.rowTitle(context)),
                                                        Text(
                                                          '${s.coachName} · ${s.courtName} · ${s.enrolledCount}/${s.capacity}',
                                                          style: AppTypography.caption(context),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  StatusBadge(label: s.status.label, tone: sessionTone(s.status)),
                                                ],
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
