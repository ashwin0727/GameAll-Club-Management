import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/dashboard.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/metric_carousel.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';

const Map<DateRangePreset, String> _presetLabels = {
  DateRangePreset.today: 'Today',
  DateRangePreset.yesterday: 'Yesterday',
  DateRangePreset.thisWeek: 'This Week',
  DateRangePreset.thisMonth: 'This Month',
};

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _facilityId;
  String? _selectedSportId;
  DateRangePreset _preset = DateRangePreset.today;
  int _revenueMonthOffset = 0;

  bool _isLoading = true;
  String? _loadError;
  DashboardSummary? _summary;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final facility = ref.read(sessionControllerProvider).facility;
    _facilityId = facility?.id;
    await _load();
  }

  Future<void> _load() async {
    if (_facilityId == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'Unable to load your facility.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final summary = await ref.read(dashboardRepositoryProvider).getDashboardSummary(
        _facilityId!,
        facilitySportId: _selectedSportId,
        preset: _preset,
        revenueMonthOffset: _revenueMonthOffset,
      );
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GameAll'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Bookings',
            onPressed: () => context.push(AppRoutes.bookings),
          ),
          IconButton(
            icon: const Icon(Icons.event_available_outlined),
            tooltip: 'Guest Bookings',
            onPressed: () => context.push(AppRoutes.guestBookings),
          ),
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Guest Players',
            onPressed: () => context.push(AppRoutes.guests),
          ),
          IconButton(
            icon: const Icon(Icons.workspace_premium_outlined),
            tooltip: 'Memberships',
            onPressed: () => context.push(AppRoutes.memberships),
          ),
          IconButton(
            icon: const Icon(Icons.event_repeat_outlined),
            tooltip: 'Membership Sessions',
            onPressed: () => context.push(AppRoutes.membershipSessions),
          ),
          IconButton(
            icon: const Icon(Icons.currency_rupee),
            tooltip: 'Refunds',
            onPressed: () => context.push(AppRoutes.refunds),
          ),
          // Mirrors the web's NAV_ITEMS "Finance" entry (src/lib/constants.ts).
          // This app has no drawer or bottom nav — every module is reached
          // from these dashboard app-bar actions.
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Finance',
            onPressed: () => context.push(AppRoutes.finance),
          ),
          // Sign out now lives on the Profile screen — this avatar is the
          // one entry point to it (spec §"Profile").
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
            child: InkWell(
              onTap: () => context.push(AppRoutes.profile),
              customBorder: const CircleBorder(),
              child: AppAvatar(name: user?.fullName ?? '?', size: AppAvatarSize.small),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const _DashboardSkeleton()
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ResponsivePage(
                  child: _DashboardBody(
                    summary: _summary!,
                    greeting: _greeting(),
                    firstName: user?.fullName.split(' ').first,
                    selectedSportId: _selectedSportId,
                    preset: _preset,
                    onPickSport: () async {
                      final picked = await _showSportPicker(context, _summary!.sports);
                      if (picked != _selectedSportId) {
                        setState(() => _selectedSportId = picked);
                        _load();
                      }
                    },
                    onPickPreset: () async {
                      final picked = await _showDatePresetPicker(context, _preset);
                      if (picked != null && picked != _preset) {
                        setState(() => _preset = picked);
                        _load();
                      }
                    },
                    revenueMonthOffset: _revenueMonthOffset,
                    onPickRevenueMonth: () async {
                      final picked = await _showRevenueMonthPicker(context, _revenueMonthOffset);
                      if (picked != null && picked != _revenueMonthOffset) {
                        setState(() => _revenueMonthOffset = picked);
                        _load();
                      }
                    },
                  ),
                ),
              ),
      ),
    );
  }

  Future<String?> _showSportPicker(BuildContext context, List<AvailableSportOption> sports) {
    return showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('All Sports'), onTap: () => Navigator.pop(context, null)),
            ...sports.map(
              (s) => ListTile(
                leading: Text(s.sportIcon),
                title: Text(s.sportName),
                onTap: () => Navigator.pop(context, s.facilitySportId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateRangePreset?> _showDatePresetPicker(BuildContext context, DateRangePreset current) {
    return showModalBottomSheet<DateRangePreset>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _presetLabels.entries
              .map((e) => ListTile(title: Text(e.value), onTap: () => Navigator.pop(context, e.key)))
              .toList(),
        ),
      ),
    );
  }

  Future<int?> _showRevenueMonthPicker(BuildContext context, int current) {
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var offset = 0; offset < 12; offset++)
              ListTile(
                title: Text(revenueMonthLabel(offset)),
                selected: offset == current,
                onTap: () => Navigator.pop(context, offset),
              ),
          ],
        ),
      ),
    );
  }
}

const _monthNamesShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String revenueMonthLabel(int offset) {
  if (offset == 0) return 'This Month';
  if (offset == 1) return 'Last Month';
  final now = DateTime.now();
  final d = DateTime(now.year, now.month - offset, 1);
  return '${_monthNamesShort[d.month - 1]} ${d.year}';
}

/// The whole scrolling dashboard body, in mobile-first priority order:
/// greeting → filters → metrics → expiring alert → schedule → attention →
/// memberships → revenue → utilization → quick actions.
class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.summary,
    required this.greeting,
    required this.firstName,
    required this.selectedSportId,
    required this.preset,
    required this.onPickSport,
    required this.onPickPreset,
    required this.revenueMonthOffset,
    required this.onPickRevenueMonth,
  });

  final DashboardSummary summary;
  final String greeting;
  final String? firstName;
  final String? selectedSportId;
  final DateRangePreset preset;
  final VoidCallback onPickSport;
  final VoidCallback onPickPreset;
  final int revenueMonthOffset;
  final VoidCallback onPickRevenueMonth;

  String get _sportLabel => selectedSportId == null
      ? 'All Sports'
      : summary.sports
                .where((s) => s.facilitySportId == selectedSportId)
                .map((s) => s.sportName)
                .firstOrNull ??
            'All Sports';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting${firstName != null ? ', $firstName' : ''} 👋',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${summary.facilityName}${summary.facilityCity.isNotEmpty ? ' · ${summary.facilityCity}' : ''}',
          style: TextStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _SelectorChip(label: _sportLabel, onSelect: onPickSport),
            _SelectorChip(label: _presetLabels[preset]!, onSelect: onPickPreset),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _MetricCarousel(kpis: summary.kpis),
        if (summary.memberships.expiringSoon > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          _ExpiringMembershipCard(count: summary.memberships.expiringSoon),
        ],
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: "Today's Schedule"),
        const SizedBox(height: AppSpacing.sm),
        _ScheduleTimeline(timeline: summary.scheduleTimeline, showNow: preset == DateRangePreset.today),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(
          title: 'Revenue Overview',
          trailing: _SelectorChip(
            label: revenueMonthLabel(revenueMonthOffset),
            onSelect: onPickRevenueMonth,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _RevenueOverviewCard(overview: summary.revenueOverview),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: 'Attention Required'),
        const SizedBox(height: AppSpacing.sm),
        _AttentionCard(items: summary.attentionItems),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: 'Memberships'),
        const SizedBox(height: AppSpacing.sm),
        _MembershipSummaryCard(memberships: summary.memberships),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: 'Court/Turf Utilization'),
        const SizedBox(height: AppSpacing.sm),
        _UtilizationCard(utilization: summary.utilization),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: 'Quick Actions'),
        const SizedBox(height: AppSpacing.sm),
        const _QuickActionGrid(),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// The dashboard's KPI tiles, shown one at a time by [MetricCarousel].
class _MetricCarousel extends StatelessWidget {
  const _MetricCarousel({required this.kpis});

  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MetricCarousel(
      cards: [
        AppMetricCard(
          label: 'Revenue',
          value: Formatters.currencyInr(kpis.revenueInr.value),
          countTo: kpis.revenueInr.value,
          formatValue: (v) => Formatters.currencyInr(v.round()),
          changePercent: kpis.revenueInr.changePercent,
          icon: Icons.account_balance_wallet_outlined,
          accentColor: tokens.electricBlue,
        ),
        AppMetricCard(
          label: 'Active Membership',
          value: kpis.activeMemberships.value.toStringAsFixed(0),
          countTo: kpis.activeMemberships.value,
          formatValue: (v) => v.round().toString(),
          changePercent: kpis.activeMemberships.changePercent,
          icon: Icons.group_outlined,
          accentColor: tokens.violet,
        ),
        AppMetricCard(
          label: 'Guest Bookings',
          value: kpis.guestBookings.value.toStringAsFixed(0),
          countTo: kpis.guestBookings.value,
          formatValue: (v) => v.round().toString(),
          changePercent: kpis.guestBookings.changePercent,
          icon: Icons.group_add_outlined,
          accentColor: tokens.warning,
        ),
        AppMetricCard(
          label: 'Utilization',
          value: '${kpis.utilizationPercent.value}%',
          countTo: kpis.utilizationPercent.value,
          formatValue: (v) => '${v.round()}%',
          changePercent: kpis.utilizationPercent.changePercent,
          icon: Icons.pie_chart_outline,
          accentColor: tokens.primary,
        ),
      ],
    );
  }
}

class _ExpiringMembershipCard extends StatelessWidget {
  const _ExpiringMembershipCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      onTap: () => context.push(AppRoutes.memberships),
      child: Row(
        children: [
          Icon(Icons.card_membership_outlined, color: tokens.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count membership${count == 1 ? '' : 's'} expiring soon',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('Tap to view memberships', style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: tokens.textSecondary),
        ],
      ),
    );
  }
}

/// A positioned court-by-court timeline for today — one row per court, each
/// block a real booking or confirmed membership session placed by its actual
/// start/end within a window derived from today's operating hours. Scrolls
/// horizontally; overlapping blocks in a court stack onto separate lanes.
class _ScheduleTimeline extends StatefulWidget {
  const _ScheduleTimeline({required this.timeline, required this.showNow});

  final ScheduleTimeline timeline;
  final bool showNow;

  @override
  State<_ScheduleTimeline> createState() => _ScheduleTimelineState();
}

class _ScheduleTimelineState extends State<_ScheduleTimeline> {
  static const _hourWidth = 64.0;
  static const _labelWidth = 96.0;
  static const _laneHeight = 34.0;
  static const _trackPad = 0.0;

  String? _sportFilter;

  String _hourTick(int hour) {
    final h = hour % 24;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'AM' : 'PM'}';
  }

  Color _blockColor(BuildContext context, ScheduleBlockType type) {
    switch (type) {
      case ScheduleBlockType.member:
        return context.tokens.success;
      case ScheduleBlockType.guest:
        return context.tokens.electricBlue;
      case ScheduleBlockType.session:
        return context.tokens.violet;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final timeline = widget.timeline;
    final hours = timeline.endHour - timeline.startHour;
    if (timeline.courts.isEmpty || hours <= 0) {
      return const AppCard(child: Text('No courts configured yet.'));
    }

    final sportNames = timeline.courts.map((c) => c.sportName).toSet().toList()..sort();
    final activeSport = sportNames.contains(_sportFilter) ? _sportFilter : null;
    final courts = activeSport == null
        ? timeline.courts
        : timeline.courts.where((c) => c.sportName == activeSport).toList();

    final trackWidth = hours * _hourWidth;
    final windowMinutes = hours * 60;
    double toX(int minute) => (minute - timeline.startHour * 60) / windowMinutes * trackWidth;

    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;
    final showNowLine =
        widget.showNow && nowMinute >= timeline.startHour * 60 && nowMinute <= timeline.endHour * 60;

    // The grid settles first (ruler, then each court row), then the
    // bookings wipe open in the order they start during the day.
    const rulerSettleMs = 120;
    final rows = <Widget>[];
    for (var rowIndex = 0; rowIndex < courts.length; rowIndex++) {
      final court = courts[rowIndex];
      final rowHeight = court.laneCount * _laneHeight + _trackPad;
      final rowDelayMs = rulerSettleMs + rowIndex * 55;
      rows.add(
        _DelayedEnter(
          delay: Duration(milliseconds: rowDelayMs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        court.courtName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        court.sportName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: trackWidth,
                height: rowHeight,
                child: Stack(
                  children: [
                    for (var i = 0; i < hours; i++)
                      Positioned(
                        left: i * _hourWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 1, color: tokens.borderColor.withValues(alpha: 0.4)),
                      ),
                    for (final block in court.blocks)
                      Positioned(
                        left: toX(block.startMinute),
                        top: block.lane * _laneHeight,
                        width: (toX(block.endMinute) - toX(block.startMinute)).clamp(6.0, trackWidth).toDouble(),
                        height: _laneHeight,
                        child: _DelayedWipe(
                          delay: Duration(
                            milliseconds:
                                rowDelayMs + 140 + (toX(block.startMinute) / (trackWidth == 0 ? 1 : trackWidth) * 260).round(),
                          ),
                          child: _block(context, block),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      rows.add(Divider(height: 1, color: tokens.borderColor.withValues(alpha: 0.6)));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sportNames.length > 1) ...[
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final name in <String?>[null, ...sportNames])
                  _SportFilterChip(
                    label: name ?? 'All Courts',
                    selected: activeSport == name,
                    onTap: () => setState(() => _sportFilter = name),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Keyed on the filter so switching sports replays the reveal
            // rather than snapping the new grid into place.
            key: ValueKey(activeSport ?? '__all'),
            child: SizedBox(
              width: _labelWidth + trackWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: _labelWidth, bottom: 4),
                    child: Row(
                      children: [
                        for (var i = 0; i < hours; i++)
                          SizedBox(
                            width: _hourWidth,
                            child: _DelayedEnter(
                              delay: Duration(milliseconds: i * 18),
                              slideX: 0,
                              child: Text(
                                _hourTick(timeline.startHour + i),
                                style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Stack(
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
                      if (showNowLine)
                        Positioned(
                          left: _labelWidth + toX(nowMinute),
                          top: 0,
                          bottom: 0,
                          child: _DelayedEnter(
                            delay: Duration(milliseconds: rulerSettleMs + courts.length * 55 + 260),
                            slideX: 0,
                            child: Container(width: 2, color: tokens.destructive),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              _legendDot(context, tokens.success, 'Member'),
              _legendDot(context, tokens.electricBlue, 'Guest'),
              _legendDot(context, tokens.violet, 'Membership session'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, ScheduleBlock block) {
    final color = _blockColor(context, block.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            block.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
          Text(
            block.timeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: context.tokens.textSecondary)),
      ],
    );
  }
}

/// Drives a 0→1 value for chart/bar reveals (line draw, donut sweep,
/// progress fill). Returns the settled state immediately under reduced
/// motion, so the figure is never withheld from someone who opted out.
class _AnimatedProgress extends StatelessWidget {
  const _AnimatedProgress({
    required this.builder,
    required this.duration,
    this.delay = Duration.zero,
  });

  final Widget Function(double progress) builder;
  final Duration duration;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return builder(1);
    final totalMs = duration.inMilliseconds + delay.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(delay.inMilliseconds / totalMs, 1, curve: Curves.easeOutCubic),
      builder: (context, t, _) => builder(t.clamp(0, 1)),
    );
  }
}

/// Today's Schedule motion primitives — a delayed fade/slide for the grid
/// (ruler ticks, court rows) and a delayed left-to-right wipe for the
/// booking blocks, so the day reveals in the order it happens. Both are
/// skipped when the platform asks for reduced motion.
class _DelayedEnter extends StatelessWidget {
  const _DelayedEnter({required this.delay, required this.child, this.slideX = -8});

  final Duration delay;
  final Widget child;
  final double slideX;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    const runMs = 420;
    final totalMs = runMs + delay.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(delay.inMilliseconds / totalMs, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(slideX * (1 - t), 0), child: child),
      ),
      child: child,
    );
  }
}

/// Reveals its child left-to-right by clipping rather than scaling, so the
/// booking label inside never stretches.
class _DelayedWipe extends StatelessWidget {
  const _DelayedWipe({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    const runMs = 460;
    final totalMs = runMs + delay.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(delay.inMilliseconds / totalMs, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: ClipRect(clipper: _WipeClipper(t.clamp(0, 1)), child: child),
      ),
      child: child,
    );
  }
}

class _WipeClipper extends CustomClipper<Rect> {
  const _WipeClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(_WipeClipper oldClipper) => oldClipper.progress != progress;
}

/// A pill in the Today's Schedule court/sport filter row.
class _SportFilterChip extends StatelessWidget {
  const _SportFilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? tokens.primary : tokens.borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? tokens.onPrimary : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.items});

  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (items.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.check_circle, color: tokens.success, size: 18),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(child: Text("You're all caught up. No immediate attention required.")),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: tokens.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(item.message)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MembershipSummaryCard extends StatelessWidget {
  const _MembershipSummaryCard({required this.memberships});

  final MembershipSummary memberships;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final total = memberships.active + memberships.expiringSoon + memberships.expired;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$total', style: Theme.of(context).textTheme.headlineSmall),
          Text('Total members', style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
          const SizedBox(height: AppSpacing.md),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  Expanded(flex: memberships.active, child: Container(height: 8, color: tokens.success)),
                  Expanded(flex: memberships.expiringSoon, child: Container(height: 8, color: tokens.warning)),
                  Expanded(flex: memberships.expired, child: Container(height: 8, color: tokens.destructive)),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _LegendDot(color: tokens.success, label: 'Active ${memberships.active}'),
              _LegendDot(color: tokens.warning, label: 'Expiring ${memberships.expiringSoon}'),
              _LegendDot(color: tokens.destructive, label: 'Expired ${memberships.expired}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: context.tokens.textSecondary, fontSize: 12)),
      ],
    );
  }
}

/// Collected revenue for the selected period, its change vs. the previous
/// period, and a real day-by-day trend (mobile keeps this compact — the full
/// breakdown lives on the Finance screen).
class _RevenueOverviewCard extends StatelessWidget {
  const _RevenueOverviewCard({required this.overview});

  final RevenueOverview overview;

  static double _niceCeil(num v) {
    if (v <= 0) return 1000;
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final n = v / p;
    final step = n <= 1 ? 1 : (n <= 2 ? 2 : (n <= 5 ? 5 : 10));
    return step * p;
  }

  static String _compactInr(num v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(v % 10000000 == 0 ? 0 : 1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(v % 100000 == 0 ? 0 : 1)}L';
    if (v >= 1000) return '₹${(v / 1000).round()}K';
    return '₹${v.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final change = overview.changePercent;
    final up = change != null && change > 0;
    final down = change != null && change < 0;
    final changeColor = up ? tokens.success : (down ? tokens.destructive : tokens.textSecondary);

    final values = overview.points.map((p) => p.amountInr).toList();
    final niceMax = _niceCeil(values.isEmpty ? 0 : values.reduce(math.max));
    final yTicks = [1.0, 0.75, 0.5, 0.25, 0.0].map((f) => niceMax * f).toList();

    final n = overview.points.length;
    final tickCount = math.min(5, n);
    final xTickIdx = [
      for (var k = 0; k < tickCount; k++) tickCount <= 1 ? 0 : ((k / (tickCount - 1)) * (n - 1)).round(),
    ];

    return AppCard(
      onTap: () => context.push(AppRoutes.finance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CurrencyText(overview.totalInr, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('Total Revenue · ${overview.monthLabel}',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
              if (change != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(up ? Icons.arrow_upward : (down ? Icons.arrow_downward : Icons.remove),
                    size: 12, color: changeColor),
                Text('${change.abs().toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: changeColor)),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                height: 130,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final t in yTicks)
                      Text(_compactInr(t), style: TextStyle(fontSize: 9, color: tokens.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 130,
                  child: _AnimatedProgress(
                    duration: const Duration(milliseconds: 900),
                    builder: (t) => CustomPaint(
                      painter: _RevenueChartPainter(
                        values: values,
                        niceMax: niceMax,
                        lineColor: tokens.primary,
                        gridColor: tokens.borderColor.withValues(alpha: 0.4),
                        progress: t,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Stack(
              children: [
                const SizedBox(height: 14, width: double.infinity),
                for (final idx in xTickIdx)
                  Align(
                    alignment: Alignment(n <= 1 ? 0 : (idx / (n - 1)) * 2 - 1, 0),
                    child: Text(
                      _dayLabel(overview.points[idx].date),
                      style: TextStyle(fontSize: 9, color: tokens.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: tokens.borderColor),
          const SizedBox(height: AppSpacing.sm),
          Text('Revenue Breakdown', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _RevenueBreakdownChart(segments: overview.breakdown, total: overview.totalInr),
        ],
      ),
    );
  }

  static Color breakdownColor(BuildContext context, RevenueBreakdownKey key) {
    final tokens = context.tokens;
    switch (key) {
      case RevenueBreakdownKey.bookings:
        return tokens.success;
      case RevenueBreakdownKey.memberships:
        return tokens.electricBlue;
      case RevenueBreakdownKey.coaching:
        return tokens.warning;
      case RevenueBreakdownKey.other:
        return tokens.violet;
    }
  }

  static String _dayLabel(String iso) {
    final parts = iso.split('-');
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
    final d = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 1;
    return '$d ${_monthNamesShort[m - 1]}';
  }
}

class _RevenueChartPainter extends CustomPainter {
  _RevenueChartPainter({
    required this.values,
    required this.niceMax,
    required this.lineColor,
    required this.gridColor,
    this.progress = 1,
  });

  final List<int> values;
  final double niceMax;
  final Color lineColor;
  final Color gridColor;

  /// 0..1 — how much of the trend has been drawn, left to right.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;

    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;
    Offset pointAt(int i) {
      final x = values.length > 1 ? i * stepX : size.width / 2;
      final y = size.height - (values[i] / niceMax).clamp(0.0, 1.0) * size.height;
      return Offset(x, y);
    }

    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      linePath.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(pointAt(values.length - 1).dx, size.height)
      ..lineTo(pointAt(0).dx, size.height)
      ..close();

    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) return;

    // The fill wipes in behind the line; the line itself is drawn by
    // extracting the leading portion of the path, so it truly "draws".
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withValues(alpha: 0.3), lineColor.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    if (t >= 1) {
      canvas.drawPath(linePath, strokePaint);
    } else {
      for (final metric in linePath.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * t), strokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_RevenueChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.niceMax != niceMax ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.progress != progress;
}

/// Donut + legend showing where the month's revenue came from.
class _RevenueBreakdownChart extends StatelessWidget {
  const _RevenueBreakdownChart({required this.segments, required this.total});

  final List<RevenueBreakdownSegment> segments;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: _AnimatedProgress(
            duration: const Duration(milliseconds: 820),
            builder: (t) => CustomPaint(
              painter: _DonutPainter(
                values: [for (final s in segments) s.amountInr.toDouble()],
                colors: [for (final s in segments) _RevenueOverviewCard.breakdownColor(context, s.key)],
                trackColor: tokens.surface2,
                progress: t,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            children: [
              for (final s in segments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _RevenueOverviewCard.breakdownColor(context, s.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.count != null ? '${s.label} · ${s.count}' : s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.unavailable ? '—' : Formatters.currencyInr(s.amountInr),
                        style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${total > 0 ? ((s.amountInr / total) * 100).round() : 0}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors, required this.trackColor, this.progress = 1});

  final List<double> values;
  final List<Color> colors;
  final Color trackColor;

  /// 0..1 — how far the ring has swept open, clockwise from 12 o'clock.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 14.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    // One clockwise sweep reveals the whole ring, so each segment appears in
    // order rather than the colours all fading in at once.
    final revealed = (progress.clamp(0.0, 1.0)) * 2 * math.pi;
    var start = -math.pi / 2;
    var drawn = 0.0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = (values[i] / total) * 2 * math.pi;
      final visible = (revealed - drawn).clamp(0.0, sweep);
      if (visible > 0) {
        canvas.drawArc(
          rect,
          start,
          visible,
          false,
          Paint()
            ..color = colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke,
        );
      }
      start += sweep;
      drawn += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors || oldDelegate.progress != progress;
}

class _UtilizationCard extends StatelessWidget {
  const _UtilizationCard({required this.utilization});

  final UtilizationSummary utilization;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (utilization.bySport.isEmpty) {
      return const AppCard(child: Text('No sports configured yet.'));
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, s) in utilization.bySport.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.sportName)),
                      Text('${s.utilizationPercent}%', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    // Each bar fills from empty, staggered down the list.
                    child: _AnimatedProgress(
                      duration: const Duration(milliseconds: 700),
                      delay: Duration(milliseconds: 160 + i * 90),
                      builder: (t) => LinearProgressIndicator(
                        value: (s.utilizationPercent / 100).clamp(0, 1).toDouble() * t,
                        minHeight: 6,
                        backgroundColor: tokens.surface2,
                        valueColor: AlwaysStoppedAnimation(tokens.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 2-column grid of real, currently-navigable destinations — never a tile
/// that leads nowhere (spec §"Owner Home").
class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid();

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickActionData>[
      _QuickActionData(Icons.add_circle_outline, 'Add Booking', AppRoutes.bookings),
      _QuickActionData(Icons.person_add_alt_1_outlined, 'Add Member', AppRoutes.memberships),
      _QuickActionData(Icons.event_available_outlined, 'Guest Slots', AppRoutes.membershipSessions),
      _QuickActionData(Icons.groups_outlined, 'Add Guest', AppRoutes.guests),
      _QuickActionData(Icons.account_balance_wallet_outlined, 'Finance', AppRoutes.finance),
      _QuickActionData(Icons.currency_exchange, 'Refunds', AppRoutes.refunds),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.8,
      children: [
        for (final a in actions)
          _QuickAction(icon: a.icon, label: a.label, onTap: () => context.push(a.route)),
      ],
    );
  }
}

class _QuickActionData {
  const _QuickActionData(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: tokens.surface1,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: tokens.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(icon, color: tokens.primary, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({required this.label, required this.onSelect});

  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: context.tokens.borderColor),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder shown while the summary loads — never a
/// bare spinner, never a screen briefly rendered with fabricated zeros.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkelBox(width: 220, height: 28),
          const SizedBox(height: AppSpacing.sm),
          const _SkelBox(width: 160, height: 14),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, _) => const _SkelBox(width: 156, height: 116),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SkelBox(width: 140, height: 18),
          const SizedBox(height: AppSpacing.sm),
          const _SkelBox(height: 120),
          const SizedBox(height: AppSpacing.xl),
          const _SkelBox(width: 140, height: 18),
          const SizedBox(height: AppSpacing.sm),
          const _SkelBox(height: 88),
        ],
      ),
    );
  }
}

class _SkelBox extends StatelessWidget {
  const _SkelBox({this.width = double.infinity, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.tokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}