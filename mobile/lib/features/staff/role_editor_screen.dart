import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import 'staff_common.dart';

class RoleEditorScreen extends ConsumerStatefulWidget {
  const RoleEditorScreen({super.key, this.roleId, this.templateId});

  final String? roleId;
  final String? templateId;

  bool get isEdit => roleId != null;

  @override
  ConsumerState<RoleEditorScreen> createState() => _RoleEditorScreenState();
}

class _RoleEditorScreenState extends ConsumerState<RoleEditorScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _isActive = true;
  final Set<String> _selected = {};

  List<Permission> _catalog = const [];
  RoleDetail? _existing;
  String _module = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final repo = ref.read(staffRepositoryProvider);
      final catalog = await repo.listPermissions();
      if (widget.isEdit) {
        final r = await repo.getRole(widget.roleId!);
        _existing = r;
        _name.text = r.name;
        _description.text = r.description ?? '';
        _isActive = r.isActive;
        _selected.addAll(r.permissionKeys);
      } else if (widget.templateId != null) {
        final t = (await repo.listRoleTemplates()).cast<RoleTemplate?>().firstWhere(
              (x) => x?.id == widget.templateId,
              orElse: () => null,
            );
        if (t != null) {
          _name.text = t.name;
          _description.text = t.description ?? '';
          _selected.addAll(t.permissionKeys);
        }
      }
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _module = catalog.isEmpty ? '' : catalog.first.module;
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

  Future<void> _save() async {
    final fid = _facilityId;
    if (fid == null || _busy) return;
    final session = ref.read(sessionControllerProvider);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A role needs a name.');
      return;
    }
    final disallowed = _selected.where((k) => session.baseRole != 'owner' && !session.permissions.contains(k));
    if (disallowed.isNotEmpty) {
      setState(() => _error = 'You can only grant permissions you hold yourself.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(staffRepositoryProvider);
      if (widget.isEdit) {
        await repo.updateRole(
          roleId: widget.roleId!,
          facilityId: fid,
          name: _existing?.isSystem == true ? null : _name.text.trim(),
          description: _existing?.isSystem == true ? null : _description.text.trim(),
          isActive: _isActive,
          permissionKeys: _selected.toList(),
          expectedVersion: _existing?.version,
        );
      } else {
        await repo.createRole(
          facilityId: fid,
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          permissionKeys: _selected.toList(),
        );
      }
      if (mounted) context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('USERS_MANAGE_ROLES')) {
      return const StaffPermissionDenied(message: "You don't have permission to manage roles.", title: 'Edit Role');
    }
    final modules = _catalog.map((p) => p.module).toSet().toList();
    final modulePerms = _catalog.where((p) => p.module == _module).toList();
    final dangerous = _catalog.where((p) => p.isDangerous && _selected.contains(p.key)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit Role' : 'Create Role')),
      body: SafeArea(
        child: _loading
            ? const _RoleEditorSkeleton()
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _name,
                          enabled: _existing?.isSystem != true,
                          decoration: const InputDecoration(labelText: 'Role name'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _description,
                          enabled: _existing?.isSystem != true,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Description'),
                        ),
                        if (widget.isEdit && _existing?.isSystem != true)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v ?? true),
                            title: const Text('Active — staff can be assigned this role'),
                          ),
                        if (_existing?.isSystem == true)
                          Text('System role names can’t be changed — you can still adjust its permissions here.',
                              style: AppTypography.caption(context)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: modules
                          .map((m) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(m),
                                  selected: _module == m,
                                  onSelected: (_) => setState(() => _module = m),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('$_module permissions', style: const TextStyle(fontWeight: FontWeight.w700))),
                            TextButton(
                              onPressed: () => setState(() => _selected.addAll(modulePerms.map((p) => p.key))),
                              child: const Text('All'),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _selected.removeAll(modulePerms.map((p) => p.key))),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                        ...modulePerms.map((p) {
                          final cannot = session.baseRole != 'owner' && !session.permissions.contains(p.key);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _selected.contains(p.key),
                            onChanged: cannot
                                ? null
                                : (v) => setState(() => v == true ? _selected.add(p.key) : _selected.remove(p.key)),
                            title: Row(
                              children: [
                                Flexible(child: Text(p.label)),
                                if (p.isDangerous) ...[
                                  const SizedBox(width: 6),
                                  const StatusBadge(label: 'Sensitive', tone: StatusTone.warning),
                                ],
                              ],
                            ),
                            subtitle: p.description != null
                                ? Text(cannot ? "You don't hold this permission yourself." : p.description!)
                                : null,
                          );
                        }),
                      ],
                    ),
                  ),
                  if (dangerous.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'This role includes sensitive permissions: ${dangerous.map((p) => p.label).join(", ")}.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: const TextStyle(color: AppColors.destructive)),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: widget.isEdit ? 'Save changes' : 'Create role',
                    loadingLabel: 'Saving…',
                    isLoading: _busy,
                    onPressed: _save,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
      ),
    );
  }
}

class _RoleEditorSkeleton extends StatelessWidget {
  const _RoleEditorSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 100, height: 12),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 44, radius: 8),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SkeletonChipRow(count: 4),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < 5; i++) ...[
          SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _permRow(),
                const SizedBox(height: AppSpacing.sm),
                _permRow(),
                const SizedBox(height: AppSpacing.sm),
                _permRow(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _permRow() {
    return const Row(
      children: [
        Expanded(child: AppSkeleton(height: 11)),
        SizedBox(width: AppSpacing.sm),
        AppSkeleton(width: 32, height: 18, radius: AppRadius.pill),
      ],
    );
  }
}
