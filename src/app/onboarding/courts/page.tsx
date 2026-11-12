// src/app/onboarding/courts/page.tsx
import { redirect } from "next/navigation";

/** Sports and courts are now one step; the old courts address lands on the merged page. */
export default function CourtsRedirectPage() {
  redirect("/onboarding/sports");
}
