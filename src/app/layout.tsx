import type { Metadata } from "next";
import { Toaster } from "sonner";
import { QueryProvider } from "@/providers/query-provider";
import { APP_NAME } from "@/lib/constants";
import "./globals.css";

export const metadata: Metadata = {
  title: `${APP_NAME} — Club Management`,
  description: "Membership, booking, and inventory management for GameAll Club.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark" suppressHydrationWarning>
      <body>
        <QueryProvider>
          {children}
          <Toaster theme="dark" position="top-right" richColors closeButton />
        </QueryProvider>
      </body>
    </html>
  );
}