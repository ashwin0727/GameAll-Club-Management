import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { ComingSoonReport } from "./coming-soon-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";

// The reports read the top bar's sport selection; these tests have no query client, and All Sports is what they mean.
vi.mock("@/features/facility/hooks/use-sport-filter", () => ({
  useSportIds: () => ({ sportIds: null, ready: true, key: "all" }),
}));

describe("ComingSoonReport", () => {
  it("renders the title, a filter control and an empty-state message", async () => {
    installFakeReportsFilterDeps();
    render(
      <ComingSoonReport
        title="Booking Report"
        description="desc"
        emptyMessage="No booking data for this period."
      />,
    );
    expect(await screen.findByRole("heading", { name: "Booking Report" })).toBeInTheDocument();
    expect(await screen.findByText("No booking data for this period.")).toBeInTheDocument();
    // a date-range control is present (desktop bar and/or mobile sheet trigger)
    await screen.findAllByRole("combobox", { name: /date range/i });
  });
});
