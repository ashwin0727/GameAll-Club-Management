// ═══════════════════════════════════════════════════════════════════════════
// Inventory & Vendors — the shapes the UI works with.
//
// Inventory is the source of truth for STOCK; Finance owns MONEY. Every
// authorization decision is the database's (has_permission + RLS on every
// RPC). Nothing the client sends about quantities, costs or payment status is
// trusted — the RPCs validate server-side.
// ═══════════════════════════════════════════════════════════════════════════

export type ItemStatus = "ACTIVE" | "INACTIVE";
export type StockStatus = "IN_STOCK" | "LOW_STOCK" | "OUT_OF_STOCK";
export type VendorStatus = "ACTIVE" | "INACTIVE";
export type MovementType =
  | "STOCK_IN"
  | "STOCK_OUT"
  | "ADJUSTMENT"
  | "PURCHASE_RECEIVED"
  | "RETURN";
export type PoStatus =
  | "DRAFT"
  | "ORDERED"
  | "PARTIALLY_RECEIVED"
  | "RECEIVED"
  | "CANCELLED";
export type PoPaymentStatus = "UNBILLED" | "PENDING" | "PARTIAL" | "PAID";

// ── Overview ───────────────────────────────────────────────────────────────
export interface InventoryOverview {
  kpis: {
    totalItems: number;
    lowStockItems: number;
    outOfStockItems: number;
    inactiveItems: number;
    inventoryValueMinor: number;
    activeVendors: number;
    pendingPurchaseOrders: number;
  };
  stockStatus: { inStock: number; lowStock: number; outOfStock: number };
  recentMovements: StockMovementRow[];
  lowStockItems: {
    id: string;
    name: string;
    sku: string;
    currentStock: number;
    reorderLevel: number;
    unit: string;
  }[];
  topCategoriesByValue: { id: string; name: string; valueMinor: number; itemCount: number }[];
}

// ── Items ──────────────────────────────────────────────────────────────────
export interface ItemRow {
  id: string;
  name: string;
  sku: string;
  brand: string | null;
  categoryId: string | null;
  categoryName: string | null;
  unit: string;
  currentStock: number;
  reorderLevel: number;
  unitCostMinor: number;
  inventoryValueMinor: number;
  status: ItemStatus;
  stockStatus: StockStatus;
  preferredVendorId: string | null;
  preferredVendorName: string | null;
  imagePath: string | null;
  updatedAt: string | null;
}

export interface ItemPage {
  items: ItemRow[];
  totalCount: number;
}

export interface ItemFilters {
  search?: string | null;
  categoryId?: string | null;
  status?: ItemStatus | null;
  stockStatus?: StockStatus | null;
  vendorId?: string | null;
  sort?: string | null;
}

export interface ItemDetail {
  id: string;
  facilityId: string;
  name: string;
  sku: string;
  brand: string | null;
  description: string | null;
  categoryId: string | null;
  categoryName: string | null;
  unit: string;
  reorderLevel: number;
  unitCostMinor: number;
  defaultUnitCostMinor: number | null;
  currentStock: number;
  inventoryValueMinor: number;
  status: ItemStatus;
  stockStatus: StockStatus;
  preferredVendorId: string | null;
  preferredVendorName: string | null;
  imagePath: string | null;
  createdAt: string;
  updatedAt: string | null;
  stats: {
    totalInQty: number;
    totalOutQty: number;
    lastStockInAt: string | null;
    lastStockOutAt: string | null;
  };
  recentMovements: StockMovementRow[];
  purchases: {
    poId: string;
    poNumber: string;
    vendorName: string;
    orderDate: string;
    quantityOrdered: number;
    quantityReceived: number;
    unitCostMinor: number;
    status: PoStatus;
  }[];
}

export interface CreateItemInput {
  facilityId: string;
  name: string;
  sku: string;
  categoryId?: string | null;
  unit?: string;
  reorderLevel?: number;
  brand?: string | null;
  description?: string | null;
  defaultUnitCostMinor?: number | null;
  preferredVendorId?: string | null;
  imagePath?: string | null;
  openingStock?: number;
}

export interface UpdateItemInput {
  itemId: string;
  name?: string | null;
  sku?: string | null;
  categoryId?: string | null;
  unit?: string | null;
  reorderLevel?: number | null;
  brand?: string | null;
  description?: string | null;
  defaultUnitCostMinor?: number | null;
  preferredVendorId?: string | null;
  imagePath?: string | null;
  status?: ItemStatus | null;
}

// ── Stock movements ────────────────────────────────────────────────────────
export interface StockMovementRow {
  id: string;
  createdAt: string;
  movementType: MovementType;
  itemId: string;
  itemName: string;
  quantity: number;
  balanceAfter: number;
  unitCostMinor: number | null;
  reason: string | null;
  notes: string | null;
  referenceType: string | null;
  referenceId: string | null;
  referenceLabel: string | null;
  performedBy: string | null;
  performedByName: string | null;
}

export interface StockMovementPage {
  movements: StockMovementRow[];
  totalCount: number;
}

export interface StockMovementFilters {
  movementType?: MovementType | null;
  itemId?: string | null;
  from?: string | null;
  to?: string | null;
  performedBy?: string | null;
}

export interface RecordMovementInput {
  itemId: string;
  movementType: "STOCK_IN" | "STOCK_OUT" | "ADJUSTMENT" | "RETURN";
  /** Signed. STOCK_OUT is normalised to a negative value server-side. */
  quantity: number;
  reason?: string | null;
  notes?: string | null;
  unitCostMinor?: number | null;
  referenceType?: string;
  referenceId?: string | null;
}

// ── Categories ─────────────────────────────────────────────────────────────
export interface CategoryRow {
  id: string;
  name: string;
  description: string | null;
  isActive: boolean;
  sortOrder: number;
  itemCount: number;
  inventoryValueMinor: number;
}

// ── Vendors ────────────────────────────────────────────────────────────────
export interface VendorRow {
  id: string;
  name: string;
  contactPerson: string | null;
  phone: string | null;
  email: string | null;
  status: VendorStatus;
  poCount: number;
  totalPurchasesMinor: number;
  outstandingMinor: number;
}

export interface VendorPage {
  vendors: VendorRow[];
  totalCount: number;
}

export interface VendorFilters {
  search?: string | null;
  status?: VendorStatus | null;
}

export interface VendorDetail {
  id: string;
  facilityId: string;
  name: string;
  contactPerson: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
  gstNumber: string | null;
  panNumber: string | null;
  notes: string | null;
  status: VendorStatus;
  createdAt: string;
  summary: {
    poCount: number;
    totalPurchasesMinor: number;
    paidMinor: number;
    outstandingMinor: number;
    lastOrderDate: string | null;
  };
  suppliedItems: {
    id: string;
    name: string;
    sku: string;
    currentStock: number;
    unit: string;
    lastUnitCostMinor: number | null;
  }[];
  purchaseHistory: {
    poId: string;
    poNumber: string;
    orderDate: string;
    status: PoStatus;
    totalMinor: number;
    paymentStatus: PoPaymentStatus;
  }[];
  payments: {
    id: string;
    poNumber: string | null;
    amountMinor: number;
    paidOn: string;
    method: string | null;
    reference: string | null;
  }[];
}

export interface VendorInput {
  name: string;
  contactPerson?: string | null;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  gstNumber?: string | null;
  panNumber?: string | null;
  notes?: string | null;
  status?: VendorStatus | null;
}

// ── Purchase orders ────────────────────────────────────────────────────────
export interface PurchaseOrderRow {
  id: string;
  poNumber: string;
  vendorId: string;
  vendorName: string;
  orderDate: string;
  expectedDelivery: string | null;
  status: PoStatus;
  totalMinor: number;
  amountPaidMinor: number;
  paymentStatus: PoPaymentStatus;
  itemCount: number;
}

export interface PurchaseOrderPage {
  purchaseOrders: PurchaseOrderRow[];
  totalCount: number;
}

export interface PurchaseOrderFilters {
  vendorId?: string | null;
  status?: PoStatus | null;
  paymentStatus?: PoPaymentStatus | null;
  from?: string | null;
  to?: string | null;
}

export interface PurchaseOrderLineInput {
  itemId: string;
  quantity: number;
  unitCostMinor: number;
  taxMinor?: number;
  discountMinor?: number;
}

export interface CreatePurchaseOrderInput {
  facilityId: string;
  vendorId: string;
  lines: PurchaseOrderLineInput[];
  orderDate?: string | null;
  expectedDelivery?: string | null;
  reference?: string | null;
  notes?: string | null;
  invoicePath?: string | null;
}

export interface PurchaseOrderDetail {
  id: string;
  facilityId: string;
  poNumber: string;
  orderDate: string;
  expectedDelivery: string | null;
  status: PoStatus;
  reference: string | null;
  notes: string | null;
  invoicePath: string | null;
  cancelReason: string | null;
  createdAt: string;
  vendor: { id: string; name: string; contactPerson: string | null; phone: string | null; email: string | null };
  financials: {
    subtotalMinor: number;
    taxMinor: number;
    discountMinor: number;
    totalMinor: number;
    paidMinor: number;
    outstandingMinor: number;
    paymentStatus: PoPaymentStatus;
    expenseId: string | null;
  };
  lines: {
    id: string;
    itemId: string;
    itemName: string;
    sku: string;
    unit: string;
    quantityOrdered: number;
    quantityReceived: number;
    quantityPending: number;
    unitCostMinor: number;
    taxMinor: number;
    discountMinor: number;
    lineTotalMinor: number;
  }[];
  events: { id: string; event: string; summary: string; actorName: string | null; createdAt: string }[];
}

export interface ReceiptLineInput {
  lineId: string;
  quantity: number;
}
