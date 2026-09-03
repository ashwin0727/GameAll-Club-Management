import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'finance_presentation.dart';

/// Finance → Transaction Details — mirrors
/// src/features/finance/components/transaction-details-page.tsx.
///
/// One transaction in full, plus every payment made against the same booking
/// or membership. The receipt is a real PDF built server-side by the
/// download-transaction-receipt edge function; this screen only asks for the
/// bytes and hands them to the OS share sheet.
class TransactionDetailsScreen extends ConsumerStatefulWidget {
  const TransactionDetailsScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailsScreen> createState() => _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends ConsumerState<TransactionDetailsScreen> {
  TransactionDetails? _details;
  _State _state = _State.loading;
  bool _downloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final found = await ref
          .read(financeRepositoryProvider)
          .getTransactionDetails(widget.transactionId);
      if (!mounted) return;
      setState(() {
        _details = found;
        _state = _State.ready;
      });
    } on AppException {
      if (mounted) setState(() => _state = _State.error);
    }
  }

  Future<void> _downloadReceipt() async {
    final details = _details;
    if (details == null || _downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final bytes = await ref
          .read(financeRepositoryProvider)
          .downloadTransactionReceipt(details.id);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt-${details.reference}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
      );
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not download the receipt. Please try again.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          if (_state == _State.ready)
            TextButton.icon(
              onPressed: _downloading ? null : _downloadReceipt,
              icon: const Icon(Icons.download, size: 18),
              label: Text(_downloading ? 'Preparing…' : 'Receipt'),
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_state) {
      case _State.loading:
        return const LoadingView(message: 'Loading…');
      case _State.error:
        return const ErrorView(
          message: "We couldn't find that transaction. It may have been removed, "
              'or belong to another facility.',
        );
      case _State.ready:
        return _content(_details!);
    }
  }

  Widget _content(TransactionDetails d) {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transaction Information', style: AppTypography.rowTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                _Row(label: 'Transaction ID', value: d.reference),
                _Row(label: 'Type', value: 'Income'),
                _Row(label: 'Category', value: d.category),
                _Row(label: 'Amount', value: financeAmount(d.amountMinor)),
                _Row(label: 'Payment Mode', value: d.paymentMethod ?? '—'),
                _Row(label: 'Status', value: _statusLabel(d.status), tone: _statusTone(d.status)),
                _Row(label: 'Transaction Date', value: Formatters.dateTimeShort(d.occurredAt)),
                _Row(label: 'Reference', value: d.sourceReference ?? '—'),
                _Row(label: 'Description', value: d.description),
                _Row(label: 'Recorded By', value: d.recordedBy ?? '—'),
                _Row(label: 'Created At', value: Formatters.dateTimeShort(d.createdAt)),
                if (d.refundedMinor > 0) ...[
                  _Row(label: 'Refunded', value: financeAmount(d.refundedMinor)),
                  _Row(label: 'Net', value: financeAmount(d.netMinor)),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Related Information', style: AppTypography.rowTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (d.bookingId != null)
                  _Row(label: 'Booking', value: d.sourceReference ?? 'Booking'),
                if (d.membershipId != null)
                  _Row(label: 'Membership', value: d.sourceReference ?? 'Membership'),
                _Row(label: 'Customer', value: d.customerName ?? '—'),
                if (d.customerPhone != null) _Row(label: 'Phone', value: d.customerPhone!),
                _Row(label: 'Facility', value: d.facilityName ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment History', style: AppTypography.rowTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (d.history.isEmpty)
                  Text('No payments recorded.', style: AppTypography.secondary(context))
                else
                  ...d.history.map((h) => _HistoryRow(row: h)),
                if (d.history.length > 1) ...[
                  const Divider(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Total collected', style: AppTypography.secondary(context)),
                      ),
                      Text(
                        // Display sum of the server's own per-payment figures —
                        // the same "total collected" the web page and the PDF
                        // show; never a headline revenue figure.
                        financeAmount(
                          d.history.fold<int>(0, (sum, h) => sum + h.amountMinor),
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

enum _State { loading, ready, error }

String _statusLabel(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

StatusTone _statusTone(String status) {
  switch (status) {
    case 'paid':
      return StatusTone.success;
    case 'failed':
      return StatusTone.danger;
    case 'refunded':
      return StatusTone.neutral;
    default:
      return StatusTone.warning;
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label, style: AppTypography.secondary(context)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: tone != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: StatusBadge(label: value, tone: tone!),
                  )
                : Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});

  final TransactionPaymentHistoryRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: row.isThisOne ? AppColors.primary.withValues(alpha: 0.08) : context.tokens.surface2,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Formatters.dateTimeShort(row.paidAt), style: AppTypography.caption(context)),
                Text(
                  '${row.paymentMethod ?? '—'}${row.reference != null ? ' · ${row.reference}' : ''}',
                  style: AppTypography.caption(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(financeAmount(row.amountMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
