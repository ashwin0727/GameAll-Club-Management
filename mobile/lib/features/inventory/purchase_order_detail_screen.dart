import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Inventory → Purchase order detail — mirrors
/// src/features/inventory/components/purchase-order-details-page.tsx.
class PurchaseOrderDetailScreen extends ConsumerStatefulWidget {
  const PurchaseOrderDetailScreen({super.key, required this.poId});

  final String poId;

  @override
  ConsumerState<PurchaseOrderDetailScreen> createState() => _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends ConsumerState<PurchaseOrderDetailScreen> {
  static const _tabs = ['Overview', 'Items Received'];

  PurchaseOrderDetail? _po;
  String? _error;
  int _tab = 0;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final po = await ref.read(inventoryRepositoryProvider).getPurchaseOrder(widget.poId);
      if (mounted) setState(() => _po = po);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      await _load();
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('PURCHASE_VIEW')) {
      return const StaffPermissionDenied(title: 'Purchase Order', message: "You don't have permission to view purchase orders.");
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_po?.poNumber ?? 'Purchase Order')),
        body: SafeArea(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _po == null
                  ? const _PurchaseOrderDetailSkeleton()
                  : _content(_po!, session),
        ),
      ),
    );
  }

  Widget _content(PurchaseOrderDetail po, session) {
    final canPlace = session.can('PURCHASE_CREATE') && po.status == PoStatus.draft;
    final canReceive = session.can('PURCHASE_RECEIVE') &&
        (po.status == PoStatus.ordered || po.status == PoStatus.partiallyReceived);
    final canPay = session.can('FINANCE_RECORD_PAYMENT') && po.expenseId != null && po.outstandingMinor > 0;
    final canCancel = session.can('PURCHASE_CANCEL') && po.status != PoStatus.received && po.status != PoStatus.cancelled;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(po.vendorName, style: AppTypography.rowTitle(context)),
          Text('Ordered ${invDate(po.orderDate)}', style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              StatusBadge(label: po.status.label, tone: poTone(po.status)),
              StatusBadge(label: po.paymentStatus.label, tone: poPaymentTone(po.paymentStatus)),
            ],
          ),
          if (po.status == PoStatus.cancelled && po.cancelReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Cancelled: ${po.cancelReason}', style: AppTypography.caption(context)),
          ],
          const SizedBox(height: AppSpacing.md),
          if (canPlace || canReceive || canPay || canCancel)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (canPlace)
                  ElevatedButton(
                    onPressed: _busy ? null : () => _run(() => ref.read(inventoryRepositoryProvider).placePurchaseOrder(po.id)),
                    child: const Text('Place Order'),
                  ),
                if (canReceive)
                  ElevatedButton(onPressed: _busy ? null : () => _receive(po), child: const Text('Receive Goods')),
                if (canPay)
                  OutlinedButton(onPressed: _busy ? null : () => _pay(po), child: const Text('Record Payment')),
                if (canCancel)
                  OutlinedButton(onPressed: _busy ? null : () => _cancel(po), child: const Text('Cancel')),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: AppSpacing.md),
          if (_tab == 0) ..._overview(po) else ..._received(po),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  List<Widget> _overview(PurchaseOrderDetail po) => [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Line Items', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              ...po.lines.map((l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.itemName, style: AppTypography.body(context)),
                              Text('${l.quantityReceived}/${l.quantityOrdered} ${l.unit} · ${invMoney(l.unitCostMinor)}',
                                  style: AppTypography.caption(context)),
                            ],
                          ),
                        ),
                        Text(invMoney(l.lineTotalMinor), style: AppTypography.body(context)),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Financials', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              _fin('Subtotal', invMoney(po.subtotalMinor)),
              _fin('Tax', invMoney(po.taxMinor)),
              _fin('Discount', '− ${invMoney(po.discountMinor)}'),
              _fin('Total', invMoney(po.totalMinor), bold: true),
              _fin('Paid', invMoney(po.paidMinor)),
              _fin('Outstanding', invMoney(po.outstandingMinor)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fin('Expected delivery', invDate(po.expectedDelivery)),
              _fin('Reference', po.reference ?? '—'),
              if (po.notes != null && po.notes!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(po.notes!, style: AppTypography.secondary(context)),
              ],
            ],
          ),
        ),
      ];

  List<Widget> _received(PurchaseOrderDetail po) => [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: po.lines.map((l) {
              final pct = l.quantityOrdered > 0 ? l.quantityReceived / l.quantityOrdered : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(l.itemName)),
                        Text('${l.quantityReceived}/${l.quantityOrdered} · ${l.quantityPending} pending',
                            style: AppTypography.caption(context)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: pct.clamp(0, 1)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (po.events.isNotEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Activity', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                ...po.events.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.summary, style: AppTypography.body(context))),
                          Text(invDate(e.createdAt), style: AppTypography.caption(context)),
                        ],
                      ),
                    )),
              ],
            ),
          ),
      ];

  Widget _fin(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: bold ? AppTypography.rowTitle(context) : AppTypography.secondary(context)),
            Text(v, style: bold ? AppTypography.rowTitle(context) : AppTypography.body(context)),
          ],
        ),
      );

  Future<void> _receive(PurchaseOrderDetail po) async {
    final pending = po.lines.where((l) => l.quantityPending > 0).toList();
    final controllers = {for (final l in pending) l.id: TextEditingController(text: '${l.quantityPending}')};
    final result = await showModalBottomSheet<List<({String lineId, int quantity})>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Receive goods', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              ...pending.map((l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text('${l.itemName} · ${l.quantityPending} pending')),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: controllers[l.id],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Confirm receipt',
                onPressed: () {
                  final receipts = <({String lineId, int quantity})>[];
                  for (final l in pending) {
                    final q = int.tryParse(controllers[l.id]!.text.trim()) ?? 0;
                    if (q > 0) receipts.add((lineId: l.id, quantity: q));
                  }
                  Navigator.of(ctx).pop(receipts);
                },
              ),
            ],
          ),
        ),
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result == null || result.isEmpty) return;
    // Client-side guard; the RPC re-checks and is authoritative.
    for (final r in result) {
      final line = pending.firstWhere((l) => l.id == r.lineId);
      if (r.quantity > line.quantityPending) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot receive more than the ${line.quantityPending} pending for ${line.itemName}.')),
          );
        }
        return;
      }
    }
    await _run(() => ref.read(inventoryRepositoryProvider).receivePurchaseOrder(po.id, result));
  }

  Future<void> _pay(PurchaseOrderDetail po) async {
    final amountController = TextEditingController(text: (po.outstandingMinor / 100).toString());
    final methodController = TextEditingController();
    final referenceController = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record payment', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text('${invMoney(po.outstandingMinor)} outstanding', style: AppTypography.caption(context)),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount (₹)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(controller: methodController, decoration: const InputDecoration(labelText: 'Method (optional)')),
              const SizedBox(height: AppSpacing.sm),
              TextField(controller: referenceController, decoration: const InputDecoration(labelText: 'Reference (optional)')),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(label: 'Record payment', onPressed: () => Navigator.of(ctx).pop(true)),
            ],
          ),
        ),
      ),
    );
    final minor = ((num.tryParse(amountController.text.trim()) ?? 0) * 100).round();
    final method = methodController.text.trim();
    final reference = referenceController.text.trim();
    amountController.dispose();
    methodController.dispose();
    referenceController.dispose();
    if (confirmed != true) return;
    if (minor <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount greater than zero.')));
      return;
    }
    if (minor > po.outstandingMinor) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That's more than the amount outstanding.")));
      return;
    }
    await _run(() => ref.read(inventoryRepositoryProvider).recordPurchasePayment(
          poId: po.id,
          amountMinor: minor,
          paymentMethod: method.isEmpty ? null : method,
          reference: reference.isEmpty ? null : reference,
        ));
  }

  Future<void> _cancel(PurchaseOrderDetail po) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel purchase order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This cannot be undone. If nothing has been received, the linked expense is voided.'),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep order')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cancel Order')),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true) return;
    if (reason.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required.')));
      return;
    }
    await _run(() => ref.read(inventoryRepositoryProvider).cancelPurchaseOrder(po.id, reason));
  }
}

/// Structure-shaped placeholder mirroring the loaded PO detail: vendor/date
/// title lines, status badges, action buttons, line items, then a total.
class _PurchaseOrderDetailSkeleton extends StatelessWidget {
  const _PurchaseOrderDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        AppSkeleton(width: 180, height: 16),
        SizedBox(height: 6),
        AppSkeleton(width: 130, height: 12),
        SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            AppSkeleton(width: 72, height: 24, radius: 999),
            AppSkeleton(width: 96, height: 24, radius: 999),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppSkeleton(width: 108, height: 36, radius: 8),
            AppSkeleton(width: 120, height: 36, radius: 8),
            AppSkeleton(width: 96, height: 36, radius: 8),
            AppSkeleton(width: 72, height: 36, radius: 8),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonChipRow(count: 2),
        SizedBox(height: AppSpacing.md),
        SkeletonListRow(trailing: false),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(trailing: false),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(trailing: false),
        SizedBox(height: AppSpacing.md),
        AppSkeleton(width: 160, height: 15),
      ],
    );
  }
}
