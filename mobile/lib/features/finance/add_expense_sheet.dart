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

/// Records an expense — mirrors src/features/finance/components/add-expense-dialog.tsx.
///
/// Income is never entered here: it always arrives as a payment against a
/// booking or membership, which is what keeps the ledger traceable. This sheet
/// does the one rupee→minor-unit conversion (the repository takes an already
/// minor-unit amount and never does money arithmetic itself).
///
/// Returns `true` via `Navigator.pop` when an expense was saved, so the caller
/// can refresh; `null` if dismissed.
class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key, required this.facilityId, required this.categories});

  final String facilityId;
  final List<ExpenseCategory> categories;

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  static const _methods = ['Cash', 'UPI', 'Card', 'Bank Transfer'];

  final _amountController = TextEditingController();
  final _vendorController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  late String? _categoryId = widget.categories.isNotEmpty ? widget.categories.first.id : null;
  String _method = 'Cash';
  DateTime _spentOn = DateTime.now();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _vendorController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _spentOn,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _spentOn = picked);
  }

  Future<void> _save() async {
    final rupees = num.tryParse(_amountController.text.trim());
    if (rupees == null || rupees <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    final categoryId = _categoryId;
    if (categoryId == null) {
      setState(() => _error = 'Choose a category.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(financeRepositoryProvider).createExpense(
            facilityId: widget.facilityId,
            categoryId: categoryId,
            // Stored in minor units, like every other amount in the ledger.
            amountMinor: (rupees * 100).round(),
            spentOn: DateFormat('yyyy-MM-dd').format(_spentOn),
            paymentMethod: _method,
            vendor: _vendorController.text.trim().isEmpty ? null : _vendorController.text.trim(),
            reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
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
            Text('Add expense', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Money the facility spent. Income is recorded against its booking or membership, not here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Amount (₹)', hintText: '0'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date'),
                      child: Text(DateFormat('d MMM yyyy').format(_spentOn)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Payment mode', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
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
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _vendorController,
              decoration: const InputDecoration(labelText: 'Vendor (optional)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(labelText: 'Reference (optional)', hintText: 'INV-1023'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Save expense',
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
