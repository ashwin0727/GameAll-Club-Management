import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ReportShell } from "./report-shell";

const base = { title: "Booking Report", description: "desc" };

describe("ReportShell", () => {
  it("shows skeletons and no children while loading", () => {
    render(
      <ReportShell {...base} status="loading">
        <div>revenue Rs 1,20,000</div>
      </ReportShell>,
    );
    expect(screen.queryByText(/1,20,000/)).not.toBeInTheDocument();
    expect(document.querySelectorAll(".animate-pulse").length).toBeGreaterThan(0);
  });

  it("renders children and an export button when ready", async () => {
    const onExportCsv = vi.fn();
    render(
      <ReportShell {...base} status="ready" onExportCsv={onExportCsv}>
        <div>revenue Rs 1,20,000</div>
      </ReportShell>,
    );
    expect(screen.getByText(/1,20,000/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /download csv/i }));
    expect(onExportCsv).toHaveBeenCalledOnce();
  });

  it("shows a distinct empty message", () => {
    render(
      <ReportShell {...base} status="empty" emptyMessage="No booking data for this period.">
        <div />
      </ReportShell>,
    );
    expect(screen.getByText("No booking data for this period.")).toBeInTheDocument();
  });

  it("shows an error with a working retry", async () => {
    const onRetry = vi.fn();
    render(
      <ReportShell {...base} status="error" onRetry={onRetry}>
        <div />
      </ReportShell>,
    );
    expect(screen.getByText(/unable to load/i)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /try again/i }));
    expect(onRetry).toHaveBeenCalledOnce();
  });

  it("always renders the title and, when given, the filter bar", () => {
    render(
      <ReportShell {...base} status="loading" filterBar={<div data-testid="bar" />}>
        <div />
      </ReportShell>,
    );
    expect(screen.getByRole("heading", { name: "Booking Report" })).toBeInTheDocument();
    expect(screen.getByTestId("bar")).toBeInTheDocument();
  });
});
