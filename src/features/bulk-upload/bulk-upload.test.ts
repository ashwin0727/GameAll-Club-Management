import { describe, expect, it } from "vitest";
import ExcelJS from "exceljs";
import { buildTemplate, parseSheetDate, readSheet } from "@/features/bulk-upload/spreadsheet";
import { localPhone, MEMBER_COLUMNS, memberTemplateSpec, validateMemberRows } from "@/features/bulk-upload/member-bulk";
import { programCycleFeeMinor, STUDENT_COLUMNS, validateStudentRows } from "@/features/bulk-upload/student-bulk";
import type { MembershipPlan } from "@/features/memberships/types";
import type { PlanSlot } from "@/features/memberships/plan-slots";
import type { ProgramDetail } from "@/features/coaching/types";

const NOW = new Date(2026, 9, 17);

function sheetRows(columns: { header: string }[], rows: Record<string, string>[]) {
  const headers = columns.map((c) => c.header.toLowerCase());
  return {
    headers,
    rows: rows.map((r, i) => ({
      rowNumber: i + 2,
      values: Object.fromEntries(Object.entries(r).map(([k, v]) => [k.toLowerCase(), v])),
    })),
  };
}

const plan = (id: string, name: string, extra: Partial<MembershipPlan> = {}): MembershipPlan => ({
  id, facilityId: "f", name, description: null, category: null, planType: "RECURRING", priceInr: 1000, durationDays: 30,
  joiningFeeInr: 200, securityDepositInr: null, badgeText: null, features: [], isActive: true, createdAt: "", ...extra,
});
const slot = (batchId: string, courtId: string, courtName: string): PlanSlot => ({
  batchId, courtId, courtName, daysOfWeek: [1, 2, 3], startTime: "06:00", endTime: "07:00",
});

const PLANS = [plan("p1", "Single Court Plan"), plan("p2", "Two Court Plan")];
const SLOTS = new Map<string, PlanSlot[]>([
  ["p1", [slot("b1", "c1", "Court 1")]],
  ["p2", [slot("b2", "c1", "Court 1"), slot("b3", "c2", "Court 2")]],
]);
const ctx = { plans: PLANS, slotsByPlan: SLOTS, existingRows: [], now: NOW };

const good = {
  "Full Name": "Rahul Sharma",
  "Phone Number": "9876543210",
  "Plan Name": "Single Court Plan",
  Court: "",
  "Start Date": "2026-11-01",
};

describe("spreadsheet", () => {
  it("round-trips a template: headers carry * for required, the example row reads back", async () => {
    const buf = await buildTemplate(memberTemplateSpec(PLANS));
    const sheet = await readSheet(buf);
    expect(sheet.headers).toContain("full name");
    expect(sheet.headers).toContain("plan name");
    expect(sheet.rows).toHaveLength(1);
    expect(sheet.rows[0]!.values["full name"]).toBe("Rahul Sharma");
    expect(sheet.rows[0]!.values["phone number"]).toBe("9876543210");
  });

  it("reads numeric and date cells as plain text and skips blank rows", async () => {
    const wb = new ExcelJS.Workbook();
    const ws = wb.addWorksheet("S");
    ws.addRow(["Full Name *", "Phone Number *", "Start Date *"]);
    ws.addRow(["Asha", 9876543210, new Date(Date.UTC(2026, 10, 1))]);
    ws.addRow([null, null, null]);
    const sheet = await readSheet((await wb.xlsx.writeBuffer()) as ArrayBuffer);
    expect(sheet.rows).toHaveLength(1);
    expect(sheet.rows[0]!.values).toEqual({ "full name": "Asha", "phone number": "9876543210", "start date": "2026-11-01" });
  });

  it("parses dates in the accepted formats and rejects impossible ones", () => {
    expect(parseSheetDate("2026-11-01")).toBe("2026-11-01");
    expect(parseSheetDate("1/11/2026")).toBe("2026-11-01");
    expect(parseSheetDate("31-02-2026")).toBeNull();
    expect(parseSheetDate("tomorrow")).toBeNull();
  });

  it("normalises phone numbers typed with a country code", () => {
    expect(localPhone("+91 98765-43210")).toBe("9876543210");
    expect(localPhone("09876543210")).toBe("9876543210");
  });
});

describe("validateMemberRows", () => {
  it("accepts a good row and computes plan, court, timings and amount", () => {
    const { errors, members } = validateMemberRows(...(Object.values(sheetRows(MEMBER_COLUMNS, [good])) as [string[], never]), ctx);
    expect(errors).toEqual([]);
    expect(members).toHaveLength(1);
    expect(members[0]!.courtName).toBe("Court 1");
    expect(members[0]!.amountInr).toBe(1200); // fee + joining fee
    expect(members[0]!.timings).toMatch(/Mon\/Tue\/Wed/);
  });

  const run = (rows: Record<string, string>[], headersFrom = MEMBER_COLUMNS) => {
    const s = sheetRows(headersFrom, rows);
    return validateMemberRows(s.headers, s.rows, ctx);
  };

  it("rejects the whole upload when a single mandatory value is missing", () => {
    const r = run([good, { ...good, "Full Name": "", "Phone Number": "9123456789" }]);
    expect(r.members).toEqual([]); // the good row is NOT created either
    expect(r.errors).toEqual([{ row: 3, column: "Full Name", message: "Full name is required." }]);
  });

  it("names every missing mandatory column of a row", () => {
    const r = run([{ ...good, "Full Name": "", "Phone Number": "", "Plan Name": "", "Start Date": "" }]);
    expect(r.errors.map((e) => e.column).sort()).toEqual(["Full Name", "Phone Number", "Plan Name", "Start Date"]);
  });

  it("requires a court choice on a multi-court plan, and only that court's slots are kept", () => {
    const multi = { ...good, "Plan Name": "Two Court Plan" };
    expect(run([multi]).errors[0]).toMatchObject({ column: "Court" });
    const ok = run([{ ...multi, Court: "court 2" }]);
    expect(ok.errors).toEqual([]);
    expect(ok.members[0]!.slots.map((s) => s.batchId)).toEqual(["b3"]);
    expect(ok.members[0]!.courtName).toBe("Court 2");
    expect(run([{ ...multi, Court: "Court 9" }]).errors[0]!.message).toMatch(/not on this plan/);
  });

  it("flags unknown plans, bad phones, bad dates and duplicate rows", () => {
    expect(run([{ ...good, "Plan Name": "Nope" }]).errors[0]).toMatchObject({ column: "Plan Name" });
    expect(run([{ ...good, "Phone Number": "1234567890" }]).errors[0]).toMatchObject({ column: "Phone Number" });
    expect(run([{ ...good, "Start Date": "soon" }]).errors[0]).toMatchObject({ column: "Start Date" });
    const dup = run([good, good]);
    expect(dup.errors).toEqual([{ row: 3, column: "Phone Number", message: "Same phone number and plan as row 2." }]);
  });

  it("rejects a sheet missing a mandatory column, an empty sheet and an oversized one", () => {
    const noPlan = MEMBER_COLUMNS.filter((c) => c.header !== "Plan Name");
    expect(run([good], noPlan).errors[0]).toMatchObject({ row: 0, column: "Plan Name" });
    expect(run([]).errors[0]!.message).toMatch(/no members/);
    expect(run(Array.from({ length: 201 }, (_, i) => ({ ...good, "Phone Number": `98765${String(10000 + i)}` }))).errors[0]!.message).toMatch(/at most 200/);
  });
});

const program = (extra: Partial<ProgramDetail> = {}): ProgramDetail =>
  ({
    id: "pr1", name: "Junior Camp", sessionCount: 24, defaultPriceMinor: 500000, earlyBirdDiscountMinor: null, taxPercent: 18,
    isMembershipIncluded: false, feeType: "ONE_TIME", paymentMode: "BOTH", endDate: null,
    batches: [{ id: "bt1", name: "Evening", status: "ACTIVE" }], ...extra,
  }) as unknown as ProgramDetail;

describe("validateStudentRows", () => {
  const goodStudent = { "Student Name": "Aarav Mehta", "Phone Number": "9876543210", "Program Name": "Junior Camp", Batch: "Evening", "Start Date": "2026-11-01" };
  const run = (rows: Record<string, string>[], programs = [program()], cyclesFor = () => 3) => {
    const s = sheetRows(STUDENT_COLUMNS, rows);
    return validateStudentRows(s.headers, s.rows, { programs, cyclesFor, now: NOW });
  };

  it("accepts a good row with the program's total sessions and fee incl. tax", () => {
    const r = run([goodStudent]);
    expect(r.errors).toEqual([]);
    expect(r.students[0]!.totalMinor).toBe(590000);
    expect(r.students[0]!.program.sessionCount).toBe(24);
    expect(r.students[0]!.batchId).toBe("bt1");
  });

  it("multiplies a monthly program by its billing cycles", () => {
    const monthly = program({ feeType: "MONTHLY", endDate: "2027-01-31" });
    expect(run([goodStudent], [monthly]).students[0]!.totalMinor).toBe(590000 * 3);
  });

  it("is all-or-nothing and names the missing mandatory values", () => {
    const r = run([goodStudent, { ...goodStudent, "Student Name": "", "Phone Number": "9123456789", "Program Name": "" }]);
    expect(r.students).toEqual([]);
    expect(r.errors.map((e) => [e.row, e.column])).toEqual([[3, "Student Name"], [3, "Program Name"]]);
  });

  it("requires a batch when the program has batches, and rejects one when it has none", () => {
    expect(run([{ ...goodStudent, Batch: "" }]).errors[0]).toMatchObject({ column: "Batch" });
    expect(run([goodStudent], [program({ batches: [] })]).errors[0]).toMatchObject({ column: "Batch" });
  });

  it("a membership-included program costs nothing", () => {
    expect(programCycleFeeMinor(program({ isMembershipIncluded: true }))).toBe(0);
  });
});
