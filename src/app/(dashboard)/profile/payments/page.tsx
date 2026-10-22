import type { Metadata } from "next";
import { PaymentMethodsPage } from "@/features/profile/components/payment-methods-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Payment Methods — ${APP_NAME}`,
};

export default function PaymentsPage() {
  return <PaymentMethodsPage />;
}
