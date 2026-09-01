import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/booking.dart';
import '../../data/models/membership_session.dart';
import '../../data/models/payment.dart';
import '../../data/models/pricing.dart';
import '../../data/models/sport.dart';
import '../../data/models/playing_area.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../payments/payment_checkout_controller.dart';
import '../payments/payment_status_panel.dart';
import 'booking_slots.dart';

const _steps = ['Select Court & Time', 'Guest Details', 'Review & Confirm', 'Payment'];

String _hhmm(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
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
  // Specificity: a windowed rule beats a full-day one, and a day-scoped
  // rule (WEEKDAYS/WEEKENDS) beats ALL_DAYS — so an "all days ₹300" base
  // with a "weekends 6-9pm ₹350" override resolves to ₹350 in that window.
  int spec(PricingRule r) => (r.coversFullDay ? 0 : 2) + (r.dayType == 'ALL_DAYS' ? 0 : 1);
  matches.sort((a, b) {
    // court-specific beats sport-level, then priority, then specificity.
    final ac = a.playingAreaId != null ? 1 : 0;
    final bc = b.playingAreaId != null ? 1 : 0;
    if (ac != bc) return bc - ac;
    if (a.priority != b.priority) return b.priority - a.priority;
    return spec(b) - spec(a);
  });
  return matches.first.amountMinor;
}

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
  String? _courtId;
  DateTime _date = DateTime.now();
  BookingTimeSlot? _slot;
  List<BookingTimeSlot> _slots = [];
  List<MembershipSessionSlot> _membershipSlots = [];
  bool _slotsLoading = false;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _players = TextEditingController(text: '2');
  final _notes = TextEditingController();
  String _paymentMethod = 'Cash';
  String _payMode = 'offline'; // offline | online

  bool _submitting = false;
  String? _error;
  Booking? _booked;
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
  PlayingArea? get _court => _areas.where((a) => a.id == _courtId).firstOrNull;

  String get _sportName {
    final fs = _facilitySports.where((x) => x.id == _facilitySportId).firstOrNull;
    if (fs == null) return '';
    return fs.customSportName ?? _sports.where((s) => s.id == fs.sportId).firstOrNull?.name ?? 'Sport';
  }

  double get _hours => _slot == null ? 0 : _slot!.endTime.difference(_slot!.startTime).inMinutes / 60.0;

  int? get _priceMinor {
    final slot = _slot;
    if (slot == null || _facilitySportId == null) return null;
    final t = '${slot.startTime.hour.toString().padLeft(2, '0')}:${slot.startTime.minute.toString().padLeft(2, '0')}';
    return _resolvePriceMinor(_rules, _facilitySportId!, _courtId, _date, t);
  }

  int? get _totalMinor => _priceMinor == null ? null : (_priceMinor! * _hours).round();

  Future<void> _loadSlots() async {
    final courtId = _courtId;
    if (_facilityId == null || courtId == null) {
      setState(() => _slots = []);
      return;
    }
    setState(() {
      _slotsLoading = true;
      _slot = null;
    });
    try {
      final dow = _date.weekday % 7;
      final hoursRepo = ref.read(operatingHoursRepositoryProvider);
      final override = await hoursRepo.getPlayingAreaSchedule(courtId);
      final facilitySchedule = await hoursRepo.getFacilitySchedule(_facilityId!);
      final day = (override ?? facilitySchedule)?.days.where((d) => d.dayOfWeek == dow).firstOrNull;
      final existing = await ref.read(bookingRepositoryProvider).getBookingsForCourtOnDate(courtId, _date);
      final dateStr =
          '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      List<MembershipSessionSlot> mSlots = const [];
      try {
        mSlots = await ref.read(membershipSessionRepositoryProvider).listSessionsForDate(_facilityId!, dateStr);
      } on AppException catch (_) {}
      if (!mounted) return;
      setState(() {
        _slots = day == null
            ? []
            : computeAvailableSlots(_date, day, existing.map((b) => (startTime: b.startTime, endTime: b.endTime)).toList());
        _membershipSlots = mSlots.where((m) => m.courtId == courtId).toList();
        _slotsLoading = false;
      });
    } on AppException catch (_) {
      if (mounted) {
        setState(() {
          _slots = [];
          _membershipSlots = [];
          _slotsLoading = false;
        });
      }
    }
  }

  bool get _canNext {
    if (_step == 0) return _courtId != null && _slot != null;
    if (_step == 1) return _name.text.trim().length >= 2 && _phone.text.trim().length >= 6;
    return true;
  }

  Future<void> _confirm() async {
    final slot = _slot;
    if (_facilityId == null || _courtId == null || slot == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final extra = _email.text.trim().isEmpty ? '' : 'Email: ${_email.text.trim()}';
      final notes = [_notes.text.trim(), extra].where((s) => s.isNotEmpty).join(' · ');
      final b = await ref.read(bookingRepositoryProvider).createBooking(
            NewBookingInput(
              facilityId: _facilityId!,
              courtId: _courtId!,
              startTime: slot.startTime,
              endTime: slot.endTime,
              customerType: CustomerType.guest,
              guestName: _name.text.trim(),
              guestPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              notes: notes.isEmpty ? null : notes,
              paymentStatus: PaymentStatus.pending,
              partySize: int.tryParse(_players.text.trim()) ?? 1,
              paymentMethod: _payMode == 'online' ? 'Online (Razorpay)' : _paymentMethod,
            ),
          );

      if (_payMode == 'online') {
        _pendingBooking = b;
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
                  bookingId: b.id,
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
              _booked = b.copyWith(status: BookingStatus.confirmed, paymentStatus: PaymentStatus.paid);
            }
          }
        } on AppException catch (e) {
          if (mounted) setState(() => _error = e.message);
        } finally {
          if (mounted) setState(() => _isPaying = false);
        }
        return;
      }

      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _booked = b);
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
        _booked = _pendingBooking!.copyWith(status: BookingStatus.confirmed, paymentStatus: PaymentStatus.paid);
      }
    } finally {
      if (mounted) setState(() => _isCheckingAgain = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guest Booking')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : _booked != null
                    ? _success()
                    : _wizard(),
      ),
      bottomNavigationBar: (_loading || _loadError != null || _booked != null)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _step == 0 ? () => Navigator.of(context).pop() : () => setState(() => _step--),
                        child: Text(_step == 0 ? 'Cancel' : 'Back'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _step < 3
                          ? FilledButton(
                              onPressed: _canNext ? () => setState(() => _step++) : null,
                              child: Text('Next: ${_steps[_step + 1]}', overflow: TextOverflow.ellipsis),
                            )
                          : _paymentState != null
                              ? OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Go to Bookings'),
                                )
                              : FilledButton(
                                  onPressed: (_submitting || _isPaying) ? null : _confirm,
                                  child: Text(
                                    (_submitting || _isPaying)
                                        ? 'Processing…'
                                        : _payMode == 'online'
                                            ? 'Pay & Confirm'
                                            : 'Confirm Booking',
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _success() {
    return Center(
      child: ResponsivePage(
        scrollable: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text('Booking confirmed', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$_sportName · ${_court?.name} · ${_dateLong(_date)}\n${_hhmm(_booked!.startTime)} – ${_hhmm(_booked!.endTime)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _booked!.paymentStatus == PaymentStatus.paid
                  ? 'Payment received online. Nothing to collect at the venue.'
                  : 'Payment is to be collected offline at the venue.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Back to Bookings', onPressed: () => Navigator.of(context).pop(true)),
          ],
        ),
      ),
    );
  }

  Widget _wizard() {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Book your favorite court in a few simple steps',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          const SizedBox(height: AppSpacing.md),
          _stepIndicator(),
          const SizedBox(height: AppSpacing.lg),
          if (_step == 0) _stepCourtTime(),
          if (_step == 1) _stepGuest(),
          if (_step == 2) _stepReview(),
          if (_step == 3) _stepPayment(),
          const SizedBox(height: AppSpacing.lg),
          _summaryCard(),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _stepIndicator() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: List.generate(_steps.length, (i) {
        final done = i < _step;
        final active = i == _step;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: done
                  ? AppColors.success
                  : active
                      ? AppColors.primary
                      : AppColors.border,
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : Text('${i + 1}', style: TextStyle(fontSize: 11, color: active ? AppColors.onPrimary : AppColors.muted)),
            ),
            const SizedBox(width: 4),
            Text(_steps[i],
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active ? AppColors.foreground : AppColors.muted,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    )),
          ],
        );
      }),
    );
  }

  Widget _stepCourtTime() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dropdownRow(),
          const SizedBox(height: AppSpacing.md),
          Text('Select Court', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (_courtsForSport.isEmpty)
            Text('No bookable courts for this sport.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted))
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _courtsForSport.map((c) {
                final active = _courtId == c.id;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _courtId = c.id;
                      _slot = null;
                    });
                    _loadSlots();
                  },
                  child: Container(
                    width: 110,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: active ? AppColors.primary : AppColors.border, width: active ? 2 : 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            gradient: const LinearGradient(colors: [Color(0xFF064E3B), Color(0xFF047857)]),
                          ),
                          child: active
                              ? const Icon(Icons.check_circle, color: Colors.white, size: 18)
                              : const Text('COURT', style: TextStyle(fontSize: 9, color: Color(0xFFA7F3D0))),
                        ),
                        const SizedBox(height: 4),
                        Text(c.name, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                        Text(c.areaType == 'INDOOR' ? 'Indoor' : 'Outdoor',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          if (_courtId != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Select Time Slot', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (_slotsLoading)
              const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator()))
            else if (_slots.isEmpty)
              Text('No slots available on this date.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted))
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _slots.map((s) {
                  final active = _slot?.startTime == s.startTime;
                  final blocked = findMembershipSlot(_courtId!, s, _membershipSlots) != null;
                  final bookable = s.available && !blocked;
                  return GestureDetector(
                    onTap: bookable ? () => setState(() => _slot = s) : null,
                    child: Container(
                      width: 100,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: active ? AppColors.primary : AppColors.border),
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : bookable
                                ? null
                                : AppColors.mutedBackground,
                      ),
                      child: Column(
                        children: [
                          Text(_hhmm(s.startTime), style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            blocked
                                ? 'Blocked'
                                : s.available
                                    ? 'Available'
                                    : 'Booked',
                            style: TextStyle(
                              fontSize: 11,
                              color: active
                                  ? AppColors.primary
                                  : blocked
                                      ? AppColors.warning
                                      : s.available
                                          ? AppColors.success
                                          : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
          if (_slot != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Selected: ${_dateLong(_date)} · ${_hhmm(_slot!.startTime)} – ${_hhmm(_slot!.endTime)}'
                      ' (${_hours.toStringAsFixed(_hours == _hours.roundToDouble() ? 0 : 1)} hr)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdownRow() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _facilitySportId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Sport'),
          items: _facilitySports.map((fs) {
            final s = _sports.where((x) => x.id == fs.sportId).firstOrNull;
            return DropdownMenuItem(value: fs.id, child: Text(fs.customSportName ?? s?.name ?? 'Sport'));
          }).toList(),
          onChanged: (v) {
            setState(() {
              _facilitySportId = v;
              _courtId = null;
              _slot = null;
              _slots = [];
            });
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Location'),
          child: Text(_facilityName),
        ),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 90)),
            );
            if (picked != null) {
              setState(() {
                _date = picked;
                _slot = null;
              });
              if (_courtId != null) _loadSlots();
            }
          },
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
            child: Text(_dateLong(_date)),
          ),
        ),
      ],
    );
  }

  Widget _stepGuest() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Guest Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Full Name *'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _phone,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone Number *'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _players,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Players'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
        ],
      ),
    );
  }

  Widget _stepReview() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review & Confirm', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _kv('Guest', '${_name.text.trim()}${_phone.text.trim().isEmpty ? '' : ' · ${_phone.text.trim()}'}'),
          if (_email.text.trim().isNotEmpty) _kv('Email', _email.text.trim()),
          _kv('Sport', _sportName),
          _kv('Location', _facilityName),
          _kv('Court', _court?.name ?? '—'),
          _kv('Date', _dateLong(_date)),
          _kv('Time', _slot == null ? '—' : '${_hhmm(_slot!.startTime)} – ${_hhmm(_slot!.endTime)}'),
          _kv('Duration', '${_hours.toStringAsFixed(_hours == _hours.roundToDouble() ? 0 : 1)} hr'),
          _kv('Players', _players.text.trim().isEmpty ? '1' : _players.text.trim()),
          if (_notes.text.trim().isNotEmpty) _kv('Notes', _notes.text.trim()),
          _kv('Total', _totalMinor == null ? '—' : Formatters.currencyInr((_totalMinor! / 100).round())),
        ],
      ),
    );
  }

  Widget _stepPayment() {
    final amount = _totalMinor == null ? 'the amount' : Formatters.currencyInr((_totalMinor! / 100).round());
    if (_paymentState != null) {
      return AppCard(
        child: PaymentStatusPanel(
          state: _paymentState,
          settledLabel: 'Booking Confirmed',
          resourceLabel: 'booking',
          isCheckingAgain: _isCheckingAgain,
          onCheckAgain: _paymentState is CheckoutPending
              ? () => _checkAgain((_paymentState as CheckoutPending).paymentOrderId)
              : null,
          onRetry: _paymentState is CheckoutFailed
              ? () {
                  setState(() => _paymentState = null);
                  _confirm();
                }
              : null,
        ),
      );
    }
    Widget option(String mode, String title, String subtitle) {
      final selected = _payMode == mode;
      return InkWell(
        onTap: () => setState(() => _payMode = mode),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
            color: selected ? AppColors.primary.withValues(alpha: 0.06) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 18, color: selected ? AppColors.primary : AppColors.muted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          option('offline', 'Pay at venue',
              'Collect $amount at the venue. Booking is created with payment status Pending.'),
          option('online', 'Pay online now',
              'Collect $amount now via Razorpay (UPI / card / net banking). Confirmed as Paid once it settles.'),
          if (_payMode == 'offline') ...[
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(labelText: 'Payment method (for your records)'),
              items: const ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Other']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _paymentMethod = v ?? 'Cash'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.destructive)),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Booking Summary', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              gradient: const LinearGradient(colors: [Color(0xFF064E3B), Color(0xFF047857)]),
            ),
            child: Text(_court?.name ?? 'Select a court', style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 12)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _kv('Sport', _sportName.isEmpty ? '—' : _sportName),
          _kv('Location', _facilityName),
          _kv('Court', _court?.name ?? '—'),
          _kv('Date', _dateLong(_date)),
          _kv('Time', _slot == null ? '—' : '${_hhmm(_slot!.startTime)} – ${_hhmm(_slot!.endTime)}'),
          _kv('Duration', _slot == null ? '—' : '${_hours.toStringAsFixed(_hours == _hours.roundToDouble() ? 0 : 1)} hr'),
          const Divider(height: AppSpacing.lg),
          Text('Price Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text('Court Price (Per Hour)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
              ),
              Text(_priceMinor == null ? '—' : Formatters.currencyInr((_priceMinor! / 100).round()),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text('Total Amount',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
              ),
              Text(_totalMinor == null ? '—' : Formatters.currencyInr((_totalMinor! / 100).round()),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.mutedBackground, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: AppColors.muted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Payment is to be made offline · You will pay at the venue',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(v, textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}