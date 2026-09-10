import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import 'finance_presentation.dart';

/// Settle all or part of an unpaid expense — mirrors the web's
/// mark-expense-paid-dialog.tsx. The server (`record_expense_payment`, 0069)
/// revalidates the outstanding balance; the [_idempotencyKey] makes a
/// double-submit safe. This sheet does the one rupee→minor conversion.
///
/// Returns `true` via `Navigator.pop` when a payment was recorded.
class MarkExpensePaidSheet extends ConsumerStatefulWidget {
  const MarkExpensePaidSheet({super.key, required this.expense});

  final ExpenseRow expense;

  @override
  ConsumerState<MarkExpensePaidSheet> createState() => _MarkExpensePaidSheetState();
}

class _MarkExpensePaidSheetState extends ConsumerState<MarkExpensePaidSheet> {
  static const _methods = ['Cash', 'UPI', 'Card', 'Bank Transfer'];

  late final TextEditingController _amountController =
      TextEditingController(text: (widget.expense.outstandingMinor / 100).toStringAsFixed(2));
  late String _method = widget.expense.paymentMethod ?? 'Cash';
  DateTime _paidOn = DateTime.now();
  final String _idempotencyKey = DateTime.now().microsecondsSinceEpoch.toString();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
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

  Future<void> _save() async {
    final rupees = num.tryParse(_amountController.text.trim());
    final outstanding = widget.expense.outstandingMinor;
    if (rupees == null || rupees <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    final minor = (rupees * 100).round();
    if (minor > outstanding) {
      setState(() => _error = 'That is more than the ${financeAmount(outstanding)} outstanding.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(financeRepositoryProvider).recordExpensePayment(
            expenseId: widget.expense.id,
            amountMinor: minor,
            paidOn: DateFormat('yyyy-MM-dd').format(_paidOn),
            paymentMethod: _method,
            idempotencyKey: _idempotencyKey,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Record expense payment', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.expense.vendor ?? widget.expense.categoryName} · '
              '${financeAmount(widget.expense.outstandingMinor)} outstanding',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Paid on'),
                child: Text(DateFormat('d MMM yyyy').format(_paidOn)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Method', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _methods
                  .map((m) => ChoiceChip(
                        label: Text(m),
                        selected: _method == m,
                        onSelected: (_) => setState(() => _method = m),
                      ))
                  .toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Record payment',
              loadingLabel: 'Saving…',
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
