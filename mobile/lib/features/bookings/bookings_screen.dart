import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/booking.dart';
import '../../data/models/guest.dart';
import '../../data/models/membership_session.dart';
import '../../data/models/operating_hours.dart';
import '../../data/models/payment.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/refund.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/booking_slot_chip.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../membership_sessions/membership_slot_card.dart';
import 'guest_booking_screen.dart';
import '../payments/payment_checkout_controller.dart';
import '../payments/payment_status_panel.dart';
import 'booking_operations.dart';
import 'booking_slots.dart';
import 'booking_status_presentation.dart';
import '../../shared/widgets/app_dropdown.dart';

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

  String? _sportFilter; // null = All Sports
  DateTime _selectedDate = DateTime.now();

  bool _gridLoading = false;
  String? _gridError;
  List<Booking> _bookings = [];
  List<MembershipSessionSlot> _membershipSlots = [];
  final Map<String, OperatingDay?> _dayByCourt = {};

  @override
  void initState() {
    super.initState();
    _load();
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
          _loadError = 'Complete your facility setup before taking bookings.';
        });
        return;
      }
      final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);

      setState(() {
        _facilityId = facility.id;
        _facilitySports = facilitySports.where((fs) => fs.enabled).toList();
        _sports = sports;
        _areas = areas.where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled).toList();
        _isLoading = false;
      });
      await _reloadGrid();
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
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
      });
    } on AppException catch (e) {
      setState(() {
        _gridError = e.message;
        _gridLoading = false;
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

  Booking? _findBookingAt(String courtId, DateTime startTime) {
    return (_bookingsByCourt[courtId] ?? []).where((b) => b.startTime == startTime).firstOrNull;
  }

  /// A membership batch's protected window never renders as a plain
  /// available/booked cell — the owner always sees the membership slot
  /// panel instead, whether or not any of it has been released yet.
  MembershipSessionSlot? _findMembershipSlot(String courtId, BookingTimeSlot slot) {
    return findMembershipSlot(courtId, slot, _membershipSlots);
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
  }

  void _changeDate(int deltaDays) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: deltaDays)));
    _reloadGrid();
  }

  void _onSlotTap(PlayingArea area, BookingTimeSlot slot) {
    final membershipSlot = _findMembershipSlot(area.id, slot);
    if (membershipSlot != null) {
      _openMembershipSlot(membershipSlot);
      return;
    }
    if (slot.available) {
      _openQuickBooking(area, slot);
    } else {
      final booking = _findBookingAt(area.id, slot.startTime);
      if (booking != null) _openBookingDetails(booking, area);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading bookings…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _reloadGrid,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateNav(),
                      const SizedBox(height: AppSpacing.md),
                      if (_isToday) _buildTodaysOperations(),
                      const SizedBox(height: AppSpacing.md),
                      _buildSportFilter(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildAvailability(),
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButton: _facilityId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final booked = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const GuestBookingScreen()),
                );
                if (booked == true) _reloadGrid();
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Booking'),
            ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.bookings),
    );
  }

  Widget _buildDateNav() {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeDate(-1)),
        Expanded(
          child: Center(
            child: Text(
              _isToday ? 'Today · ${Formatters.dateShort(_selectedDate)}' : Formatters.dateShort(_selectedDate),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeDate(1)),
        if (!_isToday)
          TextButton(
            onPressed: () {
              setState(() => _selectedDate = DateTime.now());
              _reloadGrid();
            },
            child: const Text('Today'),
          ),
      ],
    );
  }

  Widget _buildTodaysOperations() {
    final ops = computeTodaysOperations(_bookings, DateTime.now());
    return Row(
      children: [
        Expanded(child: _OpsStat(label: "Today's Bookings", value: ops.totalBookings)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _OpsStat(label: 'Upcoming', value: ops.upcoming)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _OpsStat(label: 'Occupied', value: ops.currentlyOccupied)),
      ],
    );
  }

  Widget _buildSportFilter() {
    return SizedBox(
      height: AppSpacing.minTouchTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: const Text('All Sports'),
              selected: _sportFilter == null,
              onSelected: (_) => setState(() => _sportFilter = null),
            ),
          ),
          ..._facilitySports.map((fs) {
            final sport = _sports.where((s) => s.id == fs.sportId).firstOrNull;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(fs.customSportName ?? sport?.name ?? 'Sport'),
                selected: _sportFilter == fs.id,
                onSelected: (_) => setState(() => _sportFilter = fs.id),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAvailability() {
    if (_gridLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_gridError != null) {
      return Text(_gridError!, style: const TextStyle(color: AppColors.destructive));
    }
    if (_visibleAreas.isEmpty) {
      return const Text('No courts configured for this sport.');
    }

    final grouped = _facilitySports
        .where((fs) => _sportFilter == null || fs.id == _sportFilter)
        .map((fs) => (facilitySport: fs, courts: _areas.where((a) => a.facilitySportId == fs.id).toList()))
        .where((g) => g.courts.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.map((group) {
        final sport = _sports.where((s) => s.id == group.facilitySport.sportId).firstOrNull;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.facilitySport.customSportName ?? sport?.name ?? 'Sport',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...group.courts.map((area) {
                final slots = _slotsFor(area);
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(area.name, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.sm),
                        if (slots.isEmpty)
                          Text('Closed on this date.', style: AppTypography.secondary(context))
                        else
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: slots.map((slot) {
                              final membershipSlot = _findMembershipSlot(area.id, slot);
                              return BookingSlotChip(
                                label: TimeOfDay.fromDateTime(slot.startTime).format(context),
                                available: slot.available,
                                selected: false,
                                locked: membershipSlot != null,
                                onTap: () => _onSlotTap(area, slot),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _OpsStat extends StatelessWidget {
  const _OpsStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.caption(context)),
          const SizedBox(height: 2),
          Text('$value', style: Theme.of(context).textTheme.titleLarge),
        ],
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
                          label: TimeOfDay.fromDateTime(s.startTime).format(context),
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
  List<BookingTimeSlot> _slots = [];
  bool _slotsLoading = false;
  BookingTimeSlot? _selectedSlot;
  bool _isWorking = false;
  String? _error;
  bool _isPaying = false;
  bool _isCheckingAgain = false;
  CheckoutResult? _paymentState;

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

  Future<void> _payNow() async {
    setState(() {
      _isPaying = true;
      _error = null;
      _paymentState = null;
    });
    try {
      final result = await ref.read(paymentCheckoutControllerProvider).startCheckout(
        CreatePaymentOrderInput(
          facilityId: widget.facilityId,
          sourceType: _booking.customerType == CustomerType.member
              ? PaymentSourceType.memberBooking
              : PaymentSourceType.guestBooking,
          bookingId: _booking.id,
        ),
      );
      if (!mounted) return;
      setState(() => _paymentState = result is CheckoutCancelled ? null : result);
      if (result is CheckoutSettled) _markSettled();
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  Future<void> _handleCheckAgain(String paymentOrderId) async {
    setState(() => _isCheckingAgain = true);
    try {
      final result = await ref.read(paymentCheckoutControllerProvider).checkAgain(paymentOrderId);
      if (!mounted) return;
      setState(() => _paymentState = result);
      if (result is CheckoutSettled) _markSettled();
    } finally {
      if (mounted) setState(() => _isCheckingAgain = false);
    }
  }

  /// The server already flipped `bookings.status`/`payment_status` by the
  /// time a checkout resolves "settled" (settle_payment, 0021_payment_
  /// settlement.sql) — mirrors booking-details-dialog.tsx's
  /// `onChanged({...booking, status: "confirmed", paymentStatus: "PAID"})`
  /// optimistic update rather than waiting for a full grid refetch.
  void _markSettled() {
    setState(() {
      _booking = _booking.copyWith(status: BookingStatus.confirmed, paymentStatus: PaymentStatus.paid);
      _changed = true;
    });
  }

  Future<void> _pickRescheduleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _newDate = picked;
      _slotsLoading = true;
      _selectedSlot = null;
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
      _slots = day != null
          ? computeAvailableSlots(
              picked,
              day,
              existing.where((b) => b.id != _booking.id).map((b) => (startTime: b.startTime, endTime: b.endTime)).toList(),
            )
          : [];
      _slotsLoading = false;
    });
  }

  Future<void> _confirmReschedule() async {
    if (_selectedSlot == null) return;
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      await ref.read(bookingRepositoryProvider).rescheduleBooking(
        RescheduleBookingInput(
          bookingId: _booking.id,
          courtId: widget.area.id,
          startTime: _selectedSlot!.startTime,
          endTime: _selectedSlot!.endTime,
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
            Text('Booking Details', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            if (!_rescheduling) ...[
              Text('${widget.sportName} · ${widget.area.name}', style: Theme.of(context).textTheme.titleSmall),
              Text(
                '${Formatters.dateShort(b.startTime)} · '
                '${TimeOfDay.fromDateTime(b.startTime).format(context)} – ${TimeOfDay.fromDateTime(b.endTime).format(context)}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _DetailField(
                      label: 'Customer',
                      value: b.customerType == CustomerType.guest ? '${b.guestName} (Guest)' : 'Member',
                    ),
                  ),
                  Expanded(
                    child: _DetailField(
                      label: 'Amount',
                      value: b.amountMinor != null ? Formatters.currencyInr((b.amountMinor! / 100).round()) : '—',
                    ),
                  ),
                ],
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
              if (_paymentState != null || _isPaying) ...[
                const SizedBox(height: AppSpacing.sm),
                PaymentStatusPanel(
                  state: _paymentState,
                  isProcessing: _isPaying,
                  isCheckingAgain: _isCheckingAgain,
                  settledLabel: 'Booking Confirmed',
                  resourceLabel: 'booking',
                  onCheckAgain: _paymentState is CheckoutPending
                      ? () => _handleCheckAgain((_paymentState as CheckoutPending).paymentOrderId)
                      : null,
                  onRetry: _paymentState is CheckoutFailed ? _payNow : null,
                ),
              ],
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
                PrimaryButton(
                  label: 'Pay Now',
                  loadingLabel: 'Starting payment…',
                  isLoading: _isPaying,
                  onPressed: _isWorking ? null : _payNow,
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
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.destructive),
                        onPressed: _isWorking ? null : _cancel,
                        child: Text(_isWorking ? 'Cancelling…' : 'Cancel Booking'),
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              OutlinedButton(onPressed: _pickRescheduleDate, child: Text(_newDate == null ? 'Pick a new date' : Formatters.dateShort(_newDate!))),
              const SizedBox(height: AppSpacing.sm),
              if (_slotsLoading)
                const Center(child: CircularProgressIndicator())
              else if (_newDate != null && _slots.isEmpty)
                const Text('No slots available.')
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: _slots.map((s) {
                    return BookingSlotChip(
                      label: TimeOfDay.fromDateTime(s.startTime).format(context),
                      available: s.available,
                      selected: _selectedSlot?.startTime == s.startTime,
                      onTap: () => setState(() => _selectedSlot = s),
                    );
                  }).toList(),
                ),
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
                      onPressed: _selectedSlot == null ? null : _confirmReschedule,
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