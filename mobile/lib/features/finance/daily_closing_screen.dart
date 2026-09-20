import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import '../authentication/session_controller.dart';
import '../reports/report_section_header.dart';
import '../../shared/widgets/skeleton.dart';
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
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Closing', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: _loading
            ? const _DailyClosingSkeleton()
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        _labeled(
                          'Business date',
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg, vertical: 14),
                              decoration: BoxDecoration(
                                color: tokens.surface2,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(color: tokens.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(Formatters.dateShort(_date),
                                        style: TextStyle(color: tokens.textPrimary)),
                                  ),
                                  Icon(Icons.calendar_today_outlined,
                                      size: 18, color: tokens.textSecondary),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_summary != null) ..._sections(_summary!),
                        const SizedBox(height: AppSpacing.xl),
                        const ReportSectionHeader(title: 'Recent closings'),
                        const SizedBox(height: AppSpacing.sm),
                        if (_history.isEmpty)
                          _EmptyRow(
                            icon: Icons.event_note_outlined,
                            color: tokens.textSecondary,
                            message: 'No closings recorded this month.',
                          )
                        else
                          ..._history.map(_historyRow),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _labeled(String label, {required Widget child}) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: tokens.textSecondary)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _sectionCard({required Widget child}) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.borderColor),
      ),
      child: child,
    );
  }

  Widget _sectionHeading(String title, IconData icon, Color accent, {Widget? trailing}) {
    final tokens = context.tokens;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.accentFill(accent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
        ),
        ?trailing,
      ],
    );
  }

  List<Widget> _sections(DailyClosingSummary s) {
    final tokens = context.tokens;
    final notStarted = s.status == DailyClosingStatus.notStarted;
    final closed = s.status == DailyClosingStatus.closed;
    final previewActual = num.tryParse(_actualController.text.trim());
    final previewVariance =
        previewActual != null ? (previewActual * 100).round() - s.expectedCashMinor : null;
    final statusColor = _toneColor(context, _tone(s.status));

    return [
      _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading("Today's collections", Icons.payments_outlined, tokens.primary),
            const SizedBox(height: AppSpacing.sm),
            _amountRow('Cash', s.cashCollectedMinor),
            _amountRow('UPI', s.upiCollectedMinor),
            _amountRow('Card', s.cardCollectedMinor),
            _amountRow('Online', s.onlineCollectedMinor),
            _amountRow('Bank transfer', s.bankTransferCollectedMinor),
            _amountRow('Other', s.otherCollectedMinor),
            Divider(color: tokens.borderColor),
            _amountRow('Total collected', s.totalCollectedMinor, bold: true),
            const SizedBox(height: AppSpacing.lg),
            _sectionHeading("Today's expenses", Icons.receipt_long_outlined, tokens.destructive),
            const SizedBox(height: AppSpacing.sm),
            _amountRow('Cash expenses', s.cashExpenseMinor),
            _amountRow('Other expenses', s.otherExpenseMinor),
            Divider(color: tokens.borderColor),
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
      _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeading('Cash reconciliation', Icons.point_of_sale_outlined, statusColor,
                trailing: StatusBadge(label: s.status.name, tone: _tone(s.status))),
            const SizedBox(height: AppSpacing.md),
            if (notStarted) ...[
              Text('The day for ${Formatters.dateShort(DateTime.parse(s.closingDate))} has not been opened yet.',
                  style: AppTypography.secondary(context)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _openingController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: 'Opening cash float (₹)',
                  hintText: (s.openingCashMinor / 100).toStringAsFixed(2),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AuthGradientButton(
                label: 'Open day',
                loadingLabel: 'Opening…',
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
              Divider(color: tokens.borderColor),
              _amountRow('Expected cash', s.expectedCashMinor, bold: true),
              const SizedBox(height: AppSpacing.md),
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
                      ? tokens.destructive
                      : ((previewVariance ?? s.varianceMinor ?? 0) > 0 ? tokens.warning : null),
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
                AuthGradientButton(
                  label: 'Complete closing',
                  loadingLabel: 'Closing…',
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

  Color _toneColor(BuildContext context, StatusTone tone) {
    final tokens = context.tokens;
    return switch (tone) {
      StatusTone.success => tokens.success,
      StatusTone.warning => tokens.warning,
      StatusTone.danger => tokens.destructive,
      StatusTone.info => tokens.info,
      StatusTone.neutral => tokens.textSecondary,
    };
  }

  Widget _historyRow(DailyClosingRow h) {
    final tokens = context.tokens;
    final color = _toneColor(context, _tone(h.status));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() => _date = DateTime.parse(h.closingDate));
            _load();
          },
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: tokens.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentFill(color),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.point_of_sale_outlined, size: 17, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
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
                            color: h.varianceMinor! < 0 ? tokens.destructive : tokens.warning,
                          )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder shown while the closing summary and recent
/// closings load — mirrors the business-date field, the two section cards,
/// and the recent-closings list.
class _DailyClosingSkeleton extends StatelessWidget {
  const _DailyClosingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        AppSkeleton(height: 48, radius: AppRadius.md),
        SizedBox(height: AppSpacing.md),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 160, height: 16),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(width: 120, height: 13),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 180, height: 16),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(width: 140, height: 13),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.xl),
        AppSkeleton(width: 140, height: 16),
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

/// A quiet "nothing here" row — an icon + message instead of a bare line of
/// grey text, matching the rest of the app's list screens.
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.icon, required this.color, required this.message});

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: tokens.textSecondary)),
          ),
        ],
      ),
    );
  }
}
