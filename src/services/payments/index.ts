import type { PaymentService } from "@/services/payments/payment.service";
import { SupabasePaymentService } from "@/services/payments/supabase-payment.service";

let instance: PaymentService | null = null;

/** Single entry point for the payments implementation. */
export function getPaymentService(): PaymentService {
  instance ??= new SupabasePaymentService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setPaymentService(service: PaymentService | null): void {
  instance = service;
}

export type { PaymentService } from "@/services/payments/payment.service";