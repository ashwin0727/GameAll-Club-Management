import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';
import 'stock_movement_sheet.dart';

/// Inventory → Items — mirrors src/features/inventory/components/items-page.tsx.
class InventoryItemsScreen extends ConsumerStatefulWidget {
  const InventoryItemsScreen({super.key});

  @override
  ConsumerState<InventoryItemsScreen> createState() => _InventoryItemsScreenState();
}

class _InventoryItemsScreenState extends ConsumerState<InventoryItemsScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  String? _categoryId;
  ItemStatus? _status;
  StockStatus? _stockStatus;
  int _page = 0;

  List<InventoryCategory> _categories = const [];
  List<ItemRow>? _items;
  int _total = 0;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _init() async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final cats = await ref.read(inventoryRepositoryProvider).listCategories(fid);
      if (mounted) setState(() => _categories = cats);
    } on AppException {
      // Filter still works without the category list.
    }
    await _load();
  }

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    final reqId = ++_requestId;
    setState(() => _error = null);
    try {
      final page = await ref.read(inventoryRepositoryProvider).listItems(
            facilityId: fid,
            search: _search,
            categoryId: _categoryId,
            status: _status,
            stockStatus: _stockStatus,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _items = page.items;
        _total = page.totalCount;
      });
    } on AppException catch (e) {
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _error = e.message;
        _items = const [];
      });
    }
  }

  void _apply(VoidCallback mutate) {
    setState(() {
      mutate();
      _page = 0;
    });
    _load();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _apply(() => _search = v));
  }

  Future<void> _pickCategory() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _categoryId ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Categories'),
        ..._categories.map((c) => (value: c.id, label: c.name)),
      ],
    );
    if (picked == null) return;
    _apply(() => _categoryId = picked == 'ALL' ? null : picked);
  }

  Future<void> _pickStock() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _stockStatus?.name ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Stock'),
        (value: 'inStock', label: 'In Stock'),
        (value: 'lowStock', label: 'Low Stock'),
        (value: 'outOfStock', label: 'Out of Stock'),
      ],
    );
    if (picked == null) return;
    _apply(() => _stockStatus = switch (picked) {
          'inStock' => StockStatus.inStock,
          'lowStock' => StockStatus.lowStock,
          'outOfStock' => StockStatus.outOfStock,
          _ => null,
        });
  }

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _status?.toJson() ?? 'ALL',
      options: const [
        (value: 'ALL', label: 'All Status'),
        (value: 'ACTIVE', label: 'Active'),
        (value: 'INACTIVE', label: 'Inactive'),
      ],
    );
    if (picked == null) return;
    _apply(() => _status = picked == 'ALL' ? null : ItemStatus.fromJson(picked));
  }

  Future<void> _move(ItemRow item, MovementType type) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StockMovementSheet(
        itemId: item.id,
        itemName: item.name,
        unit: item.unit,
        currentStock: item.currentStock,
        type: type,
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('INVENTORY_VIEW')) {
      return const StaffPermissionDenied(
        title: 'Items',
        message: "You don't have permission to view inventory.",
      );
    }
    final canCreate = session.can('INVENTORY_CREATE_ITEM');
    final canIn = session.can('INVENTORY_STOCK_IN');
    final canOut = session.can('INVENTORY_STOCK_OUT');
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add item',
              onPressed: () async {
                final created = await context.push<bool>(AppRoutes.inventoryItemNew);
                if (created == true) _load();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name, SKU or brand',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  PickerChip(
                    label: _categoryId == null
                        ? 'All Categories'
                        : _categories.firstWhere((c) => c.id == _categoryId,
                            orElse: () => const InventoryCategory(
                                id: '', name: 'Category', description: null, isActive: true, sortOrder: 0, itemCount: 0, inventoryValueMinor: 0)).name,
                    onSelect: _pickCategory,
                  ),
                  PickerChip(label: _stockStatus?.label ?? 'All Stock', onSelect: _pickStock),
                  PickerChip(label: _status?.label ?? 'All Status', onSelect: _pickStatus),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_items == null)
                const _InventoryItemsSkeleton()
              else if (_items!.isEmpty)
                Text('No items match these filters.', style: AppTypography.secondary(context))
              else ...[
                ..._items!.map((i) => _row(i, canIn, canOut)),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total items',
                    onPrevious: _page == 0 ? null : () { setState(() => _page--); _load(); },
                    onNext: _page + 1 >= totalPages ? null : () { setState(() => _page++); _load(); },
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ItemRow i, bool canIn, bool canOut) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            final changed = await context.push<bool>('/inventory/items/${i.id}');
            if (changed == true) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.name, style: AppTypography.rowTitle(context)),
                          Text(
                            '${i.sku}${i.categoryName != null ? ' · ${i.categoryName}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(context),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(label: i.stockStatus.label, tone: stockTone(i.stockStatus)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${i.currentStock} ${i.unit} · reorder ${i.reorderLevel} · ${invMoney(i.inventoryValueMinor)}',
                        style: AppTypography.caption(context),
                      ),
                    ),
                    if (canIn && i.status == ItemStatus.active)
                      TextButton(onPressed: () => _move(i, MovementType.stockIn), child: const Text('In')),
                    if (canOut && i.status == ItemStatus.active)
                      TextButton(onPressed: () => _move(i, MovementType.stockOut), child: const Text('Out')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder mirroring the loaded items list: search
/// field, filter-chip row, then a stack of item rows.
class _InventoryItemsSkeleton extends StatelessWidget {
  const _InventoryItemsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSkeleton(height: 48, radius: 8),
        SizedBox(height: AppSpacing.sm),
        SkeletonChipRow(count: 3),
        SizedBox(height: AppSpacing.lg),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
      ],
    );
  }
}
