import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';

/// Records a manual stock movement — mirrors
/// src/features/inventory/components/record-movement-dialog.tsx.
///
/// Does the one rupee→minor-unit conversion for the optional unit cost; the
/// repository takes an already-minor amount and never does money arithmetic.
/// Returns `true` via `Navigator.pop` when a movement was saved.
class StockMovementSheet extends ConsumerStatefulWidget {
  const StockMovementSheet({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.currentStock,
    required this.type,
  });

  final String itemId;
  final String itemName;
  final String unit;
  final int currentStock;

  /// One of stockIn / stockOut / adjustment.
  final MovementType type;

  @override
  ConsumerState<StockMovementSheet> createState() => _StockMovementSheetState();
}

class _StockMovementSheetState extends ConsumerState<StockMovementSheet> {
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  final _costController = TextEditingController();

  bool _saving = false;
  String? _error;

  bool get _isAdjustment => widget.type == MovementType.adjustment;
  bool get _isIn => widget.type == MovementType.stockIn;

  String get _title => switch (widget.type) {
        MovementType.stockIn => 'Record Stock In',
        MovementType.stockOut => 'Record Stock Out',
        MovementType.adjustment => 'Adjust Stock',
        _ => 'Record Movement',
      };

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = num.tryParse(_qtyController.text.trim());
    if (n == null || n <= 0) {
      setState(() => _error = 'Enter a quantity greater than zero.');
      return;
    }
    if (_isAdjustment && _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'An adjustment needs a reason.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final int quantity = _isAdjustment
          ? n.toInt() - widget.currentStock // delta to the counted total
          : widget.type == MovementType.stockOut
              ? -n.toInt()
              : n.toInt();
      final cost = num.tryParse(_costController.text.trim());
      await ref.read(inventoryRepositoryProvider).recordMovement(
            itemId: widget.itemId,
            type: widget.type,
            quantity: quantity,
            reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            unitCostMinor: (_isIn && cost != null && cost > 0) ? (cost * 100).round() : null,
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
            Text(_title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.itemName} · ${widget.currentStock} ${widget.unit} in stock',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: _isAdjustment ? 'Counted quantity (${widget.unit})' : 'Quantity (${widget.unit})',
              ),
            ),
            if (_isIn) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(
                  labelText: 'Unit cost (₹, optional)',
                  hintText: 'Updates the weighted-average cost',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(labelText: _isAdjustment ? 'Reason' : 'Reason (optional)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: context.tokens.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', loadingLabel: 'Saving…', isLoading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
