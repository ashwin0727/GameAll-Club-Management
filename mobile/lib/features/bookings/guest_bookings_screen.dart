import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/page_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/guest_booking_dashboard.dart';
import '../../data/models/payment.dart';
import '../../data/models/refund.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_dropdown.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../payments/payment_checkout_controller.dart';
import '../payments/payment_status_panel.dart';
import 'booking_status_presentation.dart';
import 'guest_booking_edit_screen.dart';
import 'guest_booking_screen.dart';

const _perPage = 10;

const _statusOptions = <({String value, String label})>[
  (value: 'confirmed', label: 'Confirmed'),
  (value: 'completed', label: 'Completed'),
  (value: 'pending', label: 'Pending'),
  (value: 'cancelled', label: 'Cancelled'),
];
const _payOptions = <({String value, String label})>[
  (value: 'PAID', label: 'Paid'),
  (value: 'PENDING', label: 'Pending'),
  (value: 'REFUNDED', label: 'Refunded'),
];

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

/// Guest Bookings — an overview hero with a breakdown chart on top, then a
/// searchable / multi-filterable list of guest court bookings.
class GuestBookingsScreen extends ConsumerStatefulWidget {
  const GuestBookingsScreen({super.key});

  @override
  ConsumerState<GuestBookingsScreen> createState() =>
      _GuestBookingsScreenState();
}

class _GuestBookingsScreenState extends ConsumerState<GuestBookingsScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;

  GuestBookingsSummary? _summary;
  List<GuestBookingRow>? _rows;
  int _totalCount = 0;
  bool _multiActive = false;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  final Set<String> _statusSel = {};
  final Set<String> _paySel = {};
  late DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  late DateTime _to = DateTime.now();
  int _page = 0;

  bool get _hasFilters =>
      _statusSel.isNotEmpty || _paySel.isNotEmpty || _dateChanged;

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

    // The list RPC takes one status / one payment status. For a single
    // selection we let the server filter; for a multi-select we pull a wider
    // page and narrow it here.
    final multi = _statusSel.length > 1 || _paySel.length > 1;
    final serverStatus = _statusSel.length == 1 ? _statusSel.first : null;
    final serverPay = _paySel.length == 1 ? _paySel.first : null;

    try {
      final results = await Future.wait([
        repo.getGuestBookingsSummary(facilityId, _iso(_from), _iso(_to)),
        repo.listGuestBookings(
          facilityId,
          search: _search.isEmpty ? null : _search,
          status: serverStatus,
          paymentStatus: serverPay,
          from: _iso(_from),
          to: _iso(_to),
          limit: multi ? 200 : _perPage,
          offset: multi ? 0 : _page * _perPage,
        ),
      ]);
      if (!mounted) return;
      final list = results[1] as ({List<GuestBookingRow> rows, int totalCount});
      var rows = list.rows;
      if (_statusSel.isNotEmpty) {
        rows = rows.where((r) => _statusSel.contains(r.status)).toList();
      }
      if (_paySel.isNotEmpty) {
        rows = rows.where((r) => _paySel.contains(r.paymentStatus)).toList();
      }
      setState(() {
        _summary = results[0] as GuestBookingsSummary;
        _rows = rows;
        _multiActive = multi;
        _totalCount = multi ? rows.length : list.totalCount;
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

  Future<void> _openFilterSheet() async {
    final tokens = context.tokens;
    final tmpStatus = {..._statusSel};
    final tmpPay = {..._paySel};
    var tmpFrom = _from;
    var tmpTo = _to;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Widget group(
            String title,
            List<({String value, String label})> opts,
            Set<String> sel,
          ) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final o in opts)
                      _FilterPill(
                        label: o.label,
                        selected: sel.contains(o.value),
                        onTap: () => setSheet(
                          () => sel.contains(o.value)
                              ? sel.remove(o.value)
                              : sel.add(o.value),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Filter bookings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (tmpStatus.isNotEmpty ||
                          tmpPay.isNotEmpty ||
                          !_isDefaultRange(tmpFrom, tmpTo))
                        TextButton(
                          onPressed: () => setSheet(() {
                            tmpStatus.clear();
                            tmpPay.clear();
                            tmpFrom = _defaultFrom();
                            tmpTo = DateTime.now();
                          }),
                          child: const Text('Clear all'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'DATE RANGE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Material(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        final range = await showDateRangePicker(
                          context: sheetCtx,
                          initialDateRange: DateTimeRange(
                            start: tmpFrom,
                            end: tmpTo,
                          ),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (range != null) {
                          setSheet(() {
                            tmpFrom = range.start;
                            tmpTo = range.end;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: tokens.borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 15,
                              color: tokens.violet,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              '${Formatters.dateShort(tmpFrom)}  –  ${Formatters.dateShort(tmpTo)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: tokens.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  group('STATUS', _statusOptions, tmpStatus),
                  const SizedBox(height: AppSpacing.lg),
                  group('PAYMENT', _payOptions, tmpPay),
                  const SizedBox(height: AppSpacing.xl),
                  AuthGradientButton(
                    label: 'Show results',
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      setState(() {
                        _statusSel
                          ..clear()
                          ..addAll(tmpStatus);
                        _paySel
                          ..clear()
                          ..addAll(tmpPay);
                        _from = tmpFrom;
                        _to = tmpTo;
                        _page = 0;
                      });
                      _reload();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static DateTime _defaultFrom() =>
      DateTime.now().subtract(const Duration(days: 29));

  /// True unless [from]–[to] is exactly the default "last 30 days" window.
  static bool _isDefaultRange(DateTime from, DateTime to) {
    final now = DateTime.now();
    final toToday =
        to.year == now.year && to.month == now.month && to.day == now.day;
    return toToday && from.difference(_defaultFrom()).inDays.abs() == 0;
  }

  bool get _dateChanged => !_isDefaultRange(_from, _to);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guest Bookings')),
      floatingActionButton: _loading || _loadError != null
          ? null
          : _NewBookingFab(
              onTap: () async {
                await Navigator.of(context).push<bool>(
                  AppPageRoute(builder: (_) => const GuestBookingScreen()),
                );
                _reload();
              },
            ),
      body: SafeArea(
        child: _loading
            ? const _GuestBookingsSkeleton()
            : _loadError != null && _rows == null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _reload,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OverviewCard(summary: _summary),
                      const SizedBox(height: AppSpacing.lg),
                      _searchAndFilter(),
                      const SizedBox(height: AppSpacing.lg),
                      _list(),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _searchAndFilter() {
    final tokens = context.tokens;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: _onSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search guest, phone, booking ID…',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Material(
          color: _hasFilters ? tokens.violet : tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openFilterSheet,
            child: Container(
              height: 48,
              width: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: _hasFilters ? tokens.violet : tokens.borderColor,
                ),
              ),
              child: Badge(
                isLabelVisible: _hasFilters,
                label: Text('${_statusSel.length + _paySel.length}'),
                child: Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: _hasFilters ? tokens.onPrimary : tokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _openEdit(String id) async {
    final changed = await Navigator.of(context).push<bool>(
      AppPageRoute(builder: (_) => GuestBookingEditScreen(bookingId: id)),
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

  PopupMenuItem<GuestBookingAction> _mi(
    GuestBookingAction v,
    String title,
    String sub,
  ) => PopupMenuItem(
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

  Future<bool> _confirm(
    String title,
    String body, {
    String confirm = 'Confirm',
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirm),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _delete(GuestBookingRow r) async {
    if (!await _confirm(
      'Delete booking',
      'Permanently delete ${r.code}? Bookings with a settled payment can\'t be deleted.',
      confirm: 'Delete',
    )) {
      return;
    }
    try {
      await ref.read(bookingRepositoryProvider).deleteGuestBooking(r.bookingId);
      _reload();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _cancel(GuestBookingRow r) async {
    final reason = TextEditingController();
    final amount = TextEditingController(
      text: r.amountMinor != null ? '${(r.amountMinor! / 100)}' : '',
    );
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
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
              if (r.paymentStatus == 'PAID') ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: refund,
                  onChanged: (v) => setSt(() => refund = v ?? false),
                  title: const Text('Issue a refund'),
                ),
                if (refund)
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Refund amount (₹)',
                    ),
                  ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel Booking'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (r.paymentStatus == 'PAID') {
        final total = r.amountMinor ?? 0;
        final pct = refund && total > 0
            ? ((double.tryParse(amount.text.trim()) ?? 0) * 100 * 100 / total)
                  .round()
                  .clamp(0, 100)
            : 0;
        await ref
            .read(refundRepositoryProvider)
            .cancelBooking(
              CancelBookingInput(
                bookingId: r.bookingId,
                reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
                refundOverridePercent: pct,
              ),
            );
      } else {
        await ref
            .read(bookingRepositoryProvider)
            .cancelBooking(
              r.bookingId,
              reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
            );
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
          decoration: const InputDecoration(
            labelText: 'Guest email',
            hintText: 'guest@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (send != true) return;
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email.text.trim())) {
      _toast('Enter a valid email address.');
      return;
    }
    try {
      await ref
          .read(bookingRepositoryProvider)
          .sendBookingReceipt(r.bookingId, email.text.trim());
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
              const Text(
                'Creates a new booking with the same guest, court and players.',
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: start,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (d == null || !ctx.mounted) return;
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(start),
                  );
                  if (t == null) return;
                  setSt(
                    () => start = DateTime(
                      d.year,
                      d.month,
                      d.day,
                      t.hour,
                      t.minute,
                    ),
                  );
                },
                child: Text(
                  '${Formatters.dateShort(start)} · ${Formatters.time12h(_hm(start))}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Duplicate'),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    try {
      final b = await ref
          .read(bookingRepositoryProvider)
          .duplicateGuestBooking(r.bookingId, start, start.add(duration));
      _reload();
      await _collectAndComplete(
        bookingId: b.id,
        amountMinor: b.amountMinor,
        alreadyPaid: false,
        label: '${r.sportName ?? "Court"} · ${r.courtName}',
        guestName: r.guestName,
        guestPhone: r.guestPhone,
        promptOnly: true,
      );
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
      if (!await _confirm(
        'Mark as Completed',
        'This booking is paid. Mark it completed?',
        confirm: 'Complete',
      )) {
        return;
      }
      try {
        await ref
            .read(bookingRepositoryProvider)
            .completeGuestBooking(bookingId);
        _reload();
      } on AppException catch (e) {
        _toast(e.message);
      }
      return;
    }

    final method = TextEditingController(text: 'Cash');
    final amount = TextEditingController(
      text: amountMinor != null ? '${(amountMinor / 100)}' : '',
    );
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
              for (final opt in const [
                ('offline', 'Payment collected offline'),
                ('online', 'Collect online (Razorpay)'),
              ])
                InkWell(
                  onTap: () => setSt(() => mode = opt.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          mode == opt.$1
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: mode == opt.$1
                              ? AppColors.primary
                              : AppColors.muted,
                        ),
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
                  items: const ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Other']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => method.text = v ?? 'Cash',
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(promptOnly ? 'Later' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, mode),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    try {
      if (choice == 'offline') {
        await ref
            .read(bookingRepositoryProvider)
            .recordGuestBookingPayment(
              bookingId,
              method.text.trim().isEmpty ? 'Cash' : method.text.trim(),
              ((double.tryParse(amount.text.trim()) ?? 0) * 100).round(),
            );
      } else {
        final result = await ref
            .read(paymentCheckoutControllerProvider)
            .startCheckout(
              CreatePaymentOrderInput(
                facilityId: facilityId,
                sourceType: PaymentSourceType.guestBooking,
                bookingId: bookingId,
              ),
              contactName: guestName,
              contactPhone: guestPhone,
            );
        if (result is CheckoutCancelled) return;
        if (result is! CheckoutSettled) {
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                content: PaymentStatusPanel(
                  state: result,
                  settledLabel: 'Payment received',
                  resourceLabel: 'booking',
                ),
              ),
            );
          }
          _reload();
          return;
        }
      }
      if (!promptOnly) {
        await ref
            .read(bookingRepositoryProvider)
            .completeGuestBooking(bookingId);
      }
      _reload();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  /// Offline payment for a released membership seat.
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
              items: const [
                'Cash',
                'UPI',
                'Card',
                'Bank Transfer',
                'Other',
              ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => method.text = v ?? 'Cash',
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount received (₹)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(bookingRepositoryProvider)
          .recordSessionGuestPayment(
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
      (
        'Guest',
        '${r.guestName}${r.guestPhone != null ? ' · ${r.guestPhone}' : ''}',
      ),
      ('Sport / Court', '${r.sportName ?? '—'} · ${r.courtName}'),
      ('Date', Formatters.dateShort(r.startTime)),
      (
        'Time',
        '${Formatters.time12h(_hm(r.startTime))} – ${Formatters.time12h(_hm(r.endTime))}',
      ),
      ('Players', '${r.partySize}'),
      (
        'Amount',
        r.amountMinor == null
            ? '—'
            : Formatters.currencyInr((r.amountMinor! / 100).round()),
      ),
      (
        'Payment',
        '${r.paymentStatus}${r.paymentMethod != null ? ' · ${r.paymentMethod}' : ''}',
      ),
      ('Status', r.status),
    ];
    final text = [
      'GameAll — Invoice',
      ...lines.map((e) => '${e.$1}: ${e.$2}'),
    ].join('\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invoice'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: lines
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${e.$1}: ${e.$2}'),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
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
      return const _BookingListSkeleton();
    }
    if (rows.isEmpty) {
      return const EmptyStateView(
        message: 'No guest bookings match these filters.',
      );
    }
    final totalPages = (_totalCount / _perPage).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 2),
          child: Row(
            children: [
              Text(
                _multiActive
                    ? '${rows.length} booking${rows.length == 1 ? '' : 's'}'
                    : '$_totalCount booking${_totalCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.calendar_today_rounded,
                size: 12,
                color: context.tokens.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${Formatters.dateShort(_from)} – ${Formatters.dateShort(_to)}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        ...rows.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _BookingCard(
              row: r,
              onTap: r.isSession ? null : () => _openEdit(r.bookingId),
              menu: _rowMenu(r),
              time12: _hm,
            ),
          ),
        ),
        if (!_multiActive && totalPages > 1)
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
              Text(
                'Page ${_page + 1} of $totalPages',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ───────────────────────────────────────────────────── overview hero ──

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.summary});

  final GuestBookingsSummary? summary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final s = summary;

    final green = tokens.primary;
    final blue = AppColors.electricBlue;
    final amber = tokens.warning;
    final red = tokens.destructive;

    final parts = s == null
        ? const <({Color color, String label, int value})>[]
        : [
            (color: green, label: 'Confirmed', value: s.confirmed),
            (color: blue, label: 'Completed', value: s.completed),
            (color: amber, label: 'Pending', value: s.pending),
            (color: red, label: 'Cancelled', value: s.cancelled),
          ];
    final barTotal = parts.fold<int>(0, (a, p) => a + p.value);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.borderColor),
          color: tokens.surface1,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_rounded, size: 16, color: green),
                  const SizedBox(width: 6),
                  Text(
                    'Bookings overview',
                    style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                  ),
                  const Spacer(),
                  if (s?.totalChangePct != null && s!.totalChangePct != 0)
                    _DeltaChip(pct: s.totalChangePct!),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    s == null ? '—' : '${s.total}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'total bookings',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (barTotal > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        for (final p in parts)
                          if (p.value > 0)
                            Expanded(
                              flex: p.value,
                              child: Container(color: p.color),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final p in parts)
                      _LegendDot(
                        color: p.color,
                        label: p.label,
                        value: p.value,
                      ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Divider(height: 1, color: tokens.borderColor),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revenue',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s == null
                            ? '—'
                            : Formatters.currencyInr(
                                (s.totalRevenueMinor / 100).round(),
                              ),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (s?.revenueChangePct != null && s!.revenueChangePct != 0)
                    _DeltaChip(pct: s.revenueChangePct!),
                ],
              ),
              if (s != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'Avg / booking',
                        value: Formatters.currencyInr(
                          (s.avgPerBookingMinor / 100).round(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _MiniStat(
                        label: 'Highest',
                        value: Formatters.currencyInr(
                          (s.highestBookingMinor / 100).round(),
                        ),
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

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ',
          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
        Text(
          '$value',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: tokens.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final up = pct >= 0;
    final c = up ? tokens.primary : tokens.destructive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: c,
          ),
          const SizedBox(width: 2),
          Text(
            '${pct.abs()}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── list card ──

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.row,
    required this.onTap,
    required this.menu,
    required this.time12,
  });

  final GuestBookingRow row;
  final VoidCallback? onTap;
  final Widget menu;
  final String Function(DateTime) time12;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final chip = _statusChip(row.status);
    final pay = _payChip(row.paymentStatus);
    final accent = switch (row.status) {
      'completed' => AppColors.electricBlue,
      'cancelled' => tokens.destructive,
      'pending' => tokens.warning,
      _ => tokens.primary,
    };
    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: tokens.borderColor),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${row.code} · ${row.guestName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    row.isSession
                                        ? 'Session seat · ${row.courtName}'
                                        : '${row.sportName ?? '—'} · ${row.courtName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(label: chip.label, tone: chip.tone),
                            menu,
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${Formatters.dateShort(row.startTime)} · ${Formatters.time12h(time12(row.startTime))} – ${Formatters.time12h(time12(row.endTime))} · ${row.partySize} players',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Text(
                              row.amountMinor == null
                                  ? '—'
                                  : Formatters.currencyInr(
                                      (row.amountMinor! / 100).round(),
                                    ),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            StatusBadge(label: pay.label, tone: pay.tone),
                            if (row.paymentMethod != null) ...[
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                row.paymentMethod!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
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

// ─────────────────────────────────────────────────── shared widgets ──

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.accentSolid(tokens.violet) : tokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected
                ? tokens.accentSolid(tokens.violet)
                : tokens.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(
                Icons.check_rounded,
                size: 14,
                color: tokens.onAccent(tokens.violet),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? tokens.onAccent(tokens.violet)
                    : tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewBookingFab extends StatelessWidget {
  const _NewBookingFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        color: tokens.accentSolid(tokens.primary),
        boxShadow: [
          BoxShadow(
            color: tokens.primary.withValues(alpha: 0.42),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 14,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: tokens.onAccent(tokens.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'New booking',
                  style: TextStyle(
                    color: tokens.onAccent(tokens.primary),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
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

// ───────────────────────────────────────────────────────── skeletons ──

/// Structure-shaped placeholder for the whole page — the overview stat
/// card, the search/filter row, then a few booking-card rows.
class _GuestBookingsSkeleton extends StatelessWidget {
  const _GuestBookingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeleton(width: 140, height: 13),
                SizedBox(height: AppSpacing.sm),
                AppSkeleton(width: 90, height: 30),
                SizedBox(height: AppSpacing.md),
                AppSkeleton(height: 10, radius: AppRadius.pill),
                SizedBox(height: AppSpacing.md),
                AppSkeleton(width: 200, height: 12),
                SizedBox(height: AppSpacing.md),
                AppSkeleton(width: 100, height: 12),
                SizedBox(height: 6),
                AppSkeleton(width: 140, height: 22),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: AppSkeleton(height: 48, radius: AppRadius.sm)),
              SizedBox(width: AppSpacing.sm),
              AppSkeleton(width: 48, height: 48, radius: AppRadius.md),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          _BookingListSkeleton(),
        ],
      ),
    );
  }
}

/// The booking-card list alone — reused for the list's own refresh region
/// so the shape doesn't change between the full-page gate and a re-filter.
class _BookingListSkeleton extends StatelessWidget {
  const _BookingListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
      ],
    );
  }
}
