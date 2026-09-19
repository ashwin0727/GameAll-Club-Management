import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import 'staff_common.dart';

/// Users & Roles → Staff → Add — mirrors add-staff-page.tsx (3-step wizard).
class AddStaffScreen extends ConsumerStatefulWidget {
  const AddStaffScreen({super.key});

  @override
  ConsumerState<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends ConsumerState<AddStaffScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  String? _roleId;
  bool _isPrimary = true;

  List<RoleRow> _roles = const [];
  bool _busy = false;
  String? _error;
  CreateStaffResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoles());
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _loadRoles() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final roles = (await ref.read(staffRepositoryProvider).listRoles(fid))
          .where((r) => r.isActive && r.key != 'owner')
          .toList();
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _roleId ??= roles
            .cast<RoleRow?>()
            .firstWhere((r) => r?.key == 'staff', orElse: () => roles.isEmpty ? null : roles.first)
            ?.id;
        _loading = false;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  bool get _emailValid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());

  void _next() {
    setState(() => _error = null);
    if (_step == 0) {
      if (_name.text.trim().isEmpty) return setState(() => _error = "Enter the staff member's full name.");
      if (!_emailValid) return setState(() => _error = 'Enter a valid email address.');
    }
    if (_step == 1 && _roleId == null) return setState(() => _error = 'Choose a role.');
    setState(() => _step = (_step + 1).clamp(0, 2));
  }

  Future<void> _submit() async {
    final fid = _facilityId;
    if (fid == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(staffRepositoryProvider).createStaff(
            facilityId: fid,
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            roleId: _roleId!,
            isPrimary: _isPrimary,
            notes: _notes.text.trim(),
          );
      if (mounted) setState(() => _result = res);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('USERS_CREATE')) {
      return const StaffPermissionDenied(message: "You don't have permission to add staff.", title: 'Add Staff');
    }

    final facilityName = session.facility?.name ?? 'this facility';
    final selectedRole = _roles.cast<RoleRow?>().firstWhere((r) => r?.id == _roleId, orElse: () => null);

    if (_result != null) return _resultView(facilityName);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Staff')),
      body: SafeArea(
        child: _loading
            ? const _AddStaffSkeleton()
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text('Invite a new staff member to your facility.', style: AppTypography.secondary(context)),
                  const SizedBox(height: AppSpacing.md),
                  _Stepper(step: _step),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_step == 0) ...[
                          const Text('Basic Information', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name *')),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email address *'),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone number')),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _notes,
                            maxLines: 3,
                            maxLength: 500,
                            decoration: const InputDecoration(labelText: 'Notes (optional)'),
                          ),
                        ] else if (_step == 1) ...[
                          const Text('Access & Role', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: AppSpacing.sm),
                          DropdownButtonFormField<String>(
                            initialValue: _roleId,
                            decoration: const InputDecoration(labelText: 'Role *'),
                            items: _roles
                                .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                                .toList(),
                            onChanged: (v) => setState(() => _roleId = v),
                          ),
                          if (selectedRole?.description != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(selectedRole!.description!, style: AppTypography.caption(context)),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _isPrimary,
                            onChanged: (v) => setState(() => _isPrimary = v ?? true),
                            title: Text('Make $facilityName their primary facility'),
                          ),
                          Text(
                            'Access is scoped to $facilityName. You can grant access to other facilities from the '
                            'staff member’s details afterwards.',
                            style: AppTypography.caption(context),
                          ),
                        ] else ...[
                          const Text('Review & Invite', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: AppSpacing.sm),
                          _review('Full name', _name.text),
                          _review('Email', _email.text),
                          _review('Phone', _phone.text.isEmpty ? '—' : _phone.text),
                          _review('Role', selectedRole?.name ?? '—'),
                          _review('Facility', facilityName),
                          _review('Primary facility', _isPrimary ? 'Yes' : 'No'),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'An account will be created with a one-time password you’ll share with them. They must '
                            'set their own password on first sign-in.',
                            style: AppTypography.caption(context),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_error!, style: const TextStyle(color: AppColors.destructive)),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            SecondaryButton(
                              label: _step == 0 ? 'Cancel' : 'Back',
                              onPressed: _busy
                                  ? null
                                  : () => _step == 0 ? context.pop() : setState(() => _step--),
                            ),
                            const Spacer(),
                            if (_step < 2)
                              PrimaryButton(label: 'Next', isLoading: false, onPressed: _next)
                            else
                              PrimaryButton(
                                label: 'Add staff member',
                                loadingLabel: 'Adding…',
                                isLoading: _busy,
                                onPressed: _submit,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _review(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: AppTypography.caption(context))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _resultView(String facilityName) {
    final r = _result!;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Staff')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline, size: 40, color: AppColors.success),
                  const SizedBox(height: AppSpacing.sm),
                  Text(r.linked ? '${_name.text} was added' : '${_name.text} was invited',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    r.linked
                        ? 'They already had a GameAll account — access to $facilityName is active now.'
                        : "Share the one-time password below. They'll set their own on first sign-in.",
                    textAlign: TextAlign.center,
                    style: AppTypography.secondary(context),
                  ),
                  if (r.temporaryPassword != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: SelectableText(r.temporaryPassword!, style: const TextStyle(fontWeight: FontWeight.w700))),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: r.temporaryPassword!));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied')));
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Shown once and never stored.', style: AppTypography.caption(context)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'View ${_name.text}',
              isLoading: false,
              onPressed: () => context.pushReplacement('/users-roles/staff/${r.userId}'),
            ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(label: 'Back to staff', onPressed: () => context.pop()),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Basic Info', 'Access & Role', 'Review'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          CircleAvatar(
            radius: 12,
            backgroundColor: i <= step ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text('${i + 1}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: i <= step ? Theme.of(context).colorScheme.onPrimary : null)),
          ),
          const SizedBox(width: 6),
          Text(labels[i], style: TextStyle(fontSize: 12, fontWeight: i == step ? FontWeight.w700 : FontWeight.w400)),
          if (i < 2) const Expanded(child: Divider(indent: 8, endIndent: 8)),
        ],
      ],
    );
  }
}

class _AddStaffSkeleton extends StatelessWidget {
  const _AddStaffSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        AppSkeleton(width: 220, height: 13),
        SizedBox(height: AppSpacing.md),
        _StepperSkeleton(),
        SizedBox(height: AppSpacing.lg),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 140, height: 15),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(height: 44, radius: 8),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 44, radius: 8),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 44, radius: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperSkeleton extends StatelessWidget {
  const _StepperSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        AppSkeleton(width: 24, height: 24, radius: 12),
        SizedBox(width: 6),
        AppSkeleton(width: 60, height: 11),
        SizedBox(width: 8),
        Expanded(child: AppSkeleton(height: 1)),
        SizedBox(width: 8),
        AppSkeleton(width: 24, height: 24, radius: 12),
        SizedBox(width: 6),
        AppSkeleton(width: 70, height: 11),
        SizedBox(width: 8),
        Expanded(child: AppSkeleton(height: 1)),
        SizedBox(width: 8),
        AppSkeleton(width: 24, height: 24, radius: 12),
        SizedBox(width: 6),
        AppSkeleton(width: 50, height: 11),
      ],
    );
  }
}
