import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CourtUtilizationReport } from "./court-utilization-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

const TWO_COURTS = [
  {
    courtId: "c1",
    courtName: "Court 1",
    facilitySportId: "fs1",
    sportName: "Badminton",
    openMinutes: 3000,
    bookedMinutes: 2460,
    utilizationPct: 82,
  },
  {
    courtId: "c2",
    courtName: "Court 2",
    facilitySportId: "fs1",
    sportName: "Badminton",
    openMinutes: 3000,
    bookedMinutes: 1620,
    utilizationPct: 54,
  },
];

describe("CourtUtilizationReport", () => {
  it("shows the empty state when the facility has no bookable hours", async () => {
    setup();
    render(<CourtUtilizationReport />);
    expect(await screen.findByText(/no court activity/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders the overall figure, the court table and the heatmap when there is data", async () => {
    const reports = setup();
    reports.overallUtilization = { openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 };
    reports.courtUtilization = TWO_COURTS;
    reports.sportUtilization = [
      { facilitySportId: "fs1", sportName: "Badminton", openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 },
    ];
    reports.peakHours = [{ hour: 18, openMinutes: 300, bookedMinutes: 270, demandPct: 90 }];
    reports.demandHeatmap = [{ dow: 1, hour: 18, openMinutes: 60, bookedMinutes: 54, demandPct: 90 }];

    render(<CourtUtilizationReport />);

    // the prominent overall figure (a <p>, not the table cell that also reads 68%)
    expect(await screen.findByText("68%", { selector: "p" }, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /court utilization/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /demand by day/i })).toBeInTheDocument();
  });

  it("re-sorts the court list lowest-first", async () => {
    const reports = setup();
    reports.overallUtilization = { openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 };
    reports.courtUtilization = TWO_COURTS;
    render(<CourtUtilizationReport />);
    await screen.findByText("68%", {}, SLOW);

    await userEvent.click(screen.getByRole("combobox", { name: /sort/i }));
    await userEvent.click(await screen.findByRole("option", { name: /lowest/i }));

    const table = screen.getByRole("table", { name: /court utilization/i });
    const bodyText = table.textContent ?? "";
    expect(bodyText.indexOf("Court 2")).toBeLessThan(bodyText.indexOf("Court 1"));
  });

  it("offers a CSV download once data is loaded", async () => {
    const reports = setup();
    reports.overallUtilization = { openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 };
    reports.courtUtilization = TWO_COURTS;
    render(<CourtUtilizationReport />);
    expect(await screen.findByRole("button", { name: /download csv/i }, SLOW)).toBeInTheDocument();
  });
});
