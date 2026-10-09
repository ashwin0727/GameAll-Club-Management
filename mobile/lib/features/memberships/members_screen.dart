import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/routing/page_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/membership_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/tab_pop_scope.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'add_member_wizard_screen.dart';
import 'member_detail_screen.dart';
import 'member_row.dart';
import 'membership_plan_details_screen.dart';
import 'membership_plans_tab.dart';
import 'members_insights.dart';
import 'members_ordering.dart';
import 'membership_plan_wizard_screen.dart';

/// The Memberships hub — Members (the default tab) and Plans. Membership sessions live on their own
/// screen (Profile → Manage → Membership Sessions).
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, this.openPlans = false, this.openNew = false});

  /// When true (deep-linked from the "+" menu), the Plans tab is shown and the plan editor
  /// opens as soon as the screen has loaded.
  final bool openPlans;

  /// When true, the "New membership" form opens as soon as the screen loads.
  final bool openNew;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen>
    with SingleTickerProviderStateMixin {
  // Members is the first tab and the one the screen lands on; Plans only when deep-linked to.
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.openPlans ? 1 : 0);

  bool _loading = true;
  String? _error;
  String? _facilityId;
  late int _tabIndex = widget.openPlans ? 1 : 0;
  bool _autoOpenedPlans = false;
  bool _autoOpenedNew = false;

  List<MembershipPlan> _plans = const [];
  MembershipPageSummary? _summary;
  List<MembershipListRow> _members = const [];
  int _memberTotal = 0;
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
        _loadAllMemberships(repo, facility.id),
        repo.listAssignableBatches(facility.id),
      ]);
      setState(() {
        _facilityId = facility.id;
        _plans = results[0] as List<MembershipPlan>;
        _summary = results[1] as MembershipPageSummary;
        _members = (results[2] as MembershipListResult).rows;
        _memberTotal = (results[2] as MembershipListResult).totalCount;
        _batches = results[3] as List<AssignableBatch>;
        _loading = false;
      });
      if (widget.openPlans && !_autoOpenedPlans && mounted) {
        _autoOpenedPlans = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _managePlans());
      }
      if (widget.openNew && !_autoOpenedNew && mounted) {
        _autoOpenedNew = true;
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

  /// Every membership at the facility, a page at a time (capped). The list RPC sorts oldest-first, so
  /// a single page of 100 would hide the newest joiners at a larger club — and the Members tab shows
  /// the most recent first.
  Future<MembershipListResult> _loadAllMemberships(MembershipRepository repo, String facilityId) async {
    const perPage = 100;
    const maxPages = 10;
    final rows = <MembershipListRow>[];
    var total = 0;
    for (var page = 1; page <= maxPages; page++) {
      final result = await repo.listMemberships(facilityId, MembershipListParams(page: page, perPage: perPage));
      total = result.totalCount;
      rows.addAll(result.rows);
      if (rows.length >= total || result.rows.isEmpty) break;
    }
    return MembershipListResult(rows: rows, totalCount: total);
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

  /// A plan's details page — its price and length, benefits, session slots and members.
  Future<void> _openPlan(MembershipPlan plan) async {
    final id = _facilityId;
    if (id == null) return;
    final changed = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => MembershipPlanDetailsScreen(
          plan: plan,
          facilityId: id,
          members: _planMembers(plan),
          batches: _batches.where((b) => b.planId == plan.id).toList(),
        ),
      ),
    );
    if (changed == true) _load();
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

  /// New plan — the four-step Create Plan wizard (Plan Details → Plan Configuration → Court Access →
  /// Review & Create), same as the web's /memberships/v1/plans/new.
  Future<void> _managePlans() async {
    final created = await Navigator.of(context).push<bool>(
      AppPageRoute(builder: (_) => const MembershipPlanWizardScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openNewMembership() async {
    final created = await Navigator.of(context).push<bool>(
      AppPageRoute(builder: (_) => const AddMemberWizardScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TabPopScope(
      tab: AppTab.members,
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: const Text('Memberships',
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
                  Tab(text: 'Members'),
                  Tab(text: 'Plans'),
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
                        _MembersTab(
                          members: _members,
                          counts: countMembers(_members, DateTime.now(), total: _memberTotal),
                          summary: _summary!,
                          batches: _batches,
                          onNew: _openNewMembership,
                          onReload: _load,
                        ),
                        MembershipPlansTab(
                          plans: _plans,
                          batches: _batches,
                          memberCount: _planMemberCount,
                          onOpen: _openPlan,
                          onCreate: _managePlans,
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
  /// Members → new membership, Plans → new plan.
  Widget? _buildCreateFab() {
    if (_loading || _error != null) return null;
    final (label, icon, onTap) = switch (_tabIndex) {
      0 => ('New membership', Icons.person_add_alt_1, _openNewMembership),
      _ => ('New plan', Icons.add_card_outlined, _managePlans),
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

/// The photo hero card — a title, one big figure, and a row of small figures beneath a hairline.
/// The Members tab shows the total member count in it.
class _HeroStatCard extends StatelessWidget {
  const _HeroStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.figs,
  });

  final IconData icon;
  final String title;
  final String value;
  final List<({String value, String label})> figs;

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
                      Icon(icon, size: 16, color: const Color(0xFFFFFFFF)),
                      const SizedBox(width: 6),
                      Text(title,
                          style: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFFFFFFFF)
                                  .withValues(alpha: 0.8))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
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
                      for (var i = 0; i < figs.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.xl),
                        _MiniFig(
                            value: figs[i].value,
                            label: figs[i].label,
                            onAccent: true),
                      ],
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

// ─────────────────────────────────────────────────────────────── People ──

/// The Members tab — a total-members hero card, a collapsible "View More Insights" panel, then the
/// members themselves: Active first, then Inactive, most recent joiners first within each.
class _MembersTab extends StatefulWidget {
  const _MembersTab({
    required this.members,
    required this.counts,
    required this.summary,
    required this.batches,
    required this.onNew,
    required this.onReload,
  });

  final List<MembershipListRow> members;
  final MemberCounts counts;
  final MembershipPageSummary summary;
  final List<AssignableBatch> batches;
  final VoidCallback onNew;
  final VoidCallback onReload;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  String _query = '';
  bool _insightsOpen = false;
  bool _expiringOnly = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final now = DateTime.now();
    final q = _query.trim().toLowerCase();
    final ordered = orderMembersForDisplay(widget.members);
    final rows = ordered.where((m) {
      if (_expiringOnly && !isExpiringSoon(m, now)) return false;
      if (q.isEmpty) return true;
      return m.memberName.toLowerCase().contains(q) || m.memberPhone.contains(q);
    }).toList();
    final c = widget.counts;
    final utilization = utilizationPercent(widget.batches);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        _HeroStatCard(
          icon: Icons.groups_rounded,
          title: 'Total members',
          value: '${c.total}',
          figs: [
            (value: '${c.active}', label: 'active'),
            (value: '${c.inactive}', label: 'inactive'),
            (value: '${c.expiring}', label: 'expiring'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        InsightsPanel(
          open: _insightsOpen,
          onToggle: () => setState(() => _insightsOpen = !_insightsOpen),
          tiles: [
            InsightData(
              icon: Icons.groups_outlined,
              color: tokens.electricBlue,
              title: 'Total Members',
              value: '${c.total}',
              onTap: () => setState(() => _expiringOnly = false),
            ),
            InsightData(
              icon: Icons.schedule_rounded,
              color: tokens.warning,
              title: 'Expiring Soon',
              value: '${c.expiring}',
              sub: 'Next 30 days',
              onTap: () => setState(() => _expiringOnly = true),
            ),
            InsightData(
              icon: Icons.account_balance_wallet_outlined,
              color: tokens.violet,
              title: 'Total Revenue',
              value: Formatters.currencyInr(widget.summary.revenueInr),
              sub: _changeLabel(widget.summary.revenueChangePct),
              subColor: _changeColor(tokens, widget.summary.revenueChangePct),
              onTap: () => context.push(AppRoutes.reportsMemberships),
            ),
            InsightData(
              icon: Icons.bar_chart_rounded,
              color: tokens.primary,
              title: 'Utilization',
              value: utilization == null ? '—' : '$utilization%',
              sub: 'Avg. slot usage',
              onTap: () => context.push(AppRoutes.membershipSessions),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${rows.length} member${rows.length == 1 ? '' : 's'}',
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
        if (_expiringOnly) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: const Text('Expiring in 30 days'),
              onDeleted: () => setState(() => _expiringOnly = false),
            ),
          ),
        ],
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
                      : _expiringOnly
                          ? 'No memberships are expiring in the next 30 days.'
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
              child: MemberRow(
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

  static String? _changeLabel(double? pct) {
    if (pct == null) return null;
    final rounded = pct.abs().round();
    return pct >= 0 ? '↑ +$rounded%' : '↓ $rounded%';
  }

  static Color? _changeColor(AppColorTokens tokens, double? pct) {
    if (pct == null) return null;
    return pct >= 0 ? tokens.primary : tokens.destructive;
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
