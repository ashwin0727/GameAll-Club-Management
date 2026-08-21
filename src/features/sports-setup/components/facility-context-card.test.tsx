import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import type { Facility } from "@/features/onboarding/types";

const FACILITY: Facility = {
  id: "facility-1",
  ownerId: "owner-1",
  name: "GameAll Sports Arena",
  type: "MULTI_SPORT",
  businessEmail: "owner@yourturf.com",
  businessPhone: "9876543210",
  address: {
    line1: "123 Anna Salai",
    area: "Ambattur",
    city: "Chennai",
    state: "Tamil Nadu",
    country: "India",
    pinCode: "600053",
  },
  status: "ACTIVE",
  createdAt: "2026-08-20T00:00:00.000Z",
  updatedAt: "2026-08-20T00:00:00.000Z",
};

describe("FacilityContextCard", () => {
  it("shows the facility name and city", () => {
    render(<FacilityContextCard facility={FACILITY} />);
    expect(screen.getByText("GameAll Sports Arena")).toBeInTheDocument();
    expect(screen.getByText("Chennai")).toBeInTheDocument();
  });

  it("shows a human-readable facility type label, not the raw enum value", () => {
    render(<FacilityContextCard facility={FACILITY} />);
    expect(screen.getByText(/Multi-Sport Facility/)).toBeInTheDocument();
    expect(screen.queryByText("MULTI_SPORT")).not.toBeInTheDocument();
  });
});