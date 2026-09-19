import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/payment.dart';
import '../../data/models/refund.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import '../finance/finance_presentation.dart';

/// Owner-facing refund visibility (spec §13/§28/§29/§30) — mirrors
/// `refunds-panel.tsx`: open settlement exceptions (payment received,
/// business operation not confirmed — spec §16) with a one-click "Initiate
/// Refund", plus the facility's refund history. Every refund shown here is
/// server-authoritative — this screen never lets the owner type in a refund
/// amount for a settlement exception (the server always refunds the full
/// captured amount for those).
class RefundsScreen extends ConsumerStatefulWidget {
  const RefundsScreen({super.key});

  @override
  ConsumerState<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends ConsumerState<RefundsScreen> {
  bool _isLoading = true;
  String? _loadError;
  String? _facilityId;
  List<SettlementException> _exceptions = [];
  List<Refund> _refunds = [];
  String? _workingId;
  String? _actionError;

  /// Phase 7 filters (spec §"Refund Filters" / §"Exception Filters"),
  /// mirroring the dropdowns refunds-panel.tsx gained. All three are applied
  /// by `list_refunds`/`list_settlement_exceptions` themselves
  /// (0024_finance.sql) — never by filtering an already-fetched list here.
  /// `null` means "no filter" (the web's "ALL" option).
  SettlementExceptionStatus? _exceptionStatus = SettlementExceptionStatus.open;
  RefundStatus? _refundStatus;
  PaymentSourceType? _refundSource;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'No facility found for this account yet.';
      });
      return;
    }
    _facilityId = facility.id;
    await _load();
  }

  Future<void> _load() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(refundRepositoryProvider);
      final exceptions = await repo.listSettlementExceptions(
        facilityId,
        filters: SettlementExceptionListFilters(status: _exceptionStatus),
      );
      final refunds = await repo.listRefunds(
        facilityId,
        filters: RefundListFilters(status: _refundStatus, sourceType: _refundSource),
      );
      setState(() {
        _exceptions = exceptions;
        _refunds = refunds;
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _initiateRefund(String exceptionId) async {
    setState(() {
      _workingId = exceptionId;
      _actionError = null;
    });
    try {
      await ref.read(refundRepositoryProvider).initiateRefund(InitiateRefundInput(settlementExceptionId: exceptionId));
      await _load();
    } on AppException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  /// Every filter change refetches from the server rather than narrowing the
  /// list already in memory — the RPCs own the filtering (0024_finance.sql).
  Future<void> _pickExceptionStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _exceptionStatus?.toJson() ?? 'ALL',
      options: const [
        (value: 'OPEN', label: 'Open'),
        (value: 'RESOLVED', label: 'Resolved'),
        (value: 'ALL', label: 'All'),
      ],
    );
    if (picked == null) return;
    setState(() {
      _exceptionStatus = picked == 'ALL' ? null : SettlementExceptionStatus.fromJson(picked);
    });
    await _load();
  }

  Future<void> _pickRefundSource() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _refundSource?.toJson() ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Sources'),
        ...PaymentSourceType.values.map((s) => (value: s.toJson(), label: sourceTypeMenuLabel(s))),
      ],
    );
    if (picked == null) return;
    setState(() => _refundSource = picked == 'ALL' ? null : PaymentSourceType.fromJson(picked));
    await _load();
  }

  Future<void> _pickRefundStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _refundStatus?.toJson() ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Status'),
        (value: 'PROCESSING', label: 'Processing'),
        (value: 'PENDING', label: 'Pending'),
        (value: 'PROCESSED', label: 'Processed'),
        (value: 'FAILED', label: 'Failed'),
      ],
    );
    if (picked == null) return;
    setState(() => _refundStatus = picked == 'ALL' ? null : RefundStatus.fromJson(picked));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refunds', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: _isLoading
            ? const _RefundsSkeleton()
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Resolve payments that couldn't be confirmed, and track every refund.",
                        style: AppTypography.secondary(context),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_actionError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: tokens.destructive.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text(_actionError!,
                              style: TextStyle(color: tokens.destructive, fontSize: 13)),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _SectionHeader(
                        title: 'Payment Received, Not Confirmed',
                        color: tokens.warning,
                        trailing: PickerChip(
                          label: _exceptionStatusLabel(_exceptionStatus),
                          onSelect: _pickExceptionStatus,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_exceptions.isEmpty)
                        _EmptyRow(
                          icon: Icons.check_circle_outline_rounded,
                          color: tokens.success,
                          message: 'No open settlement exceptions.',
                        )
                      else
                        for (final ex in _exceptions) _ExceptionCard(
                          exception: ex,
                          isWorking: _workingId == ex.id,
                          sourceLabel: _sourceTypeLabel(ex.sourceType),
                          reasonLabel: _exceptionReasonLabel(ex.reason),
                          onInitiate: () => _initiateRefund(ex.id),
                        ),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionHeader(
                        title: 'Refund History',
                        color: tokens.primary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          PickerChip(
                            label: _refundSource == null ? 'All Sources' : sourceTypeMenuLabel(_refundSource!),
                            onSelect: _pickRefundSource,
                          ),
                          PickerChip(
                            label: _refundStatus == null ? 'All Status' : _refundStatusChipLabel(_refundStatus!),
                            onSelect: _pickRefundStatus,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_refunds.isEmpty)
                        _EmptyRow(
                          icon: Icons.receipt_long_outlined,
                          color: tokens.textSecondary,
                          message: 'No refunds yet.',
                        )
                      else
                        for (final r in _refunds) _RefundCard(
                          refund: r,
                          titleLabel:
                              '${_sourceTypeLabel(r.sourceType)} · ${Formatters.currencyInr((r.amountMinor / 100).round())}',
                          subtitleLabel: '${_refundReasonLabel(r.reason)} · ${Formatters.dateShort(r.createdAt)}'
                              '${r.policyPercentApplied != null ? ' · ${r.policyPercentApplied}% policy' : ''}',
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// A list-page section header — a coloured accent bar + bold title, the same
/// motif the dashboard uses for "Free slots left today" etc, so this screen
/// reads as part of the same app rather than a plainer, older one.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color, this.trailing});

  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.tokens.textPrimary)),
        ),
        ?trailing,
      ],
    );
  }
}

/// A quiet "nothing here" row for inline use between sections — lighter than
/// the full-page [EmptyStateView], but still an icon + message instead of a
/// bare line of grey text.
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

class _ExceptionCard extends StatelessWidget {
  const _ExceptionCard({
    required this.exception,
    required this.isWorking,
    required this.sourceLabel,
    required this.reasonLabel,
    required this.onInitiate,
  });

  final SettlementException exception;
  final bool isWorking;
  final String sourceLabel;
  final String reasonLabel;
  final VoidCallback onInitiate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface1,
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
                color: tokens.accentFill(tokens.warning),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(Icons.error_outline_rounded, size: 18, color: tokens.warning),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sourceLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$reasonLabel · ${Formatters.dateShort(exception.createdAt)}',
                      style: TextStyle(fontSize: 11.5, color: tokens.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _RefundButton(isWorking: isWorking, onPressed: onInitiate),
          ],
        ),
      ),
    );
  }
}

/// Small solid-green pill CTA — matches every other primary action in the
/// app (an outlined button here would read as secondary, but resolving an
/// exception is the whole point of this card).
class _RefundButton extends StatelessWidget {
  const _RefundButton({required this.isWorking, required this.onPressed});

  final bool isWorking;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.primary,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isWorking ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
          child: isWorking
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: tokens.onAccent(tokens.primary)),
                )
              : Text('Initiate Refund',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.onAccent(tokens.primary))),
        ),
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.refund, required this.titleLabel, required this.subtitleLabel});

  final Refund refund;
  final String titleLabel;
  final String subtitleLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tone = _refundStatusTone(refund.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface1,
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
                color: tokens.accentFill(_toneColor(tokens, tone)),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(Icons.currency_exchange_rounded, size: 17, color: _toneColor(tokens, tone)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitleLabel, style: TextStyle(fontSize: 11.5, color: tokens.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(label: _refundStatusLabel(refund.status), tone: tone),
          ],
        ),
      ),
    );
  }
}

Color _toneColor(AppColorTokens tokens, StatusTone tone) => switch (tone) {
      StatusTone.success => tokens.success,
      StatusTone.warning => tokens.warning,
      StatusTone.danger => tokens.destructive,
      StatusTone.info => tokens.info,
      StatusTone.neutral => tokens.textSecondary,
    };

String _sourceTypeLabel(PaymentSourceType sourceType) => sourceType.toJson().replaceAll('_', ' ');

String _exceptionReasonLabel(SettlementExceptionReason reason) {
  switch (reason) {
    case SettlementExceptionReason.bookingNoLongerAvailable:
      return 'booking no longer available';
    case SettlementExceptionReason.guestCapacityExhausted:
      return 'guest capacity exhausted';
    case SettlementExceptionReason.membershipInvalid:
      return 'membership invalid';
    case SettlementExceptionReason.businessValidationFailed:
      return 'business validation failed';
    case SettlementExceptionReason.databaseSettlementFailure:
      return 'database settlement failure';
  }
}

String _refundReasonLabel(RefundReason reason) => reason.toJson().replaceAll('_', ' ').toLowerCase();

String _refundStatusLabel(RefundStatus status) => status.toJson().toLowerCase();

/// Title-cased variants for the Phase 7 filter chips ("Processed", "Open") —
/// the badges keep their existing lowercase styling.
String _titleCase(String raw) => raw[0] + raw.substring(1).toLowerCase();

String _refundStatusChipLabel(RefundStatus status) => _titleCase(status.toJson());

/// `null` is the web's "ALL" option — no status filter at all.
String _exceptionStatusLabel(SettlementExceptionStatus? status) =>
    status == null ? 'All' : _titleCase(status.toJson());

StatusTone _refundStatusTone(RefundStatus status) {
  switch (status) {
    case RefundStatus.processed:
      return StatusTone.success;
    case RefundStatus.failed:
    case RefundStatus.cancelled:
      return StatusTone.danger;
    case RefundStatus.requested:
    case RefundStatus.processing:
    case RefundStatus.pending:
      return StatusTone.warning;
  }
}

class _RefundsSkeleton extends StatelessWidget {
  const _RefundsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          AppSkeleton(width: 260, height: 13),
          SizedBox(height: AppSpacing.lg),
          AppSkeleton(width: 220, height: 15),
          SizedBox(height: AppSpacing.md),
          SkeletonListRow(trailing: false),
          SizedBox(height: AppSpacing.sm),
          SkeletonListRow(trailing: false),
          SizedBox(height: AppSpacing.xl),
          AppSkeleton(width: 140, height: 15),
          SizedBox(height: AppSpacing.md),
          SkeletonChipRow(count: 2),
          SizedBox(height: AppSpacing.md),
          SkeletonListRow(),
          SizedBox(height: AppSpacing.sm),
          SkeletonListRow(),
          SizedBox(height: AppSpacing.sm),
          SkeletonListRow(),
        ],
      ),
    );
  }
}
