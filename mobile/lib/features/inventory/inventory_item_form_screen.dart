import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';

/// Add / edit an inventory item — mirrors the web's Add Item wizard and the
/// item-details edit dialog. A single scrolling form on mobile.
///
/// Does the one rupee→minor-unit conversion for the default unit cost.
class InventoryItemFormScreen extends ConsumerStatefulWidget {
  const InventoryItemFormScreen({super.key, this.existing});

  final ItemDetail? existing;

  @override
  ConsumerState<InventoryItemFormScreen> createState() => _InventoryItemFormScreenState();
}

class _InventoryItemFormScreenState extends ConsumerState<InventoryItemFormScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _sku = TextEditingController(text: widget.existing?.sku ?? '');
  late final _brand = TextEditingController(text: widget.existing?.brand ?? '');
  late final _unit = TextEditingController(text: widget.existing?.unit ?? 'piece');
  late final _reorder = TextEditingController(text: '${widget.existing?.reorderLevel ?? 0}');
  late final _opening = TextEditingController(text: '0');
  late final _cost = TextEditingController(
    text: widget.existing?.defaultUnitCostMinor != null
        ? (widget.existing!.defaultUnitCostMinor! / 100).toString()
        : '',
  );
  late final _description = TextEditingController(text: widget.existing?.description ?? '');

  String? _categoryId;
  ItemStatus _status = ItemStatus.active;
  List<InventoryCategory> _categories = const [];
  List<VendorRow> _vendors = const [];
  String? _preferredVendorId;

  bool _saving = false;
  bool _loadingRefs = true;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?.categoryId;
    _status = widget.existing?.status ?? ItemStatus.active;
    _preferredVendorId = widget.existing?.preferredVendorId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRefs());
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _brand, _unit, _reorder, _opening, _cost, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRefs() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) {
      if (mounted) setState(() => _loadingRefs = false);
      return;
    }
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final cats = await repo.listCategories(fid);
      final vendors = await repo.listVendors(facilityId: fid, status: VendorStatus.active, limit: 200);
      if (mounted) {
        setState(() {
          _categories = cats;
          _vendors = vendors.vendors;
          _loadingRefs = false;
        });
      }
    } on AppException {
      // The form still works without the reference lists.
      if (mounted) setState(() => _loadingRefs = false);
    }
  }

  Future<void> _save() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter an item name.');
      return;
    }
    if (_sku.text.trim().isEmpty) {
      setState(() => _error = 'Enter a SKU.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final cost = num.tryParse(_cost.text.trim());
    final costMinor = (cost != null && cost > 0) ? (cost * 100).round() : null;
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      if (_isEdit) {
        await repo.updateItem(
          itemId: widget.existing!.id,
          name: _name.text.trim(),
          sku: _sku.text.trim(),
          brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
          unit: _unit.text.trim(),
          reorderLevel: int.tryParse(_reorder.text.trim()) ?? 0,
          defaultUnitCostMinor: costMinor,
          categoryId: _categoryId,
          preferredVendorId: _preferredVendorId,
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          status: _status,
        );
      } else {
        await repo.createItem(
          facilityId: fid,
          name: _name.text.trim(),
          sku: _sku.text.trim(),
          categoryId: _categoryId,
          unit: _unit.text.trim().isEmpty ? 'piece' : _unit.text.trim(),
          reorderLevel: int.tryParse(_reorder.text.trim()) ?? 0,
          brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          defaultUnitCostMinor: costMinor,
          preferredVendorId: _preferredVendorId,
          openingStock: int.tryParse(_opening.text.trim()) ?? 0,
        );
      }
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
    final perm = _isEdit ? 'INVENTORY_EDIT_ITEM' : 'INVENTORY_CREATE_ITEM';
    if (!session.can(perm)) {
      return StaffPermissionDenied(
        title: _isEdit ? 'Edit Item' : 'Add Item',
        message: "You don't have permission to do that.",
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Item' : 'Add Item')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _field(_name, 'Item name'),
            _field(_sku, 'SKU / Code'),
            _field(_brand, 'Brand (optional)'),
            _field(_unit, 'Unit of measure', hint: 'piece, box, litre…'),
            _field(_reorder, 'Reorder level', number: true),
            if (!_isEdit) _field(_opening, 'Opening stock', number: true),
            _field(_cost, 'Default unit cost (₹, optional)', decimal: true),
            const SizedBox(height: AppSpacing.sm),
            if (_loadingRefs)
              const AppSkeleton(height: 56, radius: 8)
            else
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            const SizedBox(height: AppSpacing.sm),
            if (_loadingRefs)
              const AppSkeleton(height: 56, radius: 8)
            else
              DropdownButtonFormField<String?>(
                initialValue: _preferredVendorId,
                decoration: const InputDecoration(labelText: 'Preferred vendor (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ..._vendors.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name))),
                ],
                onChanged: (v) => setState(() => _preferredVendorId = v),
              ),
            if (_isEdit) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<ItemStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: ItemStatus.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                    .toList(),
                onChanged: (v) => setState(() => _status = v ?? ItemStatus.active),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: context.tokens.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: _isEdit ? 'Save changes' : 'Create item',
              loadingLabel: 'Saving…',
              isLoading: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool number = false, bool decimal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: c,
        keyboardType: (number || decimal) ? TextInputType.numberWithOptions(decimal: decimal) : null,
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly]
            : decimal
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                : null,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}
