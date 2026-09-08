import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { Heatmap } from "./heatmap";

const cells = [
  { dow: 1, hour: 18, openMinutes: 60, bookedMinutes: 54, demandPct: 90 },
  { dow: 2, hour: 18, openMinutes: 60, bookedMinutes: 30, demandPct: 50 },
];

describe("Heatmap", () => {
  it("renders an accessible grid with the percentage as text (not colour alone)", () => {
    render(<Heatmap cells={cells} />);
    expect(screen.getByRole("table", { name: /demand by day/i })).toBeInTheDocument();
    expect(screen.getByText("90")).toBeInTheDocument();
    expect(screen.getByRole("rowheader", { name: "Mon" })).toBeInTheDocument();
  });

  it("labels each cell with a descriptive title", () => {
    render(<Heatmap cells={cells} />);
    expect(screen.getByTitle(/Mon 18:00 — 90% demand/)).toBeInTheDocument();
  });

  it("shows an empty message with no cells", () => {
    render(<Heatmap cells={[]} />);
    expect(screen.getByText(/no demand data/i)).toBeInTheDocument();
  });
});
