import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/payment.dart';
import '../../data/models/refund.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';

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
      final exceptions = await repo.listSettlementExceptions(facilityId, status: 'OPEN');
      final refunds = await repo.listRefunds(facilityId);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Refunds')),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading refunds…')
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
                        Text(_actionError!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      Text('Payment Received, Not Confirmed', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      if (_exceptions.isEmpty)
                        Text('No open settlement exceptions.', style: AppTypography.secondary(context))
                      else
                        ..._exceptions.map(_buildExceptionCard),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Refund History', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      if (_refunds.isEmpty)
                        Text('No refunds yet.', style: AppTypography.secondary(context))
                      else
                        ..._refunds.map(_buildRefundCard),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildExceptionCard(SettlementException ex) {
    final isWorking = _workingId == ex.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_sourceTypeLabel(ex.sourceType), style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '${_exceptionReasonLabel(ex.reason)} · ${Formatters.dateShort(ex.createdAt)}',
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: isWorking ? null : () => _initiateRefund(ex.id),
              child: Text(isWorking ? 'Refunding…' : 'Initiate Refund'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundCard(Refund r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_sourceTypeLabel(r.sourceType)} · ${Formatters.currencyInr((r.amountMinor / 100).round())}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${_refundReasonLabel(r.reason)} · ${Formatters.dateShort(r.createdAt)}'
                    '${r.policyPercentApplied != null ? ' · ${r.policyPercentApplied}% policy' : ''}',
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
            StatusBadge(label: _refundStatusLabel(r.status), tone: _refundStatusTone(r.status)),
          ],
        ),
      ),
    );
  }
}

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