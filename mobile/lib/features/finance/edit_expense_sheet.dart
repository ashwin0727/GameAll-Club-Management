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

/// Edit a RECORDED expense — mirrors the web's EditExpenseDialog. `update_
/// expense` (0069) rejects a total below what has already been paid, and
/// leaves any field passed null unchanged.
class EditExpenseSheet extends ConsumerStatefulWidget {
  const EditExpenseSheet({super.key, required this.expense});

  final ExpenseDetail expense;

  @override
  ConsumerState<EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends ConsumerState<EditExpenseSheet> {
  late final _amountController =
      TextEditingController(text: (widget.expense.amountMinor / 100).toStringAsFixed(2));
  late final _vendorController = TextEditingController(text: widget.expense.vendor ?? '');
  late final _referenceController = TextEditingController(text: widget.expense.reference ?? '');
  late final _notesController = TextEditingController(text: widget.expense.notes ?? '');

  late String _categoryId = widget.expense.categoryId;
  late DateTime _spentOn = DateTime.parse(widget.expense.spentOn);
  List<ExpenseCategory> _categories = [];

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final cats = await ref
            .read(financeRepositoryProvider)
            .listExpenseCategories(widget.expense.facilityId);
        if (mounted) setState(() => _categories = cats);
      } on AppException {
        // Editing other fields still works without the category list.
      }
    });
  }

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
    final minor = (rupees * 100).round();
    if (minor < widget.expense.amountPaidMinor) {
      setState(() => _error = 'The total cannot be less than what has already been paid.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(financeRepositoryProvider).updateExpense(
            expenseId: widget.expense.id,
            categoryId: _categoryId,
            amountMinor: minor,
            spentOn: DateFormat('yyyy-MM-dd').format(_spentOn),
            vendor: _vendorController.text.trim().isEmpty ? null : _vendorController.text.trim(),
            reference:
                _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
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
            Text('Edit expense', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            if (_categories.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Expense date'),
                      child: Text(DateFormat('d MMM yyyy').format(_spentOn)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _vendorController,
              decoration: const InputDecoration(labelText: 'Vendor / Payee (optional)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(labelText: 'Reference (optional)'),
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
              label: 'Save changes',
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
