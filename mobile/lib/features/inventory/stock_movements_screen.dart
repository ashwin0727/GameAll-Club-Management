import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';

/// Inventory → Stock Movements — mirrors
/// src/features/inventory/components/stock-movements-page.tsx.
class StockMovementsScreen extends ConsumerStatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  ConsumerState<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  static const _pageSize = 25;

  MovementType? _type;
  int _page = 0;
  List<StockMovementRow>? _rows;
  int _total = 0;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fid = ref.read(sessionControllerProvider).facility?.id;
    if (fid == null) return;
    final reqId = ++_requestId;
    setState(() => _error = null);
    try {
      final page = await ref.read(inventoryRepositoryProvider).listMovements(
            facilityId: fid,
            type: _type,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _rows = page.movements;
        _total = page.totalCount;
      });
    } on AppException catch (e) {
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _error = e.message;
        _rows = const [];
      });
    }
  }

  Future<void> _pickType() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _type?.toJson() ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Types'),
        ...MovementType.values.map((t) => (value: t.toJson(), label: t.label)),
      ],
    );
    if (picked == null) return;
    setState(() {
      _type = picked == 'ALL' ? null : MovementType.fromJson(picked);
      _page = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('INVENTORY_VIEW')) {
      return const StaffPermissionDenied(title: 'Stock Movements', message: "You don't have permission to view inventory.");
    }
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Movements')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              PickerChip(label: _type?.label ?? 'All Types', onSelect: _pickType),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_rows == null)
                const _StockMovementsSkeleton()
              else if (_rows!.isEmpty)
                Text('No stock movements match this filter.', style: AppTypography.secondary(context))
              else ...[
                ..._rows!.map(_row),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total movements',
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

  Widget _row(StockMovementRow m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            await context.push('/inventory/items/${m.itemId}');
            if (mounted) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.itemName, style: AppTypography.rowTitle(context)),
                      Text(
                        '${m.movementType.label} · ${invDateTime(m.createdAt)}'
                        '${m.referenceLabel != null ? ' · ${m.referenceLabel}' : ''}'
                        '${m.performedByName != null ? ' · ${m.performedByName}' : ''}',
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MovementQty(m.quantity),
                    Text('bal ${m.balanceAfter}', style: AppTypography.caption(context)),
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

/// Structure-shaped placeholder mirroring the loaded movements list: type
/// filter chip, then a stack of movement rows.
class _StockMovementsSkeleton extends StatelessWidget {
  const _StockMovementsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonChipRow(count: 1),
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
