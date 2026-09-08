import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { DataTable } from "./data-table";

const columns = [
  { key: "sport", label: "Sport" },
  { key: "count", label: "Bookings", align: "right" as const },
];
const rows = [
  { sport: "Badminton", count: 120 },
  { sport: "Football", count: 60 },
];

describe("DataTable", () => {
  it("renders headers, rows and an accessible caption", () => {
    render(<DataTable caption="Bookings by sport" columns={columns} rows={rows} />);
    expect(screen.getByRole("table", { name: "Bookings by sport" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Sport" })).toBeInTheDocument();
    expect(screen.getByRole("cell", { name: "120" })).toBeInTheDocument();
  });

  it("links the first cell when href is given", () => {
    render(
      <DataTable
        caption="Bookings by sport"
        columns={columns}
        rows={rows}
        href={(row) => `/reports/bookings?sport=${row.sport}`}
      />,
    );
    expect(screen.getByRole("link", { name: "Badminton" })).toHaveAttribute(
      "href",
      "/reports/bookings?sport=Badminton",
    );
  });
});
