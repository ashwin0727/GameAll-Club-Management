import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';

/// Inventory → Categories — mirrors
/// src/features/inventory/components/categories-page.tsx.
class InventoryCategoriesScreen extends ConsumerStatefulWidget {
  const InventoryCategoriesScreen({super.key});

  @override
  ConsumerState<InventoryCategoriesScreen> createState() => _InventoryCategoriesScreenState();
}

class _InventoryCategoriesScreenState extends ConsumerState<InventoryCategoriesScreen> {
  List<InventoryCategory>? _rows;
  String? _error;

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
      final rows = await ref.read(inventoryRepositoryProvider).listCategories(fid);
      if (mounted) setState(() => _rows = rows);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _rows = const [];
        });
      }
    }
  }

  Future<void> _editSheet(InventoryCategory? existing) async {
    final fid = _facilityId;
    if (fid == null) return;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    var isActive = existing?.isActive ?? true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'Add category' : 'Edit category',
                    style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                ),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: isActive,
                    onChanged: (v) => setSheet(() => isActive = v),
                  ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Save',
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final name = nameController.text.trim();
    final desc = descController.text.trim();
    nameController.dispose();
    descController.dispose();
    if (saved != true) return;
    if (name.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A category needs a name.')));
      return;
    }
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      if (existing == null) {
        await repo.createCategory(facilityId: fid, name: name, description: desc.isEmpty ? null : desc);
      } else {
        await repo.updateCategory(
          categoryId: existing.id,
          name: name,
          description: desc.isEmpty ? null : desc,
          isActive: isActive,
        );
      }
      await _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('INVENTORY_VIEW')) {
      return const StaffPermissionDenied(title: 'Categories', message: "You don't have permission to view inventory.");
    }
    final canManage = session.can('INVENTORY_MANAGE_CATEGORIES');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          if (canManage)
            IconButton(icon: const Icon(Icons.add), tooltip: 'Add category', onPressed: () => _editSheet(null)),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _rows == null
                ? const _InventoryCategoriesSkeleton()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _rows!.isEmpty
                        ? ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.xl),
                                child: Text('No categories yet.', style: AppTypography.secondary(context)),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: _rows!
                                .map((c) => Padding(
                                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                      child: AppCard(
                                        padding: const EdgeInsets.all(AppSpacing.md),
                                        onTap: canManage ? () => _editSheet(c) : null,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(c.name, style: AppTypography.rowTitle(context)),
                                                  Text(
                                                    '${c.itemCount} items · ${invMoney(c.inventoryValueMinor)}'
                                                    '${c.description != null && c.description!.isNotEmpty ? ' · ${c.description}' : ''}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: AppTypography.caption(context),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            StatusBadge(
                                              label: c.isActive ? 'Active' : 'Inactive',
                                              tone: c.isActive ? StatusTone.success : StatusTone.neutral,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                  ),
      ),
    );
  }
}

/// Structure-shaped placeholder mirroring the loaded categories list: a
/// stack of category cards, each with a title line + two stat lines.
class _InventoryCategoriesSkeleton extends StatelessWidget {
  const _InventoryCategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SkeletonCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeleton(width: 140, height: 15),
                SizedBox(height: 6),
                AppSkeleton(width: 200, height: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
