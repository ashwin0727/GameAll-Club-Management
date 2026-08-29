import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../data/models/membership.dart';
import '../../data/repositories/membership_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';

/// Result of [AddMemberSheet]. Mirrors the web `MemberFormDialog`'s
/// `onCreated`/`onViewExisting` — a brand-new member record or an already
/// existing member (by phone) either way ends with a member id the caller
/// should immediately open the Assign Membership sheet for.
class AddMemberResult {
  const AddMemberResult({required this.memberId, required this.isExisting});

  final String memberId;
  final bool isExisting;
}

/// Add a new facility CUSTOMER/PLAYER record — never a Supabase Auth
/// account. A member has no login, no password, and needs no email
/// verification. Mirrors `member-form-dialog.tsx`.
class AddMemberSheet extends ConsumerStatefulWidget {
  const AddMemberSheet({super.key, required this.facilityId});

  final String facilityId;

  @override
  ConsumerState<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<AddMemberSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _genderController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nameError = Validators.name(_nameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final phoneError = Validators.phone(_phoneController.text);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    if (_emailController.text.trim().isNotEmpty) {
      final emailError = Validators.email(_emailController.text);
      if (emailError != null) {
        setState(() => _error = emailError);
        return;
      }
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final member = await ref.read(membershipRepositoryProvider).createMember(
        MemberInput(
          facilityId: widget.facilityId,
          fullName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
          dateOfBirth: _dobController.text.trim().isNotEmpty ? _dobController.text.trim() : null,
          gender: _genderController.text.trim().isNotEmpty ? _genderController.text.trim() : null,
          notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        ),
      );
      if (mounted) Navigator.of(context).pop(AddMemberResult(memberId: member.id, isExisting: false));
    } on MemberAlreadyExistsException catch (e) {
      if (mounted) Navigator.of(context).pop(AddMemberResult(memberId: e.existingMemberId, isExisting: true));
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
            Text('Add Member', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Creates a facility customer profile — no login or password is created.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Mobile number'),
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
              controller: _dobController,
              decoration: const InputDecoration(labelText: 'Date of birth (optional, YYYY-MM-DD)'),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _genderController, decoration: const InputDecoration(labelText: 'Gender (optional)')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Create Member', loadingLabel: 'Creating…', isLoading: _isSaving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

/// Edit an existing member's name/phone — the only fields the web dialog's
/// Edit Member form exposes. Returns the updated [FacilityMemberRow] via
/// `Navigator.pop`.
class EditMemberSheet extends ConsumerStatefulWidget {
  const EditMemberSheet({super.key, required this.member});

  final FacilityMemberRow member;

  @override
  ConsumerState<EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends ConsumerState<EditMemberSheet> {
  late final _nameController = TextEditingController(text: widget.member.fullName);
  late final _phoneController = TextEditingController(text: widget.member.phone);
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nameError = Validators.name(_nameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final phoneError = Validators.phone(_phoneController.text);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final phone = _phoneController.text.trim();
      await ref
          .read(membershipRepositoryProvider)
          .updateMember(widget.member.memberId, fullName: _nameController.text.trim(), phone: phone);
      if (mounted) {
        Navigator.of(context).pop(widget.member.copyWith(fullName: _nameController.text.trim(), phone: phone));
      }
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
            Text('Edit Member', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', loadingLabel: 'Saving…', isLoading: _isSaving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}