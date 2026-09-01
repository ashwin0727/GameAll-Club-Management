import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/booking.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import 'booking_slots.dart';

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _clock(DateTime d) => Formatters.time12h(_hm(d));

/// Edit a guest booking — guest fields + optional court/time reschedule.
/// Mirrors the web `guest-booking-edit-page.tsx`.
class GuestBookingEditScreen extends ConsumerStatefulWidget {
  const GuestBookingEditScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<GuestBookingEditScreen> createState() => _GuestBookingEditScreenState();
}

class _GuestBookingEditScreenState extends ConsumerState<GuestBookingEditScreen> {
  bool _loading = true;
  bool _notFound = false;
  Booking? _booking;
  String? _facilityId;
  List<PlayingArea> _areas = [];
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _players = TextEditingController();
  final _notes = TextEditingController();

  String? _courtId;
  DateTime _date = DateTime.now();
  BookingTimeSlot? _slot;
  List<BookingTimeSlot> _slots = [];
  bool _slotsLoading = false;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _players, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await ref.read(bookingRepositoryProvider).getBooking(widget.bookingId);
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (b == null || b.customerType != CustomerType.guest || facility == null) {
        setState(() {
          _notFound = true;
          _loading = false;
        });
        return;
      }
      final fs = await ref.read(sportsRepositoryProvider).getFacilitySports(facility.id);
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(facility.id);
      if (!mounted) return;
      setState(() {
        _booking = b;
        _facilityId = facility.id;
        _facilitySports = fs.where((x) => x.enabled).toList();
        _sports = sports;
        _areas = areas.where((a) => !a.archived).toList();
        _name.text = b.guestName ?? '';
        _phone.text = b.guestPhone ?? '';
        _players.text = '${b.partySize}';
        _notes.text = b.notes ?? '';
        _courtId = b.courtId;
        _date = DateTime(b.startTime.year, b.startTime.month, b.startTime.day);
        _loading = false;
      });
    } on AppException catch (_) {
      setState(() {
        _notFound = true;
        _loading = false;
      });
    }
  }

  PlayingArea? get _court => _areas.where((a) => a.id == _courtId).firstOrNull;
  List<PlayingArea> get _courtsForSport =>
      _court == null ? _areas : _areas.where((a) => a.facilitySportId == _court!.facilitySportId).toList();

  String get _sportName {
    final fs = _facilitySports.where((x) => x.id == _court?.facilitySportId).firstOrNull;
    return fs?.customSportName ?? _sports.where((s) => s.id == fs?.sportId).firstOrNull?.name ?? '';
  }

  bool get _timeChanged {
    final b = _booking;
    if (b == null) return false;
    if (_courtId != b.courtId) return true;
    if (DateTime(b.startTime.year, b.startTime.month, b.startTime.day) != _date) return true;
    return _slot != null && _slot!.startTime != b.startTime;
  }

  Future<void> _loadSlots() async {
    final courtId = _courtId;
    if (_facilityId == null || courtId == null) return;
    setState(() => _slotsLoading = true);
    final dow = _date.weekday % 7;
    final hoursRepo = ref.read(operatingHoursRepositoryProvider);
    final override = await hoursRepo.getPlayingAreaSchedule(courtId);
    final facilitySchedule = await hoursRepo.getFacilitySchedule(_facilityId!);
    final day = (override ?? facilitySchedule)?.days.where((d) => d.dayOfWeek == dow).firstOrNull;
    final existing = await ref.read(bookingRepositoryProvider).getBookingsForCourtOnDate(courtId, _date);
    if (!mounted) return;
    setState(() {
      _slots = day == null
          ? []
          : computeAvailableSlots(
              _date,
              day,
              existing.where((x) => x.id != widget.bookingId).map((x) => (startTime: x.startTime, endTime: x.endTime)).toList(),
            );
      _slotsLoading = false;
    });
  }

  Future<void> _save() async {
    final b = _booking;
    if (b == null) return;
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter a guest name.');
      return;
    }
    if (_timeChanged && _slot == null) {
      setState(() => _error = 'Pick a new time slot.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(bookingRepositoryProvider);
      await repo.updateGuestBooking(
        widget.bookingId,
        guestName: _name.text.trim(),
        guestPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        partySize: int.tryParse(_players.text.trim()) ?? 1,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (_timeChanged && _slot != null) {
        await repo.rescheduleBooking(RescheduleBookingInput(
          bookingId: widget.bookingId,
          courtId: _courtId!,
          startTime: _slot!.startTime,
          endTime: _slot!.endTime,
        ));
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Guest Booking')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _notFound || _booking == null
                ? const ErrorView(message: 'This booking could not be found.')
                : ResponsivePage(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Guest', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(controller: _players, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Players')),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Court & time', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Currently $_sportName · ${_court?.name} · ${Formatters.dateShort(_booking!.startTime)} · ${_clock(_booking!.startTime)} – ${_clock(_booking!.endTime)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              DropdownButtonFormField<String>(
                                initialValue: _courtId,
                                decoration: const InputDecoration(labelText: 'Court'),
                                items: _courtsForSport.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                                onChanged: (v) {
                                  setState(() {
                                    _courtId = v;
                                    _slot = null;
                                  });
                                  _loadSlots();
                                },
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
                                    _loadSlots();
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                                  child: Text(Formatters.dateShort(_date)),
                                ),
                              ),
                              if (_timeChanged) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text('Pick a new slot', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                                const SizedBox(height: AppSpacing.xs),
                                if (_slotsLoading)
                                  const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: CircularProgressIndicator()))
                                else if (_slots.isEmpty)
                                  Text('No slots available.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted))
                                else
                                  Wrap(
                                    spacing: AppSpacing.xs,
                                    runSpacing: AppSpacing.xs,
                                    children: _slots.map((s) {
                                      final active = _slot?.startTime == s.startTime;
                                      return GestureDetector(
                                        onTap: s.available ? () => setState(() => _slot = s) : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                            border: Border.all(color: active ? AppColors.primary : AppColors.border),
                                            color: active
                                                ? AppColors.primary.withValues(alpha: 0.1)
                                                : s.available
                                                    ? null
                                                    : AppColors.mutedBackground,
                                          ),
                                          child: Text(_clock(s.startTime), style: Theme.of(context).textTheme.bodySmall),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_error!, style: const TextStyle(color: AppColors.destructive)),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        PrimaryButton(label: 'Save Changes', loadingLabel: 'Saving…', isLoading: _saving, onPressed: _save),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
      ),
    );
  }
}
