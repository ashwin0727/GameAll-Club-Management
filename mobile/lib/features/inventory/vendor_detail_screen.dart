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
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../staff/staff_common.dart';
import 'inventory_common.dart';
import 'vendor_form_sheet.dart';

/// Inventory → Vendor detail — mirrors
/// src/features/inventory/components/vendor-details-page.tsx.
class VendorDetailScreen extends ConsumerStatefulWidget {
  const VendorDetailScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  ConsumerState<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends ConsumerState<VendorDetailScreen> {
  static const _tabs = ['Overview', 'Supplied Items', 'Purchases', 'Payments', 'Notes'];

  VendorDetail? _vendor;
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
      final v = await ref.read(inventoryRepositoryProvider).getVendor(widget.vendorId);
      if (mounted) setState(() => _vendor = v);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VendorFormSheet(facilityId: _vendor!.facilityId, existing: _vendor),
    );
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('VENDOR_VIEW')) {
      return const StaffPermissionDenied(title: 'Vendor', message: "You don't have permission to view vendors.");
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_vendor?.name ?? 'Vendor'),
          actions: [
            if (_vendor != null && session.can('VENDOR_EDIT'))
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit),
          ],
        ),
        body: SafeArea(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _vendor == null
                  ? const LoadingView(message: 'Loading vendor…')
                  : _content(_vendor!),
        ),
      ),
    );
  }

  Widget _content(VendorDetail v) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          StatusBadge(label: v.status.label, tone: vendorTone(v.status)),
          const SizedBox(height: AppSpacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 2.2,
            children: [
              _stat('Purchase Orders', '${v.poCount}'),
              _stat('Total Purchases', invMoney(v.totalPurchasesMinor)),
              _stat('Paid', invMoney(v.paidMinor)),
              _stat('Outstanding', invMoney(v.outstandingMinor)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: AppSpacing.md),
          if (_tab == 0) _overview(v),
          if (_tab == 1) ..._supplied(v),
          if (_tab == 2) ..._purchases(v),
          if (_tab == 3) ..._payments(v),
          if (_tab == 4) _notes(v),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _overview(VendorDetail v) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Contact person', v.contactPerson ?? '—'),
            _kv('Phone', v.phone ?? '—'),
            _kv('Email', v.email ?? '—'),
            _kv('Address', v.address ?? '—'),
            _kv('GST', v.gstNumber ?? '—'),
            _kv('PAN', v.panNumber ?? '—'),
            _kv('Last order', invDate(v.lastOrderDate)),
            _kv('Added', invDate(v.createdAt)),
          ],
        ),
      );

  List<Widget> _supplied(VendorDetail v) {
    if (v.suppliedItems.isEmpty) {
      return [Text('No items are linked to this vendor yet.', style: AppTypography.secondary(context))];
    }
    return v.suppliedItems
        .map((i) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: () => context.push('/inventory/items/${i.id}'),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.name, style: AppTypography.rowTitle(context)),
                        Text('${i.sku} · ${i.currentStock} ${i.unit}', style: AppTypography.caption(context)),
                      ],
                    ),
                  ),
                  if (i.lastUnitCostMinor != null) Text(invMoney(i.lastUnitCostMinor!), style: AppTypography.body(context)),
                ],
              ),
            ))
        .toList();
  }

  List<Widget> _purchases(VendorDetail v) {
    if (v.purchaseHistory.isEmpty) {
      return [Text('No purchase orders for this vendor.', style: AppTypography.secondary(context))];
    }
    return v.purchaseHistory
        .map((p) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: () => context.push('/inventory/purchase-orders/${p.poId}'),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.poNumber} · ${invMoney(p.totalMinor)}', style: AppTypography.rowTitle(context)),
                        Text(invDate(p.orderDate), style: AppTypography.caption(context)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusBadge(label: p.status.label, tone: poTone(p.status)),
                      const SizedBox(height: 2),
                      StatusBadge(label: p.paymentStatus.label, tone: poPaymentTone(p.paymentStatus)),
                    ],
                  ),
                ],
              ),
            ))
        .toList();
  }

  List<Widget> _payments(VendorDetail v) {
    if (v.payments.isEmpty) {
      return [Text('No payments recorded for this vendor.', style: AppTypography.secondary(context))];
    }
    return v.payments
        .map((p) => AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(invMoney(p.amountMinor), style: AppTypography.rowTitle(context)),
                        Text(
                          '${invDate(p.paidOn)}${p.poNumber != null ? ' · ${p.poNumber}' : ''}${p.method != null ? ' · ${p.method}' : ''}',
                          style: AppTypography.caption(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ))
        .toList();
  }

  Widget _notes(VendorDetail v) => AppCard(
        child: Text(
          v.notes == null || v.notes!.isEmpty ? 'No notes.' : v.notes!,
          style: AppTypography.body(context),
        ),
      );

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
            SizedBox(width: 120, child: Text(k, style: AppTypography.caption(context))),
            Expanded(child: Text(v, style: AppTypography.body(context))),
          ],
        ),
      );
}
