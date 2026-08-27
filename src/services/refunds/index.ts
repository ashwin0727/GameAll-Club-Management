import type { RefundService } from "@/services/refunds/refund.service";
import { SupabaseRefundService } from "@/services/refunds/supabase-refund.service";

let instance: RefundService | null = null;

/** Single entry point for the cancellation/refund implementation. */
export function getRefundService(): RefundService {
  instance ??= new SupabaseRefundService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setRefundService(service: RefundService | null): void {
  instance = service;
}

export type { RefundService } from "@/services/refunds/refund.service";