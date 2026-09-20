import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/booking.dart';
import '../../data/models/finance.dart';
import '../../data/models/guest.dart';
import '../../data/models/membership_session.dart';
import '../../data/models/operating_hours.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/pricing.dart';
import '../../data/models/refund.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/tab_pop_scope.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/booking_slot_chip.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../membership_sessions/membership_slot_card.dart';
import 'booking_slots.dart';
import 'booking_status_presentation.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../authentication/session_controller.dart';

enum _CourtAvailability { pickTime, available, conflict, outsideHours, checking }

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;

  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];
  PricingPlan? _pricingPlan;

  String? _sportFilter; // null = All Sports
  DateTime _selectedDate = DateTime.now();
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final ScrollController _dayStripController = ScrollController();

  bool _gridLoading = false;
  bool _hasLoadedGridOnce = false;
  String? _gridError;
  List<Booking> _bookings = [];
  List<MembershipSessionSlot> _membershipSlots = [];
  final Map<String, OperatingDay?> _dayByCourt = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dayStripController.dispose();
    super.dispose();
  }

  void _scrollToSelectedDay() {
    if (!_dayStripController.hasClients) return;
    const boxWidth = 68.0;
    final index = _selectedDate.day - 1;
    final offset = (index * boxWidth - 100).clamp(0.0, _dayStripController.position.maxScrollExtent);
    _dayStripController.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
          _loadError = 'Complete your facility setup before taking bookings.';
        });
        return;
      }
      final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);
      PricingPlan? pricingPlan;
      try {
        pricingPlan = await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);
      } catch (_) {
        // Pricing is a nice-to-have label here — never block the screen on it.
      }

      setState(() {
        _facilityId = facility.id;
        _facilitySports = facilitySports.where((fs) => fs.enabled).toList();
        _sports = sports;
        _areas = areas.where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled).toList();
        _pricingPlan = pricingPlan;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedDay());
      await _reloadGrid();
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      debugPrint('Bookings screen load failed: $e\n$stack');
      setState(() {
        _isLoading = false;
        _loadError = 'Unable to load bookings. Please try again.';
      });
    }
  }

  Future<void> _reloadGrid() async {
    if (_facilityId == null || _areas.isEmpty) return;
    setState(() {
      _gridLoading = true;
      _gridError = null;
    });
    try {
      final dayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final dow = dayStart.weekday % 7;

      final dateStr =
          '${dayStart.year.toString().padLeft(4, '0')}-${dayStart.month.toString().padLeft(2, '0')}-${dayStart.day.toString().padLeft(2, '0')}';

      final hoursRepo = ref.read(operatingHoursRepositoryProvider);
      final facilitySchedule = await hoursRepo.getFacilitySchedule(_facilityId!);
      final bookings = await ref.read(bookingRepositoryProvider).getBookingsForFacility(_facilityId!, dayStart, dayEnd);
      final membershipSlots = await ref
          .read(membershipSessionRepositoryProvider)
          .listSessionsForDate(_facilityId!, dateStr);

      _dayByCourt.clear();
      for (final area in _areas) {
        final override = await hoursRepo.getPlayingAreaSchedule(area.id);
        final schedule = override ?? facilitySchedule;
        _dayByCourt[area.id] = schedule?.days.where((d) => d.dayOfWeek == dow).firstOrNull;
      }

      setState(() {
        _bookings = bookings;
        _membershipSlots = membershipSlots;
        _gridLoading = false;
        _hasLoadedGridOnce = true;
      });
    } on AppException catch (e) {
      setState(() {
        _gridError = e.message;
        _gridLoading = false;
        _hasLoadedGridOnce = true;
      });
    } catch (e, stack) {
      // Never leave the grid stuck on its skeleton forever — a parse
      // failure (e.g. a row shaped differently than the model expects)
      // isn't an AppException and must still resolve the loading state.
      debugPrint('Court grid load failed: $e\n$stack');
      setState(() {
        _gridError = 'Unable to load the court schedule. Please try again.';
        _gridLoading = false;
        _hasLoadedGridOnce = true;
      });
    }
  }

  Map<String, List<Booking>> get _bookingsByCourt {
    final map = <String, List<Booking>>{};
    for (final b in _bookings) {
      if (b.status != BookingStatus.pending && b.status != BookingStatus.confirmed) continue;
      (map[b.courtId] ??= []).add(b);
    }
    return map;
  }

  List<BookingTimeSlot> _slotsFor(PlayingArea area) {
    final day = _dayByCourt[area.id];
    if (day == null) return [];
    final existing = (_bookingsByCourt[area.id] ?? []).map((b) => (startTime: b.startTime, endTime: b.endTime)).toList();
    return computeAvailableSlots(_selectedDate, day, existing);
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
  }

  void _selectDay(DateTime day) {
    setState(() => _selectedDate = day);
    _reloadGrid();
  }

  /// Every day in [_visibleMonth] — never spills into the previous/next
  /// month, so every cell in the strip is a real bookable day.
  List<DateTime> get _monthDays {
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    return List.generate(daysInMonth, (i) => DateTime(_visibleMonth.year, _visibleMonth.month, i + 1));
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MonthPickerSheet(initial: _visibleMonth),
    );
    if (picked == null) return;
    setState(() {
      _visibleMonth = picked;
      // Jump into the picked month on its 1st, or keep today's day-of-month
      // if we're picking the month we're already in.
      final today = DateTime.now();
      _selectedDate = (picked.year == today.year && picked.month == today.month)
          ? today
          : DateTime(picked.year, picked.month, 1);
    });
    _reloadGrid();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dayStripController.hasClients) _dayStripController.jumpTo(0);
      _scrollToSelectedDay();
    });
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = now;
      _visibleMonth = DateTime(now.year, now.month);
    });
    _reloadGrid();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedDay());
  }

  Future<void> _openFilterSheet() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final tokens = sheetContext.tokens;
        Widget tile(String label, String? value) {
          final selected = value == _sportFilter;
          return ListTile(
            dense: true,
            title: Text(label),
            trailing: selected ? Icon(Icons.check, color: tokens.primary) : null,
            onTap: () => Navigator.pop(sheetContext, value ?? '__all__'),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xs),
                child: Text('Filter by sport',
                    style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              tile('All sports', null),
              for (final fs in _facilitySports)
                tile(
                  fs.customSportName ?? _sports.where((s) => s.id == fs.sportId).firstOrNull?.name ?? 'Sport',
                  fs.id,
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
    if (picked == null) return; // dismissed
    setState(() => _sportFilter = picked == '__all__' ? null : picked);
  }

  Future<void> _openMembershipSlot(MembershipSessionSlot slot) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: MembershipSlotCard(facilityId: _facilityId!, slot: slot, onChanged: _reloadGrid),
        ),
      ),
    );
  }

  Future<void> _openQuickBooking(PlayingArea area, BookingTimeSlot slot) async {
    final booked = await showModalBottomSheet<Booking>(
      context: context,
      isScrollControlled: true,
      builder: (context) => QuickBookingSheet(facilityId: _facilityId!, area: area, slot: slot),
    );
    if (booked != null) _reloadGrid();
  }

  Future<void> _openBookingDetails(Booking booking, PlayingArea area) async {
    final sport = _sports.where((s) => s.id == _facilitySports.where((fs) => fs.id == area.facilitySportId).firstOrNull?.sportId).firstOrNull;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BookingDetailsSheet(
        booking: booking,
        area: area,
        sportName: sport?.name ?? 'Sport',
        facilityId: _facilityId!,
      ),
    );
    if (changed == true) _reloadGrid();
  }

  List<PlayingArea> get _visibleAreas =>
      _sportFilter == null ? _areas : _areas.where((a) => a.facilitySportId == _sportFilter).toList();

  /// What the filter chip shows — the selected sport's name, or "All
  /// sports" — so the current filter is visible without opening the sheet.
  String get _sportFilterLabel {
    if (_sportFilter == null) return 'All sports';
    final fs = _facilitySports.where((f) => f.id == _sportFilter).firstOrNull;
    if (fs == null) return 'All sports';
    return fs.customSportName ??
        _sports.where((s) => s.id == fs.sportId).firstOrNull?.name ??
        'Sport';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TabPopScope(
      tab: AppTab.courts,
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: const Text('Courts',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          if (!_isToday)
            TextButton(
              onPressed: _jumpToToday,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: const Text('Today'),
            ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: GestureDetector(
              onTap: _openFilterSheet,
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
                    Icon(Icons.tune_rounded, size: 14, color: tokens.primary),
                    const SizedBox(width: 6),
                    Text(_sportFilterLabel,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded,
                        size: 15, color: tokens.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const _BookingsSkeleton()
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, 0),
                        child: _buildWeekStrip(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(child: _buildSchedule()),
                    ],
                  ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.courts),
      ),
    );
  }

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Widget _buildWeekStrip() {
    final days = _monthDays;
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: _pickMonth,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: tokens.textSecondary),
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _ScheduleLegend(),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ScrollConfiguration(
          behavior:
              ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SizedBox(
            height: 68,
            child: ListView.separated(
              controller: _dayStripController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, index) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) {
                final day = days[i];
                final selected = _isSameDay(day, _selectedDate);
                final isToday = _isSameDay(day, DateTime.now());
                final isWeekend = day.weekday == DateTime.saturday ||
                    day.weekday == DateTime.sunday;
                final weekdayColor = selected
                    ? tokens.onAccent(tokens.primary)
                    : (isWeekend ? tokens.warning : tokens.textSecondary);
                final numberColor = selected
                    ? tokens.onAccent(tokens.primary)
                    : (isWeekend ? tokens.warning : tokens.textPrimary);
                return GestureDetector(
                  onTap: () => _selectDay(day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    width: 54,
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.accentSolid(tokens.primary)
                          : tokens.surface1,
                      border: Border.all(
                        color: selected
                            ? tokens.accentSolid(tokens.primary)
                            : (isToday
                                ? tokens.primary.withValues(alpha: 0.5)
                                : (isWeekend
                                    ? tokens.warning.withValues(alpha: 0.4)
                                    : tokens.borderColor)),
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color:
                                    tokens.primary.withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: -2,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _weekdayLabels[day.weekday - 1],
                          style: TextStyle(fontSize: 11, color: weekdayColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          day.day.toString(),
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: numberColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// A base "₹X/hr" label for a court, from the pricing plan — a
  /// court-specific rule wins over a sport-wide one.
  String? _priceLabel(PlayingArea area) {
    final plan = _pricingPlan;
    if (plan == null) return null;
    PricingRule? pick(bool Function(PricingRule) test) {
      final matches = plan.rules.where(test).toList();
      if (matches.isEmpty) return null;
      matches.sort((a, b) =>
          (a.coversFullDay ? 0 : 1).compareTo(b.coversFullDay ? 0 : 1));
      return matches.first;
    }

    final rule = pick((r) => r.playingAreaId == area.id) ??
        pick((r) =>
            r.playingAreaId == null &&
            r.facilitySportId == area.facilitySportId);
    if (rule == null) return null;
    return '₹${rule.amountRupees}/hr';
  }

  Widget _buildSchedule() {
    if (_gridLoading && !_hasLoadedGridOnce) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: _ScheduleGridSkeleton(),
      );
    }
    if (_gridError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(_gridError!,
            style: const TextStyle(color: AppColors.destructive)),
      );
    }
    final areas = _visibleAreas;
    if (areas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text('No courts configured for this sport.'),
      );
    }

    // Group courts by sport, in the facility's own sport order, then by
    // court name within each sport.
    final sportOrder = {
      for (var i = 0; i < _facilitySports.length; i++) _facilitySports[i].id: i,
    };
    final ordered = [...areas]..sort((a, b) {
        final sa = sportOrder[a.facilitySportId] ?? 999;
        final sb = sportOrder[b.facilitySportId] ?? 999;
        if (sa != sb) return sa.compareTo(sb);
        return a.name.compareTo(b.name);
      });

    final rows = ordered.map((area) {
      final fs =
          _facilitySports.where((f) => f.id == area.facilitySportId).firstOrNull;
      final sport = _sports.where((s) => s.id == fs?.sportId).firstOrNull;
      return CourtScheduleRow(
        area: area,
        sportName: fs?.customSportName ?? sport?.name ?? 'Sport',
        priceLabel: _priceLabel(area),
        day: _dayByCourt[area.id],
        bookings: (_bookingsByCourt[area.id] ?? const <Booking>[])
            .where((b) =>
                b.status == BookingStatus.pending ||
                b.status == BookingStatus.confirmed)
            .toList(),
        membershipSlots:
            _membershipSlots.where((m) => m.courtId == area.id).toList(),
        availableSlots: _slotsFor(area),
      );
    }).toList();

    return RefreshIndicator(
      onRefresh: _reloadGrid,
      child: CourtsScheduleView(
        date: _selectedDate,
        isToday: _isToday,
        rows: rows,
        loading: _gridLoading,
        onEmptyTap: (area, slot) => _openQuickBooking(area, slot),
        onBookingTap: (booking, area) => _openBookingDetails(booking, area),
        onMembershipTap: _openMembershipSlot,
      ),
    );
  }
}

/// One court's data for [CourtsScheduleView].
class CourtScheduleRow {
  CourtScheduleRow({
    required this.area,
    required this.sportName,
    required this.priceLabel,
    required this.day,
    required this.bookings,
    required this.membershipSlots,
    required this.availableSlots,
  });

  final PlayingArea area;
  final String sportName;
  final String? priceLabel;
  final OperatingDay? day;
  final List<Booking> bookings;
  final List<MembershipSessionSlot> membershipSlots;
  final List<BookingTimeSlot> availableSlots;
}

const double _pxPerMin = 2.0;

/// 12-hour clock label — "11 AM", "12 PM", "1:30 PM" — since not everyone
/// reads 24-hour time comfortably.
String _time12(DateTime t, {bool alwaysMinutes = false}) {
  final period = t.hour < 12 ? 'AM' : 'PM';
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  if (t.minute == 0 && !alwaysMinutes) return '$h12 $period';
  return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
}

/// The redesigned Courts schedule: one shared, horizontally-scrolling time
/// ruler with every court's lane locked to it, so dragging any lane scrolls
/// them all together. Bookings render as gradient blocks sized to their real
/// duration, with a live "now" line and a "+" in each free gap.
class CourtsScheduleView extends StatefulWidget {
  const CourtsScheduleView({
    super.key,
    required this.date,
    required this.isToday,
    required this.rows,
    required this.loading,
    required this.onEmptyTap,
    required this.onBookingTap,
    required this.onMembershipTap,
  });

  final DateTime date;
  final bool isToday;
  final List<CourtScheduleRow> rows;
  final bool loading;
  final void Function(PlayingArea area, BookingTimeSlot slot) onEmptyTap;
  final void Function(Booking booking, PlayingArea area) onBookingTap;
  final ValueChanged<MembershipSessionSlot> onMembershipTap;

  @override
  State<CourtsScheduleView> createState() => _CourtsScheduleViewState();
}

class _CourtsScheduleViewState extends State<CourtsScheduleView> {
  late final LinkedScrollControllerGroup _group;
  late final ScrollController _ruler;
  final Map<String, ScrollController> _lanes = {};

  @override
  void initState() {
    super.initState();
    _group = LinkedScrollControllerGroup();
    _ruler = _group.addAndGet();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRelevant());
  }

  @override
  void didUpdateWidget(covariant CourtsScheduleView old) {
    super.didUpdateWidget(old);
    // Drop controllers for courts that are no longer shown (e.g. after a
    // sport filter change) — a linked controller cannot be re-bound to a
    // different scroll view, so a stale one left in the map crashes on the
    // next rebuild.
    final liveIds = widget.rows.map((r) => r.area.id).toSet();
    _lanes.removeWhere((id, ctrl) {
      if (liveIds.contains(id)) return false;
      ctrl.dispose();
      return true;
    });
    if (!old.date.isAtSameMomentAs(widget.date)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRelevant());
    }
  }

  @override
  void dispose() {
    _ruler.dispose();
    for (final c in _lanes.values) {
      c.dispose();
    }
    super.dispose();
  }

  ScrollController _laneFor(String id) =>
      _lanes.putIfAbsent(id, () => _group.addAndGet());

  DateTime get _dayStart =>
      DateTime(widget.date.year, widget.date.month, widget.date.day);

  DateTime _hm(String hhmm) {
    final p = hhmm.split(':');
    return DateTime(widget.date.year, widget.date.month, widget.date.day,
        int.parse(p[0]), int.parse(p[1]));
  }

  (DateTime, DateTime) get _window {
    DateTime? start;
    DateTime? end;
    for (final r in widget.rows) {
      final d = r.day;
      if (d == null || d.isClosed || d.slots.isEmpty) continue;
      final s = _hm(d.slots.first.startTime);
      final e = _hm(d.slots.last.endTime);
      if (start == null || s.isBefore(start)) start = s;
      if (end == null || e.isAfter(end)) end = e;
    }
    var s = start ?? _dayStart.add(const Duration(hours: 6));
    var e = end ?? _dayStart.add(const Duration(hours: 23));
    s = s.subtract(const Duration(minutes: 30));
    e = e.add(const Duration(minutes: 30));
    if (s.isBefore(_dayStart)) s = _dayStart;
    if (!e.isAfter(s.add(const Duration(hours: 2)))) {
      e = s.add(const Duration(hours: 6));
    }
    return (s, e);
  }

  double _x(DateTime from, DateTime t) =>
      t.difference(from).inMinutes * _pxPerMin;

  void _scrollToRelevant() {
    if (!_ruler.hasClients) return;
    final (winStart, winEnd) = _window;
    final now = DateTime.now();
    final target = widget.isToday && now.isAfter(winStart) && now.isBefore(winEnd)
        ? now
        : winStart;
    final offset = (_x(winStart, target) - 60)
        .clamp(0.0, _ruler.position.maxScrollExtent);
    _ruler.animateTo(offset,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  static const _periodBands =
      <({String label, int startHour, int endHour, Color color})>[
    (label: 'TWILIGHT', startHour: 0, endHour: 6, color: AppColors.violet),
    (label: 'MORNING', startHour: 6, endHour: 12, color: AppColors.warning),
    (label: 'NOON', startHour: 12, endHour: 16, color: AppColors.primary),
    (label: 'EVENING', startHour: 16, endHour: 24, color: AppColors.electricBlue),
  ];

  Color _bandColor(String label, AppColorTokens t) {
    switch (label) {
      case 'TWILIGHT':
        return t.violet;
      case 'MORNING':
        return t.warning;
      case 'NOON':
        return t.primary;
      default:
        return t.electricBlue;
    }
  }

  (double, double) _bandRect(
    ({String label, int startHour, int endHour, Color color}) p,
    DateTime winStart,
    DateTime winEnd,
  ) {
    final bandStart = _dayStart.add(Duration(hours: p.startHour));
    final bandEnd = _dayStart.add(Duration(hours: p.endHour));
    final s = bandStart.isBefore(winStart) ? winStart : bandStart;
    final e = bandEnd.isAfter(winEnd) ? winEnd : bandEnd;
    if (!e.isAfter(s)) return (0, 0);
    return (_x(winStart, s), _x(winStart, e) - _x(winStart, s));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final (winStart, winEnd) = _window;
    final totalWidth = _x(winStart, winEnd);
    final now = DateTime.now();
    final showNow =
        widget.isToday && now.isAfter(winStart) && now.isBefore(winEnd);
    final nowX = showNow ? _x(winStart, now) : 0.0;

    final ticks = <DateTime>[];
    var t = DateTime(
        winStart.year, winStart.month, winStart.day, winStart.hour);
    if (t.isBefore(winStart)) t = t.add(const Duration(hours: 1));
    while (t.isBefore(winEnd)) {
      ticks.add(t);
      t = t.add(const Duration(hours: 1));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.loading)
          LinearProgressIndicator(
              minHeight: 2,
              color: tokens.primary,
              backgroundColor: Colors.transparent),
        SizedBox(
          height: 42,
          child: SingleChildScrollView(
            controller: _ruler,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SizedBox(
              width: totalWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── period bands ──────────────────────────────
                  SizedBox(
                    height: 18,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final p in _periodBands)
                          if (_bandRect(p, winStart, winEnd) case (
                            final l,
                            final w
                          )
                              when w > 2)
                            Positioned(
                              left: l,
                              width: w,
                              top: 0,
                              bottom: 0,
                              child: Builder(builder: (context) {
                                final bc = _bandColor(p.label, tokens);
                                return Container(
                                  alignment: Alignment.center,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: bc.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    p.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                      color: bc,
                                    ),
                                  ),
                                );
                              }),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  // ── hour labels + now pill ────────────────────
                  SizedBox(
                    height: 16,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final tk in ticks)
                          Positioned(
                            left: _x(winStart, tk),
                            child: Text(
                              _time12(tk),
                              style: TextStyle(
                                  fontSize: 10, color: tokens.textSecondary),
                            ),
                          ),
                        if (showNow)
                          Positioned(
                            left: (nowX - 26).clamp(0.0, totalWidth),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                  color: tokens.primary,
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(
                                _time12(now, alwaysMinutes: true),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.onPrimary),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          // A plain Column (not ListView.builder) so each lane's scroll view
          // is built once and keeps its linked controller for its lifetime —
          // recycling would rebind controllers and crash the linked group.
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 4, bottom: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.rows.length; i++) ...[
                  if (i == 0 || widget.rows[i].sportName != widget.rows[i - 1].sportName)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 2),
                      child: Text(
                        widget.rows[i].sportName.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  _CourtLane(
                    key: ValueKey(widget.rows[i].area.id),
                    row: widget.rows[i],
                    controller: _laneFor(widget.rows[i].area.id),
                    winStart: winStart,
                    winEnd: winEnd,
                    totalWidth: totalWidth,
                    nowX: nowX,
                    showNow: showNow,
                    isToday: widget.isToday,
                    onEmptyTap: (slot) =>
                        widget.onEmptyTap(widget.rows[i].area, slot),
                    onBookingTap: (b) =>
                        widget.onBookingTap(b, widget.rows[i].area),
                    onMembershipTap: widget.onMembershipTap,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _BlockKind { booked, unpaid, membership }

LinearGradient _blockGradient(_BlockKind k, AppColorTokens t) {
  switch (k) {
    case _BlockKind.booked:
      return LinearGradient(
        colors: [t.primary, const Color(0xFF00A76A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    case _BlockKind.unpaid:
      return const LinearGradient(
        colors: [Color(0xFFFFB020), Color(0xFF7A4A12)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    case _BlockKind.membership:
      return LinearGradient(
        colors: [t.violet, const Color(0xFF4C1D95)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  }
}

class _CourtLane extends StatelessWidget {
  const _CourtLane({
    super.key,
    required this.row,
    required this.controller,
    required this.winStart,
    required this.winEnd,
    required this.totalWidth,
    required this.nowX,
    required this.showNow,
    required this.isToday,
    required this.onEmptyTap,
    required this.onBookingTap,
    required this.onMembershipTap,
  });

  final CourtScheduleRow row;
  final ScrollController controller;
  final DateTime winStart;
  final DateTime winEnd;
  final double totalWidth;
  final double nowX;
  final bool showNow;
  final bool isToday;
  final ValueChanged<BookingTimeSlot> onEmptyTap;
  final ValueChanged<Booking> onBookingTap;
  final ValueChanged<MembershipSessionSlot> onMembershipTap;

  double _x(DateTime t) => t.difference(winStart).inMinutes * _pxPerMin;

  DateTime _hm(String hhmm) {
    final p = hhmm.split(':');
    return DateTime(winStart.year, winStart.month, winStart.day,
        int.parse(p[0]), int.parse(p[1]));
  }

  ({DateTime? open, DateTime? close}) get _openRange {
    final d = row.day;
    if (d == null || d.isClosed || d.slots.isEmpty) {
      return (open: null, close: null);
    }
    return (open: _hm(d.slots.first.startTime), close: _hm(d.slots.last.endTime));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final range = _openRange;

    BookingTimeSlot? slotAt(DateTime t) => row.availableSlots
        .where((s) =>
            !t.isBefore(s.startTime) && t.isBefore(s.endTime) && s.available)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: tokens.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(row.area.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: tokens.textPrimary)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(row.sportName,
                    style: TextStyle(
                        fontSize: 12, color: tokens.textSecondary)),
              ),
              if ((row.priceLabel ?? '').isNotEmpty)
                Text(row.priceLabel!,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: tokens.textSecondary)),
            ],
          ),
          const SizedBox(height: 5),
          ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: totalWidth,
                height: 68,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final minutes = (d.localPosition.dx / _pxPerMin).round();
                          final tapped =
                              winStart.add(Duration(minutes: minutes));
                          if (isToday && tapped.isBefore(DateTime.now())) return;
                          final s = slotAt(tapped);
                          if (s != null) onEmptyTap(s);
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.surface1,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: tokens.borderColor),
                          ),
                        ),
                      ),
                    ),
                    if (range.open != null && range.open!.isAfter(winStart))
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: _x(range.open!),
                        child: _closed(tokens),
                      ),
                    if (range.close != null && range.close!.isBefore(winEnd))
                      Positioned(
                        left: _x(range.close!),
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: _closed(tokens),
                      ),
                    if (range.open == null)
                      Positioned.fill(child: _closed(tokens)),
                    for (final b in row.bookings)
                      _block(
                        context,
                        start: b.startTime,
                        end: b.endTime,
                        kind: b.paymentStatus == PaymentStatus.pending
                            ? _BlockKind.unpaid
                            : _BlockKind.booked,
                        title: b.customerType == CustomerType.guest
                            ? (b.guestName ?? 'Guest')
                            : 'Member',
                        onTap: () => onBookingTap(b),
                      ),
                    for (final m in row.membershipSlots)
                      _block(
                        context,
                        start: _hm(m.startTime),
                        end: _hm(m.endTime),
                        kind: _BlockKind.membership,
                        title: m.batchName,
                        onTap: () => onMembershipTap(m),
                      ),
                    if (showNow)
                      Positioned(
                        left: nowX,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: tokens.primary),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _closed(AppColorTokens tokens) => Container(
        decoration: BoxDecoration(
          color: tokens.isLight
              ? tokens.surface2
              : Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      );

  Widget _block(
    BuildContext context, {
    required DateTime start,
    required DateTime end,
    required _BlockKind kind,
    required String title,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    final left = _x(start).clamp(0.0, totalWidth);
    final right = _x(end).clamp(0.0, totalWidth);
    final w = (right - left).clamp(8.0, totalWidth);
    return Positioned(
      left: left + 1.5,
      top: 5,
      bottom: 5,
      width: (w - 3).clamp(6.0, totalWidth),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            gradient: _blockGradient(kind, tokens),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 7,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              Text(
                _time12(start, alwaysMinutes: true),
                style: TextStyle(
                    fontSize: 9, color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The colour key shown top-right, above the schedule.
class _ScheduleLegend extends StatelessWidget {
  const _ScheduleLegend();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5, color: tokens.textSecondary)),
          ],
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(tokens.primary, 'Paid'),
        const SizedBox(width: 10),
        dot(const Color(0xFFFFB020), 'Unpaid'),
        const SizedBox(width: 10),
        dot(tokens.violet, 'Session'),
      ],
    );
  }
}

/// Lets an owner jump the Bookings day strip to any month — a year stepper
/// above a 12-month grid, rather than paging one week at a time.
class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _year = widget.initial.year;

  static const _monthShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _year -= 1)),
                Text('$_year', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _year += 1)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 1.8,
              ),
              itemCount: 12,
              itemBuilder: (context, i) {
                final month = i + 1;
                final selected = month == widget.initial.month && _year == widget.initial.year;
                return InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => Navigator.of(context).pop(DateTime(_year, month)),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? tokens.accentSolid(tokens.primary) : tokens.surface1,
                      border: Border.all(color: selected ? tokens.accentSolid(tokens.primary) : tokens.borderColor),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      _monthShort[i],
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected ? tokens.onAccent(tokens.primary) : tokens.textPrimary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Handles both entry points: tapping an available grid slot (court+time
/// already known — jumps straight to the customer step) and "Create
/// Booking" (starts from Sport → Court, still against the same date).
class QuickBookingSheet extends ConsumerStatefulWidget {
  const QuickBookingSheet({
    super.key,
    required this.facilityId,
    this.area,
    this.slot,
    this.facilitySports = const [],
    this.sports = const [],
    this.areas = const [],
    this.date,
    this.initialGuest,
    this.initialMember,
  });

  final String facilityId;
  final PlayingArea? area;
  final BookingTimeSlot? slot;
  final List<FacilitySport> facilitySports;
  final List<Sport> sports;
  final List<PlayingArea> areas;
  final DateTime? date;
  /// Set when opened via "Book Court" from a Guest Profile — skips search entirely.
  final GuestPlayer? initialGuest;
  /// Set when opened via "Book Court" from a Member Profile — skips member search entirely.
  final MemberSearchResult? initialMember;

  @override
  ConsumerState<QuickBookingSheet> createState() => QuickBookingSheetState();
}

class QuickBookingSheetState extends ConsumerState<QuickBookingSheet> {
  String? _facilitySportId;
  PlayingArea? _area;
  BookingTimeSlot? _slot;
  List<BookingTimeSlot> _slots = [];
  bool _slotsLoading = false;

  CustomerType _customerType = CustomerType.guest;
  GuestPlayer? _selectedGuest;
  final _guestQueryController = TextEditingController();
  List<GuestPlayer> _guestResults = [];
  Timer? _guestSearchDebounce;
  bool _showNewGuestForm = false;
  final _newGuestNameController = TextEditingController();
  final _newGuestPhoneController = TextEditingController();
  bool _isSavingGuest = false;
  final _notesController = TextEditingController();
  final _memberQueryController = TextEditingController();
  List<MemberSearchResult> _memberResults = [];
  MemberSearchResult? _selectedMember;
  Timer? _memberSearchDebounce;
  PaymentStatus _paymentStatus = PaymentStatus.pending;

  bool _isBooking = false;
  String? _error;

  bool get _isQuick => widget.area != null && widget.slot != null;

  @override
  void initState() {
    super.initState();
    _area = widget.area;
    _slot = widget.slot;
    _facilitySportId = widget.area?.facilitySportId;
    _selectedGuest = widget.initialGuest;
    _selectedMember = widget.initialMember;
    if (widget.initialMember != null) _customerType = CustomerType.member;
  }

  @override
  void dispose() {
    _guestQueryController.dispose();
    _newGuestNameController.dispose();
    _newGuestPhoneController.dispose();
    _notesController.dispose();
    _memberQueryController.dispose();
    _guestSearchDebounce?.cancel();
    _memberSearchDebounce?.cancel();
    super.dispose();
  }

  void _onGuestQueryChanged(String value) {
    _guestSearchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _guestResults = []);
      return;
    }
    _guestSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref.read(guestRepositoryProvider).searchGuests(widget.facilityId, value);
      if (mounted) setState(() => _guestResults = results);
    });
  }

  Future<void> _saveNewGuest() async {
    final nameError = Validators.name(_newGuestNameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final phoneError = Validators.optionalPhone(_newGuestPhoneController.text);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    setState(() {
      _isSavingGuest = true;
      _error = null;
    });
    try {
      final guest = await ref.read(guestRepositoryProvider).findOrCreateGuest(
        GuestInput(
          facilityId: widget.facilityId,
          name: _newGuestNameController.text.trim(),
          phone: _newGuestPhoneController.text.trim().isNotEmpty ? _newGuestPhoneController.text.trim() : null,
        ),
      );
      setState(() {
        _selectedGuest = guest;
        _showNewGuestForm = false;
      });
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSavingGuest = false);
    }
  }

  Future<void> _loadSlots() async {
    if (_area == null) return;
    setState(() {
      _slotsLoading = true;
      _slot = null;
    });
    final date = widget.date ?? DateTime.now();
    final dow = date.weekday % 7;
    final hoursRepo = ref.read(operatingHoursRepositoryProvider);
    final override = await hoursRepo.getPlayingAreaSchedule(_area!.id);
    final facilitySchedule = await hoursRepo.getFacilitySchedule(widget.facilityId);
    final schedule = override ?? facilitySchedule;
    final day = schedule?.days.where((d) => d.dayOfWeek == dow).firstOrNull;
    final existing = await ref.read(bookingRepositoryProvider).getBookingsForCourtOnDate(_area!.id, date);
    if (!mounted) return;
    setState(() {
      _slots = day != null
          ? computeAvailableSlots(date, day, existing.map((b) => (startTime: b.startTime, endTime: b.endTime)).toList())
          : [];
      _slotsLoading = false;
    });
  }

  void _onMemberQueryChanged(String value) {
    _memberSearchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _memberResults = []);
      return;
    }
    _memberSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref.read(bookingRepositoryProvider).searchMembers(widget.facilityId, value);
      if (mounted) setState(() => _memberResults = results);
    });
  }

  Future<void> _confirm() async {
    if (_area == null || _slot == null) return;
    if (_customerType == CustomerType.guest && _selectedGuest == null) {
      setState(() => _error = 'Search for and select a guest, or create a new one.');
      return;
    }
    if (_customerType == CustomerType.member && _selectedMember == null) {
      setState(() => _error = 'Search for and select a member.');
      return;
    }
    setState(() {
      _isBooking = true;
      _error = null;
    });
    try {
      final booking = await ref.read(bookingRepositoryProvider).createBooking(
        NewBookingInput(
          facilityId: widget.facilityId,
          courtId: _area!.id,
          startTime: _slot!.startTime,
          endTime: _slot!.endTime,
          customerType: _customerType,
          memberId: _customerType == CustomerType.member ? _selectedMember!.id : null,
          guestPlayerId: _customerType == CustomerType.guest ? _selectedGuest!.id : null,
          notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          paymentStatus: _paymentStatus,
        ),
      );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(booking);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  List<PlayingArea> get _courtsForSport => widget.areas.where((a) => a.facilitySportId == _facilitySportId).toList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick Booking', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                if (!_isQuick) ...[
                  AppDropdown<String>(
                    initialValue: _facilitySportId,
                    decoration: const InputDecoration(labelText: 'Sport'),
                    items: widget.facilitySports
                        .map(
                          (fs) => DropdownMenuItem(
                            value: fs.id,
                            child: Text(fs.customSportName ?? widget.sports.where((s) => s.id == fs.sportId).firstOrNull?.name ?? 'Sport'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _facilitySportId = v;
                      _area = null;
                      _slot = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdown<PlayingArea>(
                    initialValue: _area,
                    decoration: const InputDecoration(labelText: 'Court / Turf'),
                    items: _courtsForSport.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                    onChanged: _facilitySportId == null
                        ? null
                        : (v) {
                            setState(() => _area = v);
                            _loadSlots();
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else ...[
                  Text('${_area!.name} · ${Formatters.dateShort(widget.date ?? DateTime.now())}'),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (!_isQuick && _area != null) ...[
                  Text('Time', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  if (_slotsLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_slots.isEmpty)
                    const Text('No slots available.')
                  else
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: _slots.map((s) {
                        final selected = _slot?.startTime == s.startTime;
                        return BookingSlotChip(
                          label:
                              '${TimeOfDay.fromDateTime(s.startTime).format(context)} – ${TimeOfDay.fromDateTime(s.endTime).format(context)}',
                          available: s.available,
                          selected: selected,
                          onTap: () => setState(() => _slot = s),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_slot != null) ...[
                  if (_isQuick)
                    Text(
                      '${TimeOfDay.fromDateTime(_slot!.startTime).format(context)} – ${TimeOfDay.fromDateTime(_slot!.endTime).format(context)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Guest'),
                        selected: _customerType == CustomerType.guest,
                        onSelected: (_) => setState(() => _customerType = CustomerType.guest),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ChoiceChip(
                        label: const Text('Member'),
                        selected: _customerType == CustomerType.member,
                        onSelected: (_) => setState(() => _customerType = CustomerType.member),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_customerType == CustomerType.guest) ...[
                    if (_selectedGuest != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedGuest!.phone != null
                                  ? '${_selectedGuest!.name} · ${_selectedGuest!.phone}'
                                  : _selectedGuest!.name,
                            ),
                          ),
                          TextButton(onPressed: () => setState(() => _selectedGuest = null), child: const Text('Change')),
                        ],
                      )
                    else if (_showNewGuestForm) ...[
                      TextField(controller: _newGuestNameController, decoration: const InputDecoration(labelText: 'Guest name')),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _newGuestPhoneController,
                        decoration: const InputDecoration(labelText: 'Phone (optional)'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _isSavingGuest ? null : _saveNewGuest,
                            child: Text(_isSavingGuest ? 'Saving…' : 'Save Guest'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _showNewGuestForm = false),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ] else ...[
                      TextField(
                        controller: _guestQueryController,
                        decoration: const InputDecoration(labelText: 'Search by name or phone'),
                        onChanged: _onGuestQueryChanged,
                      ),
                      ..._guestResults.map(
                        (g) => ListTile(
                          dense: true,
                          title: Text(g.name),
                          subtitle: g.phone != null ? Text(g.phone!) : null,
                          onTap: () => setState(() {
                            _selectedGuest = g;
                            _guestResults = [];
                          }),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton(
                        onPressed: () => setState(() => _showNewGuestForm = true),
                        child: const Text('+ Create New Guest'),
                      ),
                    ],
                  ] else if (_selectedMember != null) ...[
                    Row(
                      children: [
                        Expanded(child: Text(_selectedMember!.fullName)),
                        TextButton(onPressed: () => setState(() => _selectedMember = null), child: const Text('Change')),
                      ],
                    ),
                  ] else ...[
                    TextField(
                      controller: _memberQueryController,
                      decoration: const InputDecoration(labelText: 'Search by name or email'),
                      onChanged: _onMemberQueryChanged,
                    ),
                    ..._memberResults.map(
                      (m) => ListTile(
                        dense: true,
                        title: Text(m.fullName),
                        subtitle: Text(m.email != null ? '${m.phone} · ${m.email}' : m.phone),
                        onTap: () => setState(() {
                          _selectedMember = m;
                          _memberResults = [];
                        }),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text('Payment', style: Theme.of(context).textTheme.titleSmall),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Paid'),
                        selected: _paymentStatus == PaymentStatus.paid,
                        onSelected: (_) => setState(() => _paymentStatus = PaymentStatus.paid),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ChoiceChip(
                        label: const Text('Pending'),
                        selected: _paymentStatus == PaymentStatus.pending,
                        onSelected: (_) => setState(() => _paymentStatus = PaymentStatus.pending),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'Notes (optional)')),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: const TextStyle(color: AppColors.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: 'Confirm Booking',
                    loadingLabel: 'Booking…',
                    isLoading: _isBooking,
                    onPressed: _confirm,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookingDetailsSheet extends ConsumerStatefulWidget {
  const _BookingDetailsSheet({
    required this.booking,
    required this.area,
    required this.sportName,
    required this.facilityId,
  });

  final Booking booking;
  final PlayingArea area;
  final String sportName;
  final String facilityId;

  @override
  ConsumerState<_BookingDetailsSheet> createState() => _BookingDetailsSheetState();
}

class _BookingDetailsSheetState extends ConsumerState<_BookingDetailsSheet> {
  late Booking _booking = widget.booking;
  bool _rescheduling = false;
  DateTime? _newDate;
  TimeOfDay? _newStartTime;
  TimeOfDay? _newEndTime;
  bool _slotsLoading = false;
  OperatingDay? _rescheduleDay;
  List<Booking> _rescheduleExisting = [];
  bool _isWorking = false;
  String? _error;
  bool _isPaying = false;

  /// Set after a cancellation that created a refund — mirrors
  /// `booking-details-dialog.tsx`'s `cancelRefundNote`. Never silently
  /// discarded: the sheet stays open to show it instead of popping
  /// immediately, the same way a no-refund cancellation still does.
  String? _cancelRefundNote;

  /// Set once a payment on this booking settles (server-confirmed) so a
  /// plain system-back/swipe-to-dismiss still tells the grid to reload,
  /// even though this sheet — mirroring `booking-details-dialog.tsx` — never
  /// auto-closes on a settled payment the way the membership sheet does.
  bool _changed = false;

  bool get _canModify => _booking.status == BookingStatus.pending || _booking.status == BookingStatus.confirmed;

  bool get _canPay => _booking.paymentStatus == PaymentStatus.pending;

  /// Asks which method the guest/member actually paid with — no Razorpay
  /// checkout here; this records a payment already collected offline (cash
  /// handed over, a UPI transfer shown on their phone, etc.), the same
  /// `record_obligation_payment` path Finance's own Record Payment screen
  /// uses, which works identically for a guest or member booking.
  Future<void> _payNow() async {
    final amount = _booking.amountMinor ?? 0;
    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentMethodSheet(amountMinor: amount),
    );
    if (method == null || !mounted) return;

    setState(() {
      _isPaying = true;
      _error = null;
    });
    try {
      await ref.read(financeRepositoryProvider).recordObligationPayment(
            sourceType: _booking.customerType == CustomerType.guest
                ? ObligationSource.guestBooking
                : ObligationSource.booking,
            sourceId: _booking.id,
            amountMinor: amount,
            method: method,
            idempotencyKey: const Uuid().v4(),
            paidOn: _isoDate(DateTime.now()),
          );
      // Re-fetch rather than assume "paid" locally — the server is the
      // source of truth for status/payment_status after the RPC runs.
      final refreshed = await ref.read(bookingRepositoryProvider).getBooking(_booking.id);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _booking = refreshed;
        _changed = true;
      });
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  Future<void> _pickRescheduleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _newDate = picked;
      _slotsLoading = true;
    });
    final dow = picked.weekday % 7;
    final hoursRepo = ref.read(operatingHoursRepositoryProvider);
    final override = await hoursRepo.getPlayingAreaSchedule(widget.area.id);
    final facilitySchedule = await hoursRepo.getFacilitySchedule(widget.facilityId);
    final schedule = override ?? facilitySchedule;
    final day = schedule?.days.where((d) => d.dayOfWeek == dow).firstOrNull;
    final existing = await ref.read(bookingRepositoryProvider).getBookingsForCourtOnDate(widget.area.id, picked);
    if (!mounted) return;
    setState(() {
      _rescheduleDay = day;
      _rescheduleExisting = existing.where((b) => b.id != _booking.id).toList();
      _slotsLoading = false;
    });
  }

  Future<void> _pickRescheduleTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _newStartTime : _newEndTime) ?? TimeOfDay.fromDateTime(_booking.startTime),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false), child: child!),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _newStartTime = picked;
      } else {
        _newEndTime = picked;
      }
    });
  }

  double get _rescheduleHours {
    if (_newStartTime == null || _newEndTime == null) return 0;
    final mins = (_newEndTime!.hour * 60 + _newEndTime!.minute) - (_newStartTime!.hour * 60 + _newStartTime!.minute);
    return mins <= 0 ? 0 : mins / 60.0;
  }

  DateTime? _combineReschedule(TimeOfDay? t) {
    if (_newDate == null || t == null) return null;
    return DateTime(_newDate!.year, _newDate!.month, _newDate!.day, t.hour, t.minute);
  }

  _CourtAvailability get _rescheduleAvailability {
    if (_newDate == null || _newStartTime == null || _newEndTime == null || _rescheduleHours <= 0) {
      return _CourtAvailability.pickTime;
    }
    if (_slotsLoading) return _CourtAvailability.checking;
    final day = _rescheduleDay;
    if (day == null || day.isClosed) return _CourtAvailability.outsideHours;
    final rangeStart = _combineReschedule(_newStartTime)!;
    final rangeEnd = _combineReschedule(_newEndTime)!;
    if (!day.is24Hours) {
      final withinAnySlot = day.slots.any((s) {
        final sp = s.startTime.split(':');
        final open = DateTime(_newDate!.year, _newDate!.month, _newDate!.day, int.parse(sp[0]), int.parse(sp[1]));
        final ep = s.endTime.split(':');
        var close = DateTime(_newDate!.year, _newDate!.month, _newDate!.day, int.parse(ep[0]), int.parse(ep[1]));
        if (s.crossesMidnight) close = close.add(const Duration(days: 1));
        return !rangeStart.isBefore(open) && !rangeEnd.isAfter(close);
      });
      if (!withinAnySlot) return _CourtAvailability.outsideHours;
    }
    for (final b in _rescheduleExisting) {
      if (rangeStart.isBefore(b.endTime) && b.startTime.isBefore(rangeEnd)) return _CourtAvailability.conflict;
    }
    return _CourtAvailability.available;
  }

  Future<void> _confirmReschedule() async {
    final start = _combineReschedule(_newStartTime);
    final end = _combineReschedule(_newEndTime);
    if (start == null || end == null || _rescheduleAvailability != _CourtAvailability.available) return;
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      await ref.read(bookingRepositoryProvider).rescheduleBooking(
        RescheduleBookingInput(
          bookingId: _booking.id,
          courtId: widget.area.id,
          startTime: start,
          endTime: end,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Cancel Booking?',
      message: 'This booking will be cancelled. This cannot be undone.',
      confirmLabel: 'Cancel Booking',
      cancelLabel: 'Keep Booking',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() {
      _isWorking = true;
      _error = null;
      _cancelRefundNote = null;
    });
    try {
      // Server-side (cancel-booking Edge Function): cancels the booking,
      // releases court availability, and — if the booking was paid —
      // requests and submits a cancellation-policy-derived refund, all in
      // one call (spec §8/§13). Never a plain client-side status update.
      final result = await ref.read(refundRepositoryProvider).cancelBooking(
        CancelBookingInput(bookingId: _booking.id, reason: 'Owner Request'),
      );
      if (!mounted) return;
      setState(() {
        _booking = result.booking;
        _changed = true;
      });
      final refund = result.refund;
      if (refund != null) {
        setState(() {
          _cancelRefundNote = refund.status == RefundStatus.failed
              ? 'The booking was cancelled, but the refund could not be submitted. Please retry from Refunds.'
              : 'Refund requested — it will show as processed once Razorpay confirms it.';
        });
      } else if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Booking Details',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: context.tokens.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            // Who + when — visible in both modes, so the person you're
            // rescheduling never scrolls out of view while you pick a new time.
            Builder(builder: (context) {
              final tokens = context.tokens;
              final phone = b.customerType == CustomerType.guest ? b.guestPhone : null;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: tokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: tokens.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: tokens.accentFill(tokens.primary), shape: BoxShape.circle),
                          child: Icon(
                            b.customerType == CustomerType.guest ? Icons.person_outline_rounded : Icons.badge_outlined,
                            size: 16,
                            color: tokens.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            b.customerType == CustomerType.guest ? (b.guestName ?? 'Guest') : 'Member',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                          decoration: BoxDecoration(
                            color: tokens.surface1,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: tokens.borderColor),
                          ),
                          child: Text('${widget.sportName} · ${widget.area.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: tokens.textSecondary)),
                        ),
                      ],
                    ),
                    if (phone != null && phone.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      InkWell(
                        onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.call_rounded, size: 14, color: tokens.textSecondary),
                            const SizedBox(width: 5),
                            Text(phone,
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: tokens.textPrimary)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: tokens.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          '${Formatters.dateShort(b.startTime)} · '
                          '${TimeOfDay.fromDateTime(b.startTime).format(context)} – ${TimeOfDay.fromDateTime(b.endTime).format(context)}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tokens.textPrimary),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppSpacing.md),
            if (!_rescheduling) ...[
              _DetailField(
                label: 'Amount',
                value: b.amountMinor != null ? Formatters.currencyInr((b.amountMinor! / 100).round()) : '—',
              ),
              Row(
                children: [
                  Expanded(
                    child: _DetailBadgeField(
                      label: 'Payment',
                      badgeLabel: paymentStatusLabel(b.paymentStatus),
                      tone: paymentStatusTone(b.paymentStatus),
                    ),
                  ),
                  Expanded(
                    child: _DetailBadgeField(
                      label: 'Status',
                      badgeLabel: bookingStatusLabel(b.status),
                      tone: bookingStatusTone(b.status),
                    ),
                  ),
                ],
              ),
              if (_cancelRefundNote != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_cancelRefundNote!, style: AppTypography.secondary(context)),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.destructive)),
              ],
              if (_canPay) ...[
                const SizedBox(height: AppSpacing.lg),
                _GlowButton(
                  color: context.tokens.primary,
                  child: PrimaryButton(
                    label: 'Pay Now',
                    loadingLabel: 'Recording payment…',
                    isLoading: _isPaying,
                    onPressed: _isWorking ? null : _payNow,
                  ),
                ),
              ],
              if (_canModify) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isWorking ? null : () => setState(() => _rescheduling = true),
                        child: const Text('Reschedule'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _GlowButton(
                        color: context.tokens.destructive,
                        child: DangerButton(
                          label: _isWorking ? 'Cancelling…' : 'Cancel Booking',
                          isLoading: _isWorking,
                          onPressed: _isWorking ? null : _cancel,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              Text('New date', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
              const SizedBox(height: 6),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: _pickRescheduleDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.mutedBackground,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: _newDate != null ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.muted),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _newDate == null ? 'Select a date' : Formatters.dateShort(_newDate!),
                          style: TextStyle(fontWeight: FontWeight.w600, color: _newDate == null ? AppColors.muted : AppColors.foreground),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
              if (_newDate != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text('New time', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _rescheduleTimeField('Start Time', _newStartTime, () => _pickRescheduleTime(true))),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _rescheduleTimeField('End Time', _newEndTime, () => _pickRescheduleTime(false))),
                  ],
                ),
                if (_rescheduleHours > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Builder(builder: (context) {
                    final status = _rescheduleAvailability;
                    final (icon, color, label) = switch (status) {
                      _CourtAvailability.available => (Icons.check_circle, AppColors.success, 'Available — ${_rescheduleHours.toStringAsFixed(_rescheduleHours == _rescheduleHours.roundToDouble() ? 0 : 1)} hr'),
                      _CourtAvailability.conflict => (Icons.error_outline, AppColors.destructive, 'This court is already booked then'),
                      _CourtAvailability.outsideHours => (Icons.nightlight_round, AppColors.warning, 'Outside operating hours'),
                      _CourtAvailability.checking => (Icons.hourglass_empty, AppColors.muted, 'Checking…'),
                      _CourtAvailability.pickTime => (Icons.help_outline, AppColors.muted, '—'),
                    };
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Row(
                        children: [
                          Icon(icon, size: 15, color: color),
                          const SizedBox(width: 6),
                          Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color))),
                        ],
                      ),
                    );
                  }),
                ] else if (_newStartTime != null && _newEndTime != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('End time must be after start time.', style: TextStyle(fontSize: 12, color: AppColors.destructive)),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.destructive)),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isWorking ? null : () => setState(() => _rescheduling = false),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Confirm New Time',
                      loadingLabel: 'Saving…',
                      isLoading: _isWorking,
                      onPressed: _rescheduleAvailability == _CourtAvailability.available ? _confirmReschedule : null,
                    ),
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

  Widget _rescheduleTimeField(String label, TimeOfDay? value, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.mutedBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: value != null ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: AppColors.muted),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value == null ? 'Select' : value.format(context),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: value == null ? AppColors.muted : AppColors.foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _DetailBadgeField extends StatelessWidget {
  const _DetailBadgeField({required this.label, required this.badgeLabel, required this.tone});

  final String label;
  final String badgeLabel;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context)),
          const SizedBox(height: 4),
          StatusBadge(label: badgeLabel, tone: tone),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Wraps a pill-shaped CTA in the same coloured drop-shadow "glow" the
/// dashboard/maintenance FABs use, so a full-width button in a sheet reads
/// with the same premium weight rather than the flat default elevation-0
/// button style.
class _GlowButton extends StatelessWidget {
  const _GlowButton({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 20,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

const _paymentMethodOptions = <(String label, IconData icon)>[
  ('Cash', Icons.payments_rounded),
  ('UPI', Icons.bolt_rounded),
  ('Card', Icons.credit_card_rounded),
  ('Bank Transfer', Icons.account_balance_rounded),
];

Color _paymentMethodAccent(AppColorTokens tokens, String method) => switch (method) {
      'Cash' => tokens.success,
      'UPI' => tokens.warning,
      'Card' => tokens.violet,
      'Bank Transfer' => tokens.electricBlue,
      _ => tokens.primary,
    };

/// "How was this paid?" — replaces the Razorpay checkout on the Booking
/// Details sheet's Pay Now button: the owner picks the method the guest/
/// member actually paid with (cash handed over, a UPI transfer shown on
/// their phone, …) and the booking is recorded as paid against that method,
/// rather than opening a payment gateway for money already collected.
class _PaymentMethodSheet extends StatefulWidget {
  const _PaymentMethodSheet({required this.amountMinor});

  final int amountMinor;

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  String _selected = 'Cash';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
        decoration: BoxDecoration(
          color: tokens.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(color: tokens.borderColor, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            Text('How was this paid?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
            const SizedBox(height: 4),
            Text(
              '${Formatters.currencyInr((widget.amountMinor / 100).round())} · mark this booking as paid',
              style: AppTypography.secondary(context),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final opt in _paymentMethodOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PaymentMethodTile(
                  label: opt.$1,
                  icon: opt.$2,
                  accent: _paymentMethodAccent(tokens, opt.$1),
                  selected: _selected == opt.$1,
                  onTap: () => setState(() => _selected = opt.$1),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            _GlowButton(
              color: tokens.primary,
              child: PrimaryButton(
                label: 'Mark as Paid',
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.label,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? tokens.accentFill(accent) : tokens.surface2,
          border: Border.all(color: selected ? tokens.accentEdge(accent) : tokens.borderColor, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tokens.accentSolid(accent), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: tokens.onAccent(accent)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: tokens.textPrimary)),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? accent : tokens.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder for the Courts page — the date strip and
/// the per-court schedule lanes below it — shown while the initial facility
/// data loads. Never a bare spinner.
class _BookingsSkeleton extends StatelessWidget {
  const _BookingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeleton(width: 160, height: 18),
          SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 68,
            child: Row(
              children: [
                AppSkeleton(width: 54, height: 68, radius: AppRadius.lg),
                SizedBox(width: AppSpacing.sm),
                AppSkeleton(width: 54, height: 68, radius: AppRadius.lg),
                SizedBox(width: AppSpacing.sm),
                AppSkeleton(width: 54, height: 68, radius: AppRadius.lg),
                SizedBox(width: AppSpacing.sm),
                AppSkeleton(width: 54, height: 68, radius: AppRadius.lg),
                SizedBox(width: AppSpacing.sm),
                AppSkeleton(width: 54, height: 68, radius: AppRadius.lg),
                SizedBox(width: AppSpacing.sm),
                AppSkeleton(width: 54, height: 68, radius: AppRadius.lg),
                SizedBox(width: AppSpacing.sm),
                AppSkeleton(width: 54, height: 68, radius: AppRadius.lg),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Expanded(child: SingleChildScrollView(child: _ScheduleGridSkeleton())),
        ],
      ),
    );
  }
}

/// The per-court "lane" grid alone — reused both for the full-page gate
/// above and for the schedule region's own refresh spinner, so the shape
/// never changes between the two loading moments.
class _ScheduleGridSkeleton extends StatelessWidget {
  const _ScheduleGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSkeleton(width: 90, height: 12),
        SizedBox(height: AppSpacing.sm),
        _LaneSkeleton(),
        SizedBox(height: AppSpacing.md),
        _LaneSkeleton(),
        SizedBox(height: AppSpacing.md),
        _LaneSkeleton(),
        SizedBox(height: AppSpacing.md),
        AppSkeleton(width: 90, height: 12),
        SizedBox(height: AppSpacing.sm),
        _LaneSkeleton(),
      ],
    );
  }
}

class _LaneSkeleton extends StatelessWidget {
  const _LaneSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSkeleton(width: 110, height: 13),
        SizedBox(height: 5),
        AppSkeleton(height: 68, radius: AppRadius.md),
      ],
    );
  }
}