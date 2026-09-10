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
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';

/// Inventory → Purchase Orders — mirrors
/// src/features/inventory/components/purchase-orders-page.tsx.
class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  static const _pageSize = 20;

  PoStatus? _status;
  int _page = 0;
  List<PurchaseOrderRow>? _rows;
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
      final page = await ref.read(inventoryRepositoryProvider).listPurchaseOrders(
            facilityId: fid,
            status: _status,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _rows = page.orders;
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

  Future<void> _pickStatus() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _status?.toJson() ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Status'),
        ...PoStatus.values.map((s) => (value: s.toJson(), label: s.label)),
      ],
    );
    if (picked == null) return;
    setState(() {
      _status = picked == 'ALL' ? null : PoStatus.fromJson(picked);
      _page = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('PURCHASE_VIEW')) {
      return const StaffPermissionDenied(title: 'Purchase Orders', message: "You don't have permission to view purchase orders.");
    }
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Orders'),
        actions: [
          if (session.can('PURCHASE_CREATE'))
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New purchase order',
              onPressed: () async {
                final created = await context.push<bool>(AppRoutes.inventoryPurchaseOrderNew);
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
              Text('Placing a PO records the expense; stock only moves on receipt.',
                  style: AppTypography.secondary(context)),
              const SizedBox(height: AppSpacing.sm),
              PickerChip(label: _status?.label ?? 'All Status', onSelect: _pickStatus),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_rows == null)
                const LoadingView(message: 'Loading purchase orders…')
              else if (_rows!.isEmpty)
                Text('No purchase orders match this filter.', style: AppTypography.secondary(context))
              else ...[
                ..._rows!.map(_row),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total orders',
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

  Widget _row(PurchaseOrderRow p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            final changed = await context.push<bool>('/inventory/purchase-orders/${p.id}');
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
                          Text('${p.poNumber} · ${p.vendorName}', style: AppTypography.rowTitle(context)),
                          Text('${invDate(p.orderDate)} · ${p.itemCount} items · ${invMoney(p.totalMinor)}',
                              style: AppTypography.caption(context)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusBadge(label: p.status.label, tone: poTone(p.status)),
                    StatusBadge(label: p.paymentStatus.label, tone: poPaymentTone(p.paymentStatus)),
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
