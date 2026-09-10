"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { ServiceError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";
import type {
  CategoryRow,
  CreateItemInput,
  CreatePurchaseOrderInput,
  InventoryOverview,
  ItemDetail,
  ItemFilters,
  ItemPage,
  PurchaseOrderDetail,
  PurchaseOrderFilters,
  PurchaseOrderPage,
  RecordMovementInput,
  ReceiptLineInput,
  StockMovementFilters,
  StockMovementPage,
  UpdateItemInput,
  VendorDetail,
  VendorFilters,
  VendorInput,
  VendorPage,
} from "@/features/inventory/types";

function mapError(error: unknown): ServiceError {
  console.error("[inventory-service] request failed", error);
  const message = (error as { message?: string } | null)?.message ?? "";
  const code = (error as { code?: string } | null)?.code ?? "";
  if (code === "42501" || /permission/i.test(message)) {
    return new ServiceError("INVENTORY_ACCESS_DENIED", message || undefined);
  }
  if (code === "23505" || /already (exists|in use|has)/i.test(message)) {
    return new ServiceError("INVENTORY_DUPLICATE", message || undefined);
  }
  if (code === "P0002" || /not found/i.test(message)) {
    return new ServiceError("INVENTORY_NOT_FOUND", message || undefined);
  }
  // Server-side business rules raise plain messages (insufficient stock, can't
  // receive more than pending, PO already received, …) — surface them verbatim.
  if (message) return new ServiceError("INVENTORY_RULE_ERROR", message);
  return new ServiceError("INVENTORY_DATA_ERROR");
}

export class SupabaseInventoryService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  // ── Overview ─────────────────────────────────────────────────────────────
  async getOverview(facilityId: string): Promise<InventoryOverview> {
    const { data, error } = await this.supabase.rpc("get_inventory_overview", { p_facility_id: facilityId });
    if (error || !data) throw mapError(error);
    return data as unknown as InventoryOverview;
  }

  // ── Items ────────────────────────────────────────────────────────────────
  async listItems(input: { facilityId: string; filters?: ItemFilters; limit?: number; offset?: number }): Promise<ItemPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_inventory_items", {
      p_facility_id: input.facilityId,
      p_search: f.search?.trim() || null,
      p_category_id: f.categoryId ?? null,
      p_status: f.status ?? null,
      p_stock_status: f.stockStatus ?? null,
      p_vendor_id: f.vendorId ?? null,
      p_sort: f.sort ?? "name",
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      items: (data ?? []).map((r) => ({
        id: r.id,
        name: r.name,
        sku: r.sku,
        brand: r.brand,
        categoryId: r.category_id,
        categoryName: r.category_name,
        unit: r.unit,
        currentStock: r.current_stock,
        reorderLevel: r.reorder_level,
        unitCostMinor: r.unit_cost_minor,
        inventoryValueMinor: r.inventory_value_minor,
        status: r.status,
        stockStatus: r.stock_status,
        preferredVendorId: r.preferred_vendor_id,
        preferredVendorName: r.preferred_vendor_name,
        imagePath: r.image_path,
        updatedAt: r.updated_at,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getItem(itemId: string): Promise<ItemDetail> {
    const { data, error } = await this.supabase.rpc("get_inventory_item", { p_item_id: itemId });
    if (error || !data) throw mapError(error);
    return data as unknown as ItemDetail;
  }

  async createItem(input: CreateItemInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_inventory_item", {
      p_facility_id: input.facilityId,
      p_name: input.name,
      p_sku: input.sku,
      p_category_id: input.categoryId ?? null,
      p_unit: input.unit ?? "piece",
      p_reorder_level: input.reorderLevel ?? 0,
      p_brand: input.brand ?? null,
      p_description: input.description ?? null,
      p_default_unit_cost_minor: input.defaultUnitCostMinor ?? null,
      p_preferred_vendor_id: input.preferredVendorId ?? null,
      p_image_path: input.imagePath ?? null,
      p_opening_stock: input.openingStock ?? 0,
    });
    if (error || !data) throw mapError(error);
    return data.id;
  }

  async updateItem(input: UpdateItemInput): Promise<void> {
    const { error } = await this.supabase.rpc("update_inventory_item", {
      p_item_id: input.itemId,
      p_name: input.name ?? null,
      p_sku: input.sku ?? null,
      p_category_id: input.categoryId ?? null,
      p_unit: input.unit ?? null,
      p_reorder_level: input.reorderLevel ?? null,
      p_brand: input.brand ?? null,
      p_description: input.description ?? null,
      p_default_unit_cost_minor: input.defaultUnitCostMinor ?? null,
      p_preferred_vendor_id: input.preferredVendorId ?? null,
      p_image_path: input.imagePath ?? null,
      p_status: input.status ?? null,
    });
    if (error) throw mapError(error);
  }

  // ── Stock movements ──────────────────────────────────────────────────────
  async recordMovement(input: RecordMovementInput): Promise<void> {
    const { error } = await this.supabase.rpc("record_stock_movement", {
      p_item_id: input.itemId,
      p_movement_type: input.movementType,
      p_quantity: input.quantity,
      p_reason: input.reason ?? null,
      p_notes: input.notes ?? null,
      p_unit_cost_minor: input.unitCostMinor ?? null,
      p_reference_type: input.referenceType ?? "manual",
      p_reference_id: input.referenceId ?? null,
    });
    if (error) throw mapError(error);
  }

  async listMovements(input: {
    facilityId: string;
    filters?: StockMovementFilters;
    limit?: number;
    offset?: number;
  }): Promise<StockMovementPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_stock_movements", {
      p_facility_id: input.facilityId,
      p_movement_type: f.movementType ?? null,
      p_item_id: f.itemId ?? null,
      p_from: f.from ?? null,
      p_to: f.to ?? null,
      p_performed_by: f.performedBy ?? null,
      p_limit: input.limit ?? 25,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      movements: (data ?? []).map((r) => ({
        id: r.id,
        createdAt: r.created_at,
        movementType: r.movement_type,
        itemId: r.item_id,
        itemName: r.item_name,
        quantity: r.quantity,
        balanceAfter: r.balance_after,
        unitCostMinor: r.unit_cost_minor,
        reason: r.reason,
        notes: r.notes,
        referenceType: r.reference_type,
        referenceId: r.reference_id,
        referenceLabel: r.reference_label,
        performedBy: r.performed_by,
        performedByName: r.performed_by_name,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  // ── Categories ───────────────────────────────────────────────────────────
  async listCategories(facilityId: string): Promise<CategoryRow[]> {
    const { data, error } = await this.supabase.rpc("list_inventory_categories", { p_facility_id: facilityId });
    if (error) throw mapError(error);
    return (data ?? []).map((r) => ({
      id: r.id,
      name: r.name,
      description: r.description,
      isActive: r.is_active,
      sortOrder: r.sort_order,
      itemCount: r.item_count,
      inventoryValueMinor: r.inventory_value_minor,
    }));
  }

  async createCategory(input: { facilityId: string; name: string; description?: string | null; sortOrder?: number }): Promise<void> {
    const { error } = await this.supabase.rpc("create_inventory_category", {
      p_facility_id: input.facilityId,
      p_name: input.name,
      p_description: input.description ?? null,
      p_sort_order: input.sortOrder ?? 0,
    });
    if (error) throw mapError(error);
  }

  async updateCategory(input: {
    categoryId: string;
    name?: string | null;
    description?: string | null;
    isActive?: boolean | null;
    sortOrder?: number | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("update_inventory_category", {
      p_category_id: input.categoryId,
      p_name: input.name ?? null,
      p_description: input.description ?? null,
      p_is_active: input.isActive ?? null,
      p_sort_order: input.sortOrder ?? null,
    });
    if (error) throw mapError(error);
  }

  // ── Vendors ──────────────────────────────────────────────────────────────
  async listVendors(input: {
    facilityId: string;
    filters?: VendorFilters;
    limit?: number;
    offset?: number;
  }): Promise<VendorPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_vendors", {
      p_facility_id: input.facilityId,
      p_search: f.search?.trim() || null,
      p_status: f.status ?? null,
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      vendors: (data ?? []).map((r) => ({
        id: r.id,
        name: r.name,
        contactPerson: r.contact_person,
        phone: r.phone,
        email: r.email,
        status: r.status,
        poCount: r.po_count,
        totalPurchasesMinor: r.total_purchases_minor,
        outstandingMinor: r.outstanding_minor,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getVendor(vendorId: string): Promise<VendorDetail> {
    const { data, error } = await this.supabase.rpc("get_vendor", { p_vendor_id: vendorId });
    if (error || !data) throw mapError(error);
    return data as unknown as VendorDetail;
  }

  async createVendor(facilityId: string, input: VendorInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_vendor", {
      p_facility_id: facilityId,
      p_name: input.name,
      p_contact_person: input.contactPerson ?? null,
      p_phone: input.phone ?? null,
      p_email: input.email ?? null,
      p_address: input.address ?? null,
      p_gst_number: input.gstNumber ?? null,
      p_pan_number: input.panNumber ?? null,
      p_notes: input.notes ?? null,
    });
    if (error || !data) throw mapError(error);
    return data.id;
  }

  async updateVendor(vendorId: string, input: VendorInput): Promise<void> {
    const { error } = await this.supabase.rpc("update_vendor", {
      p_vendor_id: vendorId,
      p_name: input.name ?? null,
      p_contact_person: input.contactPerson ?? null,
      p_phone: input.phone ?? null,
      p_email: input.email ?? null,
      p_address: input.address ?? null,
      p_gst_number: input.gstNumber ?? null,
      p_pan_number: input.panNumber ?? null,
      p_notes: input.notes ?? null,
      p_status: input.status ?? null,
    });
    if (error) throw mapError(error);
  }

  // ── Purchase orders ──────────────────────────────────────────────────────
  async listPurchaseOrders(input: {
    facilityId: string;
    filters?: PurchaseOrderFilters;
    limit?: number;
    offset?: number;
  }): Promise<PurchaseOrderPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_purchase_orders", {
      p_facility_id: input.facilityId,
      p_vendor_id: f.vendorId ?? null,
      p_status: f.status ?? null,
      p_payment_status: f.paymentStatus ?? null,
      p_from: f.from ?? null,
      p_to: f.to ?? null,
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      purchaseOrders: (data ?? []).map((r) => ({
        id: r.id,
        poNumber: r.po_number,
        vendorId: r.vendor_id,
        vendorName: r.vendor_name,
        orderDate: r.order_date,
        expectedDelivery: r.expected_delivery,
        status: r.status,
        totalMinor: r.total_minor,
        amountPaidMinor: r.amount_paid_minor,
        paymentStatus: r.payment_status as PurchaseOrderPage["purchaseOrders"][number]["paymentStatus"],
        itemCount: r.item_count,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getPurchaseOrder(poId: string): Promise<PurchaseOrderDetail> {
    const { data, error } = await this.supabase.rpc("get_purchase_order", { p_po_id: poId });
    if (error || !data) throw mapError(error);
    return data as unknown as PurchaseOrderDetail;
  }

  async createPurchaseOrder(input: CreatePurchaseOrderInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_purchase_order", {
      p_facility_id: input.facilityId,
      p_vendor_id: input.vendorId,
      p_lines: input.lines.map((l) => ({
        itemId: l.itemId,
        quantity: l.quantity,
        unitCostMinor: l.unitCostMinor,
        taxMinor: l.taxMinor ?? 0,
        discountMinor: l.discountMinor ?? 0,
      })),
      p_order_date: input.orderDate ?? null,
      p_expected_delivery: input.expectedDelivery ?? null,
      p_reference: input.reference ?? null,
      p_notes: input.notes ?? null,
      p_invoice_path: input.invoicePath ?? null,
    });
    if (error || !data) throw mapError(error);
    return data;
  }

  async updatePurchaseOrder(input: {
    poId: string;
    lines?: CreatePurchaseOrderInput["lines"];
    expectedDelivery?: string | null;
    reference?: string | null;
    notes?: string | null;
    invoicePath?: string | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("update_purchase_order", {
      p_po_id: input.poId,
      p_lines: input.lines
        ? input.lines.map((l) => ({
            itemId: l.itemId,
            quantity: l.quantity,
            unitCostMinor: l.unitCostMinor,
            taxMinor: l.taxMinor ?? 0,
            discountMinor: l.discountMinor ?? 0,
          }))
        : undefined,
      p_expected_delivery: input.expectedDelivery ?? null,
      p_reference: input.reference ?? null,
      p_notes: input.notes ?? null,
      p_invoice_path: input.invoicePath ?? null,
    });
    if (error) throw mapError(error);
  }

  async placePurchaseOrder(poId: string): Promise<void> {
    const { error } = await this.supabase.rpc("place_purchase_order", { p_po_id: poId });
    if (error) throw mapError(error);
  }

  async receivePurchaseOrder(poId: string, receipts: ReceiptLineInput[]): Promise<void> {
    const { error } = await this.supabase.rpc("receive_purchase_order", {
      p_po_id: poId,
      p_receipts: receipts.map((r) => ({ lineId: r.lineId, quantity: r.quantity })),
    });
    if (error) throw mapError(error);
  }

  async cancelPurchaseOrder(poId: string, reason: string): Promise<void> {
    const { error } = await this.supabase.rpc("cancel_purchase_order", { p_po_id: poId, p_reason: reason });
    if (error) throw mapError(error);
  }

  async recordPurchasePayment(input: {
    poId: string;
    amountMinor: number;
    paidOn?: string | null;
    paymentMethod?: string | null;
    reference?: string | null;
    note?: string | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("record_purchase_payment", {
      p_po_id: input.poId,
      p_amount_minor: input.amountMinor,
      p_paid_on: input.paidOn ?? null,
      p_payment_method: input.paymentMethod ?? null,
      p_reference: input.reference ?? null,
      p_note: input.note ?? null,
    });
    if (error) throw mapError(error);
  }

  // ── Storage ──────────────────────────────────────────────────────────────
  async uploadAsset(facilityId: string, file: File, kind: "items" | "invoices"): Promise<string> {
    const ext = file.name.split(".").pop()?.toLowerCase() || "bin";
    const path = `${facilityId}/${kind}/${crypto.randomUUID()}.${ext}`;
    const { error } = await this.supabase.storage.from("inventory").upload(path, file, { upsert: false });
    if (error) throw new ServiceError("INVENTORY_DATA_ERROR", error.message);
    return path;
  }

  async signedUrl(path: string): Promise<string | null> {
    const { data } = await this.supabase.storage.from("inventory").createSignedUrl(path, 3600);
    return data?.signedUrl ?? null;
  }
}
