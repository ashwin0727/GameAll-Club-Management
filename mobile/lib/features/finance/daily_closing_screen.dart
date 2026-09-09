import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'finance_presentation.dart';

/// Finance → Daily Closing — mirrors
/// src/features/finance/components/daily-closing-page.tsx.
///
/// A closing records the opening float, the counted drawer and why they
/// differ. Every collection / expense figure is re-derived server-side
/// (`get_daily_closing_summary`, 0070); `close_daily_closing` recomputes
/// expected cash itself and never trusts the number this screen shows.
class DailyClosingScreen extends ConsumerStatefulWidget {
  const DailyClosingScreen({super.key});

  @override
  ConsumerState<DailyClosingScreen> createState() => _DailyClosingScreenState();
}

class _DailyClosingScreenState extends ConsumerState<DailyClosingScreen> {
  static final _iso = DateFormat('yyyy-MM-dd');

  String? _facilityId;
  DateTime _date = DateTime.now();

  DailyClosingSummary? _summary;
  List<DailyClosingRow> _history = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _openingController = TextEditingController();
  final _actualController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _facilityId = ref.read(sessionControllerProvider).facility?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _openingController.dispose();
    _actualController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final facilityId = _facilityId;
    if (facilityId == null) {
      setState(() {
        _loading = false;
        _error = 'No facility found for this account yet.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final results = await Future.wait([
        repo.getDailyClosingSummary(facilityId, date: _iso.format(_date)),
        repo.listDailyClosings(
          facilityId,
          const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth),
        ),
      ]);
      if (!mounted) return;
      final s = results[0] as DailyClosingSummary;
      setState(() {
        _summary = s;
        _history = (results[1] as DailyClosingHistoryPage).closings;
        _actualController.text =
            s.actualCashMinor != null ? (s.actualCashMinor! / 100).toStringAsFixed(2) : '';
        _reasonController.text = s.varianceReason ?? '';
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  Future<void> _reopenDialog(String closingId) async {
    _reasonController.text = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen this day'),
        content: TextField(
          controller: _reasonController,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Reason (audited)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, _reasonController.text.trim()),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) {
      await _run(() => ref.read(financeRepositoryProvider).reopenDailyClosing(closingId, reason));
    }
  }

  StatusTone _tone(DailyClosingStatus s) => switch (s) {
        DailyClosingStatus.closed => StatusTone.success,
        DailyClosingStatus.open || DailyClosingStatus.reopened => StatusTone.warning,
        DailyClosingStatus.notStarted => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Closing')),
      body: SafeArea(
        child: _loading
            ? const LoadingView(message: 'Loading…')
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Business date'),
                            child: Text(Formatters.dateShort(_date)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_summary != null) ..._sections(_summary!),
                        const SizedBox(height: AppSpacing.xl),
                        Text('Recent closings', style: AppTypography.rowTitle(context)),
                        const SizedBox(height: AppSpacing.sm),
                        if (_history.isEmpty)
                          Text('No closings recorded this month.',
                              style: AppTypography.secondary(context))
                        else
                          ..._history.map(_historyRow),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
      ),
    );
  }

  List<Widget> _sections(DailyClosingSummary s) {
    final notStarted = s.status == DailyClosingStatus.notStarted;
    final closed = s.status == DailyClosingStatus.closed;
    final previewActual = num.tryParse(_actualController.text.trim());
    final previewVariance =
        previewActual != null ? (previewActual * 100).round() - s.expectedCashMinor : null;

    return [
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's collections", style: AppTypography.rowTitle(context)),
            const SizedBox(height: AppSpacing.sm),
            _amountRow('Cash', s.cashCollectedMinor),
            _amountRow('UPI', s.upiCollectedMinor),
            _amountRow('Card', s.cardCollectedMinor),
            _amountRow('Online', s.onlineCollectedMinor),
            _amountRow('Bank transfer', s.bankTransferCollectedMinor),
            _amountRow('Other', s.otherCollectedMinor),
            const Divider(),
            _amountRow('Total collected', s.totalCollectedMinor, bold: true),
            const SizedBox(height: AppSpacing.md),
            Text("Today's expenses", style: AppTypography.rowTitle(context)),
            const SizedBox(height: AppSpacing.sm),
            _amountRow('Cash expenses', s.cashExpenseMinor),
            _amountRow('Other expenses', s.otherExpenseMinor),
            const Divider(),
            _amountRow('Total expenses', s.totalExpenseMinor, bold: true),
            if (s.pendingPaymentCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('${s.pendingPaymentCount} booking(s) on this date are still unpaid.',
                  style: AppTypography.caption(context)),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Cash reconciliation', style: AppTypography.rowTitle(context))),
                StatusBadge(label: s.status.name, tone: _tone(s.status)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (notStarted) ...[
              Text('The day for ${Formatters.dateShort(DateTime.parse(s.closingDate))} has not been opened yet.',
                  style: AppTypography.secondary(context)),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _openingController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: 'Opening cash float (₹)',
                  hintText: (s.openingCashMinor / 100).toStringAsFixed(2),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: 'Open day',
                isLoading: _busy,
                onPressed: _busy
                    ? null
                    : () => _run(() {
                          final v = num.tryParse(_openingController.text.trim());
                          return ref.read(financeRepositoryProvider).openDailyClosing(
                                _facilityId!,
                                date: s.closingDate,
                                openingCashMinor: v != null ? (v * 100).round() : null,
                              );
                        }),
              ),
            ] else ...[
              _amountRow('Opening cash', s.openingCashMinor),
              _amountRow('Cash collections', s.cashCollectedMinor),
              _amountRow('Cash expenses', -s.cashExpenseMinor),
              const Divider(),
              _amountRow('Expected cash', s.expectedCashMinor, bold: true),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _actualController,
                enabled: !closed,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Actual cash counted (₹)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              if ((previewVariance ?? s.varianceMinor) != null)
                _amountRow(
                  'Variance',
                  previewVariance ?? s.varianceMinor ?? 0,
                  bold: true,
                  tone: (previewVariance ?? s.varianceMinor ?? 0) < 0
                      ? AppColors.destructive
                      : ((previewVariance ?? s.varianceMinor ?? 0) > 0 ? AppColors.warning : null),
                ),
              if (!closed && previewVariance != null && previewVariance != 0) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Variance reason',
                    hintText: 'e.g. cash shortage, expense not recorded…',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (closed) ...[
                if (s.varianceReason != null)
                  Text('Reason: ${s.varianceReason}', style: AppTypography.caption(context)),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'Reopen day',
                  onPressed: _busy ? null : () => _reopenDialog(s.closingId!),
                ),
              ] else
                PrimaryButton(
                  label: 'Complete closing',
                  isLoading: _busy,
                  onPressed: (_busy || _actualController.text.trim().isEmpty)
                      ? null
                      : () => _run(() {
                            final v = num.parse(_actualController.text.trim());
                            return ref.read(financeRepositoryProvider).closeDailyClosing(
                                  s.closingId!,
                                  (v * 100).round(),
                                  varianceReason: _reasonController.text.trim().isEmpty
                                      ? null
                                      : _reasonController.text.trim(),
                                );
                          }),
                ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _amountRow(String label, int minor, {bool bold = false, Color? tone}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: tone,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: bold ? style : AppTypography.secondary(context))),
          Text(financeAmount(minor), style: style),
        ],
      ),
    );
  }

  Widget _historyRow(DailyClosingRow h) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          setState(() => _date = DateTime.parse(h.closingDate));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Formatters.dateShort(DateTime.parse(h.closingDate)),
                        style: AppTypography.rowTitle(context)),
                    Text(
                      'Expected ${h.expectedCashMinor != null ? financeAmount(h.expectedCashMinor!) : '—'} · '
                      'Actual ${h.actualCashMinor != null ? financeAmount(h.actualCashMinor!) : '—'}',
                      style: AppTypography.caption(context),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(label: h.status.name, tone: _tone(h.status)),
                  if (h.varianceMinor != null && h.varianceMinor != 0)
                    Text(financeAmount(h.varianceMinor!),
                        style: TextStyle(
                          fontSize: 12,
                          color: h.varianceMinor! < 0 ? AppColors.destructive : AppColors.warning,
                        )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
