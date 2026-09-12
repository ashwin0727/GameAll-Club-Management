import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import '../../data/models/finance.dart'
    show
        LedgerEntry,
        LedgerPage,
        ListLedgerInput,
        FinanceDateRange,
        FinanceDateRangePreset,
        PaymentObligation,
        PendingPaymentsPage,
        PendingPaymentsSummary,
        ListPendingPaymentsInput;
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/tab_pop_scope.dart';
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
  List<LedgerEntry> _recent = const [];
  List<PaymentObligation> _needs = const [];
  int _needsCount = 0;

  /// What is actually owed right now, in rupees. The dashboard summary's
  /// `payments.pendingInr` only sums `payments` rows with status 'created',
  /// so an unpaid booking that never got a payments row reads as ₹0 even
  /// while it shows up under "Needs you". `get_pending_payments_summary` is
  /// the same source the Pending Payments screen uses, so the two agree.
  int? _outstandingInr;

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
      // Best-effort extras — the dashboard renders fine without them.
      try {
        final fin = ref.read(financeRepositoryProvider);
        final extras = await Future.wait([
          fin.listLedger(ListLedgerInput(
            facilityId: _facilityId!,
            dateRange: const FinanceDateRange(
                preset: FinanceDateRangePreset.thisMonth),
            limit: 5,
          )),
          fin.listPendingPayments(ListPendingPaymentsInput(
            facilityId: _facilityId!,
            limit: 3,
          )),
          fin.getPendingPaymentsSummary(_facilityId!),
        ]);
        if (!mounted) return;
        setState(() {
          _recent = (extras[0] as LedgerPage).entries;
          final pp = extras[1] as PendingPaymentsPage;
          _needs = pp.obligations;
          _needsCount = pp.totalCount;
          _outstandingInr =
              ((extras[2] as PendingPaymentsSummary).outstandingMinor / 100)
                  .round();
        });
      } catch (_) {}
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

  static String _dashDate(DateTime d) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${wd[d.weekday - 1]}, ${d.day} ${_monthNamesShort[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;

    return TabPopScope(
      tab: AppTab.today,
      child: Scaffold(
      backgroundColor: context.tokens.surface0,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.lg,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo-icon.png', width: 24, height: 24),
            const SizedBox(width: 6),
            const Text('GameAll',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.refunds),
            icon: Icon(Icons.notifications_none_rounded,
                color: context.tokens.textSecondary),
          ),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.lg),
            child: InkWell(
              onTap: () => context.push(AppRoutes.profile),
              customBorder: const CircleBorder(),
              child: AppAvatar(
                name: user?.fullName ?? '?',
                imageUrl: session.facility?.logoUrl,
                size: AppAvatarSize.medium,
              ),
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
                    dateLabel: _dashDate(DateTime.now()),
                    recent: _recent,
                    needs: _needs,
                    needsCount: _needsCount,
                    outstandingInr: _outstandingInr,
                    facilitySlug:
                        ref.watch(sessionControllerProvider).facility?.slug,
                    selectedSportId: _selectedSportId,
                    preset: _preset,
                    onOpenFilter: _openCommonFilter,
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
      bottomNavigationBar: const AppBottomNav(current: AppTab.today),
      ),
    );
  }

  /// One sheet for both filters — sport and period together.
  Future<void> _openCommonFilter() async {
    final tokens = context.tokens;
    var sport = _selectedSportId;
    var preset = _preset;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: tokens.textSecondary)),
              );
          Widget pill(String text, bool selected, VoidCallback onTap) =>
              GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? tokens.primary : tokens.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                        color: selected ? tokens.primary : tokens.borderColor,
                        width: selected ? 1.5 : 1),
                  ),
                  child: Text(text,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? tokens.onAccent(tokens.primary)
                              : tokens.textPrimary)),
                ),
              );

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Filter',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                      if (sport != null || preset != DateRangePreset.today)
                        TextButton(
                          onPressed: () => setSheet(() {
                            sport = null;
                            preset = DateRangePreset.today;
                          }),
                          child: const Text('Reset'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  label('SPORT'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      pill('All Sports', sport == null,
                          () => setSheet(() => sport = null)),
                      for (final s in _summary!.sports)
                        pill(s.sportName, sport == s.facilitySportId,
                            () => setSheet(() => sport = s.facilitySportId)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  label('PERIOD'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final e in _presetLabels.entries)
                        pill(e.value, preset == e.key,
                            () => setSheet(() => preset = e.key)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      if (sport != _selectedSportId || preset != _preset) {
                        setState(() {
                          _selectedSportId = sport;
                          _preset = preset;
                        });
                        _load();
                      }
                    },
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          );
        },
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

/// The redesigned Owner Home — a live snapshot at the top, then what needs
/// action, then the deeper reports. Every panel is backed by real data
/// (dashboard summary, finance ledger, pending obligations, today's schedule).
class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.summary,
    required this.greeting,
    required this.firstName,
    required this.dateLabel,
    required this.recent,
    required this.needs,
    required this.needsCount,
    required this.outstandingInr,
    required this.facilitySlug,
    required this.selectedSportId,
    required this.preset,
    required this.onOpenFilter,
    required this.revenueMonthOffset,
    required this.onPickRevenueMonth,
  });

  final DashboardSummary summary;
  final String greeting;
  final String? firstName;
  final String dateLabel;
  final List<LedgerEntry> recent;
  final List<PaymentObligation> needs;
  final int needsCount;

  /// Authoritative "owed right now", or null while the finance RPC is still
  /// in flight / failed — the summary's own figure is the fallback.
  final int? outstandingInr;
  final String? facilitySlug;
  final String? selectedSportId;
  final DateRangePreset preset;
  final VoidCallback onOpenFilter;
  final int revenueMonthOffset;
  final VoidCallback onPickRevenueMonth;

  bool get _isToday => preset == DateRangePreset.today;

  String get _scopeLabel {
    final sport = selectedSportId == null
        ? 'All sports'
        : summary.sports
                .where((s) => s.facilitySportId == selectedSportId)
                .map((s) => s.sportName)
                .firstOrNull ??
            'All sports';
    return '$sport  ·  ${_presetLabels[preset]}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    // ── derive "on court now" + free courts from today's schedule ──
    final tl = summary.scheduleTimeline;
    // Group courts by sport in first-seen order (Badminton, then Pickleball,
    // then the rest) so the live strip matches the Courts page grouping.
    final courtsBySport = <String, List<ScheduleCourtRow>>{};
    for (final c in tl.courts) {
      (courtsBySport[c.sportName] ??= []).add(c);
    }
    final orderedCourts = [for (final g in courtsBySport.values) ...g];
    final liveBlocks = <(_ScheduleCourtRef, ScheduleBlock)>[];
    for (final c in tl.courts) {
      for (final b in c.blocks) {
        if (b.startMinute <= nowMin && nowMin < b.endMinute) {
          liveBlocks.add((_ScheduleCourtRef(c.courtId, c.courtName, c.sportName), b));
        }
      }
    }
    final busyCourtIds = liveBlocks.map((e) => e.$1.id).toSet();
    final totalCourts = tl.courts.length;
    final busyCount = busyCourtIds.length;

    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── facility + date  ·····  filter chip (corner) ──────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary.facilityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: tokens.textSecondary)),
                  const SizedBox(height: 1),
                  Text(dateLabel,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.15)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: onOpenFilter,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 7),
                decoration: BoxDecoration(
                  color: tokens.surface1,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: tokens.borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 13, color: tokens.primary),
                    const SizedBox(width: 5),
                    Text(_scopeLabel,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 1),
                    Icon(Icons.expand_more_rounded,
                        size: 14, color: tokens.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // ── LIVE NOW ──────────────────────────────────────────────
        _LiveNowCard(
          isToday: _isToday,
          now: now,
          busyCount: busyCount,
          totalCourts: totalCourts,
          courts: orderedCourts,
          busyCourtIds: busyCourtIds,
          liveBlocks: liveBlocks,
        ),
        const SizedBox(height: AppSpacing.md),

        // ── quick top actions ─────────────────────────────────────
        _TopActionsRow(slug: facilitySlug),
        const SizedBox(height: AppSpacing.md),

        // ── money row ─────────────────────────────────────────────
        _MoneyRow(
          collectedInr: summary.kpis.revenueInr.value.round(),
          collectedChange: summary.kpis.revenueInr.changePercent,
          periodLabel: _presetLabels[preset]!,
          toCollectInr: outstandingInr ?? summary.payments.pendingInr,
          bookings: summary.kpis.guestBookings.value.round(),
          weekPoints: summary.revenueOverview.points,
        ),

        if (summary.memberships.expiringSoon > 0) ...[
          const SizedBox(height: AppSpacing.md),
          _ExpiringMembershipCard(count: summary.memberships.expiringSoon),
        ],

        // ── NEEDS YOU ─────────────────────────────────────────────
        if (needs.isNotEmpty || summary.attentionItems.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _NeedsYouSection(
              obligations: needs,
              count: needsCount,
              attention: summary.attentionItems),
        ],

        // ── ON COURT NOW ──────────────────────────────────────────
        if (_isToday && liveBlocks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _OnCourtNowSection(liveBlocks: liveBlocks, nowMin: nowMin),
        ],

        // ── EMPTY SLOTS ───────────────────────────────────────────
        if (_isToday) ...[
          Builder(builder: (context) {
            final gaps = _findGaps(tl, nowMin);
            if (gaps.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: _EmptySlotsSection(gaps: gaps),
            );
          }),
        ],

        // ── MEMBERS ───────────────────────────────────────────────
        const SizedBox(height: AppSpacing.xl),
        _MembersCard(
          memberships: summary.memberships,
          monthlyRevenueInr: _membershipRevenue(),
          monthLabel: summary.revenueOverview.monthLabel,
        ),

        // ── THIS WEEK ─────────────────────────────────────────────
        const SizedBox(height: AppSpacing.xl),
        _DashSection(
          title: 'This week',
          child: _WeekBarsCard(points: summary.revenueOverview.points),
        ),

        // ── RECENT ACTIVITY ───────────────────────────────────────
        if (recent.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _RecentActivitySection(entries: recent),
        ],

        // ── REVENUE ───────────────────────────────────────────────
        const SizedBox(height: AppSpacing.xl),
        _DashSection(
          title: 'Revenue Overview',
          trailing: _SelectorChip(
              label: revenueMonthLabel(revenueMonthOffset),
              onSelect: onPickRevenueMonth,
              dense: true),
          child: _RevenueOverviewCard(overview: summary.revenueOverview),
        ),

        // ── SHARE LINK ────────────────────────────────────────────
        const SizedBox(height: AppSpacing.xl),
        _ShareLinkCard(slug: facilitySlug),

        // ── QUICK ACTIONS (kept, restyled) ────────────────────────
        const SizedBox(height: AppSpacing.xl),
        _DashSection(
          title: 'Quick Actions',
          child: const _QuickActionGrid(),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  int _membershipRevenue() {
    for (final s in summary.revenueOverview.breakdown) {
      if (s.key == RevenueBreakdownKey.memberships && !s.unavailable) {
        return s.amountInr;
      }
    }
    return 0;
  }

  /// Free windows on each court from now until close — the biggest per court.
  static List<_SlotGap> _findGaps(ScheduleTimeline tl, int nowMin) {
    final closeMin = tl.endHour * 60;
    final startMin = math.max(nowMin, tl.startHour * 60);
    if (closeMin - startMin < 30) return const [];
    final gaps = <_SlotGap>[];
    for (final c in tl.courts) {
      final busy = c.blocks
          .where((b) => b.endMinute > startMin)
          .map((b) => (b.startMinute, b.endMinute))
          .toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
      var cursor = startMin;
      for (final (bs, be) in busy) {
        if (bs - cursor >= 45) {
          gaps.add(_SlotGap(c.courtName, c.sportName, cursor, bs));
        }
        cursor = math.max(cursor, be);
      }
      if (closeMin - cursor >= 45) {
        gaps.add(_SlotGap(c.courtName, c.sportName, cursor, closeMin));
      }
    }
    gaps.sort((a, b) => a.startMin.compareTo(b.startMin));
    return gaps.take(3).toList();
  }
}

class _ScheduleCourtRef {
  const _ScheduleCourtRef(this.id, this.name, this.sport);
  final String id;
  final String name;
  final String sport;
}

class _SlotGap {
  const _SlotGap(this.court, this.sport, this.startMin, this.endMin);
  final String court;
  final String sport;
  final int startMin;
  final int endMin;
  int get minutes => endMin - startMin;
}

String _time12(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60) % 24;
  final m = minuteOfDay % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final mm = m.toString().padLeft(2, '0');
  return '$h12:$mm ${h < 12 ? 'AM' : 'PM'}';
}

/// A short court code from the sport + court number, e.g. Badminton Court 1
/// → "BC1", Cricket Turf 2 → "CC2". Falls back to initials when there's no
/// number to key off.
String _courtCode(String sport, String court) {
  final sp = sport.trim().isEmpty ? 'C' : sport.trim()[0].toUpperCase();
  final num = RegExp(r'(\d+)').firstMatch(court)?.group(1);
  if (num != null) return '${sp}C$num';
  final rest =
      court.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  return rest.isEmpty ? '${sp}C' : '$sp${rest.substring(0, rest.length.clamp(0, 2))}';
}

Color _blockTypeColor(BuildContext context, ScheduleBlockType t) {
  final tokens = context.tokens;
  switch (t) {
    case ScheduleBlockType.member:
      return tokens.primary;
    case ScheduleBlockType.guest:
      return tokens.electricBlue;
    case ScheduleBlockType.session:
      return tokens.violet;
  }
}

// ───────────────────────────────────────────────────── LIVE NOW ──

class _LiveNowCard extends StatelessWidget {
  const _LiveNowCard({
    required this.isToday,
    required this.now,
    required this.busyCount,
    required this.totalCourts,
    required this.courts,
    required this.busyCourtIds,
    required this.liveBlocks,
  });

  final bool isToday;
  final DateTime now;
  final int busyCount;
  final int totalCourts;
  final List<ScheduleCourtRow> courts;
  final Set<String> busyCourtIds;
  final List<(_ScheduleCourtRef, ScheduleBlock)> liveBlocks;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Solid green "hero" card — reads like a filled button, not a tint.
    final card = tokens.accentSolid(tokens.primary);
    final onCard = tokens.onAccent(card);
    final onCardDim = onCard.withValues(alpha: 0.72);
    final nowMin = now.hour * 60 + now.minute;
    final pct = totalCourts == 0 ? 0 : (busyCount / totalCourts * 100).round();
    // Courts whose current booking wraps up within 15 minutes.
    final endingSoon = <String>{
      for (final (c, b) in liveBlocks)
        if (b.endMinute - nowMin <= 15) c.id,
    };

    // "Next free": a court open right now, else the soonest to free up.
    String? nextFreeLabel;
    final freeCourt =
        courts.where((c) => !busyCourtIds.contains(c.courtId)).firstOrNull;
    if (freeCourt != null) {
      nextFreeLabel = '${freeCourt.courtName} free now';
    } else if (liveBlocks.isNotEmpty) {
      final soonest =
          liveBlocks.reduce((a, b) => a.$2.endMinute <= b.$2.endMinute ? a : b);
      nextFreeLabel =
          '${soonest.$1.name} at ${_time12(soonest.$2.endMinute)}';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(AppRoutes.bookings),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isToday)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: onCard.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: onCard, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text('Live now',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: onCard)),
                    ],
                  ),
                )
              else
                Text('Snapshot',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: onCardDim)),
              const Spacer(),
              Text(
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, color: onCardDim)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$busyCount',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: onCard)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('of $totalCourts courts busy',
                    style: TextStyle(fontSize: 13, color: onCardDim)),
              ),
              Text('$pct%',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: onCard)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final c in courts.take(9)) ...[
                Expanded(
                  child: Column(
                    children: [
                      Builder(builder: (context) {
                        final busy = busyCourtIds.contains(c.courtId);
                        final soon = endingSoon.contains(c.courtId);
                        final fill = !busy
                            ? onCard.withValues(alpha: 0.14)
                            : soon
                                ? tokens.accentSolid(tokens.warning)
                                : onCard;
                        return Container(
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(6),
                            border: busy
                                ? null
                                : Border.all(
                                    color: onCard.withValues(alpha: 0.4)),
                          ),
                          child: Icon(
                            !busy
                                ? Icons.check_rounded
                                : soon
                                    ? Icons.timelapse_rounded
                                    : Icons.lock_rounded,
                            size: 11,
                            color: busy
                                ? (soon
                                    ? tokens.onAccent(tokens.warning)
                                    : card)
                                : onCard,
                          ),
                        );
                      }),
                      const SizedBox(height: 3),
                      Text(
                        _courtCode(c.sportName, c.courtName),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: onCardDim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ],
          ),
          if (liveBlocks.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final (c, b) in liveBlocks.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: onCard, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          '${_courtCode(c.sport, c.name)} · ${b.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: onCard)),
                    ),
                    Text('ends ${_time12(b.endMinute)}',
                        style: TextStyle(fontSize: 10.5, color: onCardDim)),
                  ],
                ),
              ),
          ],
          if (nextFreeLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: onCard.withValues(alpha: 0.2)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text('Next free · $nextFreeLabel',
                      style: TextStyle(fontSize: 12, color: onCardDim)),
                ),
                GestureDetector(
                  onTap: () => context.push(AppRoutes.bookings),
                  child: Text('Fill it',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: onCard)),
                ),
              ],
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }

}

// ─────────────────────────────────────────────── TOP ACTIONS ──

class _TopActionsRow extends StatelessWidget {
  const _TopActionsRow({required this.slug});
  final String? slug;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    void copyLink() {
      final link = (slug == null || slug!.isEmpty)
          ? 'https://gameall.in'
          : 'https://gameall.in/join/$slug';
      Clipboard.setData(ClipboardData(text: link));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Booking link copied')));
    }

    final actions = <(IconData, String, VoidCallback)>[
      (Icons.add_rounded, 'Book', () => context.push(AppRoutes.bookings)),
      (
        Icons.account_balance_wallet_outlined,
        'Collect',
        () => context.push(AppRoutes.financePendingPayments)
      ),
      (Icons.link_rounded, 'Share link', copyLink),
      (
        Icons.event_busy_outlined,
        'Block',
        () => context.push(AppRoutes.bookings)
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Material(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: actions[i].$3,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: tokens.borderColor),
                  ),
                  child: Column(
                    children: [
                      Icon(actions[i].$1, size: 19, color: tokens.primary),
                      const SizedBox(height: 5),
                      Text(actions[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────── MONEY ROW ──

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.collectedInr,
    required this.collectedChange,
    required this.periodLabel,
    required this.toCollectInr,
    required this.bookings,
    required this.weekPoints,
  });

  final int collectedInr;
  final double? collectedChange;
  final String periodLabel;
  final int toCollectInr;
  final int bookings;
  final List<RevenueTrendPoint> weekPoints;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final last7 = _trailingWeek(weekPoints);
    final todayKey = _dayKeyOf(DateTime.now());
    final maxV = last7.isEmpty
        ? 1
        : last7.map((p) => p.amountInr).reduce(math.max).clamp(1, 1 << 30);
    final up = (collectedChange ?? 0) >= 0;
    final changeColor = up ? tokens.success : tokens.destructive;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Material(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push(AppRoutes.finance),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: tokens.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Collected · $periodLabel',
                          style: TextStyle(
                              fontSize: 11, color: tokens.textSecondary)),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(Formatters.currencyInr(collectedInr),
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w800)),
                      ),
                      if (collectedChange != null &&
                          collectedChange!.abs() >= 0.05) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                                up
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 11,
                                color: changeColor),
                            Text(
                                '${collectedChange!.abs().toStringAsFixed(0)}% vs last',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: changeColor)),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        height: 34,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < last7.length; i++) ...[
                              if (i > 0) const SizedBox(width: 4),
                              Expanded(
                                child: Builder(builder: (context) {
                                  final isToday = last7[i].date == todayKey;
                                  final v = last7[i].amountInr;
                                  // Value drives BOTH height and colour, so a
                                  // quiet day is legible as a quiet day even
                                  // when every bar is squashed to the floor.
                                  final f =
                                      (v / maxV).clamp(0.0, 1.0).toDouble();
                                  // Opaque ends — blended onto the card, not
                                  // alpha'd over it, so bars read as a solid
                                  // dark green rather than a wash.
                                  final low = Color.alphaBlend(
                                      tokens.primary.withValues(alpha: 0.30),
                                      tokens.surface1);
                                  // A zero day is never highlighted, today
                                  // included — a bright, tall bar on ₹0 reads
                                  // as "best day of the week" and is a lie.
                                  final lit = isToday && v > 0;
                                  return Container(
                                    height: (f * 34).clamp(4, 34).toDouble(),
                                    decoration: BoxDecoration(
                                      color: lit
                                          ? tokens.primary
                                          : Color.lerp(low, tokens.primary, f),
                                      borderRadius: BorderRadius.circular(3),
                                      boxShadow: lit
                                          ? [
                                              BoxShadow(
                                                color: tokens.primary
                                                    .withValues(alpha: 0.45),
                                                blurRadius: 8,
                                                spreadRadius: -2,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () =>
                          context.push(AppRoutes.financePendingPayments),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          color: tokens.accentSolid(tokens.warning),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                  Formatters.currencyInr(toCollectInr),
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: tokens.onAccent(tokens.warning))),
                            ),
                            Text('to collect',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: tokens.onAccent(tokens.warning)
                                        .withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: tokens.surface1,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: tokens.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$bookings',
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        Text('bookings',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: tokens.textSecondary)),
                      ],
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

// ─────────────────────────────────────────────────── NEEDS YOU ──

class _NeedsYouSection extends StatelessWidget {
  const _NeedsYouSection({
    required this.obligations,
    required this.count,
    required this.attention,
  });

  final List<PaymentObligation> obligations;
  final int count;
  final List<AttentionItem> attention;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final n = count > 0 ? count : (obligations.length + attention.length);
    return _DashSection(
      title: 'Needs you',
      trailing: Text('$n item${n == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
      child: Column(
        children: [
          for (final o in obligations)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _needRow(
                context,
                icon: Icons.schedule_rounded,
                tone: tokens.warning,
                title: "${o.customerName} hasn't paid",
                subtitle: o.description,
                trailing: Formatters.currencyInr(
                    (o.outstandingMinor / 100).round()),
                trailingTone: tokens.warning,
                onTap: () => context.push(AppRoutes.financePendingPayments),
              ),
            ),
          for (final a in attention.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _needRow(
                context,
                icon: Icons.error_outline_rounded,
                tone: tokens.violet,
                title: a.message,
                subtitle: null,
                trailing: null,
                trailingTone: null,
                onTap: () => context.push(AppRoutes.memberships),
              ),
            ),
        ],
      ),
    );
  }

  Widget _needRow(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String title,
    required String? subtitle,
    required String? trailing,
    required Color? trailingTone,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
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
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 17, color: tone),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: tokens.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(trailing,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: trailingTone ?? tokens.textPrimary)),
              ] else
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────── ON COURT NOW ──

class _OnCourtNowSection extends StatelessWidget {
  const _OnCourtNowSection(
      {required this.liveBlocks, required this.nowMin});

  final List<(_ScheduleCourtRef, ScheduleBlock)> liveBlocks;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return _DashSection(
      title: 'On court now',
      trailing: GestureDetector(
        onTap: () => context.push(AppRoutes.bookings),
        child: Text('See timeline',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tokens.primary)),
      ),
      child: Column(
        children: [
          for (final (c, b) in liveBlocks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: tokens.surface1,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: tokens.borderColor),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_courtCode(c.sport, c.name),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _blockTypeColor(context, b.type))),
                          Text(c.sport,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 9,
                                  color: tokens.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: ((nowMin - b.startMinute) /
                                      math.max(1, b.endMinute - b.startMinute))
                                  .clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: tokens.surface2,
                              valueColor: AlwaysStoppedAnimation(
                                  _blockTypeColor(context, b.type)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text('ends ${_time12(b.endMinute)}',
                        style: TextStyle(
                            fontSize: 11, color: tokens.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────── EMPTY SLOTS ──

class _EmptySlotsSection extends StatelessWidget {
  const _EmptySlotsSection({required this.gaps});
  final List<_SlotGap> gaps;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return _DashSection(
      title: 'Free slots left today',
      child: SizedBox(
        height: 118,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: gaps.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, i) {
            final g = gaps[i];
            return Material(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push(AppRoutes.bookings),
                child: Container(
              width: 130,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: tokens.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_time12(g.startMin),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${g.court} · ${g.sport}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5, color: tokens.textSecondary)),
                  Text('${g.minutes} min free',
                      style: TextStyle(
                          fontSize: 10.5, color: tokens.textSecondary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.bookings),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: tokens.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Fill',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: tokens.onAccent(tokens.primary))),
                    ),
                  ),
                ],
              ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────── MEMBERS ──

class _MembersCard extends StatelessWidget {
  const _MembersCard({
    required this.memberships,
    required this.monthlyRevenueInr,
    required this.monthLabel,
  });

  final MembershipSummary memberships;
  final int monthlyRevenueInr;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final onC = tokens.onAccent(tokens.violet);
    final onCDim = onC.withValues(alpha: 0.75);
    return _DashSection(
      title: 'Members',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(AppRoutes.memberships),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              color: tokens.accentSolid(tokens.violet),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Membership revenue · $monthLabel',
                    style: TextStyle(fontSize: 12, color: onCDim)),
                const SizedBox(height: 4),
                Text(Formatters.currencyInr(monthlyRevenueInr),
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: onC)),
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: onC.withValues(alpha: 0.2)),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _stat(context, '${memberships.active}', 'active', onC),
                    const SizedBox(width: AppSpacing.xl),
                    _stat(context, '${memberships.expiringSoon}', 'expiring',
                        onC),
                    const SizedBox(width: AppSpacing.xl),
                    _stat(context, '+${memberships.newThisMonth}', 'new', onC),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: c)),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: context.tokens
                    .onAccent(context.tokens.violet)
                    .withValues(alpha: 0.75))),
      ],
    );
  }
}

/// 'YYYY-MM-DD' — matches the key `buildRevenueTrend` writes.
String _dayKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The seven days ENDING TODAY out of a month-long trend series.
///
/// `buildRevenueTrend` zero-fills one point per calendar day across the
/// whole selected month, so the tail of that list is the end of the month
/// — days that have not happened yet. `sublist(length - 7)` therefore plots
/// seven future zeroes and hides everything actually collected, which is
/// why the chart read as flat while today showed real revenue. Anchor the
/// window on today instead, falling back to the end of the series when an
/// earlier month is selected and today is not in it.
List<RevenueTrendPoint> _trailingWeek(List<RevenueTrendPoint> points) {
  if (points.length <= 7) return points;
  final todayKey = _dayKeyOf(DateTime.now());
  var end = points.lastIndexWhere((p) => p.date.compareTo(todayKey) <= 0);
  if (end < 0) end = points.length - 1;
  return points.sublist((end - 6).clamp(0, points.length - 1), end + 1);
}

// ─────────────────────────────────────────────────── THIS WEEK ──

class _WeekBarsCard extends StatelessWidget {
  const _WeekBarsCard({required this.points});
  final List<RevenueTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final last7 = _trailingWeek(points);
    if (last7.isEmpty) {
      return _card(context, const SizedBox(height: 40));
    }
    final maxV =
        last7.map((p) => p.amountInr).reduce(math.max).clamp(1, 1 << 30);
    final avg = last7.map((p) => p.amountInr).reduce((a, b) => a + b) ~/
        last7.length;
    const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    // Match by date, not position — for a past month today isn't in range.
    final todayIdx =
        last7.indexWhere((p) => p.date == _dayKeyOf(DateTime.now()));

    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text('avg ${_RevenueOverviewCard._compactInr(avg)}',
                style: TextStyle(fontSize: 11, color: tokens.textSecondary)),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 74,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < last7.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Builder(builder: (context) {
                          final v = last7[i].amountInr;
                          final f = (v / maxV).clamp(0.0, 1.0).toDouble();
                          // Same rule as the Collected sparkline: the bar's
                          // depth of green tracks the amount, so the week
                          // reads at a glance even before you parse heights.
                          final low = Color.alphaBlend(
                              tokens.primary.withValues(alpha: 0.30),
                              tokens.surface1);
                          final lit = i == todayIdx && v > 0;
                          return Container(
                            height: (f * 58).clamp(4, 58).toDouble(),
                            decoration: BoxDecoration(
                              color: lit
                                  ? tokens.primary
                                  : Color.lerp(low, tokens.primary, f),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: lit
                                  ? [
                                      BoxShadow(
                                        color: tokens.primary
                                            .withValues(alpha: 0.45),
                                        blurRadius: 10,
                                        spreadRadius: -2,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                        const SizedBox(height: 5),
                        Text(
                          wd[_weekdayOf(last7[i].date)],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i == todayIdx
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: i == todayIdx
                                ? tokens.primary
                                : tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _weekdayOf(String iso) {
    final p = iso.split('-');
    final d = DateTime(
        int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    return d.weekday - 1; // 0..6, Mon..Sun
  }

  Widget _card(BuildContext context, Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.tokens.borderColor),
        ),
        child: child,
      );
}

// ─────────────────────────────────────────────── RECENT ACTIVITY ──

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({required this.entries});
  final List<LedgerEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return _DashSection(
      title: 'Recent activity',
      trailing: GestureDetector(
        onTap: () => context.push(AppRoutes.financeTransactions),
        child: Text('See all',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tokens.primary)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: tokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.borderColor),
        ),
        child: Column(
          children: [
            for (final e in entries.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Text(
                      '${e.occurredAt.hour.toString().padLeft(2, '0')}:${e.occurredAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 11, color: tokens.textSecondary),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: _dot(context, e),
                            shape: BoxShape.circle)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(e.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${e.isIncome ? '+' : '−'}${Formatters.currencyInr((e.amountMinor / 100).round())}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: e.isIncome
                              ? tokens.success
                              : tokens.destructive),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _dot(BuildContext context, LedgerEntry e) {
    final tokens = context.tokens;
    if (!e.isIncome) return tokens.destructive;
    if (e.sourceType.contains('MEMBERSHIP')) return tokens.violet;
    return tokens.success;
  }
}

// ─────────────────────────────────────────────────── SHARE LINK ──

class _ShareLinkCard extends StatelessWidget {
  const _ShareLinkCard({required this.slug});
  final String? slug;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final onC = tokens.onAccent(tokens.violet);
    final display = (slug == null || slug!.isEmpty)
        ? 'gameall.in'
        : 'gameall.in/join/$slug';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: tokens.accentSolid(tokens.violet),
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
                Text('Share your booking link',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: onC)),
                Text(display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: onC.withValues(alpha: 0.75))),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'https://$display'));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                    const SnackBar(content: Text('Link copied')));
            },
            style: TextButton.styleFrom(foregroundColor: onC),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}

/// A titled section with an optional trailing control and consistent spacing.
class _DashSection extends StatelessWidget {
  const _DashSection(
      {required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 15,
              decoration: BoxDecoration(
                color: context.tokens.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.tokens.textPrimary)),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
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
    final onC = tokens.onAccent(tokens.warning);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(AppRoutes.memberships),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            color: tokens.accentSolid(tokens.warning),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: onC.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.card_membership_rounded,
                    color: onC, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count membership${count == 1 ? '' : 's'} expiring soon',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: onC),
                    ),
                    const SizedBox(height: 1),
                    Text('Tap to review and renew',
                        style: TextStyle(
                            color: onC.withValues(alpha: 0.75),
                            fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: onC.withValues(alpha: 0.75)),
            ],
          ),
        ),
      ),
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
  });

  final Widget Function(double progress) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return builder(1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => builder(t.clamp(0, 1)),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(AppRoutes.finance),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
            color: tokens.surface1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total revenue · ${overview.monthLabel}',
                  style:
                      TextStyle(color: tokens.textSecondary, fontSize: 12)),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(Formatters.currencyInr(overview.totalInr),
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary)),
                  const SizedBox(width: AppSpacing.sm),
                  if (change != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: changeColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              up
                                  ? Icons.arrow_upward_rounded
                                  : (down
                                      ? Icons.arrow_downward_rounded
                                      : Icons.remove_rounded),
                              size: 11,
                              color: changeColor),
                          Text('${change.abs().toStringAsFixed(0)}%',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: changeColor)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    height: 140,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final t in yTicks)
                          Text(_compactInr(t),
                              style: TextStyle(
                                  fontSize: 8.5,
                                  color: tokens.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 140,
                      child: _AnimatedProgress(
                        duration: const Duration(milliseconds: 900),
                        builder: (t) => CustomPaint(
                          painter: _RevenueChartPainter(
                            values: values,
                            niceMax: niceMax,
                            lineColor: tokens.primary,
                            gridColor:
                                tokens.borderColor.withValues(alpha: 0.35),
                            progress: t,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: Stack(
                  children: [
                    const SizedBox(height: 14, width: double.infinity),
                    for (final idx in xTickIdx)
                      Align(
                        alignment: Alignment(
                            n <= 1 ? 0 : (idx / (n - 1)) * 2 - 1, 0),
                        child: Text(_dayLabel(overview.points[idx].date),
                            style: TextStyle(
                                fontSize: 8.5,
                                color: tokens.textSecondary)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: tokens.borderColor),
              const SizedBox(height: AppSpacing.md),
              Text('Where it came from',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: tokens.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              _RevenueBreakdownChart(
                  segments: overview.breakdown, total: overview.totalInr),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Open Finance',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: tokens.primary)),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: tokens.primary),
                ],
              ),
            ],
          ),
        ),
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
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.unavailable ? '—' : Formatters.currencyInr(s.amountInr),
                        style: TextStyle(fontSize: 10, color: tokens.textSecondary),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${total > 0 ? ((s.amountInr / total) * 100).round() : 0}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
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


/// Real, currently-navigable destinations as a 3-up grid of vertical tiles —
/// each with its own accent, so the row scans quickly (spec §"Owner Home").
class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final actions = <_QuickActionData>[
      _QuickActionData(Icons.add_rounded, 'Add booking', AppRoutes.bookings,
          tokens.primary),
      _QuickActionData(Icons.person_add_alt_1_rounded, 'Add member',
          AppRoutes.memberships, tokens.violet),
      _QuickActionData(Icons.event_available_rounded, 'Guest booking',
          AppRoutes.guestBookings, tokens.electricBlue),
      _QuickActionData(Icons.groups_rounded, 'Add guest', AppRoutes.guests,
          tokens.warning),
      _QuickActionData(Icons.account_balance_wallet_rounded, 'Finance',
          AppRoutes.finance, tokens.primary),
      _QuickActionData(Icons.currency_exchange_rounded, 'Refunds',
          AppRoutes.refunds, tokens.destructive),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.42,
      children: [
        for (final a in actions)
          _QuickAction(
              icon: a.icon,
              label: a.label,
              accent: a.accent,
              onTap: () => context.push(a.route)),
      ],
    );
  }
}

class _QuickActionData {
  const _QuickActionData(this.icon, this.label, this.route, this.accent);
  final IconData icon;
  final String label;
  final String route;
  final Color accent;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final onC = tokens.onAccent(accent);
    return Semantics(
      button: true,
      label: label.replaceAll('\n', ' '),
      child: Material(
        color: tokens.accentSolid(accent),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              color: tokens.accentSolid(accent),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: onC.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, color: onC, size: 17),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: onC,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({
    required this.label,
    required this.onSelect,
    this.dense = false,
  });

  final String label;
  final VoidCallback onSelect;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        child: Container(
          constraints: BoxConstraints(minHeight: dense ? 32 : 42),
          padding: EdgeInsets.symmetric(
              horizontal: dense ? AppSpacing.md : AppSpacing.lg),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.borderColor),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: dense ? 12 : 13,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded,
                  size: dense ? 16 : 18, color: tokens.textSecondary),
            ],
          ),
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