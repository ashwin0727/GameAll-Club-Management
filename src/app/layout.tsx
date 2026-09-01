import type { Metadata } from "next";
import { Figtree } from "next/font/google";
import { Toaster } from "sonner";
import { QueryProvider } from "@/providers/query-provider";
import { APP_NAME, APP_SUBTITLE } from "@/lib/constants";
import "./globals.css";

const figtree = Figtree({
  subsets: ["latin"],
  variable: "--font-figtree",
});

export const metadata: Metadata = {
  title: `${APP_NAME} — ${APP_SUBTITLE}`,
  description: `Membership, booking, and inventory management for ${APP_NAME}.`,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={figtree.variable} suppressHydrationWarning>
      <body>
        <QueryProvider>
          {children}
          <Toaster theme="light" position="top-right" richColors closeButton />
        </QueryProvider>
      </body>
    </html>
  );
}