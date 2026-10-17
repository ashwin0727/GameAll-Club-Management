import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { PricingSummary, groupCustomized } from "@/features/pricing/components/pricing-summary";
import { defaultPeriod } from "@/features/pricing/components/types";

describe("PricingSummary", () => {
  it("shows a fully customized single turf by name, with its own rates instead of the unused default", () => {
    render(
      <PricingSummary
        currency="INR"
        totalPlayingAreas={4}
        entries={[
          {
            sportName: "Cricket",
            areaLabel: "Turf",
            areaCount: 1,
            periods: [defaultPeriod("500")],
            customized: [
              { areaName: "Turf 1", periods: [{ ...defaultPeriod("700"), dayType: "WEEKDAYS" }, { ...defaultPeriod("900"), dayType: "WEEKENDS" }] },
            ],
          },
        ]}
      />,
    );
    expect(screen.getByText("Turf 1 · custom")).toBeInTheDocument();
    expect(screen.getByText(/₹700/)).toBeInTheDocument();
    expect(screen.getByText(/₹900/)).toBeInTheDocument();
    expect(screen.queryByText(/₹500/)).not.toBeInTheDocument();
    expect(screen.getByText(/1 custom/)).toBeInTheDocument();
  });

  it("counts a sport as priced when only a court has a rate", () => {
    render(
      <PricingSummary
        currency="INR"
        totalPlayingAreas={1}
        entries={[{ sportName: "Football", areaLabel: "Turf", areaCount: 1, periods: [defaultPeriod("")], customized: [{ areaName: "Turf A", periods: [defaultPeriod("800")] }] }]}
      />,
    );
    expect(screen.getByText("Turf A · custom")).toBeInTheDocument();
    expect(screen.getByText(/1 priced/)).toBeInTheDocument();
  });
});

describe("PricingSummary — courts with the same price", () => {
  const same = () => [{ ...defaultPeriod("300"), dayType: "WEEKDAYS" as const }, { ...defaultPeriod("350"), dayType: "WEEKENDS" as const }];

  it("shows identical customized courts once, as 'All 3 Courts', without the unused default", () => {
    render(
      <PricingSummary
        currency="INR"
        totalPlayingAreas={3}
        entries={[
          {
            sportName: "Badminton",
            areaLabel: "Court",
            areaCount: 3,
            periods: [defaultPeriod("300")],
            customized: [
              { areaName: "Court 1", periods: same() },
              { areaName: "Court 2", periods: same() },
              { areaName: "Court 3", periods: same() },
            ],
          },
        ]}
      />,
    );
    expect(screen.getByText("All 3 Courts")).toBeInTheDocument();
    expect(screen.getAllByText(/₹300/)).toHaveLength(1);
    expect(screen.getAllByText(/₹350/)).toHaveLength(1);
    expect(screen.queryByText(/Court 1/)).not.toBeInTheDocument();
  });

  it("groups only the courts that match and keeps the sport rate for the rest", () => {
    render(
      <PricingSummary
        currency="INR"
        totalPlayingAreas={3}
        entries={[
          {
            sportName: "Badminton",
            areaLabel: "Court",
            areaCount: 3,
            periods: [defaultPeriod("200")],
            customized: [
              { areaName: "Court 1", periods: same() },
              { areaName: "Court 2", periods: same() },
            ],
          },
        ]}
      />,
    );
    expect(screen.getByText("Court 1, Court 2 · custom")).toBeInTheDocument();
    expect(screen.getByText(/₹200/)).toBeInTheDocument();
  });

  it("keeps courts with different prices apart", () => {
    expect(
      groupCustomized([
        { areaName: "Court 1", periods: [defaultPeriod("300")] },
        { areaName: "Court 2", periods: [defaultPeriod("400")] },
        { areaName: "Court 3", periods: [defaultPeriod("300")] },
      ]).map((g) => g.areaNames),
    ).toEqual([["Court 1", "Court 3"], ["Court 2"]]);
  });
});
