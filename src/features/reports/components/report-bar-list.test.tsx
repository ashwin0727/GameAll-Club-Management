import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ReportBarList } from "./report-bar-list";

describe("ReportBarList", () => {
  it("renders a labelled row per item with its value", () => {
    render(
      <ReportBarList
        items={[
          { label: "Badminton", value: 120 },
          { label: "Football", value: 60 },
        ]}
      />,
    );
    expect(screen.getByText("Badminton")).toBeInTheDocument();
    expect(screen.getByText("120")).toBeInTheDocument();
  });

  it("sizes each bar relative to the largest value", () => {
    const { container } = render(
      <ReportBarList
        items={[
          { label: "A", value: 100 },
          { label: "B", value: 25 },
        ]}
      />,
    );
    const bars = container.querySelectorAll("[data-bar]");
    expect((bars[0] as HTMLElement).style.width).toBe("100%");
    expect((bars[1] as HTMLElement).style.width).toBe("25%");
  });

  it("renders a caption in place of the raw value when given", () => {
    render(<ReportBarList items={[{ label: "UPI", value: 50000, caption: "₹50,000 (50%)" }]} />);
    expect(screen.getByText("₹50,000 (50%)")).toBeInTheDocument();
  });
});
