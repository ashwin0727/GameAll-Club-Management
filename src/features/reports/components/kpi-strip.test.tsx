import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { KpiStrip } from "./kpi-strip";
import { KPI_DEFINITIONS } from "../definitions";

const items = [
  { key: "totalRevenue" as const, label: "Total Revenue", value: "Rs 1,20,000", accent: "#00D084" },
  { key: "netRevenue" as const, label: "Net Revenue", value: "Rs 85,000", accent: "#00F08A" },
  {
    key: "courtUtilization" as const,
    label: "Utilization",
    value: "68%",
    accent: "#5B6CFF",
    href: "/reports/court-utilization?facility=f1&preset=THIS_MONTH",
  },
];

describe("KpiStrip", () => {
  it("renders one card per item with its value", () => {
    render(<KpiStrip items={items} />);
    expect(screen.getByText("Total Revenue")).toBeInTheDocument();
    expect(screen.getByText("Rs 85,000")).toBeInTheDocument();
  });

  it("wraps an item with href in a link to that report", () => {
    render(<KpiStrip items={items} />);
    const link = screen.getByRole("link", { name: /utilization/i });
    expect(link).toHaveAttribute("href", "/reports/court-utilization?facility=f1&preset=THIS_MONTH");
  });

  it("exposes each KPI's definition as accessible text", () => {
    render(<KpiStrip items={items} />);
    expect(screen.getByText(new RegExp(KPI_DEFINITIONS.netRevenue.slice(0, 20)))).toBeInTheDocument();
  });

  it("uses a wrapping grid, not a fixed-width row", () => {
    const { container } = render(<KpiStrip items={items} />);
    expect(container.firstElementChild?.className).toMatch(/grid/);
  });
});
