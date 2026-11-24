import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Sidebar } from "./sidebar";

let pathname = "/dashboard";
vi.mock("next/navigation", () => ({ usePathname: () => pathname }));

const heading = (name: RegExp) => screen.getByRole("button", { name });

describe("Sidebar sections", () => {
  it("shows Home, Calendar, Bookings and Tournaments as plain links, then the Management and Operations titles", () => {
    pathname = "/dashboard";
    render(<Sidebar role="admin" />);
    for (const name of ["Home", "Calendar", "Bookings", "Tournaments", "Guest Players"]) {
      expect(screen.getByRole("link", { name })).toBeInTheDocument();
    }
    expect(screen.getByText("Management")).toBeInTheDocument();
    expect(screen.getByText("Operations")).toBeInTheDocument();
  });

  it("starts every Management and Operations section collapsed", () => {
    pathname = "/dashboard";
    render(<Sidebar role="admin" />);
    for (const name of [/Memberships/i, /Coaching/i, /Maintenance/i, /Staff & Roles/i, /Finance/i, /Reports & Analytics/i]) {
      expect(heading(name)).toHaveAttribute("aria-expanded", "false");
    }
    expect(screen.queryByRole("link", { name: "Plan" })).not.toBeInTheDocument();
  });

  it("expands a section on click to show its pages, and collapses it on a second click", async () => {
    pathname = "/dashboard";
    render(<Sidebar role="admin" />);
    await userEvent.click(heading(/Memberships/i));
    expect(heading(/Memberships/i)).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("link", { name: "Plan" })).toBeInTheDocument();
    expect(heading(/Coaching/i)).toHaveAttribute("aria-expanded", "false");

    await userEvent.click(heading(/Memberships/i));
    expect(screen.queryByRole("link", { name: "Plan" })).not.toBeInTheDocument();
  });

  it("opens the section that holds the current page, and opens another when you move to it", () => {
    pathname = "/memberships/v1/plans";
    const { rerender } = render(<Sidebar role="admin" />);
    expect(heading(/Memberships/i)).toHaveAttribute("aria-expanded", "true");
    expect(heading(/Coaching/i)).toHaveAttribute("aria-expanded", "false");

    pathname = "/coaching/programs";
    rerender(<Sidebar role="admin" />);
    expect(heading(/Coaching/i)).toHaveAttribute("aria-expanded", "true");
  });
});
