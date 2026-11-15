import type { Metadata } from "next";
import { PaymentMethodsPage } from "@/features/profile/components/payment-methods-page";

export const metadata: Metadata = {
  title: `Payment Methods`,
};

export default function PaymentsPage() {
  return <PaymentMethodsPage />;
}
