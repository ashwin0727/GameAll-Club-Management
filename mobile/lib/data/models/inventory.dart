// ═══════════════════════════════════════════════════════════════════════════
// Inventory & Vendors — mirrors src/features/inventory/types.ts.
// Backend: migrations 0078-0081. Inventory is the source of truth for STOCK,
// Finance for MONEY. Every authorization decision is the database's
// (has_permission + RLS); these are just the shapes the UI renders.
// Money fields are integer minor units (paise).
// ═══════════════════════════════════════════════════════════════════════════

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;
int? _intOrNull(dynamic v) => (v as num?)?.toInt();

enum ItemStatus {
  active,
  inactive;

  static ItemStatus fromJson(String? v) => v == 'INACTIVE' ? ItemStatus.inactive : ItemStatus.active;
  String toJson() => this == ItemStatus.inactive ? 'INACTIVE' : 'ACTIVE';
  String get label => this == ItemStatus.inactive ? 'Inactive' : 'Active';
}

enum StockStatus {
  inStock,
  lowStock,
  outOfStock;

  static StockStatus fromJson(String? v) => switch (v) {
        'LOW_STOCK' => StockStatus.lowStock,
        'OUT_OF_STOCK' => StockStatus.outOfStock,
        _ => StockStatus.inStock,
      };
  String get label => switch (this) {
        StockStatus.lowStock => 'Low Stock',
        StockStatus.outOfStock => 'Out of Stock',
        StockStatus.inStock => 'In Stock',
      };
}

enum VendorStatus {
  active,
  inactive;

  static VendorStatus fromJson(String? v) => v == 'INACTIVE' ? VendorStatus.inactive : VendorStatus.active;
  String toJson() => this == VendorStatus.inactive ? 'INACTIVE' : 'ACTIVE';
  String get label => this == VendorStatus.inactive ? 'Inactive' : 'Active';
}

enum MovementType {
  stockIn,
  stockOut,
  adjustment,
  purchaseReceived,
  returnStock;

  static MovementType fromJson(String? v) => switch (v) {
        'STOCK_OUT' => MovementType.stockOut,
        'ADJUSTMENT' => MovementType.adjustment,
        'PURCHASE_RECEIVED' => MovementType.purchaseReceived,
        'RETURN' => MovementType.returnStock,
        _ => MovementType.stockIn,
      };
  String toJson() => switch (this) {
        MovementType.stockOut => 'STOCK_OUT',
        MovementType.adjustment => 'ADJUSTMENT',
        MovementType.purchaseReceived => 'PURCHASE_RECEIVED',
        MovementType.returnStock => 'RETURN',
        MovementType.stockIn => 'STOCK_IN',
      };
  String get label => switch (this) {
        MovementType.stockOut => 'Stock Out',
        MovementType.adjustment => 'Adjustment',
        MovementType.purchaseReceived => 'Received',
        MovementType.returnStock => 'Return',
        MovementType.stockIn => 'Stock In',
      };
}

enum PoStatus {
  draft,
  ordered,
  partiallyReceived,
  received,
  cancelled;

  static PoStatus fromJson(String? v) => switch (v) {
        'ORDERED' => PoStatus.ordered,
        'PARTIALLY_RECEIVED' => PoStatus.partiallyReceived,
        'RECEIVED' => PoStatus.received,
        'CANCELLED' => PoStatus.cancelled,
        _ => PoStatus.draft,
      };
  String toJson() => switch (this) {
        PoStatus.ordered => 'ORDERED',
        PoStatus.partiallyReceived => 'PARTIALLY_RECEIVED',
        PoStatus.received => 'RECEIVED',
        PoStatus.cancelled => 'CANCELLED',
        PoStatus.draft => 'DRAFT',
      };
  String get label => switch (this) {
        PoStatus.ordered => 'Ordered',
        PoStatus.partiallyReceived => 'Partially Received',
        PoStatus.received => 'Received',
        PoStatus.cancelled => 'Cancelled',
        PoStatus.draft => 'Draft',
      };
}

enum PoPaymentStatus {
  unbilled,
  pending,
  partial,
  paid;

  static PoPaymentStatus fromJson(String? v) => switch (v) {
        'PENDING' => PoPaymentStatus.pending,
        'PARTIAL' => PoPaymentStatus.partial,
        'PAID' => PoPaymentStatus.paid,
        _ => PoPaymentStatus.unbilled,
      };
  String get label => switch (this) {
        PoPaymentStatus.pending => 'Unpaid',
        PoPaymentStatus.partial => 'Partially Paid',
        PoPaymentStatus.paid => 'Paid',
        PoPaymentStatus.unbilled => 'Unbilled',
      };
}

// ── Overview ───────────────────────────────────────────────────────────────
class InventoryOverview {
  const InventoryOverview({
    required this.totalItems,
    required this.lowStockItems,
    required this.outOfStockItems,
    required this.inactiveItems,
    required this.inventoryValueMinor,
    required this.activeVendors,
    required this.pendingPurchaseOrders,
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
    required this.recentMovements,
    required this.lowStockList,
    required this.topCategories,
  });

  final int totalItems;
  final int lowStockItems;
  final int outOfStockItems;
  final int inactiveItems;
  final int inventoryValueMinor;
  final int activeVendors;
  final int pendingPurchaseOrders;
  final int inStock;
  final int lowStock;
  final int outOfStock;
  final List<StockMovementRow> recentMovements;
  final List<LowStockItem> lowStockList;
  final List<CategoryValue> topCategories;

  factory InventoryOverview.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (j['stockStatus'] as Map?)?.cast<String, dynamic>() ?? const {};
    return InventoryOverview(
      totalItems: _int(k['totalItems']),
      lowStockItems: _int(k['lowStockItems']),
      outOfStockItems: _int(k['outOfStockItems']),
      inactiveItems: _int(k['inactiveItems']),
      inventoryValueMinor: _int(k['inventoryValueMinor']),
      activeVendors: _int(k['activeVendors']),
      pendingPurchaseOrders: _int(k['pendingPurchaseOrders']),
      inStock: _int(s['inStock']),
      lowStock: _int(s['lowStock']),
      outOfStock: _int(s['outOfStock']),
      recentMovements: ((j['recentMovements'] as List?) ?? const [])
          .map((e) => StockMovementRow.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      lowStockList: ((j['lowStockItems'] as List?) ?? const [])
          .map((e) => LowStockItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      topCategories: ((j['topCategoriesByValue'] as List?) ?? const [])
          .map((e) => CategoryValue.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class LowStockItem {
  const LowStockItem({required this.id, required this.name, required this.sku, required this.currentStock, required this.reorderLevel, required this.unit});
  final String id;
  final String name;
  final String sku;
  final int currentStock;
  final int reorderLevel;
  final String unit;
  factory LowStockItem.fromJson(Map<String, dynamic> j) => LowStockItem(
        id: j['id'] as String,
        name: j['name'] as String,
        sku: j['sku'] as String? ?? '',
        currentStock: _int(j['currentStock']),
        reorderLevel: _int(j['reorderLevel']),
        unit: j['unit'] as String? ?? '',
      );
}

class CategoryValue {
  const CategoryValue({required this.id, required this.name, required this.valueMinor, required this.itemCount});
  final String id;
  final String name;
  final int valueMinor;
  final int itemCount;
  factory CategoryValue.fromJson(Map<String, dynamic> j) => CategoryValue(
        id: j['id'] as String,
        name: j['name'] as String,
        valueMinor: _int(j['valueMinor']),
        itemCount: _int(j['itemCount']),
      );
}

// ── Items ──────────────────────────────────────────────────────────────────
class ItemRow {
  const ItemRow({
    required this.id,
    required this.name,
    required this.sku,
    required this.brand,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.currentStock,
    required this.reorderLevel,
    required this.unitCostMinor,
    required this.inventoryValueMinor,
    required this.status,
    required this.stockStatus,
    required this.preferredVendorId,
    required this.preferredVendorName,
  });

  final String id;
  final String name;
  final String sku;
  final String? brand;
  final String? categoryId;
  final String? categoryName;
  final String unit;
  final int currentStock;
  final int reorderLevel;
  final int unitCostMinor;
  final int inventoryValueMinor;
  final ItemStatus status;
  final StockStatus stockStatus;
  final String? preferredVendorId;
  final String? preferredVendorName;

  factory ItemRow.fromJson(Map<String, dynamic> j) => ItemRow(
        id: j['id'] as String,
        name: j['name'] as String,
        sku: j['sku'] as String? ?? '',
        brand: j['brand'] as String?,
        categoryId: j['category_id'] as String?,
        categoryName: j['category_name'] as String?,
        unit: j['unit'] as String? ?? 'piece',
        currentStock: _int(j['current_stock']),
        reorderLevel: _int(j['reorder_level']),
        unitCostMinor: _int(j['unit_cost_minor']),
        inventoryValueMinor: _int(j['inventory_value_minor']),
        status: ItemStatus.fromJson(j['status'] as String?),
        stockStatus: StockStatus.fromJson(j['stock_status'] as String?),
        preferredVendorId: j['preferred_vendor_id'] as String?,
        preferredVendorName: j['preferred_vendor_name'] as String?,
      );
}

class ItemPage {
  const ItemPage({required this.items, required this.totalCount});
  final List<ItemRow> items;
  final int totalCount;
  factory ItemPage.fromRows(List<Map<String, dynamic>> rows) => ItemPage(
        items: rows.map(ItemRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

class ItemStats {
  const ItemStats({required this.totalInQty, required this.totalOutQty, required this.lastStockInAt, required this.lastStockOutAt});
  final int totalInQty;
  final int totalOutQty;
  final String? lastStockInAt;
  final String? lastStockOutAt;
  factory ItemStats.fromJson(Map<String, dynamic> j) => ItemStats(
        totalInQty: _int(j['totalInQty']),
        totalOutQty: _int(j['totalOutQty']),
        lastStockInAt: j['lastStockInAt'] as String?,
        lastStockOutAt: j['lastStockOutAt'] as String?,
      );
}

class ItemPurchaseRef {
  const ItemPurchaseRef({
    required this.poId,
    required this.poNumber,
    required this.vendorName,
    required this.orderDate,
    required this.quantityOrdered,
    required this.quantityReceived,
    required this.unitCostMinor,
    required this.status,
  });
  final String poId;
  final String poNumber;
  final String vendorName;
  final String orderDate;
  final int quantityOrdered;
  final int quantityReceived;
  final int unitCostMinor;
  final PoStatus status;
  factory ItemPurchaseRef.fromJson(Map<String, dynamic> j) => ItemPurchaseRef(
        poId: j['poId'] as String,
        poNumber: j['poNumber'] as String,
        vendorName: j['vendorName'] as String? ?? '',
        orderDate: j['orderDate'] as String? ?? '',
        quantityOrdered: _int(j['quantityOrdered']),
        quantityReceived: _int(j['quantityReceived']),
        unitCostMinor: _int(j['unitCostMinor']),
        status: PoStatus.fromJson(j['status'] as String?),
      );
}

class ItemDetail {
  const ItemDetail({
    required this.id,
    required this.facilityId,
    required this.name,
    required this.sku,
    required this.brand,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.reorderLevel,
    required this.unitCostMinor,
    required this.defaultUnitCostMinor,
    required this.currentStock,
    required this.inventoryValueMinor,
    required this.status,
    required this.stockStatus,
    required this.preferredVendorId,
    required this.preferredVendorName,
    required this.createdAt,
    required this.updatedAt,
    required this.stats,
    required this.recentMovements,
    required this.purchases,
  });

  final String id;
  final String facilityId;
  final String name;
  final String sku;
  final String? brand;
  final String? description;
  final String? categoryId;
  final String? categoryName;
  final String unit;
  final int reorderLevel;
  final int unitCostMinor;
  final int? defaultUnitCostMinor;
  final int currentStock;
  final int inventoryValueMinor;
  final ItemStatus status;
  final StockStatus stockStatus;
  final String? preferredVendorId;
  final String? preferredVendorName;
  final String createdAt;
  final String? updatedAt;
  final ItemStats stats;
  final List<StockMovementRow> recentMovements;
  final List<ItemPurchaseRef> purchases;

  factory ItemDetail.fromJson(Map<String, dynamic> j) => ItemDetail(
        id: j['id'] as String,
        facilityId: j['facilityId'] as String? ?? j['facility_id'] as String? ?? '',
        name: j['name'] as String,
        sku: j['sku'] as String? ?? '',
        brand: j['brand'] as String?,
        description: j['description'] as String?,
        categoryId: j['categoryId'] as String?,
        categoryName: j['categoryName'] as String?,
        unit: j['unit'] as String? ?? 'piece',
        reorderLevel: _int(j['reorderLevel']),
        unitCostMinor: _int(j['unitCostMinor']),
        defaultUnitCostMinor: _intOrNull(j['defaultUnitCostMinor']),
        currentStock: _int(j['currentStock']),
        inventoryValueMinor: _int(j['inventoryValueMinor']),
        status: ItemStatus.fromJson(j['status'] as String?),
        stockStatus: StockStatus.fromJson(j['stockStatus'] as String?),
        preferredVendorId: j['preferredVendorId'] as String?,
        preferredVendorName: j['preferredVendorName'] as String?,
        createdAt: j['createdAt'] as String? ?? '',
        updatedAt: j['updatedAt'] as String?,
        stats: ItemStats.fromJson((j['stats'] as Map?)?.cast<String, dynamic>() ?? const {}),
        recentMovements: ((j['recentMovements'] as List?) ?? const [])
            .map((e) => StockMovementRow.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        purchases: ((j['purchases'] as List?) ?? const [])
            .map((e) => ItemPurchaseRef.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

// ── Stock movements ────────────────────────────────────────────────────────
class StockMovementRow {
  const StockMovementRow({
    required this.id,
    required this.createdAt,
    required this.movementType,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.balanceAfter,
    required this.unitCostMinor,
    required this.reason,
    required this.notes,
    required this.referenceLabel,
    required this.performedByName,
  });

  final String id;
  final String createdAt;
  final MovementType movementType;
  final String itemId;
  final String itemName;
  final int quantity;
  final int balanceAfter;
  final int? unitCostMinor;
  final String? reason;
  final String? notes;
  final String? referenceLabel;
  final String? performedByName;

  factory StockMovementRow.fromJson(Map<String, dynamic> j) => StockMovementRow(
        id: j['id'] as String,
        createdAt: (j['created_at'] ?? j['createdAt']) as String? ?? '',
        movementType: MovementType.fromJson((j['movement_type'] ?? j['movementType']) as String?),
        itemId: (j['item_id'] ?? j['itemId']) as String? ?? '',
        itemName: (j['item_name'] ?? j['itemName']) as String? ?? '',
        quantity: _int(j['quantity']),
        balanceAfter: _int(j['balance_after'] ?? j['balanceAfter']),
        unitCostMinor: _intOrNull(j['unit_cost_minor'] ?? j['unitCostMinor']),
        reason: j['reason'] as String?,
        notes: j['notes'] as String?,
        referenceLabel: (j['reference_label'] ?? j['referenceLabel']) as String?,
        performedByName: (j['performed_by_name'] ?? j['performedByName']) as String?,
      );
}

class StockMovementPage {
  const StockMovementPage({required this.movements, required this.totalCount});
  final List<StockMovementRow> movements;
  final int totalCount;
  factory StockMovementPage.fromRows(List<Map<String, dynamic>> rows) => StockMovementPage(
        movements: rows.map(StockMovementRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

// ── Categories ─────────────────────────────────────────────────────────────
class InventoryCategory {
  const InventoryCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.isActive,
    required this.sortOrder,
    required this.itemCount,
    required this.inventoryValueMinor,
  });
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final int itemCount;
  final int inventoryValueMinor;
  factory InventoryCategory.fromJson(Map<String, dynamic> j) => InventoryCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: _int(j['sort_order']),
        itemCount: _int(j['item_count']),
        inventoryValueMinor: _int(j['inventory_value_minor']),
      );
}

// ── Vendors ────────────────────────────────────────────────────────────────
class VendorRow {
  const VendorRow({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.status,
    required this.poCount,
    required this.totalPurchasesMinor,
    required this.outstandingMinor,
  });
  final String id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final VendorStatus status;
  final int poCount;
  final int totalPurchasesMinor;
  final int outstandingMinor;
  factory VendorRow.fromJson(Map<String, dynamic> j) => VendorRow(
        id: j['id'] as String,
        name: j['name'] as String,
        contactPerson: j['contact_person'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        status: VendorStatus.fromJson(j['status'] as String?),
        poCount: _int(j['po_count']),
        totalPurchasesMinor: _int(j['total_purchases_minor']),
        outstandingMinor: _int(j['outstanding_minor']),
      );
}

class VendorPage {
  const VendorPage({required this.vendors, required this.totalCount});
  final List<VendorRow> vendors;
  final int totalCount;
  factory VendorPage.fromRows(List<Map<String, dynamic>> rows) => VendorPage(
        vendors: rows.map(VendorRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

class VendorSuppliedItem {
  const VendorSuppliedItem({required this.id, required this.name, required this.sku, required this.currentStock, required this.unit, required this.lastUnitCostMinor});
  final String id;
  final String name;
  final String sku;
  final int currentStock;
  final String unit;
  final int? lastUnitCostMinor;
  factory VendorSuppliedItem.fromJson(Map<String, dynamic> j) => VendorSuppliedItem(
        id: j['id'] as String,
        name: j['name'] as String,
        sku: j['sku'] as String? ?? '',
        currentStock: _int(j['currentStock']),
        unit: j['unit'] as String? ?? '',
        lastUnitCostMinor: _intOrNull(j['lastUnitCostMinor']),
      );
}

class VendorPurchaseRef {
  const VendorPurchaseRef({required this.poId, required this.poNumber, required this.orderDate, required this.status, required this.totalMinor, required this.paymentStatus});
  final String poId;
  final String poNumber;
  final String orderDate;
  final PoStatus status;
  final int totalMinor;
  final PoPaymentStatus paymentStatus;
  factory VendorPurchaseRef.fromJson(Map<String, dynamic> j) => VendorPurchaseRef(
        poId: j['poId'] as String,
        poNumber: j['poNumber'] as String,
        orderDate: j['orderDate'] as String? ?? '',
        status: PoStatus.fromJson(j['status'] as String?),
        totalMinor: _int(j['totalMinor']),
        paymentStatus: PoPaymentStatus.fromJson(j['paymentStatus'] as String?),
      );
}

class VendorPaymentRef {
  const VendorPaymentRef({required this.id, required this.poNumber, required this.amountMinor, required this.paidOn, required this.method, required this.reference});
  final String id;
  final String? poNumber;
  final int amountMinor;
  final String paidOn;
  final String? method;
  final String? reference;
  factory VendorPaymentRef.fromJson(Map<String, dynamic> j) => VendorPaymentRef(
        id: j['id'] as String,
        poNumber: j['poNumber'] as String?,
        amountMinor: _int(j['amountMinor']),
        paidOn: j['paidOn'] as String? ?? '',
        method: j['method'] as String?,
        reference: j['reference'] as String?,
      );
}

class VendorDetail {
  const VendorDetail({
    required this.id,
    required this.facilityId,
    required this.name,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.address,
    required this.gstNumber,
    required this.panNumber,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.poCount,
    required this.totalPurchasesMinor,
    required this.paidMinor,
    required this.outstandingMinor,
    required this.lastOrderDate,
    required this.suppliedItems,
    required this.purchaseHistory,
    required this.payments,
  });

  final String id;
  final String facilityId;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? gstNumber;
  final String? panNumber;
  final String? notes;
  final VendorStatus status;
  final String createdAt;
  final int poCount;
  final int totalPurchasesMinor;
  final int paidMinor;
  final int outstandingMinor;
  final String? lastOrderDate;
  final List<VendorSuppliedItem> suppliedItems;
  final List<VendorPurchaseRef> purchaseHistory;
  final List<VendorPaymentRef> payments;

  factory VendorDetail.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return VendorDetail(
      id: j['id'] as String,
      facilityId: j['facilityId'] as String? ?? j['facility_id'] as String? ?? '',
      name: j['name'] as String,
      contactPerson: j['contactPerson'] as String?,
      phone: j['phone'] as String?,
      email: j['email'] as String?,
      address: j['address'] as String?,
      gstNumber: j['gstNumber'] as String?,
      panNumber: j['panNumber'] as String?,
      notes: j['notes'] as String?,
      status: VendorStatus.fromJson(j['status'] as String?),
      createdAt: j['createdAt'] as String? ?? '',
      poCount: _int(s['poCount']),
      totalPurchasesMinor: _int(s['totalPurchasesMinor']),
      paidMinor: _int(s['paidMinor']),
      outstandingMinor: _int(s['outstandingMinor']),
      lastOrderDate: s['lastOrderDate'] as String?,
      suppliedItems: ((j['suppliedItems'] as List?) ?? const [])
          .map((e) => VendorSuppliedItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      purchaseHistory: ((j['purchaseHistory'] as List?) ?? const [])
          .map((e) => VendorPurchaseRef.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      payments: ((j['payments'] as List?) ?? const [])
          .map((e) => VendorPaymentRef.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

// ── Purchase orders ────────────────────────────────────────────────────────
class PurchaseOrderRow {
  const PurchaseOrderRow({
    required this.id,
    required this.poNumber,
    required this.vendorId,
    required this.vendorName,
    required this.orderDate,
    required this.expectedDelivery,
    required this.status,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.paymentStatus,
    required this.itemCount,
  });
  final String id;
  final String poNumber;
  final String vendorId;
  final String vendorName;
  final String orderDate;
  final String? expectedDelivery;
  final PoStatus status;
  final int totalMinor;
  final int amountPaidMinor;
  final PoPaymentStatus paymentStatus;
  final int itemCount;
  factory PurchaseOrderRow.fromJson(Map<String, dynamic> j) => PurchaseOrderRow(
        id: j['id'] as String,
        poNumber: j['po_number'] as String,
        vendorId: j['vendor_id'] as String? ?? '',
        vendorName: j['vendor_name'] as String? ?? '',
        orderDate: j['order_date'] as String? ?? '',
        expectedDelivery: j['expected_delivery'] as String?,
        status: PoStatus.fromJson(j['status'] as String?),
        totalMinor: _int(j['total_minor']),
        amountPaidMinor: _int(j['amount_paid_minor']),
        paymentStatus: PoPaymentStatus.fromJson(j['payment_status'] as String?),
        itemCount: _int(j['item_count']),
      );
}

class PurchaseOrderPage {
  const PurchaseOrderPage({required this.orders, required this.totalCount});
  final List<PurchaseOrderRow> orders;
  final int totalCount;
  factory PurchaseOrderPage.fromRows(List<Map<String, dynamic>> rows) => PurchaseOrderPage(
        orders: rows.map(PurchaseOrderRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

class PoLine {
  const PoLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.sku,
    required this.unit,
    required this.quantityOrdered,
    required this.quantityReceived,
    required this.quantityPending,
    required this.unitCostMinor,
    required this.lineTotalMinor,
  });
  final String id;
  final String itemId;
  final String itemName;
  final String sku;
  final String unit;
  final int quantityOrdered;
  final int quantityReceived;
  final int quantityPending;
  final int unitCostMinor;
  final int lineTotalMinor;
  factory PoLine.fromJson(Map<String, dynamic> j) => PoLine(
        id: j['id'] as String,
        itemId: j['itemId'] as String,
        itemName: j['itemName'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        quantityOrdered: _int(j['quantityOrdered']),
        quantityReceived: _int(j['quantityReceived']),
        quantityPending: _int(j['quantityPending']),
        unitCostMinor: _int(j['unitCostMinor']),
        lineTotalMinor: _int(j['lineTotalMinor']),
      );
}

class PoEvent {
  const PoEvent({required this.id, required this.summary, required this.actorName, required this.createdAt});
  final String id;
  final String summary;
  final String? actorName;
  final String createdAt;
  factory PoEvent.fromJson(Map<String, dynamic> j) => PoEvent(
        id: j['id'] as String,
        summary: j['summary'] as String? ?? '',
        actorName: j['actorName'] as String?,
        createdAt: j['createdAt'] as String? ?? '',
      );
}

class PurchaseOrderDetail {
  const PurchaseOrderDetail({
    required this.id,
    required this.facilityId,
    required this.poNumber,
    required this.orderDate,
    required this.expectedDelivery,
    required this.status,
    required this.reference,
    required this.notes,
    required this.invoicePath,
    required this.cancelReason,
    required this.vendorId,
    required this.vendorName,
    required this.vendorPhone,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.paidMinor,
    required this.outstandingMinor,
    required this.paymentStatus,
    required this.expenseId,
    required this.lines,
    required this.events,
  });

  final String id;
  final String facilityId;
  final String poNumber;
  final String orderDate;
  final String? expectedDelivery;
  final PoStatus status;
  final String? reference;
  final String? notes;
  final String? invoicePath;
  final String? cancelReason;
  final String vendorId;
  final String vendorName;
  final String? vendorPhone;
  final int subtotalMinor;
  final int taxMinor;
  final int discountMinor;
  final int totalMinor;
  final int paidMinor;
  final int outstandingMinor;
  final PoPaymentStatus paymentStatus;
  final String? expenseId;
  final List<PoLine> lines;
  final List<PoEvent> events;

  factory PurchaseOrderDetail.fromJson(Map<String, dynamic> j) {
    final v = (j['vendor'] as Map?)?.cast<String, dynamic>() ?? const {};
    final f = (j['financials'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PurchaseOrderDetail(
      id: j['id'] as String,
      facilityId: j['facilityId'] as String? ?? j['facility_id'] as String? ?? '',
      poNumber: j['poNumber'] as String,
      orderDate: j['orderDate'] as String? ?? '',
      expectedDelivery: j['expectedDelivery'] as String?,
      status: PoStatus.fromJson(j['status'] as String?),
      reference: j['reference'] as String?,
      notes: j['notes'] as String?,
      invoicePath: j['invoicePath'] as String?,
      cancelReason: j['cancelReason'] as String?,
      vendorId: v['id'] as String? ?? '',
      vendorName: v['name'] as String? ?? '',
      vendorPhone: v['phone'] as String?,
      subtotalMinor: _int(f['subtotalMinor']),
      taxMinor: _int(f['taxMinor']),
      discountMinor: _int(f['discountMinor']),
      totalMinor: _int(f['totalMinor']),
      paidMinor: _int(f['paidMinor']),
      outstandingMinor: _int(f['outstandingMinor']),
      paymentStatus: PoPaymentStatus.fromJson(f['paymentStatus'] as String?),
      expenseId: f['expenseId'] as String?,
      lines: ((j['lines'] as List?) ?? const [])
          .map((e) => PoLine.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      events: ((j['events'] as List?) ?? const [])
          .map((e) => PoEvent.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
