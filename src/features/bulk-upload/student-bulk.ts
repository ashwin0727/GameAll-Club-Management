import type { ProgramDetail } from "@/features/coaching/types";
import {
  missingColumnErrors,
  normaliseHeader,
  parseSheetDate,
  type BulkError,
  type SheetRow,
  type TemplateColumn,
  type TemplateSpec,
} from "@/features/bulk-upload/spreadsheet";
import { localPhone, normaliseGender, MAX_BULK_ROWS } from "@/features/bulk-upload/member-bulk";

export const STUDENT_COLUMNS: TemplateColumn[] = [
  { header: "Student Name", required: true, example: "Aarav Mehta" },
  { header: "Phone Number", required: true, example: "9876543210" },
  { header: "Program Name", required: true, example: "Junior Badminton Camp" },
  { header: "Batch", required: false, example: "Evening Batch" },
  { header: "Start Date", required: true, example: "2026-11-01" },
  { header: "Email", required: false, example: "aarav@example.com" },
  { header: "Date Of Birth", required: false, example: "2012-06-15" },
  { header: "Gender", required: false, example: "Male" },
  { header: "Address", required: false, example: "12 MG Road, Bengaluru" },
  { header: "Emergency Contact Name", required: false, example: "Neha Mehta" },
  { header: "Emergency Contact Phone", required: false, example: "9876500000" },
];

export function studentTemplateSpec(programs: Pick<ProgramDetail, "name" | "batches">[]): TemplateSpec {
  return {
    sheetName: "Students",
    columns: STUDENT_COLUMNS,
    lists: { Gender: ["Male", "Female", "Other"], "Program Name": programs.map((p) => p.name) },
    instructions: [
      "Bulk Upload — Students",
      "Fill one student per row on the Students sheet, then upload the file. Columns marked * are mandatory.",
      "If even one mandatory value is missing or invalid, nothing is uploaded — fix the rows listed and upload again.",
      "Phone Number: 10-digit Indian mobile number starting with 6, 7, 8 or 9. Razorpay sends the payment link to this number by SMS.",
      "Program Name: exactly as it appears in your active programs" + (programs.length ? ` (${programs.map((p) => p.name).join(", ")}).` : "."),
      "Batch: needed when the program has batches — the batch name exactly as it appears on the program.",
      "Start Date: yyyy-mm-dd (or dd/mm/yyyy). Gender: Male, Female or Other. Date Of Birth: yyyy-mm-dd.",
      `At most ${MAX_BULK_ROWS} students per upload.`,
    ],
  };
}

/** The fee a program charges per payment: price less the early-bird discount, plus tax. */
export function programCycleFeeMinor(p: Pick<ProgramDetail, "isMembershipIncluded" | "defaultPriceMinor" | "earlyBirdDiscountMinor" | "taxPercent">): number {
  if (p.isMembershipIncluded) return 0;
  const base = (p.defaultPriceMinor ?? 0) / 100;
  const discount = (p.earlyBirdDiscountMinor ?? 0) / 100;
  const tax = p.taxPercent ? Math.round(((base - discount) * p.taxPercent) / 100) : 0;
  return Math.round((Math.max(0, base - discount) + tax) * 100);
}

export interface ParsedStudent {
  rowNumber: number;
  fullName: string;
  phone: string;
  email: string | null;
  dateOfBirth: string | null;
  gender: string | null;
  address: string | null;
  emergencyName: string;
  emergencyPhone: string;
  program: ProgramDetail;
  batchId: string | null;
  batchName: string;
  startDate: string;
  /** The whole obligation: one fee, or every month's fee until the program ends. */
  totalMinor: number;
}

export interface StudentValidationContext {
  programs: ProgramDetail[];
  /** Number of monthly charges between two dates (decided by the database); null when unknown. */
  cyclesFor: (startDate: string, endDate: string | null) => number | null;
  now?: Date;
}

const key = (h: string) => normaliseHeader(h);
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MOBILE_RE = /^[6-9]\d{9}$/;

function dobProblem(iso: string, now: Date): boolean {
  const d = new Date(`${iso}T00:00:00`);
  return Number.isNaN(d.getTime()) || d > now || (now.getTime() - d.getTime()) / (365.25 * 24 * 3600 * 1000) > 120;
}

export function validateStudentRows(
  headers: string[],
  rows: SheetRow[],
  ctx: StudentValidationContext,
): { errors: BulkError[]; students: ParsedStudent[] } {
  const errors: BulkError[] = missingColumnErrors(headers, STUDENT_COLUMNS);
  if (errors.length) return { errors, students: [] };
  if (rows.length === 0) return { errors: [{ row: 0, column: "", message: "The sheet has no students in it." }], students: [] };
  if (rows.length > MAX_BULK_ROWS) {
    return { errors: [{ row: 0, column: "", message: `A single upload can have at most ${MAX_BULK_ROWS} students — this one has ${rows.length}.` }], students: [] };
  }
  const now = ctx.now ?? new Date();

  const byName = new Map<string, ProgramDetail[]>();
  for (const p of ctx.programs) {
    const k = p.name.trim().toLowerCase();
    byName.set(k, [...(byName.get(k) ?? []), p]);
  }
  const seen = new Map<string, number>();
  const students: ParsedStudent[] = [];

  for (const { rowNumber, values } of rows) {
    const get = (h: string) => (values[key(h)] ?? "").trim();
    const add = (column: string, message: string) => errors.push({ row: rowNumber, column, message });
    const before = errors.length;

    const fullName = get("Student Name");
    if (!fullName) add("Student Name", "Student name is required.");
    else if (!/^[A-Za-z][A-Za-z .'-]{1,59}$/.test(fullName)) add("Student Name", "Student name is invalid.");

    const phoneText = get("Phone Number");
    const phone = localPhone(phoneText);
    if (!phoneText) add("Phone Number", "Phone number is required.");
    else if (phone.length !== 10) add("Phone Number", "Enter a valid 10-digit phone number.");
    else if (!MOBILE_RE.test(phone)) add("Phone Number", "Phone number must start with 6, 7, 8 or 9.");

    const email = get("Email");
    if (email && !EMAIL_RE.test(email)) add("Email", "Email address is invalid.");

    let dateOfBirth: string | null = null;
    const dobText = get("Date Of Birth");
    if (dobText) {
      dateOfBirth = parseSheetDate(dobText);
      if (!dateOfBirth) add("Date Of Birth", "Use the format yyyy-mm-dd.");
      else if (dobProblem(dateOfBirth, now)) add("Date Of Birth", "Date of birth is invalid.");
    }
    const gender = normaliseGender(get("Gender"));
    if (gender === null) add("Gender", "Use Male, Female or Other.");

    const emergencyPhone = localPhone(get("Emergency Contact Phone"));
    if (emergencyPhone && !MOBILE_RE.test(emergencyPhone)) add("Emergency Contact Phone", "Enter a valid 10-digit phone number.");

    const startText = get("Start Date");
    let startDate: string | null = null;
    if (!startText) add("Start Date", "Start date is required.");
    else {
      startDate = parseSheetDate(startText);
      if (!startDate) add("Start Date", "Use the format yyyy-mm-dd.");
    }

    const programName = get("Program Name");
    let program: ProgramDetail | undefined;
    if (!programName) add("Program Name", "Program name is required.");
    else {
      const matches = byName.get(programName.toLowerCase()) ?? [];
      if (matches.length === 0) add("Program Name", `No active program named “${programName}”.`);
      else if (matches.length > 1) add("Program Name", `More than one active program is named “${programName}”.`);
      else program = matches[0];
    }

    let batchId: string | null = null;
    let batchName = "—";
    let totalMinor = 0;
    if (program) {
      const batchText = get("Batch");
      const activeBatches = program.batches.filter((b) => b.status === "ACTIVE");
      if (activeBatches.length > 0) {
        if (!batchText) add("Batch", `“${program.name}” has batches (${activeBatches.map((b) => b.name).join(", ")}) — name the one this student joins.`);
        else {
          const hit = activeBatches.find((b) => b.name.trim().toLowerCase() === batchText.toLowerCase());
          if (!hit) add("Batch", `“${batchText}” is not a batch of this program — choose from ${activeBatches.map((b) => b.name).join(", ")}.`);
          else {
            batchId = hit.id;
            batchName = hit.name;
          }
        }
      } else if (batchText) {
        add("Batch", "This program has no batches — leave the Batch cell empty.");
      }

      const monthly = program.feeType === "MONTHLY" && !program.isMembershipIncluded;
      const fee = programCycleFeeMinor(program);
      if (monthly) {
        if (!program.endDate) add("Program Name", "This monthly program has no end date, so its payments can't be scheduled.");
        else if (startDate) {
          const cycles = ctx.cyclesFor(startDate, program.endDate);
          if (cycles === null) add("Start Date", "Couldn't work out the monthly payments for this start date.");
          else totalMinor = fee * cycles;
        }
      } else {
        totalMinor = fee;
      }

      if (phone.length === 10) {
        const dupKey = `${phone}|${program.id}`;
        const first = seen.get(dupKey);
        if (first !== undefined) add("Phone Number", `Same phone number and program as row ${first}.`);
        else seen.set(dupKey, rowNumber);
      }
    }

    if (errors.length === before && program && startDate) {
      students.push({
        rowNumber,
        fullName,
        phone,
        email: email || null,
        dateOfBirth,
        gender: gender || null,
        address: get("Address") || null,
        emergencyName: get("Emergency Contact Name"),
        emergencyPhone,
        program,
        batchId,
        batchName,
        startDate,
        totalMinor,
      });
    }
  }

  return { errors, students: errors.length ? [] : students };
}

/** The member note the single Add Student form writes for an emergency contact. */
export function studentNotes(s: Pick<ParsedStudent, "emergencyName" | "emergencyPhone">): string | null {
  if (!s.emergencyName && !s.emergencyPhone) return null;
  return `Emergency Contact: ${s.emergencyName || "—"}${s.emergencyPhone ? ` (${s.emergencyPhone})` : ""}`;
}

export type { TemplateSpec };
