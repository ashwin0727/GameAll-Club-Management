import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ComingSoonReport } from "./coming-soon-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";

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
