/**
 * Excel in / out for the bulk uploads. ExcelJS is loaded on demand so it never weighs on the pages that don't
 * use it.
 */

export interface TemplateColumn {
  header: string;
  /** Marked with a * in the sheet and enforced by the validator. */
  required: boolean;
  /** One sample value for the first row. */
  example: string;
  /** Column width in characters. */
  width?: number;
}

export interface TemplateSpec {
  sheetName: string;
  columns: TemplateColumn[];
  /** A second sheet explaining the columns, so the sample can stay one row. */
  instructions: string[];
  /** Allowed values per header, offered as a dropdown in the sheet. */
  lists?: Record<string, string[]>;
}

/** The header exactly as it appears in the sheet: required columns carry a trailing " *". */
export function sheetHeader(col: Pick<TemplateColumn, "header" | "required">): string {
  return col.required ? `${col.header} *` : col.header;
}

/** A header read back from a sheet, with the " *" marker and stray whitespace removed. */
export function normaliseHeader(raw: string): string {
  return raw.replace(/\*/g, "").replace(/\s+/g, " ").trim().toLowerCase();
}

/** Builds the downloadable sample workbook. */
export async function buildTemplate(spec: TemplateSpec): Promise<ArrayBuffer> {
  const ExcelJS = (await import("exceljs")).default;
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(spec.sheetName);
  ws.columns = spec.columns.map((c) => ({ header: sheetHeader(c), key: c.header, width: c.width ?? Math.max(16, c.header.length + 6) }));
  const head = ws.getRow(1);
  head.font = { bold: true, color: { argb: "FFFFFFFF" } };
  head.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF0F766E" } };
  head.alignment = { vertical: "middle" };
  head.height = 22;
  ws.addRow(spec.columns.map((c) => c.example));
  // Everything is plain text, so phone numbers keep their leading digits and dates are not reinterpreted.
  spec.columns.forEach((_, i) => {
    ws.getColumn(i + 1).numFmt = "@";
  });
  spec.columns.forEach((c, i) => {
    const list = spec.lists?.[c.header];
    if (!list?.length) return;
    const formula = `"${list.join(",").replace(/"/g, "")}"`;
    if (formula.length > 255) return; // Excel's limit for an inline list
    for (let r = 2; r <= 501; r++) {
      ws.getCell(r, i + 1).dataValidation = { type: "list", allowBlank: !c.required, formulae: [formula], showErrorMessage: false };
    }
  });
  ws.views = [{ state: "frozen", ySplit: 1 }];

  const info = wb.addWorksheet("Instructions");
  info.getColumn(1).width = 110;
  spec.instructions.forEach((line, i) => {
    const row = info.addRow([line]);
    if (i === 0) row.font = { bold: true, size: 13 };
    row.alignment = { wrapText: true, vertical: "top" };
  });
  const out = await wb.xlsx.writeBuffer();
  return out as ArrayBuffer;
}

/** One data row as header → text, plus the sheet row number it came from (the header is row 1). */
export interface SheetRow {
  rowNumber: number;
  values: Record<string, string>;
}

export interface ParsedSheet {
  /** Normalised headers actually present in the sheet. */
  headers: string[];
  rows: SheetRow[];
}

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

/** Anything a cell can hold, as the plain text the user would see. */
function cellText(value: unknown): string {
  if (value == null) return "";
  if (value instanceof Date) return `${value.getUTCFullYear()}-${pad(value.getUTCMonth() + 1)}-${pad(value.getUTCDate())}`;
  if (typeof value === "object") {
    const v = value as { text?: unknown; result?: unknown; richText?: { text: string }[]; hyperlink?: unknown };
    if (Array.isArray(v.richText)) return v.richText.map((t) => t.text).join("").trim();
    if (v.result !== undefined) return cellText(v.result);
    if (v.text !== undefined) return cellText(v.text);
    return "";
  }
  return String(value).trim();
}

/** Reads the first sheet. Fully blank rows are dropped; every value comes back as trimmed text. */
export async function readSheet(data: ArrayBuffer): Promise<ParsedSheet> {
  const ExcelJS = (await import("exceljs")).default;
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(data);
  const ws = wb.worksheets[0];
  if (!ws) return { headers: [], rows: [] };

  const headerByCol = new Map<number, string>();
  ws.getRow(1).eachCell({ includeEmpty: false }, (cell, col) => {
    const h = normaliseHeader(cellText(cell.value));
    if (h) headerByCol.set(col, h);
  });

  const rows: SheetRow[] = [];
  ws.eachRow({ includeEmpty: false }, (row, rowNumber) => {
    if (rowNumber === 1) return;
    const values: Record<string, string> = {};
    let any = false;
    headerByCol.forEach((h, col) => {
      const t = cellText(row.getCell(col).value);
      values[h] = t;
      if (t) any = true;
    });
    if (any) rows.push({ rowNumber, values });
  });
  return { headers: [...headerByCol.values()], rows };
}

/** Sends a built workbook to the browser as a download. */
export function downloadWorkbook(data: ArrayBuffer, fileName: string): void {
  const blob = new Blob([data], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** A problem found in an uploaded sheet; `row` 0 means the sheet as a whole (e.g. a missing column). */
export interface BulkError {
  row: number;
  column: string;
  message: string;
}

/** The columns a sheet must have but doesn't, as one error each. */
export function missingColumnErrors(headers: string[], columns: Pick<TemplateColumn, "header" | "required">[]): BulkError[] {
  const have = new Set(headers);
  return columns
    .filter((c) => c.required && !have.has(normaliseHeader(c.header)))
    .map((c) => ({ row: 0, column: c.header, message: `The "${c.header}" column is missing — download the sample and use its headings.` }));
}

/** Accepts yyyy-mm-dd, dd/mm/yyyy and dd-mm-yyyy; returns yyyy-mm-dd or null. */
export function parseSheetDate(text: string): string | null {
  const t = text.trim();
  if (!t) return null;
  let y: number, m: number, d: number;
  let match = /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ].*)?$/.exec(t);
  if (match) {
    y = Number(match[1]);
    m = Number(match[2]);
    d = Number(match[3]);
  } else if ((match = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/.exec(t))) {
    d = Number(match[1]);
    m = Number(match[2]);
    y = Number(match[3]);
  } else {
    return null;
  }
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return null;
  return `${y}-${pad(m)}-${pad(d)}`;
}
