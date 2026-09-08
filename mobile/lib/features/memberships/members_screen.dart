import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/page_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/tab_pop_scope.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../membership_sessions/membership_batches_sheet.dart';
import '../membership_sessions/membership_session_detail_screen.dart';
import 'create_membership_screen.dart';
import 'member_detail_screen.dart';
import 'membership_plans_sheet.dart';

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _dayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// The redesigned Members hub — Plans, People and Sessions in one place.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen(
      {super.key, this.openPlans = false, this.openNew = false});

  /// When true (deep-linked from the "+" menu), the plan editor opens as soon
  /// as the screen has loaded.
  final bool openPlans;

  /// When true, the "New membership" form opens as soon as the screen loads.
  final bool openNew;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  bool _loading = true;
  String? _error;
  String? _facilityId;
  int _tabIndex = 0;
  bool _autoOpenedPlans = false;
  bool _autoOpenedNew = false;

  List<MembershipPlan> _plans = const [];
  MembershipPageSummary? _summary;
  List<MembershipRevenuePoint> _revenue = const [];
  List<MembershipListRow> _members = const [];
  List<AssignableBatch> _batches = const [];

  @override
  void initState() {
    super.initState();
    // Swap the context-aware create button when the active tab actually
    // changes — not on every frame of the swipe animation.
    _tabs.addListener(() {
      if (_tabs.index != _tabIndex && mounted) {
        setState(() => _tabIndex = _tabs.index);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final facility = ref.read(sessionControllerProvider).facility ??
          await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _loading = false;
          _error = 'Complete your facility setup to manage members.';
        });
        return;
      }
      final repo = ref.read(membershipRepositoryProvider);
      final results = await Future.wait([
        repo.getFacilityPlans(facility.id),
        repo.getMembershipPageSummary(facility.id),
        repo.getMembershipRevenueTimeseries(facility.id,
            granularity: MembershipRevenueGranularity.month),
        repo.listMemberships(
            facility.id, const MembershipListParams(page: 1, perPage: 100)),
        repo.listAssignableBatches(facility.id),
      ]);
      setState(() {
        _facilityId = facility.id;
        _plans = results[0] as List<MembershipPlan>;
        _summary = results[1] as MembershipPageSummary;
        _revenue = results[2] as List<MembershipRevenuePoint>;
        _members = (results[3] as MembershipListResult).rows;
        _batches = results[4] as List<AssignableBatch>;
        _loading = false;
      });
      if (widget.openPlans && !_autoOpenedPlans && mounted) {
        _autoOpenedPlans = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _managePlans());
      }
      if (widget.openNew && !_autoOpenedNew && mounted) {
        _autoOpenedNew = true;
        _tabs.animateTo(1); // land on People afterwards
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _openNewMembership());
      }
    } on AppException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e, stack) {
      debugPrint('Members load failed: $e\n$stack');
      setState(() {
        _loading = false;
        _error = 'We couldn’t load members. Pull to retry.';
      });
    }
  }

  int get _expiringCount {
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 30));
    return _members
        .where((m) =>
            m.status == MembershipListStatus.active &&
            m.endDate.isAfter(now) &&
            m.endDate.isBefore(soon))
        .length;
  }

  int get _newThisMonth {
    final now = DateTime.now();
    return _members
        .where((m) =>
            m.startDate.year == now.year && m.startDate.month == now.month)
        .length;
  }

  /// Memberships created via the full form are self-contained (no plan_id),
  /// so match on the plan name too — that's the link back to the plan.
  List<MembershipListRow> _planMembers(MembershipPlan plan) {
    final name = plan.name.trim().toLowerCase();
    return _members
        .where((m) =>
            m.status != MembershipListStatus.inactive &&
            (m.planId == plan.id || m.planName.trim().toLowerCase() == name))
        .toList();
  }

  int _planMemberCount(MembershipPlan plan) => _planMembers(plan).length;

  Future<void> _openPlanMembers(MembershipPlan plan) async {
    final rows = _planMembers(plan);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => _PlanMembersSheet(
        plan: plan,
        rows: rows,
        onOpen: (row) async {
          Navigator.pop(sheet);
          final changed = await Navigator.of(context).push<bool>(
            AppPageRoute(
              builder: (_) =>
                  MemberDetailScreen(membershipId: row.membershipId),
            ),
          );
          if (changed == true) _load();
        },
      ),
    );
  }

  void _copyJoinLink() {
    final slug = ref.read(sessionControllerProvider).facility?.slug;
    final link = slug == null ? 'gameall.in' : 'gameall.in/join/$slug';
    Clipboard.setData(ClipboardData(text: 'https://$link'));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Join link copied.')));
  }

  Future<void> _managePlans() async {
    final id = _facilityId;
    if (id == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipPlansSheet(facilityId: id),
    );
    _load();
  }

  Future<void> _manageSessions() async {
    final id = _facilityId;
    if (id == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipBatchesSheet(facilityId: id),
    );
    _load();
  }

  Future<void> _openNewMembership() async {
    final created = await Navigator.of(context).push<bool>(
      AppPageRoute(builder: (_) => const CreateMembershipScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openBatch(AssignableBatch batch) async {
    final id = _facilityId;
    if (id == null) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => MembershipSessionDetailScreen(
          facilityId: id,
          batchId: batch.batchId,
          title: batch.name,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TabPopScope(
      tab: AppTab.members,
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: const Text('Members',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          OutlinedButton.icon(
            onPressed: _copyJoinLink,
            icon: const Icon(Icons.ios_share, size: 16),
            label: const Text('Join link'),
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.violet,
              side: BorderSide(color: tokens.violet.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              minimumSize: const Size(0, 36),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: tokens.surface0,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: tokens.borderColor),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: tokens.surface3,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: tokens.borderColor),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                overlayColor:
                    const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                labelColor: tokens.textPrimary,
                unselectedLabelColor: tokens.textSecondary,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(text: 'Plans'),
                  Tab(text: 'People'),
                  Tab(text: 'Sessions'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _PlansTab(
                          plans: _plans,
                          summary: _summary!,
                          revenue: _revenue,
                          activeCount: _summary!.activeMembers,
                          expiringCount: _expiringCount,
                          newThisMonth: _newThisMonth,
                          planMemberCount: _planMemberCount,
                          onManagePlans: _managePlans,
                          onOpenPlan: _openPlanMembers,
                        ),
                        _PeopleTab(
                          members: _members,
                          onNew: _openNewMembership,
                          onReload: _load,
                        ),
                        _SessionsTab(
                          batches: _batches,
                          plans: _plans,
                          onManage: _manageSessions,
                          onOpenBatch: _openBatch,
                        ),
                      ],
                    ),
                  ),
      ),
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 130),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: _buildCreateFab(),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.members),
      ),
    );
  }

  /// The primary "create" action, which changes with the active tab:
  /// Plans → new plan, People → new membership, Sessions → new session.
  Widget? _buildCreateFab() {
    if (_loading || _error != null) return null;
    final (label, icon, onTap) = switch (_tabIndex) {
      0 => ('New plan', Icons.add_card_outlined, _managePlans),
      1 => ('New membership', Icons.person_add_alt_1, _openNewMembership),
      _ => ('New session', Icons.event_repeat_outlined, _manageSessions),
    };
    return _CreateFab(key: ValueKey(label), label: label, icon: icon, onTap: onTap);
  }
}

/// Violet gradient pill action button that floats above the bottom nav.
class _CreateFab extends StatelessWidget {
  const _CreateFab(
      {super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tokens.violet, tokens.violet.withValues(alpha: 0.72)],
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.violet.withValues(alpha: 0.42),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── Plans ──

class _PlansTab extends StatelessWidget {
  const _PlansTab({
    required this.plans,
    required this.summary,
    required this.revenue,
    required this.activeCount,
    required this.expiringCount,
    required this.newThisMonth,
    required this.planMemberCount,
    required this.onManagePlans,
    required this.onOpenPlan,
  });

  final List<MembershipPlan> plans;
  final MembershipPageSummary summary;
  final List<MembershipRevenuePoint> revenue;
  final int activeCount;
  final int expiringCount;
  final int newThisMonth;
  final int Function(MembershipPlan plan) planMemberCount;
  final VoidCallback onManagePlans;
  final ValueChanged<MembershipPlan> onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final maxCount = plans
        .map(planMemberCount)
        .fold<int>(1, (m, c) => c > m ? c : m);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        _RecurringRevenueCard(
          amountInr: summary.revenueInr,
          revenue: revenue,
          activeCount: activeCount,
          expiringCount: expiringCount,
          newThisMonth: newThisMonth,
        ),
        const SizedBox(height: AppSpacing.md),
        if (plans.isEmpty)
          _EmptyState(
            icon: Icons.card_membership_outlined,
            title: 'No plans yet',
            action: 'Create a plan',
            onAction: onManagePlans,
          )
        else ...[
          for (final p in plans)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _PlanCard(
                plan: p,
                members: planMemberCount(p),
                fraction: planMemberCount(p) / maxCount,
                onTap: () => onOpenPlan(p),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: TextButton.icon(
              onPressed: onManagePlans,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Manage plans'),
              style: TextButton.styleFrom(foregroundColor: tokens.violet),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecurringRevenueCard extends StatelessWidget {
  const _RecurringRevenueCard({
    required this.amountInr,
    required this.revenue,
    required this.activeCount,
    required this.expiringCount,
    required this.newThisMonth,
  });

  final int amountInr;
  final List<MembershipRevenuePoint> revenue;
  final int activeCount;
  final int expiringCount;
  final int newThisMonth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final series = revenue.length > 12
        ? revenue.sublist(revenue.length - 12)
        : revenue;
    final values = series.map((b) => b.amountInr.toDouble()).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.violet.withValues(alpha: 0.35)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tokens.violet.withValues(alpha: 0.30),
              tokens.violet.withValues(alpha: 0.06),
            ],
          ),
        ),
        child: Stack(
          children: [
            // ── graph overlay, bleeding to the card edges ──────────────
            if (values.length >= 2)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 96,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _Sparkline(
                      values: values,
                      line: tokens.violet,
                      fill: tokens.violet.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.show_chart_rounded,
                          size: 16, color: tokens.violet),
                      const SizedBox(width: 6),
                      Text('Recurring revenue',
                          style: TextStyle(
                              fontSize: 13, color: tokens.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.currencyInr(amountInr),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      _MiniFig(value: '$activeCount', label: 'active'),
                      const SizedBox(width: AppSpacing.xl),
                      _MiniFig(
                        value: '$expiringCount',
                        label: 'expiring',
                        color: tokens.warning,
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      _MiniFig(
                        value: '+$newThisMonth',
                        label:
                            'new in ${_monthShort[DateTime.now().month - 1]}',
                        color: tokens.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft area sparkline for the recurring-revenue card — smoothed line with
/// a gradient fill that fades to nothing at the bottom.
class _Sparkline extends CustomPainter {
  _Sparkline({required this.values, required this.line, required this.fill});

  final List<double> values;
  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
    const pad = 6.0;
    final h = size.height - pad;
    final dx = size.width / (values.length - 1);

    Offset pt(int i) => Offset(
          i * dx,
          pad + h - ((values[i] - minV) / range) * h,
        );

    final linePath = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = pt(i - 1);
      final p1 = pt(i);
      final cx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill, fill.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );
    // end dot
    final last = pt(values.length - 1);
    canvas.drawCircle(last, 3.5, Paint()..color = line);
    canvas.drawCircle(
        last, 6, Paint()..color = line.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.values != values;
}

class _MiniFig extends StatelessWidget {
  const _MiniFig({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? tokens.textPrimary,
            )),
        Text(label,
            style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.members,
    required this.fraction,
    required this.onTap,
  });

  final MembershipPlan plan;
  final int members;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final subtitle = plan.features.isNotEmpty
        ? plan.features.join(' · ')
        : '${plan.durationDays}-day membership';
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(plan.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary)),
              ),
              Text.rich(TextSpan(children: [
                TextSpan(
                  text: Formatters.currencyInr(plan.priceInr),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary),
                ),
                TextSpan(
                  text: '/mo',
                  style:
                      TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
              ])),
            ],
          ),
          const SizedBox(height: 3),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.02, 1.0),
                    minHeight: 6,
                    backgroundColor: tokens.surface2,
                    color: tokens.violet,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text('$members member${members == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16, color: tokens.textSecondary),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }
}

/// The members enrolled on one plan — opened by tapping a plan card.
class _PlanMembersSheet extends StatelessWidget {
  const _PlanMembersSheet({
    required this.plan,
    required this.rows,
    required this.onOpen,
  });

  final MembershipPlan plan;
  final List<MembershipListRow> rows;
  final ValueChanged<MembershipListRow> onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                  '${rows.length} member${rows.length == 1 ? '' : 's'}',
                  style:
                      TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
              child: Text('No one is on this plan yet.',
                  style: TextStyle(color: tokens.textSecondary)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                itemCount: rows.length,
                separatorBuilder: (_, i) =>
                    Divider(height: 1, color: tokens.borderColor),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final (label, color) = switch (r.status) {
                    MembershipListStatus.active =>
                      ('Active', tokens.primary),
                    MembershipListStatus.paymentIncomplete =>
                      ('Unpaid', tokens.warning),
                    MembershipListStatus.inactive =>
                      ('Inactive', tokens.textSecondary),
                  };
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AppAvatar(
                        name: r.memberName, size: AppAvatarSize.small),
                    title: Text(r.memberName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('+91 ${r.memberPhone}',
                        style: TextStyle(
                            fontSize: 12, color: tokens.textSecondary)),
                    trailing: Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color)),
                    onTap: () => onOpen(r),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── People ──

class _PeopleTab extends StatefulWidget {
  const _PeopleTab(
      {required this.members, required this.onNew, required this.onReload});

  final List<MembershipListRow> members;
  final VoidCallback onNew;
  final VoidCallback onReload;

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.members
        : widget.members
            .where((m) =>
                m.memberName.toLowerCase().contains(q) ||
                m.memberPhone.contains(q))
            .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Text(
          '${widget.members.length} member${widget.members.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search members',
            prefixIcon: Icon(Icons.search, size: 20),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Column(
              children: [
                Icon(Icons.groups_outlined,
                    size: 34, color: tokens.textSecondary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.members.isEmpty
                      ? 'No members yet.'
                      : 'No members match “$_query”.',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                if (widget.members.isEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: widget.onNew,
                    style: FilledButton.styleFrom(
                        backgroundColor: tokens.violet),
                    child: const Text('Add a member'),
                  ),
                ],
              ],
            ),
          )
        else
          for (final m in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _MemberRow(
                row: m,
                onTap: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    AppPageRoute(
                      builder: (_) =>
                          MemberDetailScreen(membershipId: m.membershipId),
                    ),
                  );
                  if (changed == true) widget.onReload();
                },
              ),
            ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.row, required this.onTap});

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
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${row.planName} · renews ${_date(row.endDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: tokens.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
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

// ────────────────────────────────────────────────────────────── Sessions ──

class _SessionsTab extends StatelessWidget {
  const _SessionsTab({
    required this.batches,
    required this.plans,
    required this.onManage,
    required this.onOpenBatch,
  });

  final List<AssignableBatch> batches;
  final List<MembershipPlan> plans;
  final VoidCallback onManage;
  final ValueChanged<AssignableBatch> onOpenBatch;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (batches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _EmptyState(
            icon: Icons.event_repeat_outlined,
            title: 'No coaching sessions yet',
            action: 'Create a session',
            onAction: onManage,
          ),
        ],
      );
    }
    final totalSeats = batches.fold<int>(0, (s, b) => s + b.capacity);
    final filledSeats = batches.fold<int>(0, (s, b) => s + b.enrolledCount);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Row(
          children: [
            Text('${batches.length} session${batches.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('$filledSeats / $totalSeats seats filled',
                style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final b in batches)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _BatchCard(
              batch: b,
              planName: plans
                  .where((p) => p.id == b.planId)
                  .map((p) => p.name)
                  .firstOrNull,
              onTap: () => onOpenBatch(b),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Manage sessions'),
            style: TextButton.styleFrom(foregroundColor: tokens.violet),
          ),
        ),
      ],
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.planName,
    required this.onTap,
  });

  final AssignableBatch batch;
  final String? planName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final days = batch.daysOfWeek.map((d) => _dayShort[d % 7]).join(' ');
    final full = batch.enrolledCount >= batch.capacity;
    final fraction =
        batch.capacity == 0 ? 0.0 : batch.enrolledCount / batch.capacity;
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tokens.violet.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.event_repeat_rounded,
                        size: 20, color: tokens.violet),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(batch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          '${batch.sportName} · $days · ${Formatters.time12h(batch.startTime)}–${Formatters.time12h(batch.endTime)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${batch.enrolledCount}/${batch.capacity}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: full ? tokens.warning : tokens.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: fraction.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: tokens.surface2,
                        color: full ? tokens.warning : tokens.violet,
                      ),
                    ),
                  ),
                  if (planName != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Text(planName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tokens.textSecondary)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: tokens.textSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: TextStyle(color: tokens.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(backgroundColor: tokens.violet),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
