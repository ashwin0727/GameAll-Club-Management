import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';
import 'inventory_item_form_screen.dart';
import 'stock_movement_sheet.dart';

/// Inventory → Item detail — mirrors
/// src/features/inventory/components/item-details-page.tsx.
class InventoryItemDetailScreen extends ConsumerStatefulWidget {
  const InventoryItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<InventoryItemDetailScreen> createState() => _InventoryItemDetailScreenState();
}

class _InventoryItemDetailScreenState extends ConsumerState<InventoryItemDetailScreen> {
  static const _tabs = ['Overview', 'Movements', 'Purchases'];

  ItemDetail? _item;
  String? _error;
  int _tab = 0;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final item = await ref.read(inventoryRepositoryProvider).getItem(widget.itemId);
      if (mounted) setState(() => _item = item);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _move(MovementType type) async {
    final d = _item!;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StockMovementSheet(
        itemId: d.id,
        itemName: d.name,
        unit: d.unit,
        currentStock: d.currentStock,
        type: type,
      ),
    );
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InventoryItemFormScreen(existing: _item)),
    );
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('INVENTORY_VIEW')) {
      return const StaffPermissionDenied(title: 'Item', message: "You don't have permission to view inventory.");
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_item?.name ?? 'Item'),
          actions: [
            if (_item != null && session.can('INVENTORY_EDIT_ITEM'))
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit),
          ],
        ),
        body: SafeArea(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _item == null
                  ? const _InventoryItemDetailSkeleton()
                  : _content(_item!, session),
        ),
      ),
    );
  }

  Widget _content(ItemDetail d, session) {
    final canIn = session.can('INVENTORY_STOCK_IN');
    final canOut = session.can('INVENTORY_STOCK_OUT');
    final canAdjust = session.can('INVENTORY_ADJUST');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusBadge(label: d.stockStatus.label, tone: stockTone(d.stockStatus)),
              StatusBadge(label: d.status.label, tone: itemTone(d.status)),
              if (d.categoryName != null) StatusBadge(label: d.categoryName!, tone: StatusTone.info),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 2.2,
            children: [
              _stat('Current Stock', '${d.currentStock} ${d.unit}'),
              _stat('Reorder Level', '${d.reorderLevel}'),
              _stat('Unit Cost (avg)', invMoney(d.unitCostMinor)),
              _stat('Stock Value', invMoney(d.inventoryValueMinor)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (d.status == ItemStatus.active && (canIn || canOut || canAdjust))
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (canIn) OutlinedButton(onPressed: () => _move(MovementType.stockIn), child: const Text('Stock In')),
                if (canOut) OutlinedButton(onPressed: () => _move(MovementType.stockOut), child: const Text('Stock Out')),
                if (canAdjust) OutlinedButton(onPressed: () => _move(MovementType.adjustment), child: const Text('Adjust')),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: AppSpacing.md),
          if (_tab == 0) ..._overview(d),
          if (_tab == 1) ..._movements(d),
          if (_tab == 2) ..._purchases(d),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  List<Widget> _overview(ItemDetail d) => [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Preferred vendor', d.preferredVendorName ?? '—'),
              _kv('Default cost', d.defaultUnitCostMinor != null ? invMoney(d.defaultUnitCostMinor!) : '—'),
              _kv('Total in', '${d.stats.totalInQty}'),
              _kv('Total out', '${d.stats.totalOutQty}'),
              _kv('Last stock in', invDate(d.stats.lastStockInAt)),
              _kv('Last stock out', invDate(d.stats.lastStockOutAt)),
              _kv('Created', invDate(d.createdAt)),
              if (d.description != null && d.description!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(d.description!, style: AppTypography.secondary(context)),
              ],
            ],
          ),
        ),
      ];

  List<Widget> _movements(ItemDetail d) {
    if (d.recentMovements.isEmpty) {
      return [Text('No movements recorded yet.', style: AppTypography.secondary(context))];
    }
    return d.recentMovements
        .map((m) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.movementType.label} · bal ${m.balanceAfter}', style: AppTypography.rowTitle(context)),
                        Text(
                          '${invDateTime(m.createdAt)}${m.referenceLabel != null ? ' · ${m.referenceLabel}' : m.reason != null ? ' · ${m.reason}' : ''}',
                          style: AppTypography.caption(context),
                        ),
                      ],
                    ),
                  ),
                  MovementQty(m.quantity),
                ],
              ),
            ))
        .toList();
  }

  List<Widget> _purchases(ItemDetail d) {
    if (d.purchases.isEmpty) {
      return [Text('This item has never been on a purchase order.', style: AppTypography.secondary(context))];
    }
    return d.purchases
        .map((p) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: () async {
                await context.push('/inventory/purchase-orders/${p.poId}');
                if (mounted) _load();
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.poNumber} · ${p.vendorName}', style: AppTypography.rowTitle(context)),
                        Text(
                          '${invDate(p.orderDate)} · ${p.quantityReceived}/${p.quantityOrdered} · ${invMoney(p.unitCostMinor)}',
                          style: AppTypography.caption(context),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(label: p.status.label, tone: poTone(p.status)),
                ],
              ),
            ))
        .toList();
  }

  Widget _stat(String label, String value) => AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: AppTypography.caption(context)),
            const SizedBox(height: 2),
            Text(value, style: AppTypography.rowTitle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: AppTypography.body(context))),
          ],
        ),
      );
}

/// Structure-shaped placeholder mirroring the loaded item detail: status
/// badges, a 2x2 stat grid, action buttons, tab bar, then tab-content rows.
class _InventoryItemDetailSkeleton extends StatelessWidget {
  const _InventoryItemDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppSkeleton(width: 72, height: 24, radius: 999),
            AppSkeleton(width: 64, height: 24, radius: 999),
            AppSkeleton(width: 88, height: 24, radius: 999),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 2.2,
          ),
          children: const [
            SkeletonStatTile(height: 72),
            SkeletonStatTile(height: 72),
            SkeletonStatTile(height: 72),
            SkeletonStatTile(height: 72),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Wrap(
          spacing: AppSpacing.sm,
          children: [
            AppSkeleton(width: 92, height: 36, radius: 8),
            AppSkeleton(width: 96, height: 36, radius: 8),
            AppSkeleton(width: 72, height: 36, radius: 8),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const SkeletonChipRow(count: 3),
        const SizedBox(height: AppSpacing.md),
        const SkeletonListRow(trailing: false),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(trailing: false),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonListRow(trailing: false),
      ],
    );
  }
}
