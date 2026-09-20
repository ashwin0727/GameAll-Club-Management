import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import 'staff_common.dart';

class RolesScreen extends ConsumerStatefulWidget {
  const RolesScreen({super.key});

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen> {
  int _tab = 0;
  List<RoleRow>? _roles;
  List<RoleTemplate> _templates = const [];
  List<Permission> _catalog = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    setState(() => _error = null);
    try {
      final repo = ref.read(staffRepositoryProvider);
      final roles = await repo.listRoles(fid);
      final catalog = await repo.listPermissions();
      List<RoleTemplate> templates = const [];
      if (ref.read(sessionControllerProvider).can('USERS_MANAGE_ROLES')) {
        templates = await repo.listRoleTemplates();
      }
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _catalog = catalog;
        _templates = templates;
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _roles = const [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('USERS_VIEW')) {
      return const StaffPermissionDenied(message: "You don't have permission to view roles.", title: 'Roles & Permissions');
    }
    final canManage = session.can('USERS_MANAGE_ROLES');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Create role',
              onPressed: () async {
                await context.push(AppRoutes.roleNew);
                if (mounted) _load();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: _roles == null && _error == null
            ? const _RolesSkeleton()
            : RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('Manage roles and module permissions for your facility.', style: AppTypography.secondary(context)),
              const SizedBox(height: AppSpacing.md),
              SegmentedTabs(
                tabs: ['Roles${_roles != null ? ' (${_roles!.length})' : ''}', 'Permissions'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_roles == null)
                const LoadingView(message: 'Loading…')
              else if (_tab == 0) ...[
                ..._roles!.map((r) => _roleCard(r, canManage)),
                if (canManage && _templates.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Need a custom role?', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Start from a pre-configured template and adjust the permissions.',
                            style: AppTypography.caption(context)),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: _templates
                              .map((t) => OutlinedButton(
                                    onPressed: () async {
                                      await context.push('${AppRoutes.roleNew}?template=${t.id}');
                                      if (mounted) _load();
                                    },
                                    child: Text(t.name),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                for (final mod in _catalog.map((p) => p.module).toSet())
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mod, style: AppTypography.caption(context)),
                        const SizedBox(height: 4),
                        ..._catalog.where((p) => p.module == mod).map((p) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(p.isDangerous ? Icons.warning_amber_rounded : Icons.circle,
                                      size: p.isDangerous ? 14 : 6, color: Theme.of(context).colorScheme.outline),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        if (p.description != null)
                                          Text(p.description!, style: AppTypography.caption(context)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleCard(RoleRow r, bool canManage) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(r.name, style: AppTypography.rowTitle(context))),
                StatusBadge(label: r.isActive ? 'Active' : 'Inactive', tone: r.isActive ? StatusTone.success : StatusTone.danger),
              ],
            ),
            if (r.description != null) Text(r.description!, style: AppTypography.caption(context)),
            const SizedBox(height: 4),
            Text('${r.staffCount} staff · ${r.permissionCount} permissions', style: AppTypography.caption(context)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                SecondaryButton(
                  label: canManage ? 'Edit' : 'View',
                  onPressed: () async {
                    await context.push('/users-roles/roles/${r.id}/edit');
                    if (mounted) _load();
                  },
                ),
                if (canManage && r.isCustom && r.staffCount == 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  SecondaryButton(
                    label: 'Delete',
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await ref.read(staffRepositoryProvider).deleteRole(r.id, _facilityId!);
                              await _load();
                            } on AppException catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RolesSkeleton extends StatelessWidget {
  const _RolesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const AppSkeleton(width: 240, height: 13),
        const SizedBox(height: AppSpacing.md),
        const SkeletonChipRow(count: 2),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < 4; i++) ...[
          SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                AppSkeleton(width: 130, height: 14),
                SizedBox(height: AppSpacing.sm),
                AppSkeleton(width: 180, height: 11),
                SizedBox(height: 4),
                AppSkeleton(width: 100, height: 11),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              AppSkeleton(width: 150, height: 14),
              SizedBox(height: 4),
              AppSkeleton(width: 220, height: 11),
              SizedBox(height: AppSpacing.sm),
              SkeletonChipRow(count: 2),
            ],
          ),
        ),
      ],
    );
  }
}
