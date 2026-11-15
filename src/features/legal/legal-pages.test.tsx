import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import PrivacyPage from "@/app/privacy/page";
import TermsPage from "@/app/terms/page";
import RefundPolicyPage from "@/app/refund-policy/page";
import { STANDALONE_PUBLIC_ROUTES } from "@/lib/supabase/public-routes";

// Google Play opens these pages and compares them with the app and the Data safety form, so they must cover both apps.
describe("the shared legal pages", () => {
  it("the Privacy Policy covers both apps, location, payments and deletion", () => {
    render(<PrivacyPage />);
    expect(screen.getAllByText(/GameAll Play/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/GameAll Venue/).length).toBeGreaterThan(0);
    expect(screen.getByText(/approximate location/i)).toBeTruthy();
    expect(screen.getAllByText(/Razorpay/).length).toBeGreaterThan(0);
    // in-app deletion paths for both apps and the web page
    expect(screen.getByText(/Delete my account/)).toBeTruthy();
    expect(screen.getByRole("link", { name: /account deletion page/i }).getAttribute("href")).toBe("/delete-account");
    expect(screen.getByRole("link", { name: /cancellation and refund policy/i }).getAttribute("href")).toBe("/refund-policy");
  });

  it("the Terms speak to players and to venues and point at the refund policy", () => {
    render(<TermsPage />);
    expect(screen.getByText(/For players/)).toBeTruthy();
    expect(screen.getByText(/For venues/)).toBeTruthy();
    expect(screen.getByRole("link", { name: /Cancellation & Refund Policy/i }).getAttribute("href")).toBe("/refund-policy");
    expect(screen.getByRole("link", { name: /Privacy Policy/i }).getAttribute("href")).toBe("/privacy");
  });

  it("the refund table is the schedule the app and the database apply: 5% kept at 12 h or more, 100% under an hour", () => {
    render(<RefundPolicyPage />);
    const rows = screen.getAllByRole("row").slice(1); // without the header
    expect(rows).toHaveLength(13);
    const kept = rows.map((r) => Number(r.children[1]!.textContent!.replace("%", "")));
    expect(kept[0]).toBe(5);
    expect(kept[kept.length - 1]).toBe(100);
    // the share kept never falls as the start time gets closer
    for (let i = 1; i < kept.length; i++) expect(kept[i]!).toBeGreaterThanOrEqual(kept[i - 1]!);
    // kept + refunded is always the whole amount
    rows.forEach((r, i) => expect(Number(r.children[2]!.textContent!.replace("%", "")) + kept[i]!).toBe(100));
  });

  it("every legal page can be opened signed out", () => {
    for (const path of ["/privacy", "/terms", "/refund-policy", "/delete-account"]) {
      expect(STANDALONE_PUBLIC_ROUTES).toContain(path);
    }
  });
});
