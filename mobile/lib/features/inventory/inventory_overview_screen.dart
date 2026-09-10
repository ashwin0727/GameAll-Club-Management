import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';

/// Inventory Overview — mirrors src/features/inventory/components/overview-page.tsx.
class InventoryOverviewScreen extends ConsumerStatefulWidget {
  const InventoryOverviewScreen({super.key});

  @override
  ConsumerState<InventoryOverviewScreen> createState() => _InventoryOverviewScreenState();
}

class _InventoryOverviewScreenState extends ConsumerState<InventoryOverviewScreen> {
  InventoryOverview? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    setState(() => _error = null);
    try {
      final data = await ref.read(inventoryRepositoryProvider).getOverview(fid);
      if (mounted) setState(() => _data = data);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('INVENTORY_VIEW')) {
      return const StaffPermissionDenied(
        title: 'Inventory & Vendors',
        message: "You don't have permission to view inventory.",
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory & Vendors'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_open),
            onSelected: (r) => context.push(r),
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppRoutes.inventoryItems, child: Text('Items')),
              PopupMenuItem(value: AppRoutes.inventoryMovements, child: Text('Stock Movements')),
              PopupMenuItem(value: AppRoutes.inventoryPurchaseOrders, child: Text('Purchase Orders')),
              PopupMenuItem(value: AppRoutes.inventoryVendors, child: Text('Vendors')),
              PopupMenuItem(value: AppRoutes.inventoryCategories, child: Text('Categories')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _data == null
                ? const LoadingView(message: 'Loading overview…')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _body(_data!),
                  ),
      ),
    );
  }

  Widget _body(InventoryOverview d) {
    final total = d.inStock + d.lowStock + d.outOfStock;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.7,
          children: [
            _kpi('Total Items', '${d.totalItems}', '${d.inactiveItems} inactive'),
            _kpi('Low Stock', '${d.lowStockItems}', 'at/below reorder'),
            _kpi('Out of Stock', '${d.outOfStockItems}', null),
            _kpi('Inventory Value', invMoney(d.inventoryValueMinor), 'avg cost'),
            _kpi('Active Vendors', '${d.activeVendors}', null),
            _kpi('Pending POs', '${d.pendingPurchaseOrders}', 'ordered'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock Status', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              _bar('In Stock', d.inStock, total, StatusTone.success),
              _bar('Low Stock', d.lowStock, total, StatusTone.warning),
              _bar('Out of Stock', d.outOfStock, total, StatusTone.danger),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Low Stock Items', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (d.lowStockList.isEmpty)
                Text('Everything is above its reorder level.', style: AppTypography.secondary(context))
              else
                ...d.lowStockList.map(
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: InkWell(
                      onTap: () => context.push('/inventory/items/${i.id}'),
                      child: Row(
                        children: [
                          Expanded(child: Text(i.name, style: AppTypography.rowTitle(context))),
                          Text('${i.currentStock} / ${i.reorderLevel} ${i.unit}',
                              style: AppTypography.caption(context)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (d.topCategories.isNotEmpty) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Top Categories by Value', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                ...d.topCategories.map((c) {
                  final max = d.topCategories.first.valueMinor.clamp(1, 1 << 62);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(c.name)),
                            Text('${invMoney(c.valueMinor)} · ${c.itemCount}',
                                style: AppTypography.caption(context)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: (c.valueMinor / max).clamp(0.02, 1)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent Stock Movements', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (d.recentMovements.isEmpty)
                Text('No stock movements recorded yet.', style: AppTypography.secondary(context))
              else
                ...d.recentMovements.map(
                  (m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.itemName, style: AppTypography.rowTitle(context)),
                              Text('${m.movementType.label} · ${invDate(m.createdAt)}',
                                  style: AppTypography.caption(context)),
                            ],
                          ),
                        ),
                        MovementQty(m.quantity),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _kpi(String label, String value, String? hint) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: AppTypography.caption(context)),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (hint != null) Text(hint, style: AppTypography.caption(context)),
        ],
      ),
    );
  }

  Widget _bar(String label, int count, int total, StatusTone tone) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text('$count (${(pct * 100).round()}%)', style: AppTypography.caption(context)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: pct.clamp(0, 1),
            color: switch (tone) {
              StatusTone.success => context.tokens.success,
              StatusTone.warning => context.tokens.warning,
              StatusTone.danger => context.tokens.destructive,
              _ => context.tokens.primary,
            },
          ),
        ],
      ),
    );
  }
}
