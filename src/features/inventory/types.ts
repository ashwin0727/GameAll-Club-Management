import { z } from "zod";

export const inventoryItemSchema = z.object({
  id: z.string().uuid(),
  facility_id: z.string().uuid(),
  name: z.string().min(1),
  category: z.string().min(1),
  sku: z.string().min(1),
  total_quantity: z.number().int().nonnegative(),
  available_quantity: z.number().int().nonnegative(),
  condition: z.string(),
  created_at: z.string(),
});
export type InventoryItem = z.infer<typeof inventoryItemSchema>;

export const inventoryTxnTypeSchema = z.enum(["checkout", "return", "restock", "damage"]);

export const inventoryTransactionSchema = z.object({
  id: z.string().uuid(),
  facility_id: z.string().uuid(),
  item_id: z.string().uuid(),
  member_id: z.string().uuid().nullable(),
  quantity: z.number().int().positive(),
  type: inventoryTxnTypeSchema,
  staff_id: z.string().uuid(),
  created_at: z.string(),
});
export type InventoryTransaction = z.infer<typeof inventoryTransactionSchema>;

// Next slice: api/, hooks/, and stock-management components for this feature.