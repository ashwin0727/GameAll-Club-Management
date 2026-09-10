import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/inventory.dart';
import '../../shared/widgets/misc.dart';

/// Presentation helpers shared across the Inventory & Vendors screens — the
/// mobile counterpart of src/features/inventory/components/shared.tsx.
///
/// Nothing here computes a monetary figure: [invMoney] only FORMATS a
/// server-provided minor-unit value.
String invMoney(int amountMinor) => Formatters.currencyInr((amountMinor / 100).round());

String invDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  return Formatters.dateShort(DateTime.parse(iso));
}

String invDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  return Formatters.dateTimeShort(DateTime.parse(iso));
}

StatusTone stockTone(StockStatus s) => switch (s) {
      StockStatus.inStock => StatusTone.success,
      StockStatus.lowStock => StatusTone.warning,
      StockStatus.outOfStock => StatusTone.danger,
    };

StatusTone itemTone(ItemStatus s) => s == ItemStatus.active ? StatusTone.success : StatusTone.neutral;

StatusTone vendorTone(VendorStatus s) => s == VendorStatus.active ? StatusTone.success : StatusTone.neutral;

StatusTone poTone(PoStatus s) => switch (s) {
      PoStatus.draft => StatusTone.neutral,
      PoStatus.ordered => StatusTone.warning,
      PoStatus.partiallyReceived => StatusTone.warning,
      PoStatus.received => StatusTone.success,
      PoStatus.cancelled => StatusTone.danger,
    };

StatusTone poPaymentTone(PoPaymentStatus s) => switch (s) {
      PoPaymentStatus.paid => StatusTone.success,
      PoPaymentStatus.partial => StatusTone.warning,
      PoPaymentStatus.pending => StatusTone.warning,
      PoPaymentStatus.unbilled => StatusTone.neutral,
    };

/// A signed movement quantity, coloured and prefixed.
class MovementQty extends StatelessWidget {
  const MovementQty(this.qty, {super.key});
  final int qty;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final positive = qty > 0;
    return Text(
      '${positive ? '+' : ''}$qty',
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: positive ? tokens.success : tokens.destructive,
      ),
    );
  }
}
