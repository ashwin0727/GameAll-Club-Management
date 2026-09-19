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
import '../../shared/widgets/skeleton.dart';
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

/// The redesigned Members hub — Plans, People and Sessions in one place.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen(
      {super.key,
      this.openPlans = false,
      this.openNew = false,
      this.openSessions = false});

  /// When true (deep-linked from the "+" menu), the plan editor opens as soon
  /// as the screen has loaded.
  final bool openPlans;

  /// When true, the "New membership" form opens as soon as the screen loads.
  final bool openNew;

  /// When true (deep-linked from the "+" menu), the sessions sheet opens as
  /// soon as the screen has loaded.
  final bool openSessions;

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
  bool _autoOpenedSessions = false;

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
      if (widget.openSessions && !_autoOpenedSessions && mounted) {
        _autoOpenedSessions = true;
        _tabs.animateTo(2); // land on Sessions afterwards
        WidgetsBinding.instance.addPostFrameCallback((_) => _manageSessions());
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
    // `/join/[facilityId]` (web) is keyed by the facility's UUID id — its
    // backing RPC (`get_public_membership_signup_info`) takes a `uuid`
    // param and can't resolve the human-readable slug.
    final id = ref.read(sessionControllerProvider).facility?.id;
    final link = id == null ? 'club.gameall.co' : 'club.gameall.co/join/$id';
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
            ? const _MembersScreenSkeleton()
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
          color: tokens.accentSolid(tokens.violet),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── photo background, same treatment as the dashboard's hero
            // cards — a dark gradient overlay keeps the white text legible.
            Image.asset('assets/images/members_card.png', fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.45),
                  ],
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
                      const Icon(Icons.show_chart_rounded,
                          size: 16, color: Color(0xFFFFFFFF)),
                      const SizedBox(width: 6),
                      Text('Recurring revenue',
                          style: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFFFFFFFF)
                                  .withValues(alpha: 0.8))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.currencyInr(amountInr),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.6,
                    child: Container(
                      height: 1,
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      _MiniFig(
                          value: '$activeCount',
                          label: 'active',
                          onAccent: true),
                      const SizedBox(width: AppSpacing.xl),
                      _MiniFig(
                        value: '$expiringCount',
                        label: 'expiring',
                        onAccent: true,
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      _MiniFig(
                        value: '+$newThisMonth',
                        label:
                            'new in ${_monthShort[DateTime.now().month - 1]}',
                        onAccent: true,
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

class _MiniFig extends StatelessWidget {
  const _MiniFig(
      {required this.value, required this.label, this.onAccent = false});

  final String value;
  final String label;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    const white = Color(0xFFFFFFFF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: onAccent ? white : tokens.textPrimary,
            )),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: onAccent
                    ? white.withValues(alpha: 0.75)
                    : tokens.textSecondary)),
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
    // Same full-bottom DraggableScrollableSheet other member/session sheets
    // use (see BatchMembersSheet) — a fixed, generous starting height rather
    // than shrink-wrapping to content, so an empty plan doesn't render as a
    // tiny stub floating over a dark scrim.
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: Column(
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
              Expanded(
                child: rows.isEmpty
                    ? ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        children: [
                          const SizedBox(height: AppSpacing.xxl),
                          Center(
                            child: Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: tokens.surface2, shape: BoxShape.circle),
                              child: Icon(Icons.group_outlined, size: 26, color: tokens.textSecondary),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text('No members yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15, color: tokens.textPrimary)),
                          const SizedBox(height: 4),
                          Text('Members who join "${plan.name}" will show up here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
                        ],
                      )
                    : ListView.separated(
                        controller: scrollController,
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
      },
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
                          '${batch.sportName} · ${Formatters.time12h(batch.startTime)}–${Formatters.time12h(batch.endTime)}',
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

/// Structure-shaped placeholder for the Members hub while its five
/// parallel loads are in flight — mirrors the default Plans tab: a tall
/// hero card (revenue + three mini figures) followed by a few plan-card
/// shapes (title/price row, subtitle, progress bar + trailing count).
class _MembersScreenSkeleton extends StatelessWidget {
  const _MembersScreenSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        SkeletonCard(
          child: SizedBox(
            height: 190 - AppSpacing.lg * 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeleton(width: 140, height: 13),
                const SizedBox(height: AppSpacing.sm),
                const AppSkeleton(width: 160, height: 26),
                const Spacer(),
                Row(
                  children: const [
                    AppSkeleton(width: 40, height: 28),
                    SizedBox(width: AppSpacing.xl),
                    AppSkeleton(width: 40, height: 28),
                    SizedBox(width: AppSpacing.xl),
                    AppSkeleton(width: 56, height: 28),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SkeletonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Expanded(child: AppSkeleton(width: 120, height: 15)),
                      SizedBox(width: AppSpacing.md),
                      AppSkeleton(width: 50, height: 15),
                    ],
                  ),
                  SizedBox(height: 6),
                  AppSkeleton(width: 160, height: 11),
                  SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                          child: AppSkeleton(height: 6, radius: AppRadius.pill)),
                      SizedBox(width: AppSpacing.md),
                      AppSkeleton(width: 64, height: 11),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

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
