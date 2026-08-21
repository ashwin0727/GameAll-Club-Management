import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { SelectedSportsSummary } from "@/features/sports-setup/components/selected-sports-summary";

describe("SelectedSportsSummary", () => {
  it("shows 'No sports selected' for zero", () => {
    render(<SelectedSportsSummary count={0} />);
    expect(screen.getByText("No sports selected")).toBeInTheDocument();
  });

  it("uses singular phrasing for exactly one", () => {
    render(<SelectedSportsSummary count={1} />);
    expect(screen.getByText("1 sport selected")).toBeInTheDocument();
  });

  it("uses plural phrasing for more than one", () => {
    render(<SelectedSportsSummary count={3} />);
    expect(screen.getByText("3 sports selected")).toBeInTheDocument();
  });

  it("counts all six when everything including Other is selected", () => {
    render(<SelectedSportsSummary count={6} />);
    expect(screen.getByText("6 sports selected")).toBeInTheDocument();
  });
});