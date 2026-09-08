import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/booking.dart';
import '../../data/models/membership_session.dart';
import '../../data/models/operating_hours.dart';
import '../../data/models/payment.dart';
import '../../data/models/pricing.dart';
import '../../data/models/sport.dart';
import '../../data/models/playing_area.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../payments/payment_checkout_controller.dart';
import '../payments/payment_status_panel.dart';

const _steps = ['Court & Time', 'Guest Details', 'Review & Payment'];

String _hhmm(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

String _dateLong(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${wd[d.weekday - 1]}';
}

/// Resolves the hourly rate for a slot — port of resolvePrice() in
/// src/features/pricing/validation.ts (playing-area rule > sport rule,
/// day-type + time-window match, highest priority wins).
int? _resolvePriceMinor(List<PricingRule> rules, String facilitySportId, String? courtId, DateTime date, String hhmm) {
  bool dayMatch(String t) {
    final dow = date.weekday; // 1..7 (Mon..Sun)
    if (t == 'ALL_DAYS') return true;
    if (t == 'WEEKDAYS') return dow >= 1 && dow <= 5;
    return dow == 6 || dow == 7;
  }

  bool timeMatch(PricingRule r) {
    if (r.coversFullDay) return true;
    final s = r.startTime, e = r.endTime;
    if (s == null || e == null) return true;
    return hhmm.compareTo(s) >= 0 && hhmm.compareTo(e) < 0;
  }

  final matches = rules
      .where((r) => r.facilitySportId == facilitySportId && dayMatch(r.dayType) && timeMatch(r))
      .where((r) => r.playingAreaId == null || r.playingAreaId == courtId)
      .toList();
  if (matches.isEmpty) return null;
  int spec(PricingRule r) => (r.coversFullDay ? 0 : 2) + (r.dayType == 'ALL_DAYS' ? 0 : 1);
  matches.sort((a, b) {
    final ac = a.playingAreaId != null ? 1 : 0;
    final bc = b.playingAreaId != null ? 1 : 0;
    if (ac != bc) return bc - ac;
    if (a.priority != b.priority) return b.priority - a.priority;
    return spec(b) - spec(a);
  });
  return matches.first.amountMinor;
}

enum _CourtAvailability { pickTime, available, conflict, outsideHours, checking }

/// Full-screen multi-step Guest Booking wizard — mirrors the web
/// `guest-booking-wizard.tsx`. Pops `true` when a booking was created.
class GuestBookingScreen extends ConsumerStatefulWidget {
  const GuestBookingScreen({super.key});

  @override
  ConsumerState<GuestBookingScreen> createState() => _GuestBookingScreenState();
}

class _GuestBookingScreenState extends ConsumerState<GuestBookingScreen> {
  bool _loading = true;
  String? _loadError;

  String? _facilityId;
  String _facilityName = '';
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];
  List<PricingRule> _rules = [];

  int _step = 0;
  String? _facilitySportId;
  final Set<String> _selectedCourtIds = {};
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  bool _availabilityLoading = false;
  final Map<String, OperatingDay?> _hoursByCourt = {};
  final Map<String, List<({DateTime startTime, DateTime endTime})>> _existingByCourt = {};
  List<MembershipSessionSlot> _membershipSlots = [];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _players = TextEditingController(text: '2');
  final _notes = TextEditingController();
  String _paymentMethod = 'Cash';
  String _payMode = 'offline'; // offline | online

  bool _submitting = false;
  String? _error;
  List<Booking> _booked = [];
  Booking? _pendingBooking; // created, awaiting online payment
  CheckoutResult? _paymentState;
  bool _isPaying = false;
  bool _isCheckingAgain = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _players, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _loading = false;
          _loadError = 'Complete your facility setup before taking bookings.';
        });
        return;
      }
      final fs = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);
      final plan = await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);
      if (!mounted) return;
      final enabled = fs.where((x) => x.enabled).toList();
      setState(() {
        _facilityId = facility.id;
        _facilityName = facility.name;
        _facilitySports = enabled;
        _sports = sports;
        _areas = areas.where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled).toList();
        _rules = plan?.rules ?? const [];
        _facilitySportId = enabled.isNotEmpty ? enabled.first.id : null;
        _loading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  List<PlayingArea> get _courtsForSport => _areas.where((a) => a.facilitySportId == _facilitySportId).toList();

  String get _sportName {
    final fs = _facilitySports.where((x) => x.id == _facilitySportId).firstOrNull;
    if (fs == null) return '';
    return fs.customSportName ?? _sports.where((s) => s.id == fs.sportId).firstOrNull?.name ?? 'Sport';
  }

  double get _hours {
    if (_startTime == null || _endTime == null) return 0;
    final mins = (_endTime!.hour * 60 + _endTime!.minute) - (_startTime!.hour * 60 + _startTime!.minute);
    return mins <= 0 ? 0 : mins / 60.0;
  }

  DateTime _combine(TimeOfDay t) => DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  DateTime _parseHhMm(String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(_date.year, _date.month, _date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  int? _priceMinorFor(String courtId) {
    if (_startTime == null || _facilitySportId == null || _hours <= 0) return null;
    final t = '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}';
    return _resolvePriceMinor(_rules, _facilitySportId!, courtId, _date, t);
  }

  int? _totalMinorFor(String courtId) {
    final p = _priceMinorFor(courtId);
    return p == null ? null : (p * _hours).round();
  }

  int? get _grandTotalMinor {
    if (_selectedCourtIds.isEmpty) return null;
    var sum = 0;
    var any = false;
    for (final id in _selectedCourtIds) {
      final t = _totalMinorFor(id);
      if (t != null) {
        sum += t;
        any = true;
      }
    }
    return any ? sum : null;
  }

  Future<void> _loadAvailability() async {
    if (_facilityId == null || _selectedCourtIds.isEmpty) return;
    setState(() => _availabilityLoading = true);
    try {
      final hoursRepo = ref.read(operatingHoursRepositoryProvider);
      final dow = _date.weekday % 7;
      final facilitySchedule = await hoursRepo.getFacilitySchedule(_facilityId!);
      final dateStr =
          '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      List<MembershipSessionSlot> mSlots = const [];
      try {
        mSlots = await ref.read(membershipSessionRepositoryProvider).listSessionsForDate(_facilityId!, dateStr);
      } on AppException catch (_) {}

      for (final courtId in _selectedCourtIds) {
        final override = await hoursRepo.getPlayingAreaSchedule(courtId);
        final day = (override ?? facilitySchedule)?.days.where((d) => d.dayOfWeek == dow).firstOrNull;
        final existing = await ref.read(bookingRepositoryProvider).getBookingsForCourtOnDate(courtId, _date);
        _hoursByCourt[courtId] = day;
        _existingByCourt[courtId] = existing.map((b) => (startTime: b.startTime, endTime: b.endTime)).toList();
      }
      if (!mounted) return;
      setState(() {
        _membershipSlots = mSlots;
        _availabilityLoading = false;
      });
    } on AppException catch (_) {
      if (mounted) setState(() => _availabilityLoading = false);
    }
  }

  bool _rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) =>
      aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

  _CourtAvailability _availabilityFor(String courtId) {
    if (_startTime == null || _endTime == null || _hours <= 0) return _CourtAvailability.pickTime;
    if (_availabilityLoading) return _CourtAvailability.checking;
    final day = _hoursByCourt[courtId];
    if (day == null || day.isClosed) return _CourtAvailability.outsideHours;
    final rangeStart = _combine(_startTime!);
    final rangeEnd = _combine(_endTime!);
    if (!day.is24Hours) {
      final withinAnySlot = day.slots.any((s) {
        final open = DateTime(_date.year, _date.month, _date.day, int.parse(s.startTime.split(':')[0]), int.parse(s.startTime.split(':')[1]));
        final closeParts = s.endTime.split(':');
        var close = DateTime(_date.year, _date.month, _date.day, int.parse(closeParts[0]), int.parse(closeParts[1]));
        if (s.crossesMidnight) close = close.add(const Duration(days: 1));
        return !rangeStart.isBefore(open) && !rangeEnd.isAfter(close);
      });
      if (!withinAnySlot) return _CourtAvailability.outsideHours;
    }
    final conflicts = _existingByCourt[courtId] ?? const [];
    for (final b in conflicts) {
      if (_rangesOverlap(rangeStart, rangeEnd, b.startTime, b.endTime)) return _CourtAvailability.conflict;
    }
    for (final m in _membershipSlots.where((m) => m.courtId == courtId)) {
      final mStart = _parseHhMm(m.startTime);
      final mEnd = _parseHhMm(m.endTime);
      if (_rangesOverlap(rangeStart, rangeEnd, mStart, mEnd)) return _CourtAvailability.conflict;
    }
    return _CourtAvailability.available;
  }

  bool get _allSelectedAvailable =>
      _selectedCourtIds.isNotEmpty && _selectedCourtIds.every((id) => _availabilityFor(id) == _CourtAvailability.available);

  bool get _canNext {
    if (_step == 0) return _selectedCourtIds.isNotEmpty && _startTime != null && _endTime != null && _hours > 0 && _allSelectedAvailable;
    if (_step == 1) return _name.text.trim().length >= 2 && _phone.text.trim().length >= 6;
    return true;
  }

  Future<void> _confirm() async {
    if (_facilityId == null || _selectedCourtIds.isEmpty || _startTime == null || _endTime == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final extra = _email.text.trim().isEmpty ? '' : 'Email: ${_email.text.trim()}';
      final notes = [_notes.text.trim(), extra].where((s) => s.isNotEmpty).join(' · ');
      final startAt = _combine(_startTime!);
      final endAt = _combine(_endTime!);
      final created = <Booking>[];
      for (final courtId in _selectedCourtIds) {
        final b = await ref.read(bookingRepositoryProvider).createBooking(
              NewBookingInput(
                facilityId: _facilityId!,
                courtId: courtId,
                startTime: startAt,
                endTime: endAt,
                customerType: CustomerType.guest,
                guestName: _name.text.trim(),
                guestPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                notes: notes.isEmpty ? null : notes,
                paymentStatus: PaymentStatus.pending,
                partySize: int.tryParse(_players.text.trim()) ?? 1,
                paymentMethod: _payMode == 'online' ? 'Online (Razorpay)' : _paymentMethod,
              ),
            );
        created.add(b);
      }

      if (_payMode == 'online' && created.length == 1) {
        _pendingBooking = created.first;
        if (mounted) {
          setState(() {
            _submitting = false;
            _isPaying = true;
          });
        }
        try {
          final result = await ref.read(paymentCheckoutControllerProvider).startCheckout(
                CreatePaymentOrderInput(
                  facilityId: _facilityId!,
                  sourceType: PaymentSourceType.guestBooking,
                  bookingId: created.first.id,
                ),
                contactName: _name.text.trim(),
                contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              );
          if (!mounted) return;
          if (result is CheckoutCancelled) {
            setState(() => _paymentState = null);
          } else {
            setState(() => _paymentState = result);
            if (result is CheckoutSettled) {
              _booked = [created.first.copyWith(status: BookingStatus.confirmed, paymentStatus: PaymentStatus.paid)];
            }
          }
        } on AppException catch (e) {
          if (mounted) setState(() => _error = e.message);
        } finally {
          if (mounted) setState(() => _isPaying = false);
        }
        if (mounted && _booked.isNotEmpty) await _showConfirmedSheet();
        return;
      }

      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() => _booked = created);
        await _showConfirmedSheet();
      }
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkAgain(String paymentOrderId) async {
    setState(() => _isCheckingAgain = true);
    try {
      final result = await ref.read(paymentCheckoutControllerProvider).checkAgain(paymentOrderId);
      if (!mounted) return;
      setState(() => _paymentState = result);
      if (result is CheckoutSettled && _pendingBooking != null) {
        _booked = [_pendingBooking!.copyWith(status: BookingStatus.confirmed, paymentStatus: PaymentStatus.paid)];
      }
    } finally {
      if (mounted) setState(() => _isCheckingAgain = false);
    }
    if (mounted && _booked.isNotEmpty) await _showConfirmedSheet();
  }

  /// Slides the confirmation up from the bottom, then pops back to the list.
  Future<void> _showConfirmedSheet() async {
    if (!mounted) return;
    final courtNames = _areas
        .where((a) => _selectedCourtIds.contains(a.id))
        .map((a) => a.name)
        .join(', ');
    final paid =
        _booked.isNotEmpty && _booked.first.paymentStatus == PaymentStatus.paid;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.tokens.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _BookingConfirmedSheet(
        sport: _sportName,
        courts: courtNames.isEmpty ? '—' : courtNames,
        date: _dateLong(_date),
        time: _startTime == null || _endTime == null
            ? '—'
            : '${_hhmm(_startTime!)} – ${_hhmm(_endTime!)}',
        totalInr: _grandTotalMinor == null
            ? null
            : (_grandTotalMinor! / 100).round(),
        paid: paid,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  // ────────────────────────────────────────────────────────────── UI ──

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.surface0,
      appBar: AppBar(
        title: const Text('Guest Booking',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : _wizard(),
      ),
      bottomNavigationBar: (_loading || _loadError != null || _booked.isNotEmpty)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                decoration: BoxDecoration(
                  color: t.surface0,
                  border: Border(top: BorderSide(color: t.borderColor)),
                ),
                child: Row(
                  children: [
                    _GhostButton(
                      label: _step == 0 ? 'Cancel' : 'Back',
                      onTap: _step == 0
                          ? () => Navigator.of(context).pop()
                          : () => setState(() => _step--),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _primaryAction()),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _primaryAction() {
    if (_step < 2) {
      return AuthGradientButton(
        label: 'Next: ${_steps[_step + 1]}',
        onPressed: _canNext ? () => setState(() => _step++) : null,
      );
    }
    if (_paymentState != null) {
      return AuthGradientButton(
        label: 'Go to Bookings',
        onPressed: () => Navigator.of(context).pop(true),
      );
    }
    return AuthGradientButton(
      label: _payMode == 'online' ? 'Pay & Confirm' : 'Confirm Booking',
      loadingLabel: 'Processing…',
      isLoading: _submitting || _isPaying,
      onPressed: (_submitting || _isPaying) ? null : _confirm,
    );
  }

  Widget _wizard() {
    final t = context.tokens;
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Book a court in a few simple steps',
              style: TextStyle(fontSize: 13, color: t.textSecondary)),
          const SizedBox(height: AppSpacing.lg),
          _stepIndicator(),
          const SizedBox(height: AppSpacing.xl),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.04, 0), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                0 => _stepCourtTime(),
                1 => _stepGuest(),
                _ => _stepReviewAndPayment(),
              },
            ),
          ),
          if (_step != 2) ...[
            const SizedBox(height: AppSpacing.md),
            _summaryCard(),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  static const double _stepCircleSize = 30;

  Widget _stepIndicator() {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftDone = (i - 1) ~/ 2 < _step;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: _stepCircleSize / 2 - 1.5),
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: leftDone ? t.primary : t.surface2,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx < _step;
        final active = idx == _step;
        return SizedBox(
          width: 74,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _stepCircleSize,
                height: _stepCircleSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: (done || active)
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(t.primary, Colors.white, 0.18)!,
                            t.primary,
                          ],
                        )
                      : null,
                  color: (done || active) ? null : t.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: (done || active)
                          ? Colors.transparent
                          : t.borderColor,
                      width: 1.4),
                  boxShadow: active
                      ? AppShadows.focusGlow(t.primary)
                      : null,
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: 16, color: t.onPrimary)
                    : Text('${idx + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: active ? t.onPrimary : t.textSecondary)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 26,
                child: Text(
                  _steps[idx],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.2,
                    color: active ? t.textPrimary : t.textSecondary,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _sectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      t.violet,
                      t.violet.withValues(alpha: 0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }

  Widget _boxField({required Widget child, VoidCallback? onTap, bool active = false}) {
    final t = context.tokens;
    final box = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 13),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: active ? t.violet.withValues(alpha: 0.6) : t.borderColor),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: box,
    );
  }

  Widget _stepCourtTime() {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          title: 'Sport & Location',
          icon: Icons.stadium_outlined,
          children: [
            AppDropdown<String>(
              initialValue: _facilitySportId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sport'),
              items: _facilitySports.map((fs) {
                final s = _sports.where((x) => x.id == fs.sportId).firstOrNull;
                return DropdownMenuItem(
                    value: fs.id,
                    child: Text(fs.customSportName ?? s?.name ?? 'Sport'));
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _facilitySportId = v;
                  _selectedCourtIds.clear();
                });
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _boxField(
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16, color: t.violet),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(_facilityName,
                          style: TextStyle(color: t.textPrimary))),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _boxField(
              active: true,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked != null) {
                  setState(() => _date = picked);
                  _loadAvailability();
                }
              },
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: t.violet),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(_dateLong(_date),
                          style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w600))),
                  Icon(Icons.expand_more_rounded,
                      size: 18, color: t.textSecondary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _sectionCard(
          title: 'Select Court(s)',
          icon: Icons.grid_view_rounded,
          children: [
            Text(
              'Tap to select — pick more than one to book them together at the same time.',
              style: TextStyle(fontSize: 12, color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_courtsForSport.isEmpty)
              Text('No bookable courts for this sport.',
                  style: TextStyle(fontSize: 12, color: t.textSecondary))
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = _courtsForSport.length.clamp(1, 2);
                  final itemWidth = (constraints.maxWidth -
                          AppSpacing.sm * (cols - 1)) /
                      cols;
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _courtsForSport.map((c) {
                      final selected = _selectedCourtIds.contains(c.id);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedCourtIds.remove(c.id);
                            } else {
                              _selectedCourtIds.add(c.id);
                            }
                          });
                          _loadAvailability();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: itemWidth,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: selected
                                    ? t.violet
                                    : t.borderColor,
                                width: selected ? 1.5 : 1),
                            color: selected
                                ? t.violet.withValues(alpha: 0.14)
                                : t.surface2,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(c.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    size: 18,
                                    color: selected
                                        ? t.violet
                                        : t.textSecondary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                  c.areaType == 'INDOOR'
                                      ? 'Indoor'
                                      : 'Outdoor',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: t.textSecondary)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
        if (_selectedCourtIds.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _sectionCard(
            title: 'Select Time',
            icon: Icons.access_time_rounded,
            children: [
              Row(
                children: [
                  Expanded(
                      child: _timeField('Start Time', _startTime,
                          (t) => setState(() => _startTime = t))),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: _timeField('End Time', _endTime,
                          (t) => setState(() => _endTime = t))),
                ],
              ),
              if (_hours > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 9),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_bottom_rounded,
                          size: 14, color: t.primary),
                      const SizedBox(width: 6),
                      Text(
                          'Duration: ${_hours.toStringAsFixed(_hours == _hours.roundToDouble() ? 0 : 1)} hr',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: t.primary)),
                    ],
                  ),
                ),
              ],
              if (_startTime != null && _endTime != null && _hours <= 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('End time must be after start time.',
                    style:
                        TextStyle(fontSize: 12, color: t.destructive)),
              ],
              if (_startTime != null && _endTime != null && _hours > 0) ...[
                const SizedBox(height: AppSpacing.md),
                Text('AVAILABILITY',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: t.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                ..._selectedCourtIds.map((id) {
                  final court =
                      _areas.where((a) => a.id == id).firstOrNull;
                  final status = _availabilityFor(id);
                  final (icon, color, label) = switch (status) {
                    _CourtAvailability.available =>
                      (Icons.check_circle_rounded, t.primary, 'Available'),
                    _CourtAvailability.conflict => (
                        Icons.error_outline_rounded,
                        t.destructive,
                        'Already booked'
                      ),
                    _CourtAvailability.outsideHours => (
                        Icons.nightlight_round,
                        t.warning,
                        'Outside operating hours'
                      ),
                    _CourtAvailability.checking => (
                        Icons.hourglass_empty_rounded,
                        t.textSecondary,
                        'Checking…'
                      ),
                    _CourtAvailability.pickTime =>
                      (Icons.help_outline_rounded, t.textSecondary, '—'),
                  };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 15, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(court?.name ?? '',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700))),
                        Text(label,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: color,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _timeField(
      String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPicked) {
    final t = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? const TimeOfDay(hour: 9, minute: 0),
          initialEntryMode: TimePickerEntryMode.dial,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
        if (picked != null) {
          onPicked(picked);
          _loadAvailability();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 11),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: value != null
                  ? t.violet.withValues(alpha: 0.6)
                  : t.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: t.textSecondary),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(fontSize: 10.5, color: t.textSecondary)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value == null ? 'Select' : _hhmm(value),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: value == null ? t.textSecondary : t.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepGuest() {
    return _sectionCard(
      title: 'Guest Details',
      icon: Icons.person_outline_rounded,
      children: [
        TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Full name *')),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _phone,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Phone number *',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text('+91',
                  style: TextStyle(
                      color: context.tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration:
                const InputDecoration(labelText: 'Email (optional)')),
        const SizedBox(height: AppSpacing.md),
        TextField(
            controller: _players,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Players')),
        const SizedBox(height: AppSpacing.md),
        TextField(
            controller: _notes,
            maxLines: 2,
            decoration:
                const InputDecoration(labelText: 'Notes (optional)')),
      ],
    );
  }

  Widget _stepReviewAndPayment() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _reviewCard(),
        const SizedBox(height: AppSpacing.md),
        _stepPayment(),
      ],
    );
  }

  Widget _reviewCard() {
    final t = context.tokens;
    final selectedCourts =
        _areas.where((a) => _selectedCourtIds.contains(a.id)).toList();
    return _sectionCard(
      title: 'Review & Confirm',
      icon: Icons.fact_check_outlined,
      children: [
        _groupLabel('GUEST'),
        _kv('Name', _name.text.trim().isEmpty ? '—' : _name.text.trim()),
        _kv('Phone', _phone.text.trim().isEmpty ? '—' : _phone.text.trim()),
        if (_email.text.trim().isNotEmpty) _kv('Email', _email.text.trim()),
        _kv('Players',
            _players.text.trim().isEmpty ? '1' : _players.text.trim()),
        if (_notes.text.trim().isNotEmpty) _kv('Notes', _notes.text.trim()),
        Divider(color: t.borderColor, height: AppSpacing.lg),
        _groupLabel('BOOKING'),
        _kv('Sport', _sportName),
        _kv('Location', _facilityName),
        _kv('Date', _dateLong(_date)),
        _kv(
            'Time',
            _startTime == null || _endTime == null
                ? '—'
                : '${_hhmm(_startTime!)} – ${_hhmm(_endTime!)}'),
        _kv('Duration',
            '${_hours.toStringAsFixed(_hours == _hours.roundToDouble() ? 0 : 1)} hr'),
        Divider(color: t.borderColor, height: AppSpacing.lg),
        _groupLabel('COURTS & PRICE'),
        const SizedBox(height: AppSpacing.xs),
        ...selectedCourts.map((c) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                      child: Text(c.name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700))),
                  Text(
                    _totalMinorFor(c.id) == null
                        ? '—'
                        : Formatters.currencyInr(
                            (_totalMinorFor(c.id)! / 100).round()),
                    style: TextStyle(fontSize: 13, color: t.textSecondary),
                  ),
                ],
              ),
            )),
        const SizedBox(height: AppSpacing.sm),
        _totalBox(),
      ],
    );
  }

  Widget _totalBox() {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.primary.withValues(alpha: 0.22),
            t.primary.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Total Amount',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                    fontSize: 14)),
          ),
          Text(
            _grandTotalMinor == null
                ? '—'
                : Formatters.currencyInr((_grandTotalMinor! / 100).round()),
            style: TextStyle(
                fontWeight: FontWeight.w800, color: t.primary, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _stepPayment() {
    final t = context.tokens;
    final amount = _grandTotalMinor == null
        ? 'the amount'
        : Formatters.currencyInr((_grandTotalMinor! / 100).round());
    final multiCourt = _selectedCourtIds.length > 1;
    if (_paymentState != null) {
      return _sectionCard(
        title: 'Payment',
        icon: Icons.payments_outlined,
        children: [
          PaymentStatusPanel(
            state: _paymentState,
            settledLabel: 'Booking Confirmed',
            resourceLabel: 'booking',
            isCheckingAgain: _isCheckingAgain,
            onCheckAgain: _paymentState is CheckoutPending
                ? () => _checkAgain(
                    (_paymentState as CheckoutPending).paymentOrderId)
                : null,
            onRetry: _paymentState is CheckoutFailed
                ? () {
                    setState(() => _paymentState = null);
                    _confirm();
                  }
                : null,
          ),
        ],
      );
    }
    Widget option(String mode, String title, String subtitle,
        {bool disabled = false}) {
      final selected = _payMode == mode && !disabled;
      return InkWell(
        onTap: disabled ? null : () => setState(() => _payMode = mode),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Opacity(
          opacity: disabled ? 0.45 : 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: selected ? t.violet : t.borderColor,
                  width: selected ? 1.5 : 1),
              color: selected
                  ? t.violet.withValues(alpha: 0.10)
                  : t.surface2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? t.violet : t.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 1),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11.5, color: t.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _sectionCard(
      title: 'Payment',
      icon: Icons.payments_outlined,
      children: [
        option('offline', 'Pay at venue',
            'Collect $amount at the venue. Booking is created with payment status Pending.'),
        option(
          'online',
          'Pay online now',
          multiCourt
              ? 'Only available when booking a single court at a time.'
              : 'Collect $amount now via Razorpay (UPI / card / net banking). Confirmed as Paid once it settles.',
          disabled: multiCourt,
        ),
        if (_payMode == 'offline') ...[
          const SizedBox(height: AppSpacing.xs),
          AppDropdown<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
                labelText: 'Payment method (for your records)'),
            items: const ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Other']
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setState(() => _paymentMethod = v ?? 'Cash'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: t.destructive.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(_error!,
                style: TextStyle(color: t.destructive, fontSize: 13)),
          ),
        ],
      ],
    );
  }

  Widget _summaryCard() {
    final t = context.tokens;
    final selectedCourts =
        _areas.where((a) => _selectedCourtIds.contains(a.id)).toList();
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.receipt_long_outlined, size: 18, color: t.violet),
            const SizedBox(width: AppSpacing.sm),
            Text('Booking Summary',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary)),
          ]),
          Divider(color: t.borderColor, height: AppSpacing.lg),
          _kv('Sport', _sportName.isEmpty ? '—' : _sportName),
          _kv('Location', _facilityName),
          _kv('Court(s)',
              selectedCourts.isEmpty ? '—' : selectedCourts.map((c) => c.name).join(', ')),
          _kv('Date', _dateLong(_date)),
          _kv(
              'Time',
              _startTime == null || _endTime == null
                  ? '—'
                  : '${_hhmm(_startTime!)} – ${_hhmm(_endTime!)}'),
          _kv(
              'Duration',
              _hours <= 0
                  ? '—'
                  : '${_hours.toStringAsFixed(_hours == _hours.roundToDouble() ? 0 : 1)} hr'),
          Divider(color: t.borderColor, height: AppSpacing.lg),
          _groupLabel('PRICE DETAILS'),
          const SizedBox(height: AppSpacing.xs),
          ...selectedCourts.map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('${c.name} (per hour)',
                            style: TextStyle(
                                fontSize: 12, color: t.textSecondary))),
                    Text(
                        _priceMinorFor(c.id) == null
                            ? '—'
                            : Formatters.currencyInr(
                                (_priceMinorFor(c.id)! / 100).round()),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              )),
          const SizedBox(height: AppSpacing.sm),
          _totalBox(),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: t.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _payMode == 'online'
                        ? 'Payment is made online · Confirmed as Paid once it settles'
                        : 'Payment is to be made offline · You will pay at the venue',
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(String text) => Text(text,
      style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: context.tokens.textSecondary));

  Widget _kv(String k, String v) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 96,
              child: Text(k,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: t.textSecondary))),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Outlined pill used for the secondary (Cancel / Back) action.
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surface1,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 54,
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: t.borderColor),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: t.textPrimary)),
        ),
      ),
    );
  }
}

/// Confirmation that slides up from the bottom once a booking is created.
class _BookingConfirmedSheet extends StatelessWidget {
  const _BookingConfirmedSheet({
    required this.sport,
    required this.courts,
    required this.date,
    required this.time,
    required this.totalInr,
    required this.paid,
  });

  final String sport;
  final String courts;
  final String date;
  final String time;
  final int? totalInr;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(t.primary, Colors.white, 0.18)!,
                        t.primary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: t.primary.withValues(alpha: 0.45),
                        blurRadius: 22,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Icon(Icons.check_rounded, color: t.onPrimary, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Text('Booking confirmed',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: t.borderColor),
              ),
              child: Column(
                children: [
                  _row(context, 'Sport', sport),
                  _row(context, 'Court(s)', courts),
                  _row(context, 'Date', date),
                  _row(context, 'Time', time),
                  Divider(color: t.borderColor, height: 18),
                  _row(
                    context,
                    'Total',
                    totalInr == null
                        ? '—'
                        : Formatters.currencyInr(totalInr!),
                    strong: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              paid
                  ? 'Payment received online — nothing to collect at the venue.'
                  : 'Payment is to be collected offline at the venue.',
              style: TextStyle(fontSize: 12, color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            AuthGradientButton(
              label: 'Back to Bookings',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String k, String v, {bool strong = false}) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: TextStyle(
                  fontSize: strong ? 14 : 13,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                  color: strong ? t.textPrimary : t.textSecondary)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: strong ? 15 : 13,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                    color: strong ? t.primary : t.textPrimary)),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
