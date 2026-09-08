import { describe, expect, it, vi } from "vitest";
import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import type { AnalyticsFilter } from "../types";

const filter: AnalyticsFilter = {
  facilityId: "fac-1",
  preset: "THIS_MONTH",
  facilitySportId: null,
  courtId: null,
};

/** Flush the component's async facility / sport / court loads. */
async function settle() {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
}

describe("AnalyticsFilterBar", () => {
  it("offers every preset and reports a change", async () => {
    installFakeReportsFilterDeps();
    const onChange = vi.fn();
    render(<AnalyticsFilterBar filter={filter} onChange={onChange} />);
    await settle();

    await userEvent.click(screen.getByRole("combobox", { name: /date range/i }));
    await userEvent.click(await screen.findByRole("option", { name: "This Quarter" }));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ preset: "THIS_QUARTER" }));
  });

  it("shows custom date inputs only for CUSTOM", async () => {
    installFakeReportsFilterDeps();
    const { rerender } = render(<AnalyticsFilterBar filter={filter} onChange={vi.fn()} />);
    await settle();
    expect(screen.queryByLabelText(/start date/i)).not.toBeInTheDocument();
    rerender(<AnalyticsFilterBar filter={{ ...filter, preset: "CUSTOM" }} onChange={vi.fn()} />);
    expect(screen.getByLabelText(/start date/i)).toBeInTheDocument();
  });

  it("clears the court when the sport changes", async () => {
    installFakeReportsFilterDeps();
    const onChange = vi.fn();
    render(
      <AnalyticsFilterBar
        filter={{ ...filter, facilitySportId: "fs-1", courtId: "court-1" }}
        onChange={onChange}
      />,
    );
    await settle();
    await userEvent.click(screen.getByRole("combobox", { name: /sport/i }));
    await userEvent.click(await screen.findByRole("option", { name: /all sports/i }));
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({ facilitySportId: null, courtId: null }),
    );
  });

  it("hides the facility control when the user has one facility", async () => {
    installFakeReportsFilterDeps({ facilities: 1 });
    render(<AnalyticsFilterBar filter={filter} onChange={vi.fn()} />);
    await settle();
    expect(screen.queryByRole("combobox", { name: /facility/i })).not.toBeInTheDocument();
  });

  it("shows the facility control when the user has more than one", async () => {
    installFakeReportsFilterDeps({ facilities: 2 });
    render(<AnalyticsFilterBar filter={filter} onChange={vi.fn()} />);
    await waitFor(() => expect(screen.getByRole("combobox", { name: /facility/i })).toBeInTheDocument());
  });
});
