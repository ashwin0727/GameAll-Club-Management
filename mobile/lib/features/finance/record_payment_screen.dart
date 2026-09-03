import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'finance_presentation.dart';
import 'money.dart';

/// Record Payment as its own page — mirrors
/// src/features/finance/components/record-payment-page.tsx.
///
/// Loads the obligation from its id rather than taking it from the list that
/// linked here, so the page survives a reload and shows the balance as it
/// stands now. Works the same for a guest booking, a court booking or a
/// membership (`record_obligation_payment`, 0052 + 0055).
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  static const _methods = ['Cash', 'UPI', 'Card', 'Bank Transfer'];

  /// One key per visit. A double-tap or retried request re-sends it, and the
  /// server returns the original payment rather than taking money twice.
  final String _idempotencyKey = const Uuid().v4();

  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  String _method = 'Cash';
  DateTime _paidOn = DateTime.now();

  PaymentObligation? _obligation;
  _LoadState _state = _LoadState.loading;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) {
      setState(() => _state = _LoadState.error);
      return;
    }
    try {
      final found = await ref
          .read(financeRepositoryProvider)
          .getPaymentObligation(facility.id, widget.sourceId);
      if (!mounted) return;
      if (found == null) {
        setState(() => _state = _LoadState.missing);
        return;
      }
      setState(() {
        _obligation = found;
        _amountController.text = toMajor(found.outstandingMinor).toString();
        _state = _LoadState.ready;
      });
    } on AppException {
      if (mounted) setState(() => _state = _LoadState.error);
    }
  }

  int get _amountMinor {
    final rupees = num.tryParse(_amountController.text.trim()) ?? 0;
    return (rupees * 100).round();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _paidOn = picked);
  }

  Future<void> _submit() async {
    final o = _obligation;
    if (o == null || _busy) return;
    final check = canRecordPayment(amountMinor: _amountMinor, outstandingMinor: o.outstandingMinor);
    if (check is RecordPaymentInvalid) {
      setState(() => _error = check.reason);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(financeRepositoryProvider).recordObligationPayment(
            sourceType: o.sourceType,
            sourceId: o.sourceId,
            amountMinor: _amountMinor,
            method: _method,
            idempotencyKey: _idempotencyKey,
            paidOn: DateFormat('yyyy-MM-dd').format(_paidOn),
            reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingView(message: 'Loading…');
      case _LoadState.error:
        return const ErrorView(message: 'Unable to load this record. Please try again.');
      case _LoadState.missing:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("We couldn't find that record", style: AppTypography.rowTitle(context)),
                const SizedBox(height: AppSpacing.xs),
                Text('It may have been cancelled or already settled.',
                    textAlign: TextAlign.center, style: AppTypography.secondary(context)),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        );
      case _LoadState.ready:
        return _form(_obligation!);
    }
  }

  Widget _form(PaymentObligation o) {
    final check = canRecordPayment(amountMinor: _amountMinor, outstandingMinor: o.outstandingMinor);
    final canSubmit = check is RecordPaymentOk && !_busy;
    final remaining = o.outstandingMinor - _amountMinor;
    final isBooking = o.sourceType != ObligationSource.membership;

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isBooking ? 'Booking Details' : 'Membership Details',
                    style: AppTypography.rowTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                _DetailRow(label: isBooking ? 'Booking ID' : 'Membership ID', value: o.reference),
                _DetailRow(label: 'Customer', value: o.customerName),
                if (o.customerPhone != null) _DetailRow(label: 'Phone', value: o.customerPhone!),
                if (o.facilityName != null) _DetailRow(label: 'Facility', value: o.facilityName!),
                _DetailRow(label: isBooking ? 'Court & Time' : 'Membership', value: o.description),
                _DetailRow(label: 'Source', value: o.sourceType.label),
                _DetailRow(label: 'Total amount', value: financeAmount(o.totalMinor)),
                if (o.paidMinor > 0)
                  _DetailRow(label: 'Already paid', value: financeAmount(o.paidMinor)),
                const Divider(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: Text('Amount Due', style: AppTypography.rowTitle(context))),
                    Text(
                      financeAmount(o.outstandingMinor),
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(label: o.status.label, tone: _tone(o.status)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (o.isSettled)
            AppCard(
              child: Column(
                children: [
                  Text('This is already paid in full', style: AppTypography.rowTitle(context)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('There is nothing left to collect against this record.',
                      textAlign: TextAlign.center, style: AppTypography.secondary(context)),
                ],
              ),
            )
          else
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Information', style: AppTypography.rowTitle(context)),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Amount (₹)'),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(labelText: 'Payment Mode'),
                    items: _methods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Payment Date'),
                      child: Text(DateFormat('d MMM yyyy').format(_paidOn)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _referenceController,
                    decoration: InputDecoration(
                      labelText: 'Reference',
                      hintText: _method == 'Cash' ? 'Receipt number (optional)' : 'UPI123456 (recommended)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                  if (check is RecordPaymentOk && _amountMinor < o.outstandingMinor) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: context.tokens.surface2,
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                      ),
                      child: Column(
                        children: [
                          Row(children: [
                            Expanded(child: Text('This payment', style: AppTypography.secondary(context))),
                            Text(financeAmount(_amountMinor)),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            Expanded(child: Text('Remaining after payment',
                                style: AppTypography.secondary(context))),
                            Text(financeAmount(remaining),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                  if (check is RecordPaymentInvalid && _amountController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(check.reason, style: const TextStyle(color: AppColors.destructive)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: const TextStyle(color: AppColors.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: check is RecordPaymentOk
                        ? 'Record Payment ${financeAmount(_amountMinor)}'
                        : 'Record Payment',
                    loadingLabel: 'Recording…',
                    isLoading: _busy,
                    onPressed: canSubmit ? _submit : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

enum _LoadState { loading, ready, missing, error }

StatusTone _tone(ObligationStatus status) {
  switch (status) {
    case ObligationStatus.overdue:
      return StatusTone.danger;
    case ObligationStatus.partiallyPaid:
      return StatusTone.warning;
    case ObligationStatus.paid:
      return StatusTone.success;
    case ObligationStatus.pending:
      return StatusTone.warning;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.secondary(context)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(value, textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
