import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/booking.dart';
import '../../data/models/guest.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../bookings/booking_status_presentation.dart';
import '../bookings/bookings_screen.dart';
import 'guest_form_sheet.dart';

class GuestProfileScreen extends ConsumerStatefulWidget {
  const GuestProfileScreen({super.key, required this.facilityId, required this.guest});

  final String facilityId;
  final GuestPlayer guest;

  @override
  ConsumerState<GuestProfileScreen> createState() => _GuestProfileScreenState();
}

class _GuestProfileScreenState extends ConsumerState<GuestProfileScreen> {
  late GuestPlayer _guest = widget.guest;
  bool _isLoading = true;
  String? _loadError;
  GuestStats? _stats;
  List<Booking> _history = [];
  List<FacilitySport> _facilitySports = [];
  List<Sport> _sports = [];
  List<PlayingArea> _areas = [];
  bool _changed = false;

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
      final guestRepo = ref.read(guestRepositoryProvider);
      final stats = await guestRepo.getGuestStats(_guest.id);
      final history = await guestRepo.getGuestBookings(_guest.id, limit: 20);
      final facilitySports = await ref.read(sportsRepositoryProvider).getFacilitySports(widget.facilityId);
      final sports = await ref.read(sportsRepositoryProvider).getActiveSports();
      final areas = await ref.read(playingAreaRepositoryProvider).getPlayingAreas(widget.facilityId);
      setState(() {
        _stats = stats;
        _history = history;
        _facilitySports = facilitySports.where((fs) => fs.enabled).toList();
        _sports = sports;
        _areas = areas.where((a) => !a.archived && a.status == 'ACTIVE' && a.bookingEnabled).toList();
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _editGuest() async {
    final saved = await showModalBottomSheet<GuestPlayer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => GuestFormSheet(facilityId: widget.facilityId, guest: _guest),
    );
    if (saved != null) {
      setState(() {
        _guest = saved;
        _changed = true;
      });
    }
  }

  Future<void> _bookCourt() async {
    final booked = await showModalBottomSheet<Booking>(
      context: context,
      isScrollControlled: true,
      builder: (context) => QuickBookingSheet(
        facilityId: widget.facilityId,
        facilitySports: _facilitySports,
        sports: _sports,
        areas: _areas,
        initialGuest: _guest,
      ),
    );
    if (booked != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed ? _guest : null);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_guest.name)),
        body: SafeArea(
          child: _isLoading
              ? const LoadingView(message: 'Loading guest profile…')
              : _loadError != null
              ? ErrorView(message: _loadError!, onRetry: _load)
              : ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_guest.phone != null) Text('Phone: ${_guest.phone}', style: AppTypography.secondary(context)),
                      if (_guest.email != null) Text('Email: ${_guest.email}', style: AppTypography.secondary(context)),
                      const SizedBox(height: AppSpacing.lg),
                      _buildStats(),
                      const SizedBox(height: AppSpacing.lg),
                      Text('Booking History', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      if (_history.isEmpty)
                        EmptyStateView(
                          message: 'No bookings found.',
                          actionLabel: '+ Book Court',
                          onAction: _bookCourt,
                        )
                      else
                        ..._history.map(
                          (b) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: AppCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(Formatters.dateShort(b.startTime)),
                                        const SizedBox(height: AppSpacing.xs),
                                        Wrap(
                                          spacing: AppSpacing.xs,
                                          children: [
                                            StatusBadge(label: bookingStatusLabel(b.status), tone: bookingStatusTone(b.status)),
                                            StatusBadge(label: paymentStatusLabel(b.paymentStatus), tone: paymentStatusTone(b.paymentStatus)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(b.amountMinor != null ? Formatters.currencyInr((b.amountMinor! / 100).round()) : '—'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(label: 'Edit Guest', onPressed: _editGuest),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: PrimaryButton(label: 'Book Court', onPressed: _bookCourt),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Total Visits', value: '${stats.totalVisits}')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _StatTile(label: 'Total Amount', value: Formatters.currencyInr((stats.totalAmountMinor / 100).round()))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _StatTile(label: 'Pending', value: Formatters.currencyInr((stats.pendingAmountMinor / 100).round()))),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Last Visit: ${stats.lastVisit != null ? Formatters.dateShort(stats.lastVisit!) : 'Never'}',
          style: AppTypography.secondary(context),
        ),
        if (stats.sports.isNotEmpty)
          Text('Sports: ${stats.sports.map((s) => s.sportName).join(', ')}', style: AppTypography.secondary(context)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.caption(context)),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}