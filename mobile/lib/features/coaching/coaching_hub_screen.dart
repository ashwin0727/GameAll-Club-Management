import 'package:flutter/material.dart';
import 'student_row_menu.dart';
import 'program_row_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/coaching.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/hub_widgets.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tab_pop_scope.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'coaching_hub.dart';
import '../../shared/widgets/smooth_switcher.dart';

/// The Coaching hub — laid out like Memberships: a pill tab strip (Coaching · Programs · Students),
/// the shared summary card with the page's headline figures, the list
/// itself, and a floating button that creates the thing on the current tab. Sessions, Coaches,
/// Schedule and Reports stay one tap away from the Coaching tab.
class CoachingHubScreen extends ConsumerStatefulWidget {
  const CoachingHubScreen({super.key});

  @override
  ConsumerState<CoachingHubScreen> createState() => _CoachingHubScreenState();
}

class _CoachingHubScreenState extends ConsumerState<CoachingHubScreen> with SingleTickerProviderStateMixin {
  static const _labels = ['Coaching', 'Programs', 'Students'];
  // Each page's list is capped at this many rows; the hero numbers use the real totals.
  static const _pageSize = 100;

  late final TabController _tabs = TabController(length: 3, vsync: this);
  int _tabIndex = 0;

  bool _loading = true;
  String? _error;
  CoachingOverview? _overview;
  List<CoachRow> _coaches = const [];
  int _coachTotal = 0;
  ProgramCardStats? _programStats;
  StudentCardStats? _studentStats;
  Map<String, int> _perWeek = const {};
  ProgramPage _programs = const ProgramPage(programs: [], totalCount: 0);
  EnrollmentPage _students = const EnrollmentPage(enrollments: [], totalCount: 0);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index != _tabIndex && mounted) setState(() => _tabIndex = _tabs.index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) {
      setState(() {
        _loading = false;
        _error = 'Complete your facility setup to manage coaching.';
      });
      return;
    }
    setState(() {
      _loading = _overview == null;
      _error = null;
    });
    try {
      final repo = ref.read(coachingRepositoryProvider);
      final now = DateTime.now();
      final week = weekRange(now);
      final results = await Future.wait<Object>([
        repo.getOverview(fid),
        repo.listPrograms(facilityId: fid, limit: _pageSize),
        repo.listEnrollments(facilityId: fid, limit: _pageSize),
        repo.listCoaches(facilityId: fid, limit: _pageSize),
        repo.listSessions(facilityId: fid, from: week.start, to: week.end, limit: 500),
      ]);
      final cardStats = await repo.getProgramCardStats(fid);
      final studentStats = await repo.getStudentCardStats(fid);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as CoachingOverview;
        _programs = results[1] as ProgramPage;
        _students = results[2] as EnrollmentPage;
        _coaches = (results[3] as CoachPage).coaches;
        _coachTotal = (results[3] as CoachPage).totalCount;
        _perWeek = sessionsPerWeek((results[4] as SessionPage).sessions, now);
        _programStats = cardStats;
        _studentStats = studentStats;
        _loading = false;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e, st) {
      debugPrint('Coaching hub load failed: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'We couldn’t load coaching. Pull to retry.';
        });
      }
    }
  }

  Future<void> _go(String route) async {
    final changed = await context.push<Object?>(route);
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('COACHING_VIEW')) {
      return const StaffPermissionDenied(title: 'Coaching', message: "You don't have permission to view coaching.");
    }
    return TabPopScope(
      tab: AppTab.coaching,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: AppSpacing.lg,
          title: const Text('Coaching', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          // The create button follows the tab and sits at the top right.
          actions: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 130),
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
              child: _fab(session) ?? const SizedBox.shrink(key: ValueKey('none')),
            ),
            const SizedBox(width: AppSpacing.lg),
          ],
          bottom: HubTabBar(controller: _tabs, labels: _labels),
        ),
        body: SafeArea(
          child: SmoothSwitcher(child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _CoachingTab(overview: _overview!, coaches: _coaches, coachTotal: _coachTotal, programTotal: _programs.totalCount, perWeek: _perWeek, onTab: _tabs.animateTo, onOpen: _go),
                          _ProgramsTab(page: _programs, cardStats: _programStats, onOpen: _go, onChanged: _load),
                          _StudentsTab(page: _students, cardStats: _studentStats, onOpen: _go, onChanged: _load),
                        ],
                      ),
                    )),
        ),
        bottomNavigationBar: const AppBottomNav(current: AppTab.coaching),
      ),
    );
  }

  /// The top-right create button follows the tab: Coaching → new coach, Programs → new program, Students →
  /// new student — each only for people allowed to do it.
  Widget? _fab(SessionState session) {
    if (_loading || _error != null) return null;
    final (label, icon, route, allowed) = switch (_tabIndex) {
      0 => ('New coach', Icons.person_add_alt_1, AppRoutes.coachingCoachAdd, session.can('COACHING_MANAGE_COACHES')),
      1 => ('New program', Icons.add_task_outlined, AppRoutes.coachingProgramNew, session.can('COACHING_MANAGE_PROGRAMS')),
      _ => ('New student', Icons.person_add_alt_1, AppRoutes.coachingStudentNew, session.can('COACHING_MANAGE_ENROLLMENTS')),
    };
    if (!allowed) return null;
    return HubCreateAction(key: ValueKey(label), label: label, icon: icon, onTap: () => _go(route));
  }
}

// ── shared bits ─────────────────────────────────────────────────────────

EdgeInsets _pagePadding() => const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl);

String _rupees(int minor) => Formatters.currencyInr(minor / 100);

/// A list row: an icon tile, a title with up to two lines beneath, and a status pill.
class _HubRow extends StatelessWidget {
  const _HubRow({required this.icon, required this.color, required this.title, required this.lines, this.pill, this.pillColor, this.trailing, required this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final List<String> lines;
  final String? pill;
  final Color? pillColor;

  /// Shown after the pill — e.g. a row's ⋮ menu.
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: tokens.borderColor)),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.rowTitle(context)),
                      for (final l in lines.where((l) => l.isNotEmpty))
                        Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.secondary(context)),
                    ],
                  ),
                ),
                if (pill != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: (pillColor ?? tokens.primary).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                    child: Text(pill!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: pillColor ?? tokens.primary)),
                  ),
                ],
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _empty(BuildContext context, IconData icon, String text) {
  final tokens = context.tokens;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Column(
      children: [
        Icon(icon, size: 34, color: tokens.textSecondary),
        const SizedBox(height: AppSpacing.sm),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary)),
      ],
    ),
  );
}

// ── Coaching ────────────────────────────────────────────────────────────

/// The Coaching tab: the headline figures, a collapsible
/// "Upcoming Coaching Sessions", then the coaches themselves — searchable and filterable. It only
/// shows values; nothing here edits anything.
class _CoachingTab extends StatefulWidget {
  const _CoachingTab({required this.overview, required this.coaches, required this.coachTotal, required this.programTotal, required this.perWeek, required this.onTab, required this.onOpen});

  final CoachingOverview overview;
  final List<CoachRow> coaches;

  /// Every coach and every program at the facility (the lists may be capped pages of them).
  final int coachTotal;
  final int programTotal;
  final Map<String, int> perWeek;
  final void Function(int) onTab;
  final Future<void> Function(String route) onOpen;

  @override
  State<_CoachingTab> createState() => _CoachingTabState();
}

class _CoachingTabState extends State<_CoachingTab> {
  bool _upcomingOpen = false;
  String _query = '';
  CoachFilters _filters = const CoachFilters();

  Future<void> _openFilters() async {
    final sports = coachSportOptions(widget.coaches);
    final picked = await showModalBottomSheet<CoachFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CoachFilterSheet(initial: _filters, sports: sports),
    );
    if (picked != null) setState(() => _filters = picked);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final o = widget.overview;
    final sessions = nextSessions(o.upcomingSessions);
    final coaches = filterCoaches(widget.coaches, query: _query, filters: _filters, perWeek: widget.perWeek);

    final header = <Widget>[
      HubSummaryCard(
        icon: Icons.person_pin_outlined,
        title: 'Total coaches',
        value: o.totalCoaches == null ? '—' : '${o.totalCoaches}',
        statusText: o.coachesOnLeave > 0 ? '${o.activeCoaches} active · ${o.coachesOnLeave} on leave' : '${o.activeCoaches} active',
        left: HubSummaryCell(
          label: 'Coach Expenses',
          value: o.coachingExpenseMinor == null ? '—' : _rupees(o.coachingExpenseMinor!),
          sub: 'This month',
          onTap: () {},
        ),
        right: HubSummaryCell(
          label: 'Scheduled Sessions',
          value: '${o.upcomingSessionsCount}',
          sub: 'Upcoming',
          onTap: () => widget.onOpen(AppRoutes.coachingSchedule),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      HubExpandPanel(
        icon: Icons.event_available_outlined,
        color: tokens.primary,
        title: 'Upcoming Coaching Sessions',
        subtitle: sessions.isEmpty ? 'Nothing scheduled' : 'Your next ${sessions.length} session${sessions.length == 1 ? '' : 's'}',
        open: _upcomingOpen,
        onToggle: () => setState(() => _upcomingOpen = !_upcomingOpen),
        child: sessions.isEmpty
            ? _empty(context, Icons.event_busy_outlined, 'No upcoming coaching sessions.')
            : Column(
                children: [
                  for (final s in sessions)
                    _HubRow(
                      icon: Icons.event_available_outlined,
                      color: tokens.primary,
                      title: s.programName,
                      lines: ['${sessionDayLabel(s.startAt)} · ${_clock(s.startAt)} · ${s.courtName}', '${s.coachName} · ${s.enrolled}/${s.capacity} students'],
                      pill: s.status == SessionStatus.scheduled ? null : s.status.label,
                      onTap: () => widget.onOpen('${AppRoutes.coachingSessions}/${s.id}'),
                    ),
                ],
              ),
      ),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final (label, icon, route) in [
            ('Sessions', Icons.event_note_outlined, AppRoutes.coachingSessions),
            ('Schedule', Icons.calendar_view_week_outlined, AppRoutes.coachingSchedule),
            ('Reports', Icons.bar_chart_rounded, AppRoutes.coachingReports),
          ])
            ActionChip(avatar: Icon(icon, size: 16), label: Text(label), onPressed: () => widget.onOpen(route)),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('${coaches.length} coach${coaches.length == 1 ? '' : 'es'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Search coaches by name or sport...', prefixIcon: Icon(Icons.search, size: 20), isDense: true),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Badge(
            isLabelVisible: _filters.isActive,
            smallSize: 9,
            child: IconButton.outlined(onPressed: _openFilters, icon: const Icon(Icons.filter_alt_outlined), tooltip: 'Filter'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      if (coaches.isEmpty) _empty(context, Icons.person_pin_outlined, widget.coaches.isEmpty ? 'No coaches yet.' : 'No coaches match.'),
    ];

    return ListView.builder(
      padding: _pagePadding(),
      itemCount: header.length + coaches.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final c = coaches[i - header.length];
        return _CoachCard(coach: c, perWeek: widget.perWeek[c.id] ?? 0, onTap: () => widget.onOpen('${AppRoutes.coachingCoaches}/${c.id}'));
      },
    );
  }
}

String _clock(DateTime t) {
  final l = t.toLocal();
  return Formatters.time12h('${l.hour}:${l.minute}');
}

/// One coach, as in the design: photo, name, sport, status, and three figures — players, sessions a
/// week and years of experience.
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.coach, required this.perWeek, required this.onTap});

  final CoachRow coach;
  final int perWeek;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final active = coach.status == CoachStatus.active;
    final statusColor = switch (coach.status) {
      CoachStatus.active => tokens.success,
      CoachStatus.onLeave => tokens.warning,
      CoachStatus.inactive => tokens.textSecondary,
    };
    Widget fig(IconData icon, Color color, String value, String label) => Expanded(
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.rowTitle(context)),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: tokens.borderColor)),
            child: Column(
              children: [
                Row(
                  children: [
                    _CoachAvatar(url: coach.avatarUrl, name: coach.fullName),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(coach.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(context)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.sports_tennis_rounded, size: 14, color: tokens.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(coachSportLabel(coach), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.secondary(context)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                      child: Text(coach.status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? tokens.success : statusColor)),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: tokens.textSecondary),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: tokens.borderColor),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    fig(Icons.groups_outlined, tokens.success, '${coach.studentCount}', 'Players'),
                    fig(Icons.calendar_month_outlined, tokens.electricBlue, '$perWeek', 'Sessions/Week'),
                    fig(Icons.emoji_events_outlined, tokens.violet, experienceLabel(coach.experienceYears), 'Years Exp.'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoachAvatar extends StatelessWidget {
  const _CoachAvatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    Widget fallback() => Container(
          color: tokens.primary.withValues(alpha: 0.14),
          alignment: Alignment.center,
          child: Text(initials, style: TextStyle(fontWeight: FontWeight.w700, color: tokens.primary)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        width: 64,
        height: 64,
        child: (url == null || url!.isEmpty)
            ? fallback()
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback()),
      ),
    );
  }
}

/// Status, sport and sort — applied with one tap, reset with another.
class _CoachFilterSheet extends StatefulWidget {
  const _CoachFilterSheet({required this.initial, required this.sports});

  final CoachFilters initial;
  final List<String> sports;

  @override
  State<_CoachFilterSheet> createState() => _CoachFilterSheetState();
}

class _CoachFilterSheetState extends State<_CoachFilterSheet> {
  late CoachFilters _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter Coaches', style: AppTypography.heading2(context)),
            const SizedBox(height: AppSpacing.md),
            Text('Status', style: AppTypography.rowTitle(context)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                ChoiceChip(label: const Text('All'), selected: _f.status == null, onSelected: (_) => setState(() => _f = _f.copyWith(clearStatus: true))),
                for (final s in CoachStatus.values)
                  ChoiceChip(label: Text(s.label), selected: _f.status == s, onSelected: (_) => setState(() => _f = _f.copyWith(status: s))),
              ],
            ),
            if (widget.sports.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Sport', style: AppTypography.rowTitle(context)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(label: const Text('All'), selected: _f.sport == null, onSelected: (_) => setState(() => _f = _f.copyWith(clearSport: true))),
                  for (final s in widget.sports)
                    ChoiceChip(label: Text(s), selected: _f.sport == s, onSelected: (_) => setState(() => _f = _f.copyWith(sport: s))),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text('Sort By', style: AppTypography.rowTitle(context)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final s in CoachSort.values)
                  ChoiceChip(label: Text(s.label), selected: _f.sort == s, onSelected: (_) => setState(() => _f = _f.copyWith(sort: s))),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(const CoachFilters()), child: const Text('Reset'))),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.of(context).pop(_f), child: const Text('Apply'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Programs ────────────────────────────────────────────────────────────

class _ProgramsTab extends StatefulWidget {
  const _ProgramsTab({required this.page, required this.cardStats, required this.onOpen, required this.onChanged});

  /// Reloads the hub after a program was deleted.
  final VoidCallback onChanged;

  final ProgramPage page;
  final ProgramCardStats? cardStats;
  final Future<void> Function(String route) onOpen;

  @override
  State<_ProgramsTab> createState() => _ProgramsTabState();
}

class _ProgramsTabState extends State<_ProgramsTab> {
  String _query = '';
  ProgramStatus? _status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final all = widget.page.programs;
    final stats = programInsights(all, total: widget.page.totalCount);
    final q = _query.trim().toLowerCase();
    final rows = orderPrograms(all).where((p) {
      if (_status != null && p.status != _status) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.level.toLowerCase().contains(q) || p.category.toLowerCase().contains(q);
    }).toList();

    final header = <Widget>[
      HubSummaryCard(
        icon: Icons.school_outlined,
        title: 'Total programs',
        value: '${widget.cardStats?.total ?? stats.total}',
        statusText: '${widget.cardStats?.active ?? stats.active} active',
        left: HubSummaryCell(
          label: 'Enrolled Students',
          value: '${widget.cardStats?.enrolled ?? stats.students}',
          sub: 'Current enrollment',
          onTap: () {},
        ),
        right: HubSummaryCell(
          label: 'Available Seats',
          value: widget.cardStats == null ? '—' : '${widget.cardStats!.availableSeats}',
          sub: 'Remaining capacity',
          onTap: () {},
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('${rows.length} program${rows.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: AppSpacing.md),
      TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(hintText: 'Search programs', prefixIcon: Icon(Icons.search, size: 20), isDense: true),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        children: [
          ChoiceChip(label: const Text('All'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
          ChoiceChip(label: const Text('Active'), selected: _status == ProgramStatus.active, onSelected: (_) => setState(() => _status = ProgramStatus.active)),
          ChoiceChip(label: const Text('Inactive'), selected: _status == ProgramStatus.inactive, onSelected: (_) => setState(() => _status = ProgramStatus.inactive)),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      if (rows.isEmpty) _empty(context, Icons.school_outlined, all.isEmpty ? 'No programs yet.' : 'No programs match.'),
    ];

    return ListView.builder(
      padding: _pagePadding(),
      itemCount: header.length + rows.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final p = rows[i - header.length];
        final active = p.status == ProgramStatus.active;
        return _HubRow(
          icon: Icons.school_outlined,
          color: tokens.violet,
          title: p.name,
          lines: [
            [p.level, p.ageGroup].where((x) => x.isNotEmpty).join(' · '),
            '${p.studentCount} students · ${p.defaultPriceMinor == null || p.defaultPriceMinor == 0 ? (p.isMembershipIncluded ? 'Included in membership' : 'No fee') : _rupees(p.defaultPriceMinor!)}',
          ],
          pill: p.status.label,
          pillColor: active ? tokens.success : tokens.textSecondary,
          trailing: ProgramRowMenu(
            programId: p.id,
            name: p.name,
            studentCount: p.studentCount,
            onChanged: widget.onChanged,
            onOpen: widget.onOpen,
          ),
          onTap: () => widget.onOpen('${AppRoutes.coachingPrograms}/${p.id}'),
        );
      },
    );
  }
}

// ── Students ────────────────────────────────────────────────────────────

class _StudentsTab extends StatefulWidget {
  const _StudentsTab({required this.page, required this.cardStats, required this.onOpen, required this.onChanged});

  /// Reloads the hub after a student was deleted.
  final VoidCallback onChanged;

  final StudentCardStats? cardStats;

  final EnrollmentPage page;
  final Future<void> Function(String route) onOpen;

  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

enum _StudentFilter { all, active, inactive, pending }

class _StudentsTabState extends State<_StudentsTab> {
  String _query = '';
  _StudentFilter _filter = _StudentFilter.all;

  bool _owes(EnrollmentRow e) => e.paymentStatus == EnrollmentPaymentStatus.pending || e.paymentStatus == EnrollmentPaymentStatus.partial;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final all = widget.page.enrollments;
    final stats = studentInsights(all, total: widget.page.totalCount);
    final q = _query.trim().toLowerCase();
    final rows = orderStudents(all).where((e) {
      switch (_filter) {
        case _StudentFilter.active:
          if (e.status != EnrollmentStatus.active) return false;
        case _StudentFilter.inactive:
          if (e.status == EnrollmentStatus.active) return false;
        case _StudentFilter.pending:
          if (e.status != EnrollmentStatus.active || !_owes(e)) return false;
        case _StudentFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return e.studentName.toLowerCase().contains(q) || e.programName.toLowerCase().contains(q) || (e.studentPhone ?? '').contains(q);
    }).toList();

    final header = <Widget>[
      HubSummaryCard(
        icon: Icons.groups_rounded,
        title: 'Total students',
        value: widget.cardStats == null ? '${stats.total}' : '${widget.cardStats!.totalStudents}',
        statusText: '${widget.cardStats == null ? stats.active : widget.cardStats!.enrolledStudents} enrolled',
        left: HubSummaryCell(
          label: 'Revenue',
          value: widget.cardStats == null ? '—' : _rupees(widget.cardStats!.revenueMinor),
          sub: 'This month',
          onTap: () {},
        ),
        right: HubSummaryCell(
          label: 'Pending Payments',
          value: widget.cardStats == null ? '—' : _rupees(widget.cardStats!.pendingMinor),
          valueColor: (widget.cardStats?.pendingMinor ?? 0) > 0 ? tokens.warning : null,
          sub: (widget.cardStats?.pendingMinor ?? 0) > 0 ? 'Needs follow-up' : 'Nothing pending',
          subColor: (widget.cardStats?.pendingMinor ?? 0) > 0 ? const Color(0xFFFFFFFF).withValues(alpha: 0.75) : null,
          tint: (widget.cardStats?.pendingMinor ?? 0) > 0 ? tokens.warning.withValues(alpha: 0.12) : null,
          onTap: () => setState(() => _filter = _StudentFilter.pending),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('${rows.length} student${rows.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: AppSpacing.md),
      TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(hintText: 'Search students', prefixIcon: Icon(Icons.search, size: 20), isDense: true),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final (label, f) in [
            ('All', _StudentFilter.all),
            ('Active', _StudentFilter.active),
            ('Inactive', _StudentFilter.inactive),
            ('Unpaid', _StudentFilter.pending),
          ])
            ChoiceChip(label: Text(label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      if (rows.isEmpty) _empty(context, Icons.groups_outlined, all.isEmpty ? 'No students yet.' : 'No students match.'),
    ];

    return ListView.builder(
      padding: _pagePadding(),
      itemCount: header.length + rows.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final e = rows[i - header.length];
        final active = e.status == EnrollmentStatus.active;
        return _HubRow(
          icon: Icons.person_outline_rounded,
          color: tokens.electricBlue,
          title: e.studentName,
          lines: [
            [e.programName, if (e.batchName != null && e.batchName!.isNotEmpty) e.batchName!].join(' · '),
            [if (e.coachName != null && e.coachName!.isNotEmpty) e.coachName!, e.paymentStatus.label].join(' · '),
          ],
          pill: e.status.label,
          pillColor: active ? tokens.success : tokens.textSecondary,
          trailing: StudentRowMenu(
            enrollmentId: e.id,
            studentName: e.studentName,
            programName: e.programName,
            programId: e.programId,
            paidMinor: e.paidMinor,
            status: e.status,
            onChanged: widget.onChanged,
            onOpen: widget.onOpen,
          ),
          onTap: () => widget.onOpen('${AppRoutes.coachingEnrollments}/${e.id}'),
        );
      },
    );
  }
}
