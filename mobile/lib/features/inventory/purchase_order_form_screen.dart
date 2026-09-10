import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';

/// Create a draft purchase order — mirrors the web's PO wizard. A single
/// scrolling form on mobile; the PO is created as DRAFT and placed from its
/// detail screen.
class PurchaseOrderFormScreen extends ConsumerStatefulWidget {
  const PurchaseOrderFormScreen({super.key});

  @override
  ConsumerState<PurchaseOrderFormScreen> createState() => _PurchaseOrderFormScreenState();
}

class _PoLine {
  _PoLine();
  String? itemId;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();
  final tax = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0');

  void dispose() {
    qty.dispose();
    cost.dispose();
    tax.dispose();
    discount.dispose();
  }

  int get lineMinor {
    final q = int.tryParse(qty.text.trim()) ?? 0;
    final c = num.tryParse(cost.text.trim()) ?? 0;
    final t = num.tryParse(tax.text.trim()) ?? 0;
    final d = num.tryParse(discount.text.trim()) ?? 0;
    return (q * (c * 100).round()) + (t * 100).round() - (d * 100).round();
  }
}

class _PurchaseOrderFormScreenState extends ConsumerState<PurchaseOrderFormScreen> {
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String? _vendorId;
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDelivery;

  List<VendorRow> _vendors = const [];
  List<ItemRow> _items = const [];
  final List<_PoLine> _lines = [_PoLine()];
  bool _loadingRefs = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRefs());
  }

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRefs() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final vendors = await repo.listVendors(facilityId: fid, status: VendorStatus.active, limit: 200);
      final items = await repo.listItems(facilityId: fid, status: ItemStatus.active, limit: 500);
      if (mounted) {
        setState(() {
          _vendors = vendors.vendors;
          _items = items.items;
          _loadingRefs = false;
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() { _error = e.message; _loadingRefs = false; });
    }
  }

  int get _totalMinor => _lines.fold(0, (sum, l) => sum + (l.itemId == null ? 0 : l.lineMinor));

  Future<void> _save() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    if (_vendorId == null) {
      setState(() => _error = 'Choose a vendor.');
      return;
    }
    final filled = _lines.where((l) => l.itemId != null).toList();
    if (filled.isEmpty) {
      setState(() => _error = 'Add at least one line item.');
      return;
    }
    for (final l in filled) {
      if ((int.tryParse(l.qty.text.trim()) ?? 0) <= 0) {
        setState(() => _error = 'Every line needs a quantity greater than zero.');
        return;
      }
      if ((num.tryParse(l.cost.text.trim()) ?? -1) < 0 || l.cost.text.trim().isEmpty) {
        setState(() => _error = 'Every line needs a unit cost.');
        return;
      }
    }
    if (_totalMinor <= 0) {
      setState(() => _error = 'The purchase order total must be greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(inventoryRepositoryProvider).createPurchaseOrder(
            facilityId: fid,
            vendorId: _vendorId!,
            orderDate: DateFormat('yyyy-MM-dd').format(_orderDate),
            expectedDelivery: _expectedDelivery == null ? null : DateFormat('yyyy-MM-dd').format(_expectedDelivery!),
            reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            lines: filled
                .map((l) => (
                      itemId: l.itemId!,
                      quantity: int.parse(l.qty.text.trim()),
                      unitCostMinor: (num.parse(l.cost.text.trim()) * 100).round(),
                      taxMinor: ((num.tryParse(l.tax.text.trim()) ?? 0) * 100).round(),
                      discountMinor: ((num.tryParse(l.discount.text.trim()) ?? 0) * 100).round(),
                    ))
                .toList(),
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
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('PURCHASE_CREATE')) {
      return const StaffPermissionDenied(
        title: 'New Purchase Order',
        message: "You don't have permission to create purchase orders.",
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase Order')),
      body: SafeArea(
        child: _loadingRefs
            ? const LoadingView(message: 'Loading…')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _vendorId,
                    decoration: const InputDecoration(labelText: 'Vendor'),
                    items: _vendors.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name))).toList(),
                    onChanged: (v) => setState(() => _vendorId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(child: _dateField('Order date', _orderDate, (d) => setState(() => _orderDate = d))),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _dateField('Expected (optional)', _expectedDelivery,
                            (d) => setState(() => _expectedDelivery = d),
                            allowNull: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Reference / invoice no. (optional)')),
                  const SizedBox(height: AppSpacing.md),
                  Text('Line items', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  ..._lines.asMap().entries.map((e) => _lineCard(e.key, e.value)),
                  const SizedBox(height: AppSpacing.xs),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _lines.add(_PoLine())),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add line'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: Theme.of(context).textTheme.titleMedium),
                        Text(invMoney(_totalMinor), style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: TextStyle(color: context.tokens.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(label: 'Create draft', loadingLabel: 'Creating…', isLoading: _saving, onPressed: _save),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
      ),
    );
  }

  Widget _lineCard(int index, _PoLine l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: l.itemId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Item', isDense: true),
                    items: _items
                        .map((it) => DropdownMenuItem(value: it.id, child: Text('${it.name} (${it.sku})', overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => l.itemId = v),
                  ),
                ),
                if (_lines.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _lines.removeAt(index)),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(child: _num(l.qty, 'Qty', digits: true)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _num(l.cost, 'Unit ₹')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _num(l.tax, 'Tax ₹')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _num(l.discount, 'Disc ₹')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _num(TextEditingController c, String label, {bool digits = false}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: !digits),
      inputFormatters: [
        digits
            ? FilteringTextInputFormatter.digitsOnly
            : FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick, {bool allowNull = false}) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 2),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value == null ? (allowNull ? 'Not set' : '') : DateFormat('d MMM yyyy').format(value)),
      ),
    );
  }
}
