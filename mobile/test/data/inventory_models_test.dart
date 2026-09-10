import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/inventory.dart';

/// Real fromJson mapping over the payload shapes migrations 0078-0081's RPCs
/// return. Money fields are integer minor units (paise).
void main() {
  test('enums round-trip through the DB spellings', () {
    expect(StockStatus.fromJson('LOW_STOCK'), StockStatus.lowStock);
    expect(StockStatus.outOfStock.label, 'Out of Stock');
    expect(MovementType.fromJson('PURCHASE_RECEIVED'), MovementType.purchaseReceived);
    expect(MovementType.stockOut.toJson(), 'STOCK_OUT');
    expect(PoStatus.fromJson('PARTIALLY_RECEIVED'), PoStatus.partiallyReceived);
    expect(PoStatus.partiallyReceived.label, 'Partially Received');
    expect(PoPaymentStatus.fromJson('PENDING'), PoPaymentStatus.pending);
    expect(PoPaymentStatus.pending.label, 'Unpaid');
    expect(ItemStatus.fromJson(null), ItemStatus.active);
  });

  test('ItemPage maps a list_inventory_items row and carries total_count', () {
    final page = ItemPage.fromRows([
      {
        'id': 'i1',
        'name': 'Shuttlecocks',
        'sku': 'SHU-01',
        'brand': 'Yonex',
        'category_id': 'c1',
        'category_name': 'Consumables',
        'unit': 'tube',
        'current_stock': 4,
        'reorder_level': 10,
        'unit_cost_minor': 25000,
        'inventory_value_minor': 100000,
        'status': 'ACTIVE',
        'stock_status': 'LOW_STOCK',
        'preferred_vendor_id': null,
        'preferred_vendor_name': null,
        'image_path': null,
        'updated_at': null,
        'total_count': 7,
      }
    ]);
    expect(page.totalCount, 7);
    expect(page.items.single.stockStatus, StockStatus.lowStock);
    expect(page.items.single.inventoryValueMinor, 100000);
  });

  test('ItemPage.fromRows is empty-safe', () {
    final page = ItemPage.fromRows(const []);
    expect(page.items, isEmpty);
    expect(page.totalCount, 0);
  });

  test('StockMovementRow accepts a signed quantity and reference label', () {
    final m = StockMovementRow.fromJson({
      'id': 'm1',
      'created_at': '2026-09-01T10:30:00Z',
      'movement_type': 'STOCK_OUT',
      'item_id': 'i1',
      'item_name': 'Shuttlecocks',
      'quantity': -5,
      'balance_after': 3,
      'unit_cost_minor': null,
      'reason': 'Court use',
      'notes': null,
      'reference_label': 'MT-ABCD',
      'performed_by_name': 'Rahul',
    });
    expect(m.quantity, -5);
    expect(m.balanceAfter, 3);
    expect(m.referenceLabel, 'MT-ABCD');
  });

  test('PurchaseOrderDetail maps the get_purchase_order jsonb shape', () {
    final po = PurchaseOrderDetail.fromJson({
      'id': 'po1',
      'facilityId': 'f1',
      'poNumber': 'PO-2026-0001',
      'orderDate': '2026-09-01',
      'expectedDelivery': null,
      'status': 'PARTIALLY_RECEIVED',
      'reference': 'INV-9',
      'notes': null,
      'invoicePath': null,
      'cancelReason': null,
      'vendor': {'id': 'v1', 'name': 'Acme Sports', 'phone': '99999'},
      'financials': {
        'subtotalMinor': 500000,
        'taxMinor': 90000,
        'discountMinor': 0,
        'totalMinor': 590000,
        'paidMinor': 100000,
        'outstandingMinor': 490000,
        'paymentStatus': 'PARTIAL',
        'expenseId': 'e1',
      },
      'lines': [
        {
          'id': 'l1',
          'itemId': 'i1',
          'itemName': 'Shuttlecocks',
          'sku': 'SHU-01',
          'unit': 'tube',
          'quantityOrdered': 20,
          'quantityReceived': 8,
          'quantityPending': 12,
          'unitCostMinor': 25000,
          'lineTotalMinor': 500000,
        }
      ],
      'events': [
        {'id': 'ev1', 'summary': 'Order placed', 'actorName': 'Priya', 'createdAt': '2026-09-01T09:00:00Z'}
      ],
    });
    expect(po.vendorName, 'Acme Sports');
    expect(po.outstandingMinor, 490000);
    expect(po.paymentStatus, PoPaymentStatus.partial);
    expect(po.lines.single.quantityPending, 12);
    expect(po.events.single.summary, 'Order placed');
  });

  test('InventoryOverview maps kpis + stockStatus', () {
    final o = InventoryOverview.fromJson({
      'kpis': {
        'totalItems': 12,
        'lowStockItems': 3,
        'outOfStockItems': 1,
        'inactiveItems': 2,
        'inventoryValueMinor': 1234500,
        'activeVendors': 4,
        'pendingPurchaseOrders': 2,
      },
      'stockStatus': {'inStock': 8, 'lowStock': 3, 'outOfStock': 1},
      'recentMovements': const [],
      'lowStockItems': const [],
      'topCategoriesByValue': const [],
    });
    expect(o.totalItems, 12);
    expect(o.inventoryValueMinor, 1234500);
    expect(o.lowStock, 3);
  });
}
