import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/guest_booking_dashboard.dart';
import '../../data/models/payment.dart';
import '../../data/models/refund.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_metric_card.dart';
import '../../shared/widgets/metric_carousel.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../payments/payment_checkout_controller.dart';
import '../payments/payment_status_panel.dart';
import 'booking_status_presentation.dart';
import 'guest_booking_edit_screen.dart';
import 'guest_booking_screen.dart';
import '../../shared/widgets/app_dropdown.dart';

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
    String n(num v) => v.round().toString();
    return MetricCarousel(
      cards: [
        AppMetricCard(
          label: 'Total Bookings',
          value: s == null ? '—' : '${s.total}',
          countTo: s?.total,
          formatValue: n,
          changePercent: s?.totalChangePct?.toDouble(),
          icon: Icons.event_note,
        ),
        AppMetricCard(
          label: 'Confirmed',
          value: s == null ? '—' : '${s.confirmed}',
          countTo: s?.confirmed,
          formatValue: n,
          icon: Icons.check_circle_outline,
          accentColor: AppColors.success,
        ),
        AppMetricCard(
          label: 'Completed',
          value: s == null ? '—' : '${s.completed}',
          countTo: s?.completed,
          formatValue: n,
          icon: Icons.task_alt,
          accentColor: AppColors.electricBlue,
        ),
        AppMetricCard(
          label: 'Cancelled',
          value: s == null ? '—' : '${s.cancelled}',
          countTo: s?.cancelled,
          formatValue: n,
          icon: Icons.cancel_outlined,
          accentColor: AppColors.destructive,
        ),
        AppMetricCard(
          label: 'Pending',
          value: s == null ? '—' : '${s.pending}',
          countTo: s?.pending,
          formatValue: n,
          icon: Icons.schedule,
          accentColor: AppColors.warning,
        ),
        AppMetricCard(
          label: 'Total Revenue',
          value: s == null ? '—' : rev(s.totalRevenueMinor),
          countTo: s?.totalRevenueMinor,
          formatValue: (v) => rev(v.round()),
          changePercent: s?.revenueChangePct?.toDouble(),
          icon: Icons.account_balance_wallet_outlined,
          accentColor: AppColors.success,
        ),
      ],
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

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openEdit(String id) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GuestBookingEditScreen(bookingId: id)),
    );
    if (changed == true) _reload();
  }

  Widget _rowMenu(GuestBookingRow r) {
    final actions = guestBookingActions(
      isSession: r.isSession,
      status: r.status,
      paymentStatus: r.paymentStatus,
    );
    return PopupMenuButton<GuestBookingAction>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (a) {
        switch (a) {
          case GuestBookingAction.complete:
            _complete(r);
          case GuestBookingAction.cancel:
            _cancel(r);
          case GuestBookingAction.sendReceipt:
            _receipt(r);
          case GuestBookingAction.duplicate:
            _duplicate(r);
          case GuestBookingAction.invoice:
            _invoice(r);
          case GuestBookingAction.delete:
            _delete(r);
          case GuestBookingAction.recordSessionPayment:
            _recordSessionPayment(r);
        }
      },
      itemBuilder: (_) => [
        for (final a in actions) _mi(a, _actionTitle(a), _actionSub(a)),
      ],
    );
  }

  static String _actionTitle(GuestBookingAction a) => switch (a) {
        GuestBookingAction.complete => 'Mark as Completed',
        GuestBookingAction.cancel => 'Cancel Booking',
        GuestBookingAction.sendReceipt => 'Send Receipt',
        GuestBookingAction.duplicate => 'Duplicate Booking',
        GuestBookingAction.invoice => 'Download Invoice',
        GuestBookingAction.delete => 'Delete Booking',
        GuestBookingAction.recordSessionPayment => 'Record Payment',
      };

  static String _actionSub(GuestBookingAction a) => switch (a) {
        GuestBookingAction.complete => 'Mark booking as completed',
        GuestBookingAction.cancel => 'Cancel this booking',
        GuestBookingAction.sendReceipt => 'Send booking receipt to guest',
        GuestBookingAction.duplicate => 'Create a new booking',
        GuestBookingAction.invoice => 'Download invoice / bill',
        GuestBookingAction.delete => 'Permanently delete booking',
        GuestBookingAction.recordSessionPayment => 'Mark payment as received',
      };

  PopupMenuItem<GuestBookingAction> _mi(GuestBookingAction v, String title, String sub) => PopupMenuItem(
        value: v,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(sub, style: TextStyle(fontSize: 10, color: AppColors.muted)),
          ],
        ),
      );

  Future<bool> _confirm(String title, String body, {String confirm = 'Confirm'}) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _delete(GuestBookingRow r) async {
    if (!await _confirm('Delete booking', 'Permanently delete ${r.code}? Bookings with a settled payment can\'t be deleted.', confirm: 'Delete')) return;
    try {
      await ref.read(bookingRepositoryProvider).deleteGuestBooking(r.bookingId);
      _reload();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _cancel(GuestBookingRow r) async {
    final reason = TextEditingController();
    final amount = TextEditingController(text: r.amountMinor != null ? '${(r.amountMinor! / 100)}' : '');
    var refund = r.paymentStatus == 'PAID';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Cancel booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
              if (r.paymentStatus == 'PAID') ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: refund,
                  onChanged: (v) => setSt(() => refund = v ?? false),
                  title: const Text('Issue a refund'),
                ),
                if (refund)
                  TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Refund amount (₹)')),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel Booking')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (r.paymentStatus == 'PAID') {
        final total = r.amountMinor ?? 0;
        final pct = refund && total > 0
            ? ((double.tryParse(amount.text.trim()) ?? 0) * 100 * 100 / total).round().clamp(0, 100)
            : 0;
        await ref.read(refundRepositoryProvider).cancelBooking(
              CancelBookingInput(bookingId: r.bookingId, reason: reason.text.trim().isEmpty ? null : reason.text.trim(), refundOverridePercent: pct),
            );
      } else {
        await ref.read(bookingRepositoryProvider).cancelBooking(r.bookingId, reason: reason.text.trim().isEmpty ? null : reason.text.trim());
      }
      _reload();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _receipt(GuestBookingRow r) async {
    final email = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Receipt'),
        content: TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Guest email', hintText: 'guest@example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (send != true) return;
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email.text.trim())) {
      _toast('Enter a valid email address.');
      return;
    }
    try {
      await ref.read(bookingRepositoryProvider).sendBookingReceipt(r.bookingId, email.text.trim());
      _toast('Receipt sent to ${email.text.trim()}');
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _duplicate(GuestBookingRow r) async {
    final duration = r.endTime.difference(r.startTime);
    var start = r.startTime.add(const Duration(days: 7));
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Duplicate booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Creates a new booking with the same guest, court and players.'),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                  if (d == null || !ctx.mounted) return;
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(start));
                  if (t == null) return;
                  setSt(() => start = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
                child: Text('${Formatters.dateShort(start)} · ${Formatters.time12h(_hm(start))}'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Duplicate')),
          ],
        ),
      ),
    );
    if (go != true) return;
    try {
      final b = await ref.read(bookingRepositoryProvider).duplicateGuestBooking(r.bookingId, start, start.add(duration));
      _reload();
      await _collectAndComplete(bookingId: b.id, amountMinor: b.amountMinor, alreadyPaid: false, label: '${r.sportName ?? "Court"} · ${r.courtName}', guestName: r.guestName, guestPhone: r.guestPhone, promptOnly: true);
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _complete(GuestBookingRow r) async {
    await _collectAndComplete(
      bookingId: r.bookingId,
      amountMinor: r.amountMinor,
      alreadyPaid: r.paymentStatus == 'PAID',
      label: '${r.sportName ?? "Court"} · ${r.courtName}',
      guestName: r.guestName,
      guestPhone: r.guestPhone,
    );
  }

  /// Shared "collect payment then complete" flow. [promptOnly] skips the
  /// final complete step (used right after Duplicate — the new booking is
  /// just pending, not something to complete yet).
  Future<void> _collectAndComplete({
    required String bookingId,
    required int? amountMinor,
    required bool alreadyPaid,
    required String label,
    String? guestName,
    String? guestPhone,
    bool promptOnly = false,
  }) async {
    final facilityId = _facilityId;
    if (facilityId == null) return;

    if (alreadyPaid) {
      if (!await _confirm('Mark as Completed', 'This booking is paid. Mark it completed?', confirm: 'Complete')) return;
      try {
        await ref.read(bookingRepositoryProvider).completeGuestBooking(bookingId);
        _reload();
      } on AppException catch (e) {
        _toast(e.message);
      }
      return;
    }

    final method = TextEditingController(text: 'Cash');
    final amount = TextEditingController(text: amountMinor != null ? '${(amountMinor / 100)}' : '');
    var mode = 'offline';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(promptOnly ? 'Collect payment' : 'Mark as Completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final opt in const [('offline', 'Payment collected offline'), ('online', 'Collect online (Razorpay)')])
                InkWell(
                  onTap: () => setSt(() => mode = opt.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(mode == opt.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            size: 18, color: mode == opt.$1 ? AppColors.primary : AppColors.muted),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(opt.$2)),
                      ],
                    ),
                  ),
                ),
              if (mode == 'offline') ...[
                AppDropdown<String>(
                  initialValue: method.text,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: const ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Other'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => method.text = v ?? 'Cash',
                ),
                TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(promptOnly ? 'Later' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, mode), child: const Text('Continue')),
          ],
        ),
      ),
    );
    if (choice == null) return;

    try {
      if (choice == 'offline') {
        await ref.read(bookingRepositoryProvider).recordGuestBookingPayment(
              bookingId,
              method.text.trim().isEmpty ? 'Cash' : method.text.trim(),
              ((double.tryParse(amount.text.trim()) ?? 0) * 100).round(),
            );
      } else {
        final result = await ref.read(paymentCheckoutControllerProvider).startCheckout(
              CreatePaymentOrderInput(facilityId: facilityId, sourceType: PaymentSourceType.guestBooking, bookingId: bookingId),
              contactName: guestName,
              contactPhone: guestPhone,
            );
        if (result is CheckoutCancelled) return;
        if (result is! CheckoutSettled) {
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(content: PaymentStatusPanel(state: result, settledLabel: 'Payment received', resourceLabel: 'booking')),
            );
          }
          _reload();
          return;
        }
      }
      if (!promptOnly) {
        await ref.read(bookingRepositoryProvider).completeGuestBooking(bookingId);
      }
      _reload();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  /// Offline payment for a released membership seat. Mirrors web's
  /// RecordSessionPaymentDialog in guest-booking-actions.tsx.
  Future<void> _recordSessionPayment(GuestBookingRow r) async {
    final method = TextEditingController(text: 'Cash');
    final amount = TextEditingController(
      text: r.amountMinor != null ? '${(r.amountMinor! / 100)}' : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r.guestName} · ${r.amountMinor == null ? '—' : Formatters.currencyInr((r.amountMinor! / 100).round())}',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: method.text,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Other']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => method.text = v ?? 'Cash',
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount received (₹)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Record payment')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(bookingRepositoryProvider).recordSessionGuestPayment(
            r.bookingId,
            method.text.trim().isEmpty ? 'Cash' : method.text.trim(),
            ((double.tryParse(amount.text.trim()) ?? 0) * 100).round(),
          );
      _toast('Payment recorded');
      _reload();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _invoice(GuestBookingRow r) async {
    final lines = <(String, String)>[
      ('Booking ID', r.code),
      ('Guest', '${r.guestName}${r.guestPhone != null ? ' · ${r.guestPhone}' : ''}'),
      ('Sport / Court', '${r.sportName ?? '—'} · ${r.courtName}'),
      ('Date', Formatters.dateShort(r.startTime)),
      ('Time', '${Formatters.time12h(_hm(r.startTime))} – ${Formatters.time12h(_hm(r.endTime))}'),
      ('Players', '${r.partySize}'),
      ('Amount', r.amountMinor == null ? '—' : Formatters.currencyInr((r.amountMinor! / 100).round())),
      ('Payment', '${r.paymentStatus}${r.paymentMethod != null ? ' · ${r.paymentMethod}' : ''}'),
      ('Status', r.status),
    ];
    final text = ['GameAll — Invoice', ...lines.map((e) => '${e.$1}: ${e.$2}')].join('\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invoice'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: lines.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${e.$1}: ${e.$2}'))).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              _toast('Invoice copied');
            },
            child: const Text('Copy'),
          ),
        ],
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
              // A released membership seat has no bookings row behind it, so
              // the edit screen doesn't apply — it is managed under Membership
              // Sessions.
              onTap: r.isSession ? null : () => _openEdit(r.bookingId),
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
                              r.isSession
                                  ? 'Session seat · ${r.courtName}'
                                  : '${r.sportName ?? '—'} · ${r.courtName}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(label: chip.label, tone: chip.tone),
                      _rowMenu(r),
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