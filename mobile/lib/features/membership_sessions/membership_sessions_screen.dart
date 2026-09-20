import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/routing/page_transitions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/membership_session_dashboard.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/app_search_field.dart';
import '../../shared/widgets/metric_carousel.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import 'membership_batches_sheet.dart';
import 'membership_session_detail_screen.dart';
import '../authentication/session_controller.dart';

const _perPage = 10;

const List<({int value, String label})> _dayOptions = [
  (value: 1, label: 'Mon'),
  (value: 2, label: 'Tue'),
  (value: 3, label: 'Wed'),
  (value: 4, label: 'Thu'),
  (value: 5, label: 'Fri'),
  (value: 6, label: 'Sat'),
  (value: 0, label: 'Sun'),
];

String hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

String daysLabel(List<int> days) {
  if (days.length == 7) return 'Every day';
  return _dayOptions.where((d) => days.contains(d.value)).map((d) => d.label).join(', ');
}

({String label, StatusTone tone}) sessionStatusChip(MembershipSessionStatus s) {
  switch (s) {
    case MembershipSessionStatus.full:
      return (label: 'Full', tone: StatusTone.warning);
    case MembershipSessionStatus.paused:
      return (label: 'Paused', tone: StatusTone.neutral);
    case MembershipSessionStatus.active:
      return (label: 'Active', tone: StatusTone.success);
  }
}

/// Membership Sessions dashboard — KPI tiles, search + filters, a paginated
/// list of recurring sessions, and a guest booking link. Tapping a session
/// opens [MembershipSessionDetailScreen]. Mirrors the web
/// `membership-sessions-page.tsx`.
class MembershipSessionsScreen extends ConsumerStatefulWidget {
  const MembershipSessionsScreen({super.key});

  @override
  ConsumerState<MembershipSessionsScreen> createState() => _MembershipSessionsScreenState();
}

class _MembershipSessionsScreenState extends ConsumerState<MembershipSessionsScreen> {
  String? _facilityId;
  bool _isLoading = true;
  String? _loadError;

  MembershipSessionsSummary? _summary;
  List<MembershipSessionListRow>? _rows;
  int _totalCount = 0;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  String? _sportId;
  String? _courtId;
  String? _status;
  int? _day;
  int _page = 0;

  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final facility = ref.read(sessionControllerProvider).facility ??
          await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _isLoading = false;
          _loadError = 'Complete your facility setup before managing membership sessions.';
        });
        return;
      }
      _facilityId = facility.id;
      final opts = await Future.wait([
        ref.read(sportsRepositoryProvider).getFacilitySports(facility.id),
        ref.read(sportsRepositoryProvider).getActiveSports(),
        ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id),
      ]);
      _facilitySports = (opts[0] as List<FacilitySport>).where((f) => f.enabled).toList();
      _sports = opts[1] as List<Sport>;
      _areas = (opts[2] as List<PlayingArea>).where((a) => !a.archived).toList();
      setState(() => _isLoading = false);
      await _reload();
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _reload() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    setState(() => _rows = null);
    try {
      final results = await Future.wait([
        ref.read(membershipSessionRepositoryProvider).getSessionsSummary(facilityId),
        ref.read(membershipSessionRepositoryProvider).listSessionsAdmin(
              facilityId,
              search: _search.isEmpty ? null : _search,
              facilitySportId: _sportId,
              courtId: _courtId,
              status: _status,
              day: _day,
              limit: _perPage,
              offset: _page * _perPage,
            ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as MembershipSessionsSummary;
        final list = results[1] as ({List<MembershipSessionListRow> rows, int totalCount});
        _rows = list.rows;
        _totalCount = list.totalCount;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _rows = [];
          _loadError = e.message;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        _search = value.trim();
        _page = 0;
      });
      _reload();
    });
  }

  void _resetPageAndReload() {
    setState(() => _page = 0);
    _reload();
  }

  String _sportName(FacilitySport fs) {
    final s = _sports.where((sp) => sp.id == fs.sportId).firstOrNull;
    return fs.customSportName ?? s?.name ?? 'Sport';
  }

  Future<void> _openCreate() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipBatchesSheet(facilityId: facilityId),
    );
    await _reload();
  }

  Future<void> _openDetail(MembershipSessionListRow row) async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => MembershipSessionDetailScreen(facilityId: facilityId, batchId: row.batchId, title: row.name),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Sessions',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_facilityId != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: Material(
                color: tokens.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openCreate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: tokens.onAccent(tokens.primary)),
                        const SizedBox(width: 4),
                        Text('Create',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: tokens.onAccent(tokens.primary))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const _MembershipSessionsSkeleton()
            : _loadError != null && _rows == null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ResponsivePage(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kpiGrid(),
                          const SizedBox(height: AppSpacing.lg),
                          _filters(),
                          const SizedBox(height: AppSpacing.lg),
                          _list(),
                          const SizedBox(height: AppSpacing.lg),
                          _guestLinkCard(),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _kpiGrid() {
    final s = _summary;
    String n(num v) => v.round().toString();
    return MetricCarousel(
      cards: [
        AppMetricCard(
          label: 'Total Sessions',
          value: s == null ? '—' : '${s.totalSessions}',
          countTo: s?.totalSessions,
          formatValue: n,
          icon: Icons.event_repeat,
        ),
        AppMetricCard(
          label: 'Active Sessions',
          value: s == null ? '—' : '${s.activeSessions}',
          countTo: s?.activeSessions,
          formatValue: n,
          icon: Icons.play_circle_outline,
          accentColor: context.tokens.success,
        ),
        AppMetricCard(
          label: "Today's Sessions",
          value: s == null ? '—' : '${s.todaysSessions}',
          countTo: s?.todaysSessions,
          formatValue: n,
          icon: Icons.today,
          accentColor: context.tokens.electricBlue,
        ),
        AppMetricCard(
          label: 'Guest Slots Released',
          value: s == null ? '—' : '${s.guestSlotsReleased}',
          countTo: s?.guestSlotsReleased,
          formatValue: n,
          icon: Icons.group_add_outlined,
          accentColor: context.tokens.warning,
        ),
        AppMetricCard(
          label: 'Utilization',
          value: s == null ? '—' : '${s.avgUtilizationPct}%',
          countTo: s?.avgUtilizationPct,
          formatValue: (v) => '${v.round()}%',
          icon: Icons.donut_small,
          accentColor: context.tokens.violet,
        ),
      ],
    );
  }

  Widget _filters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSearchField(
          controller: _searchController,
          hintText: 'Search sessions…',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        // One horizontally-scrolling filter strip — same pattern as
        // Transactions/Refunds/Reports/Expenses — instead of native
        // DropdownButtons wrapped in pills, which pop an anchored menu
        // rather than the app's usual bottom sheet.
        SizedBox(
          height: AppSpacing.minTouchTarget,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              PickerChip(
                label: _sportId == null
                    ? 'All Sports'
                    : _facilitySports
                        .where((fs) => fs.id == _sportId)
                        .map(_sportName)
                        .firstOrNull ??
                        'Sport',
                onSelect: _pickSport,
              ),
              const SizedBox(width: AppSpacing.sm),
              PickerChip(
                label: _courtId == null
                    ? 'All Courts'
                    : _areas.where((a) => a.id == _courtId).map((a) => a.name).firstOrNull ??
                        'Court',
                onSelect: _pickCourt,
              ),
              const SizedBox(width: AppSpacing.sm),
              PickerChip(
                label: switch (_status) {
                  'active' => 'Active',
                  'paused' => 'Paused',
                  'full' => 'Full',
                  _ => 'All Status',
                },
                onSelect: _pickStatus,
              ),
              const SizedBox(width: AppSpacing.sm),
              PickerChip(
                label: _day == null
                    ? 'All Days'
                    : _dayOptions.where((d) => d.value == _day).map((d) => d.label).firstOrNull ??
                        'Day',
                onSelect: _pickDay,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickSport() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _sportId ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Sports'),
        ..._facilitySports.map((fs) => (value: fs.id, label: _sportName(fs))),
      ],
    );
    if (picked == null) return;
    setState(() {
      _sportId = picked == 'ALL' ? null : picked;
      _courtId = null;
    });
    _resetPageAndReload();
  }

  Future<void> _pickCourt() async {
    final visible =
        _areas.where((a) => _sportId == null || a.facilitySportId == _sportId).toList();
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _courtId ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Courts'),
        ...visible.map((a) => (value: a.id, label: a.name)),
      ],
    );
    if (picked == null) return;
    setState(() => _courtId = picked == 'ALL' ? null : picked);
    _resetPageAndReload();
  }

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _status ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Status'),
        (value: 'active', label: 'Active'),
        (value: 'paused', label: 'Paused'),
        (value: 'full', label: 'Full'),
      ],
    );
    if (picked == null) return;
    setState(() => _status = picked == 'ALL' ? null : picked);
    _resetPageAndReload();
  }

  Future<void> _pickDay() async {
    final picked = await showPickerSheet<int>(
      context: context,
      selected: _day ?? -1,
      options: [
        (value: -1, label: 'All Days'),
        ..._dayOptions.map((d) => (value: d.value, label: d.label)),
      ],
    );
    if (picked == null) return;
    setState(() => _day = picked == -1 ? null : picked);
    _resetPageAndReload();
  }

  Widget _list() {
    final rows = _rows;
    if (rows == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (rows.isEmpty) {
      return const EmptyStateView(message: 'No membership sessions match these filters.');
    }
    final totalPages = (_totalCount / _perPage).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows.map((row) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _sessionCard(row),
            )),
        if (totalPages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _page > 0
                    ? () {
                        setState(() => _page--);
                        _reload();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Prev'),
              ),
              Text('Page ${_page + 1} of $totalPages', style: Theme.of(context).textTheme.bodySmall),
              TextButton(
                onPressed: _page + 1 < totalPages
                    ? () {
                        setState(() => _page++);
                        _reload();
                      }
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _sessionCard(MembershipSessionListRow row) {
    final t = context.tokens;
    final chip = sessionStatusChip(row.status);
    final utilization = (row.utilizationPct.clamp(0, 100)) / 100;
    // Utilization is the number that decides whether a batch is worth
    // keeping, so let it carry colour: healthy green, thin amber, empty red.
    final bar = row.utilizationPct >= 60
        ? t.primary
        : (row.utilizationPct >= 30 ? t.warning : t.destructive);

    return Material(
      color: t.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(row),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.accentSolid(t.violet),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(Icons.event_repeat_rounded,
                        size: 19, color: t.onAccent(t.violet)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: t.textPrimary)),
                        const SizedBox(height: 1),
                        Text(
                          '${row.sportName} · ${row.courtName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: t.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(label: chip.label, tone: chip.tone),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 14, color: t.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${daysLabel(row.daysOfWeek)} · ${hhmm(row.startTime)}–${hhmm(row.endTime)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _pill(Icons.people_alt_rounded,
                      '${row.rosterCount}/${row.capacity} members'),
                  const SizedBox(width: AppSpacing.sm),
                  _pill(Icons.group_add_rounded,
                      '${row.guestBookedToday}/${row.releasedToday} guests'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                // Fills from empty, matching the web row's bar-grow.
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, anim, _) => LinearProgressIndicator(
                    value: utilization * anim,
                    minHeight: 7,
                    backgroundColor: t.surface2,
                    valueColor:
                        AlwaysStoppedAnimation(t.accentSolid(bar)),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text('Utilization',
                        style: TextStyle(
                            fontSize: 11, color: t.textSecondary)),
                  ),
                  Text('${row.utilizationPct}%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: t.accentSolid(bar))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    final t = context.tokens;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: t.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: t.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
        ],
      ),
    );
  }

  Widget _guestLinkCard() {
    final facilityId = _facilityId;
    if (facilityId == null) return const SizedBox.shrink();
    final t = context.tokens;
    final onC = t.onAccent(t.violet);
    final link = 'https://gameall.club/join/$facilityId';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.accentSolid(t.violet),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onC.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.link_rounded, size: 18, color: onC),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Guest booking link',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: onC)),
                const SizedBox(height: 1),
                Text(link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: onC.withValues(alpha: 0.75))),
              ],
            ),
          ),
          Material(
            color: onC.withValues(alpha: 0.16),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => SharePlus.instance.share(ShareParams(text: link)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.ios_share_rounded, size: 18, color: onC),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Structure-shaped placeholder for the Membership Sessions dashboard —
/// mirrors `_kpiGrid()`'s horizontally-scrolling KPI carousel, `_filters()`'s
/// search + chip strip, `_list()`'s session-row list, and the guest-link
/// card at the bottom.
class _MembershipSessionsSkeleton extends StatelessWidget {
  const _MembershipSessionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, _) =>
                  const SizedBox(width: 130, child: SkeletonStatTile()),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppSkeleton(height: 44, radius: AppRadius.md),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonChipRow(count: 4),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: SkeletonListRow(),
            ),
          const SizedBox(height: AppSpacing.lg),
          SkeletonCard(
            child: Row(
              children: const [
                AppSkeleton(width: 36, height: 36, radius: AppRadius.sm),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeleton(width: 140, height: 13),
                      SizedBox(height: 4),
                      AppSkeleton(width: 180, height: 11),
                    ],
                  ),
                ),
                AppSkeleton(width: 36, height: 36, radius: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}