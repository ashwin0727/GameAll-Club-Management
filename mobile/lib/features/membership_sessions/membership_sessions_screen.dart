import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/metric_carousel.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'membership_batches_sheet.dart';
import 'membership_session_detail_screen.dart';

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
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
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
      MaterialPageRoute<void>(
        builder: (_) => MembershipSessionDetailScreen(facilityId: facilityId, batchId: row.batchId, title: row.name),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Sessions'),
        actions: [
          if (_facilityId != null)
            TextButton.icon(
              onPressed: _openCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create'),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading membership sessions…')
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
          accentColor: AppColors.success,
        ),
        AppMetricCard(
          label: "Today's Sessions",
          value: s == null ? '—' : '${s.todaysSessions}',
          countTo: s?.todaysSessions,
          formatValue: n,
          icon: Icons.today,
          accentColor: AppColors.electricBlue,
        ),
        AppMetricCard(
          label: 'Guest Slots Released',
          value: s == null ? '—' : '${s.guestSlotsReleased}',
          countTo: s?.guestSlotsReleased,
          formatValue: n,
          icon: Icons.group_add_outlined,
          accentColor: AppColors.warning,
        ),
        AppMetricCard(
          label: 'Utilization',
          value: s == null ? '—' : '${s.avgUtilizationPct}%',
          countTo: s?.avgUtilizationPct,
          formatValue: (v) => '${v.round()}%',
          icon: Icons.donut_small,
          accentColor: AppColors.violet,
        ),
      ],
    );
  }

  Widget _filters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search sessions…',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _dropdown<String?>(
              hint: 'All Sports',
              value: _sportId,
              items: [
                const DropdownMenuItem(value: null, child: Text('All Sports')),
                ..._facilitySports.map((fs) => DropdownMenuItem(value: fs.id, child: Text(_sportName(fs)))),
              ],
              onChanged: (v) {
                setState(() {
                  _sportId = v;
                  _courtId = null;
                });
                _resetPageAndReload();
              },
            ),
            _dropdown<String?>(
              hint: 'All Courts',
              value: _courtId,
              items: [
                const DropdownMenuItem(value: null, child: Text('All Courts')),
                ..._areas
                    .where((a) => _sportId == null || a.facilitySportId == _sportId)
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))),
              ],
              onChanged: (v) {
                setState(() => _courtId = v);
                _resetPageAndReload();
              },
            ),
            _dropdown<String?>(
              hint: 'All Status',
              value: _status,
              items: const [
                DropdownMenuItem(value: null, child: Text('All Status')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'paused', child: Text('Paused')),
                DropdownMenuItem(value: 'full', child: Text('Full')),
              ],
              onChanged: (v) {
                setState(() => _status = v);
                _resetPageAndReload();
              },
            ),
            _dropdown<int?>(
              hint: 'All Days',
              value: _day,
              items: [
                const DropdownMenuItem(value: null, child: Text('All Days')),
                ..._dayOptions.map((d) => DropdownMenuItem(value: d.value, child: Text(d.label))),
              ],
              onChanged: (v) {
                setState(() => _day = v);
                _resetPageAndReload();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required String hint,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<T>(
        value: value,
        hint: Text(hint),
        underline: const SizedBox.shrink(),
        isDense: true,
        borderRadius: BorderRadius.circular(AppRadius.md),
        items: items,
        onChanged: onChanged,
      ),
    );
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
    final chip = sessionStatusChip(row.status);
    final utilization = (row.utilizationPct.clamp(0, 100)) / 100;
    return AppCard(
      onTap: () => _openDetail(row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${row.sportName} · ${row.courtName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              StatusBadge(label: chip.label, tone: chip.tone),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${daysLabel(row.daysOfWeek)} · ${hhmm(row.startTime)}–${hhmm(row.endTime)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _pill(Icons.people_outline, '${row.rosterCount}/${row.capacity} members'),
              const SizedBox(width: AppSpacing.sm),
              _pill(Icons.group_add_outlined, '${row.guestBookedToday}/${row.releasedToday} guests'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            // Fills from empty, matching the web row's bar-grow.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => LinearProgressIndicator(
                value: utilization * t,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text('${row.utilizationPct}% utilization', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _guestLinkCard() {
    final facilityId = _facilityId;
    if (facilityId == null) return const SizedBox.shrink();
    final link = 'https://gameall.club/join/$facilityId';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Guest Booking Link', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Share this link so guests can book released membership slots.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}