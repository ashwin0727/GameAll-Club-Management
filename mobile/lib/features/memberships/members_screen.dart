import 'package:flutter/material.dart';
import '../../shared/widgets/hub_widgets.dart';
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
import '../../data/models/finance.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/membership_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/tab_pop_scope.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'add_member_wizard_screen.dart';
import 'membership_detail_screen.dart';
import 'member_row.dart';
import 'membership_plan_details_screen.dart';
import 'membership_plans_tab.dart';
import 'members_ordering.dart';
import 'membership_plan_wizard_screen.dart';
import '../../shared/widgets/smooth_switcher.dart';

/// The Memberships hub — Members (the default tab) and Plans. Sessions, Schedule and Reports are one tap away
/// from the Members tab, as they are on the Coaching hub.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, this.openPlans = false, this.openNew = false, this.showPlansTab = false});

  /// Open on the Plans tab without launching the plan manager (a plain menu link).
  final bool showPlansTab;

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
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.openPlans || widget.showPlansTab ? 1 : 0);

  bool _loading = true;
  String? _error;
  String? _facilityId;
  late int _tabIndex = widget.openPlans || widget.showPlansTab ? 1 : 0;
  bool _autoOpenedPlans = false;
  bool _autoOpenedNew = false;

    List<MembershipPlan> _plans = const [];
  MembershipPageSummary? _summary;
  List<MembershipListRow> _members = const [];
  int _memberTotal = 0;
  List<AssignableBatch> _batches = const [];
  int? _overallRevenueInr;
  ({int amountInr, int count})? _pending;

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
      // Best-effort: the page renders without these two figures.
      int? overall;
      ({int amountInr, int count})? pending;
      try {
        final now = DateTime.now();
        final extras = await Future.wait([
          repo.getMembershipRevenueTimeseries(
            facility.id,
            from: '2000-01-01',
            to: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          ),
          ref.read(financeRepositoryProvider).listPendingPayments(ListPendingPaymentsInput(
                facilityId: facility.id,
                filters: const PendingPaymentFilters(sourceType: ObligationSource.membership),
                limit: 5000,
              )),
        ]);
        overall = (extras[0] as List<MembershipRevenuePoint>).fold<int>(0, (a, p) => a + p.amountInr);
        final owed = {
          for (final o in (extras[1] as PendingPaymentsPage).obligations) o.sourceId: o.outstandingMinor,
        };
        pending = membershipPending((results[2] as MembershipListResult).rows, owed, now);
      } catch (_) {}
      setState(() {
        _overallRevenueInr = overall;
        _pending = pending;
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
    final first = await repo.listMemberships(facilityId, MembershipListParams(page: 1, perPage: perPage));
    final pages = (first.totalCount / perPage).ceil().clamp(1, maxPages);
    if (pages == 1 || first.rows.isEmpty) return first;
    // The first page says how many there are, so the rest can be fetched together.
    final rest = await Future.wait([
      for (var page = 2; page <= pages; page++) repo.listMemberships(facilityId, MembershipListParams(page: page, perPage: perPage)),
    ]);
    return MembershipListResult(rows: [...first.rows, for (final r in rest) ...r.rows], totalCount: first.totalCount);
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
          // Icon-only so the title, this and the create button all fit on a narrow phone.
          IconButton(
            tooltip: 'Join link',
            onPressed: _copyJoinLink,
            icon: Icon(Icons.ios_share, size: 20, color: tokens.violet),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 130),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: _buildCreateAction() ?? const SizedBox.shrink(key: ValueKey('none')),
          ),
          const SizedBox(width: AppSpacing.lg),
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
        child: SmoothSwitcher(child: _loading
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
                          overallRevenueInr: _overallRevenueInr,
                          pending: _pending,
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
                  )),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.members),
      ),
    );
  }

  /// The primary "create" action (top right), which changes with the active tab:
  /// Members → new membership, Plans → new plan.
  Widget? _buildCreateAction() {
    if (_loading || _error != null) return null;
    final (label, icon, onTap) = switch (_tabIndex) {
      0 => ('New membership', Icons.person_add_alt_1, _openNewMembership),
      _ => ('New plan', Icons.add_card_outlined, _managePlans),
    };
    return HubCreateAction(key: ValueKey(label), label: label, icon: icon, onTap: onTap);
  }
}

// ─────────────────────────────────────────────────────────────── Plans ──

/// The Members page's summary card: total + active members on the photo, then Overall Revenue and Payment Pending in a
/// strip along the bottom — the shared [HubSummaryCard], so Coaching, Programs and Students open the same way.
class _MembersSummaryCard extends StatelessWidget {
  const _MembersSummaryCard({
    required this.total,
    required this.active,
    required this.revenue,
    required this.pending,
    required this.onRevenueTap,
    required this.onPendingTap,
  });

  final int total;
  final int active;
  final int? revenue;
  final ({int amountInr, int count})? pending;
  final VoidCallback onRevenueTap;
  final VoidCallback onPendingTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasPending = (pending?.count ?? 0) > 0;
    return HubSummaryCard(
      icon: Icons.groups_outlined,
      title: 'Total members',
      value: '$total',
      statusText: '$active active',
      left: HubSummaryCell(
        label: 'Overall Revenue',
        value: revenue == null ? '—' : Formatters.currencyInr(revenue!),
        sub: revenue == null ? null : 'All collected',
        onTap: onRevenueTap,
      ),
      right: HubSummaryCell(
        label: 'Payment Pending',
        value: pending == null ? '—' : Formatters.currencyInr(pending!.amountInr),
        valueColor: hasPending ? tokens.warning : null,
        sub: pending == null ? null : (hasPending ? '${pending!.count} unpaid' : 'Nothing pending'),
        subColor: hasPending ? const Color(0xFFFFFFFF).withValues(alpha: 0.75) : null,
        tint: hasPending ? tokens.warning.withValues(alpha: 0.12) : null,
        onTap: onPendingTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── People ──

/// The Members tab — one summary card (members, revenue, pending), then the
/// members themselves: Active first, then Inactive, most recent joiners first within each.
class _MembersTab extends StatefulWidget {
  const _MembersTab({
    required this.members,
    required this.counts,
    required this.summary,
    required this.overallRevenueInr,
    required this.pending,
    required this.batches,
    required this.onNew,
    required this.onReload,
  });

  final List<MembershipListRow> members;
  final MemberCounts counts;
  final MembershipPageSummary summary;
  final int? overallRevenueInr;
  final ({int amountInr, int count})? pending;
  final List<AssignableBatch> batches;
  final VoidCallback onNew;
  final VoidCallback onReload;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final q = _query.trim().toLowerCase();
    final ordered = orderMembersForDisplay(widget.members);
    final rows = ordered.where((m) {
      if (q.isEmpty) return true;
      return m.memberName.toLowerCase().contains(q) || m.memberPhone.contains(q);
    }).toList();
    final c = widget.counts;

    // The page header is a short fixed list; the member rows come after it and are built only as they
    // scroll into view — a club can have hundreds, and typing in the search box rebuilds this page.
    final header = <Widget>[
        _MembersSummaryCard(
          total: c.total,
          active: c.active,
          revenue: widget.overallRevenueInr,
          pending: widget.pending,
          onRevenueTap: () => context.push(AppRoutes.reportsMemberships),
          onPendingTap: () => context.push(AppRoutes.financePendingPayments),
        ),
        const SizedBox(height: AppSpacing.md),
        // The same one-tap shortcuts the Coaching hub has: Sessions, Schedule and Reports.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (label, icon, route) in [
              ('Sessions', Icons.event_note_outlined, AppRoutes.membershipSessions),
              ('Schedule', Icons.calendar_view_week_outlined, AppRoutes.membershipSchedule),
              ('Reports', Icons.bar_chart_rounded, AppRoutes.reportsMemberships),
            ])
              ActionChip(avatar: Icon(icon, size: 16), label: Text(label), onPressed: () => context.push(route)),
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
                    child: const Text('Add a Member'),
                  ),
                ],
              ],
            ),
          )
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      itemCount: header.length + rows.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final m = rows[i - header.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: MemberRow(
            row: m,
            onTap: () async {
              // The same Membership Details page the web shows; the list refreshes on the way back, since
              // the page can edit, record a payment for, cancel or delete the membership.
              await Navigator.of(context).push<Object?>(
                AppPageRoute(builder: (_) => MembershipDetailScreen(membershipId: m.membershipId)),
              );
              widget.onReload();
            },
          ),
        );
      },
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
