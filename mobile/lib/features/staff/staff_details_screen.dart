import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import 'staff_common.dart';

class StaffDetailsScreen extends ConsumerStatefulWidget {
  const StaffDetailsScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<StaffDetailsScreen> createState() => _StaffDetailsScreenState();
}

class _StaffDetailsScreenState extends ConsumerState<StaffDetailsScreen> {
  static const _tabs = ['Overview', 'Access & Permissions', 'Activity', 'Notes'];
  int _tab = 0;

  StaffDetail? _detail;
  List<RoleRow> _roles = const [];
  List<Permission> _catalog = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(staffRepositoryProvider);
      final results = await Future.wait([
        repo.getStaff(fid, widget.userId),
        repo.listRoles(fid),
        repo.listPermissions(),
      ]);
      if (!mounted) return;
      final d = results[0] as StaffDetail;
      setState(() {
        _detail = d;
        _roles = results[1] as List<RoleRow>;
        _catalog = results[2] as List<Permission>;
        _notesController.text = d.notes ?? '';
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      await _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _detail?.roleId ?? _roles.firstWhere((r) => r.key == _detail?.baseRole, orElse: () => _roles.first).id,
      options: _roles.where((r) => r.isActive).map((r) => (value: r.id, label: r.name)).toList(),
    );
    if (picked != null) {
      await _run(() => ref.read(staffRepositoryProvider).assignRole(_facilityId!, widget.userId, picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('USERS_VIEW')) {
      return const StaffPermissionDenied(message: "You don't have permission to view staff.", title: 'Staff');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Staff Details')),
      body: SafeArea(
        child: _loading
            ? const _StaffDetailsSkeleton()
            : _error != null || _detail == null
                ? ErrorView(message: _error ?? 'Unable to load this staff member.', onRetry: _load)
                : _body(session),
      ),
    );
  }

  Widget _body(SessionState session) {
    final d = _detail!;
    final held = d.permissions.toSet();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              StaffAvatar(name: d.fullName, photoUrl: d.avatarUrl, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.fullName, style: AppTypography.rowTitle(context)),
                    Text(d.roleName, style: AppTypography.caption(context)),
                  ],
                ),
              ),
              StatusBadge(label: d.status.label, tone: staffStatusTone(d.status)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (session.can('USERS_MANAGE_ROLES'))
                SecondaryButton(label: 'Change Role', onPressed: _busy ? null : _changeRole),
              if (session.can('USERS_DEACTIVATE'))
                SecondaryButton(
                  label: d.status == StaffStatus.inactive ? 'Reactivate' : 'Deactivate',
                  onPressed: _busy
                      ? null
                      : () => _run(() => ref.read(staffRepositoryProvider).setStatus(
                            _facilityId!,
                            widget.userId,
                            d.status == StaffStatus.inactive ? StaffStatus.active : StaffStatus.inactive,
                          )),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: AppSpacing.md),
          if (_tab == 0) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  _kv('Full name', d.fullName),
                  _kv('Email', d.email),
                  _kv('Phone', d.phone ?? '—'),
                  _kv('Role', d.roleName),
                  _kv('Status', d.status.label),
                  _kv('Joined', staffDate(d.joinedAt)),
                  _kv('Last active', staffDate(d.lastLoginAt)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Facility Access', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.sm),
                  ...d.facilityAccess.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Expanded(child: Text('${f.facilityName} · ${f.roleName}')),
                            if (f.isPrimary) const StatusBadge(label: 'Primary', tone: StatusTone.info),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ] else if (_tab == 1) ...[
            for (final mod in _catalog.map((p) => p.module).toSet())
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mod, style: AppTypography.caption(context)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in _catalog.where((p) => p.module == mod && held.contains(p.key)))
                          StatusBadge(label: p.label, tone: p.isDangerous ? StatusTone.warning : StatusTone.neutral),
                        if (!_catalog.any((p) => p.module == mod && held.contains(p.key)))
                          Text('No access', style: AppTypography.caption(context)),
                      ],
                    ),
                  ],
                ),
              ),
          ] else if (_tab == 2) ...[
            if (d.recentActivity.isEmpty)
              Text('No recorded activity yet.', style: AppTypography.secondary(context))
            else
              ...d.recentActivity.map((e) => AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.summary, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${e.actorName ?? 'System'} · ${staffDate(e.createdAt)}',
                            style: AppTypography.caption(context)),
                      ],
                    ),
                  )),
          ] else ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _notesController,
                    maxLines: 5,
                    enabled: session.can('USERS_EDIT'),
                    decoration: const InputDecoration(labelText: 'Internal notes'),
                  ),
                  if (session.can('USERS_EDIT')) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SecondaryButton(
                      label: 'Save notes',
                      onPressed: _busy
                          ? null
                          : () => _run(() => ref.read(staffRepositoryProvider).updateProfile(
                              _facilityId!, widget.userId,
                              notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim())),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: AppTypography.caption(context))),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class _StaffDetailsSkeleton extends StatelessWidget {
  const _StaffDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SkeletonCard(
          child: Row(
            children: const [
              AppSkeleton(width: 56, height: 56, radius: 28),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 140, height: 15),
                    SizedBox(height: AppSpacing.sm),
                    AppSkeleton(width: 90, height: 11),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              AppSkeleton(width: 60, height: 20, radius: 10),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SkeletonChipRow(count: 2),
        const SizedBox(height: AppSpacing.lg),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              5,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: const [
                    Expanded(child: AppSkeleton(height: 11)),
                    SizedBox(width: AppSpacing.md),
                    AppSkeleton(width: 70, height: 11),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 110, height: 13),
              SizedBox(height: AppSpacing.sm),
              SkeletonListRow(trailing: false),
            ],
          ),
        ),
      ],
    );
  }
}
