import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/guest.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';

/// Add or edit a guest player. Returns the saved [GuestPlayer] via
/// `Navigator.pop`, or null if dismissed.
class GuestFormSheet extends ConsumerStatefulWidget {
  const GuestFormSheet({super.key, required this.facilityId, this.guest});

  final String facilityId;
  final GuestPlayer? guest;

  @override
  ConsumerState<GuestFormSheet> createState() => _GuestFormSheetState();
}

class _GuestFormSheetState extends ConsumerState<GuestFormSheet> {
  late final _nameController = TextEditingController(text: widget.guest?.name ?? '');
  late final _phoneController = TextEditingController(text: widget.guest?.phone ?? '');
  late final _emailController = TextEditingController(text: widget.guest?.email ?? '');
  late final _notesController = TextEditingController(text: widget.guest?.notes ?? '');
  GuestStatus _status = GuestStatus.active;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.guest?.status ?? GuestStatus.active;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = Validators.name(_nameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final phoneError = Validators.optionalPhone(_phoneController.text);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final repo = ref.read(guestRepositoryProvider);
      final saved = widget.guest != null
          ? await repo.updateGuest(
              widget.guest!.id,
              name: _nameController.text.trim(),
              phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
              email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
              notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
              status: _status,
            )
          : await repo.findOrCreateGuest(
              GuestInput(
                facilityId: widget.facilityId,
                name: _nameController.text.trim(),
                phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
                email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
                notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
              ),
            );
      if (mounted) Navigator.of(context).pop(saved);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            Text(widget.guest != null ? 'Edit Guest' : 'Add Guest', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Mobile number (optional)'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
            ),
            if (widget.guest != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Active'),
                    selected: _status == GuestStatus.active,
                    onSelected: (_) => setState(() => _status = GuestStatus.active),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ChoiceChip(
                    label: const Text('Inactive'),
                    selected: _status == GuestStatus.inactive,
                    onSelected: (_) => setState(() => _status = GuestStatus.inactive),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', loadingLabel: 'Saving…', isLoading: _isSaving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}