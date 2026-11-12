import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { Toaster } from "sonner";
import { QueryProvider } from "@/providers/query-provider";
import { APP_NAME, APP_SUBTITLE } from "@/lib/constants";
import "./globals.css";

// Inter is the app font. The CSS variable keeps its old name so the Tailwind font-sans stack (tailwind.config.ts) needs no change.
const inter = Inter({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
  variable: "--font-figtree",
});

export const metadata: Metadata = {
  title: `${APP_NAME} — ${APP_SUBTITLE}`,
  description: "Manage courts, bookings, memberships, and players with ease.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.variable} suppressHydrationWarning>
      <body>
        <QueryProvider>
          {children}
          <Toaster theme="light" position="top-right" richColors closeButton />
        </QueryProvider>
      </body>
    </html>
  );
}