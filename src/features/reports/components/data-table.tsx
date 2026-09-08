"use client";

import Link from "next/link";

export interface DataColumn {
  key: string;
  label: string;
  align?: "left" | "right";
}

type Row = Record<string, string | number>;

/**
 * The precise, accessible companion under every report chart (spec §42/§54).
 * When `href` is given, the first column's cell becomes a drill-down link
 * (spec §28).
 */
export function DataTable({
  columns,
  rows,
  caption,
  href,
}: {
  columns: DataColumn[];
  rows: Row[];
  caption: string;
  href?: (row: Row) => string;
}) {
  const format = (value: string | number | undefined) =>
    typeof value === "number" ? value.toLocaleString("en-IN") : (value ?? "—");

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr className="border-b border-border text-left text-xs text-muted-foreground">
            {columns.map((c) => (
              <th
                key={c.key}
                scope="col"
                className={`py-2 pr-3 font-medium ${c.align === "right" ? "text-right" : ""}`}
              >
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className="border-b border-border last:border-0">
              {columns.map((c, ci) => (
                <td
                  key={c.key}
                  className={`py-2.5 pr-3 tabular-nums ${c.align === "right" ? "text-right" : ""}`}
                >
                  {ci === 0 && href ? (
                    <Link href={href(row)} className="font-medium text-primary hover:underline">
                      {format(row[c.key])}
                    </Link>
                  ) : (
                    format(row[c.key])
                  )}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
