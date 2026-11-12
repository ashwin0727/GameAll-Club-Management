import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Sidebar } from "./sidebar";

let pathname = "/dashboard";
vi.mock("next/navigation", () => ({ usePathname: () => pathname }));

const heading = (name: RegExp) => screen.getByRole("button", { name });

describe("Sidebar management sections", () => {
  it("keeps Home, Calendar and Tournaments as plain links and starts every management collapsed", () => {
    pathname = "/dashboard";
    render(<Sidebar role="admin" />);
    expect(screen.getByRole("link", { name: "Home" })).toBeInTheDocument();
    expect(heading(/Memberships Management/i)).toHaveAttribute("aria-expanded", "false");
    expect(heading(/Coaching Management/i)).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("link", { name: "Membership Plan" })).not.toBeInTheDocument();
  });

  it("opens one management at a time: opening another closes the first", async () => {
    pathname = "/dashboard";
    render(<Sidebar role="admin" />);

    await userEvent.click(heading(/Memberships Management/i));
    expect(heading(/Memberships Management/i)).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("link", { name: "Membership Plan" })).toBeInTheDocument();

    await userEvent.click(heading(/Coaching Management/i));
    expect(heading(/Coaching Management/i)).toHaveAttribute("aria-expanded", "true");
    expect(heading(/Memberships Management/i)).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("link", { name: "Membership Plan" })).not.toBeInTheDocument();
  });

  it("clicking the open management again collapses it", async () => {
    pathname = "/dashboard";
    render(<Sidebar role="admin" />);
    await userEvent.click(heading(/Coaching Management/i));
    await userEvent.click(heading(/Coaching Management/i));
    expect(heading(/Coaching Management/i)).toHaveAttribute("aria-expanded", "false");
  });

  it("opens the management that holds the current page, and switches when you move to another one", () => {
    pathname = "/memberships/v1/plans";
    const { rerender } = render(<Sidebar role="admin" />);
    expect(heading(/Memberships Management/i)).toHaveAttribute("aria-expanded", "true");

    pathname = "/coaching/programs";
    rerender(<Sidebar role="admin" />);
    expect(heading(/Coaching Management/i)).toHaveAttribute("aria-expanded", "true");
    expect(heading(/Memberships Management/i)).toHaveAttribute("aria-expanded", "false");
  });
});
