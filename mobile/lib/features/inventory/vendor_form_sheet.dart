import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';

/// Add / edit a vendor — mirrors
/// src/features/inventory/components/vendor-form-dialog.tsx.
/// Returns `true` via `Navigator.pop` when saved.
class VendorFormSheet extends ConsumerStatefulWidget {
  const VendorFormSheet({super.key, required this.facilityId, this.existing});

  final String facilityId;
  final VendorDetail? existing;

  @override
  ConsumerState<VendorFormSheet> createState() => _VendorFormSheetState();
}

class _VendorFormSheetState extends ConsumerState<VendorFormSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _contact = TextEditingController(text: widget.existing?.contactPerson ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _gst = TextEditingController(text: widget.existing?.gstNumber ?? '');
  late final _pan = TextEditingController(text: widget.existing?.panNumber ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late VendorStatus _status = widget.existing?.status ?? VendorStatus.active;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _email, _address, _gst, _pan, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A vendor needs a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      if (_isEdit) {
        await repo.updateVendor(
          vendorId: widget.existing!.id,
          name: _name.text.trim(),
          contactPerson: t(_contact),
          phone: t(_phone),
          email: t(_email),
          address: t(_address),
          gstNumber: t(_gst),
          panNumber: t(_pan),
          notes: t(_notes),
          status: _status,
        );
      } else {
        await repo.createVendor(
          facilityId: widget.facilityId,
          name: _name.text.trim(),
          contactPerson: t(_contact),
          phone: t(_phone),
          email: t(_email),
          address: t(_address),
          gstNumber: t(_gst),
          panNumber: t(_pan),
          notes: t(_notes),
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Edit vendor' : 'Add vendor', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            _f(_name, 'Vendor name'),
            _f(_contact, 'Contact person'),
            _f(_phone, 'Phone'),
            _f(_email, 'Email'),
            _f(_address, 'Address', lines: 2),
            _f(_gst, 'GST number'),
            _f(_pan, 'PAN number'),
            _f(_notes, 'Notes', lines: 2),
            if (_isEdit) ...[
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<VendorStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: VendorStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                onChanged: (v) => setState(() => _status = v ?? VendorStatus.active),
              ),
            ],
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

  Widget _f(TextEditingController c, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: TextField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
