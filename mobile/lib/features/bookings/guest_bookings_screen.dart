import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/guest_booking_dashboard.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'guest_booking_screen.dart';

const _perPage = 10;

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

({String label, StatusTone tone}) _statusChip(String s) {
  switch (s) {
    case 'completed':
      return (label: 'Completed', tone: StatusTone.info);
    case 'cancelled':
      return (label: 'Cancelled', tone: StatusTone.danger);
    case 'pending':
      return (label: 'Pending', tone: StatusTone.warning);
    default:
      return (label: 'Confirmed', tone: StatusTone.success);
  }
}

({String label, StatusTone tone}) _payChip(String s) {
  switch (s) {
    case 'PAID':
      return (label: 'Paid', tone: StatusTone.success);
    case 'REFUNDED':
      return (label: 'Refunded', tone: StatusTone.danger);
    default:
      return (label: 'Pending', tone: StatusTone.warning);
  }
}

/// Guest Bookings dashboard — KPI tiles, filters and a paginated list of
/// guest court bookings. Mirrors the web `guest-bookings-dashboard.tsx`.
class GuestBookingsScreen extends ConsumerStatefulWidget {
  const GuestBookingsScreen({super.key});

  @override
  ConsumerState<GuestBookingsScreen> createState() => _GuestBookingsScreenState();
}

class _GuestBookingsScreenState extends ConsumerState<GuestBookingsScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;

  GuestBookingsSummary? _summary;
  List<GuestBookingRow>? _rows;
  int _totalCount = 0;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  String? _status;
  String? _paymentStatus;
  late DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  late DateTime _to = DateTime.now();
  int _page = 0;

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
      _loading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _loading = false;
          _loadError = 'Complete your facility setup before taking bookings.';
        });
        return;
      }
      _facilityId = facility.id;
      setState(() => _loading = false);
      await _reload();
    } on AppException catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _reload() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    setState(() => _rows = null);
    final repo = ref.read(bookingRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.getGuestBookingsSummary(facilityId, _iso(_from), _iso(_to)),
        repo.listGuestBookings(
          facilityId,
          search: _search.isEmpty ? null : _search,
          status: _status,
          paymentStatus: _paymentStatus,
          from: _iso(_from),
          to: _iso(_to),
          limit: _perPage,
          offset: _page * _perPage,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as GuestBookingsSummary;
        final list = results[1] as ({List<GuestBookingRow> rows, int totalCount});
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

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        _search = v.trim();
        _page = 0;
      });
      _reload();
    });
  }

  void _setFilter(void Function() apply) {
    setState(() {
      apply();
      _page = 0;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest Bookings'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const GuestBookingScreen()),
              );
              _reload();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New'),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _loadError != null && _rows == null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ResponsivePage(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kpis(),
                          const SizedBox(height: AppSpacing.lg),
                          _filters(),
                          const SizedBox(height: AppSpacing.lg),
                          _list(),
                          const SizedBox(height: AppSpacing.lg),
                          _overview(),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _kpis() {
    final s = _summary;
    String rev(int m) => Formatters.currencyInr((m / 100).round());
    final tiles = <Widget>[
      AppMetricCard(
        label: 'Total Bookings',
        value: s == null ? '—' : '${s.total}',
        changePercent: s?.totalChangePct?.toDouble(),
        icon: Icons.event_note,
      ),
      AppMetricCard(label: 'Confirmed', value: s == null ? '—' : '${s.confirmed}', icon: Icons.check_circle_outline, accentColor: AppColors.success),
      AppMetricCard(label: 'Completed', value: s == null ? '—' : '${s.completed}', icon: Icons.task_alt, accentColor: AppColors.electricBlue),
      AppMetricCard(label: 'Cancelled', value: s == null ? '—' : '${s.cancelled}', icon: Icons.cancel_outlined, accentColor: AppColors.destructive),
      AppMetricCard(label: 'Pending', value: s == null ? '—' : '${s.pending}', icon: Icons.schedule, accentColor: AppColors.warning),
      AppMetricCard(
        label: 'Total Revenue',
        value: s == null ? '—' : rev(s.totalRevenueMinor),
        changePercent: s?.revenueChangePct?.toDouble(),
        icon: Icons.account_balance_wallet_outlined,
        accentColor: AppColors.success,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 720 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.7,
          children: tiles,
        );
      },
    );
  }

  Widget _filters() {
    Widget chip<T>(String label, T? value, T? current, void Function() onTap) {
      final selected = value == current;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearch,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by guest, phone, booking ID…',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip('All Status', null, _status, () => _setFilter(() => _status = null)),
              chip('Confirmed', 'confirmed', _status, () => _setFilter(() => _status = 'confirmed')),
              chip('Completed', 'completed', _status, () => _setFilter(() => _status = 'completed')),
              chip('Cancelled', 'cancelled', _status, () => _setFilter(() => _status = 'cancelled')),
              chip('Pending', 'pending', _status, () => _setFilter(() => _status = 'pending')),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip('All Payments', null, _paymentStatus, () => _setFilter(() => _paymentStatus = null)),
              chip('Paid', 'PAID', _paymentStatus, () => _setFilter(() => _paymentStatus = 'PAID')),
              chip('Pending', 'PENDING', _paymentStatus, () => _setFilter(() => _paymentStatus = 'PENDING')),
              chip('Refunded', 'REFUNDED', _paymentStatus, () => _setFilter(() => _paymentStatus = 'REFUNDED')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              initialDateRange: DateTimeRange(start: _from, end: _to),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (range != null) {
              _setFilter(() {
                _from = range.start;
                _to = range.end;
              });
            }
          },
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text('${Formatters.dateShort(_from)} – ${Formatters.dateShort(_to)}'),
        ),
      ],
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
      return const EmptyStateView(message: 'No guest bookings match these filters.');
    }
    final totalPages = (_totalCount / _perPage).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows.map((r) {
          final chip = _statusChip(r.status);
          final pay = _payChip(r.paymentStatus);
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${r.code} · ${r.guestName}', style: Theme.of(context).textTheme.titleSmall),
                            Text(
                              '${r.sportName ?? '—'} · ${r.courtName}',
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
                    '${Formatters.dateShort(r.startTime)} · ${Formatters.time12h(_hm(r.startTime))} – ${Formatters.time12h(_hm(r.endTime))} · ${r.partySize} players',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Text(
                        r.amountMinor == null ? '—' : Formatters.currencyInr((r.amountMinor! / 100).round()),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      StatusBadge(label: pay.label, tone: pay.tone),
                      if (r.paymentMethod != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(r.paymentMethod!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        if (totalPages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _page > 0
                    ? () {
                        setState(() => _page--);
                        _reload();
                      }
                    : null,
                child: const Text('Prev'),
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

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _overview() {
    final s = _summary;
    if (s == null) return const SizedBox.shrink();
    Widget seg(Color c, String label, int value) {
      final total = s.total == 0 ? 1 : s.total;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            Text('$value (${((value / total) * 100).round()}%)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Booking Overview', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          seg(AppColors.success, 'Confirmed', s.confirmed),
          seg(AppColors.electricBlue, 'Completed', s.completed),
          seg(AppColors.destructive, 'Cancelled', s.cancelled),
          seg(AppColors.warning, 'Pending', s.pending),
          const Divider(height: AppSpacing.lg),
          Text('Revenue Overview', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(Formatters.currencyInr((s.totalRevenueMinor / 100).round()),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Average per booking', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                    Text(Formatters.currencyInr((s.avgPerBookingMinor / 100).round()), style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Highest booking', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                    Text(Formatters.currencyInr((s.highestBookingMinor / 100).round()), style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}