import { describe, expect, it, vi } from "vitest";
import { SupabaseInventoryService } from "@/services/inventory/supabase-inventory.service";
import { ServiceError } from "@/services/shared/service-error";

describe("SupabaseInventoryService", () => {
  it("listItems maps rows, sends filters and carries total_count", async () => {
    const row = {
      id: "i1",
      name: "Shuttlecocks",
      sku: "SHU-01",
      brand: "Yonex",
      category_id: "c1",
      category_name: "Consumables",
      unit: "tube",
      current_stock: 4,
      reorder_level: 10,
      unit_cost_minor: 25000,
      inventory_value_minor: 100000,
      status: "ACTIVE",
      stock_status: "LOW_STOCK",
      preferred_vendor_id: null,
      preferred_vendor_name: null,
      image_path: null,
      updated_at: null,
      total_count: 7,
    };
    const rpc = vi.fn(async () => ({ data: [row], error: null }));
    const service = new SupabaseInventoryService({ rpc } as never);
    const page = await service.listItems({ facilityId: "f1", filters: { stockStatus: "LOW_STOCK" } });

    expect(rpc).toHaveBeenCalledWith("list_inventory_items", {
      p_facility_id: "f1",
      p_search: null,
      p_category_id: null,
      p_status: null,
      p_stock_status: "LOW_STOCK",
      p_vendor_id: null,
      p_sort: "name",
      p_limit: 20,
      p_offset: 0,
    });
    expect(page.totalCount).toBe(7);
    expect(page.items[0]?.stockStatus).toBe("LOW_STOCK");
    expect(page.items[0]?.inventoryValueMinor).toBe(100000);
  });

  it("recordMovement normalises a stock-out to a negative quantity", async () => {
    const rpc = vi.fn(async () => ({ error: null }));
    await new SupabaseInventoryService({ rpc } as never).recordMovement({
      itemId: "i1",
      movementType: "STOCK_OUT",
      quantity: -5,
      referenceType: "manual",
    });
    expect(rpc).toHaveBeenCalledWith(
      "record_stock_movement",
      expect.objectContaining({ p_item_id: "i1", p_movement_type: "STOCK_OUT", p_quantity: -5 }),
    );
  });

  it("maps an insufficient-stock rule error to INVENTORY_RULE_ERROR with the server message", async () => {
    const rpc = vi.fn(async () => ({ error: { message: "Only 3 unit(s) are currently available." } }));
    await expect(
      new SupabaseInventoryService({ rpc } as never).recordMovement({
        itemId: "i1",
        movementType: "STOCK_OUT",
        quantity: -5,
      }),
    ).rejects.toMatchObject({ code: "INVENTORY_RULE_ERROR", message: "Only 3 unit(s) are currently available." });
  });

  it("maps a permission rejection (42501) to INVENTORY_ACCESS_DENIED", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { code: "42501", message: "denied" } }));
    await expect(
      new SupabaseInventoryService({ rpc } as never).createVendor("f1", { name: "Acme" }),
    ).rejects.toMatchObject({ code: "INVENTORY_ACCESS_DENIED" });
  });

  it("maps a duplicate (23505) to INVENTORY_DUPLICATE", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { code: "23505", message: "A vendor with this name already exists." } }));
    await expect(
      new SupabaseInventoryService({ rpc } as never).createVendor("f1", { name: "Acme" }),
    ).rejects.toMatchObject({ code: "INVENTORY_DUPLICATE" });
  });

  it("createPurchaseOrder serialises lines and returns the new id", async () => {
    const rpc = vi.fn(async () => ({ data: "po-1", error: null }));
    const id = await new SupabaseInventoryService({ rpc } as never).createPurchaseOrder({
      facilityId: "f1",
      vendorId: "v1",
      lines: [{ itemId: "i1", quantity: 2, unitCostMinor: 5000 }],
    });
    expect(id).toBe("po-1");
    expect(rpc).toHaveBeenCalledWith(
      "create_purchase_order",
      expect.objectContaining({
        p_facility_id: "f1",
        p_vendor_id: "v1",
        p_lines: [{ itemId: "i1", quantity: 2, unitCostMinor: 5000, taxMinor: 0, discountMinor: 0 }],
      }),
    );
  });

  it("receivePurchaseOrder forwards only lineId/quantity pairs", async () => {
    const rpc = vi.fn(async () => ({ error: null }));
    await new SupabaseInventoryService({ rpc } as never).receivePurchaseOrder("po-1", [{ lineId: "l1", quantity: 3 }]);
    expect(rpc).toHaveBeenCalledWith("receive_purchase_order", {
      p_po_id: "po-1",
      p_receipts: [{ lineId: "l1", quantity: 3 }],
    });
  });

  it("throws a ServiceError (not a raw object) from a failed list RPC", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "boom" } }));
    await expect(new SupabaseInventoryService({ rpc } as never).listCategories("f1")).rejects.toThrow(ServiceError);
  });
});
