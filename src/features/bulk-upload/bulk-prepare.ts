import { readSheet, type BulkError } from "@/features/bulk-upload/spreadsheet";
import { validateMemberRows, type MemberValidationContext, type ParsedMember } from "@/features/bulk-upload/member-bulk";
import { validateStudentRows, type ParsedStudent } from "@/features/bulk-upload/student-bulk";
import type { ProgramDetail } from "@/features/coaching/types";
import { getCoachingService } from "@/services/coaching";

async function sheetFrom(file: File) {
  try {
    return await readSheet(await file.arrayBuffer());
  } catch {
    return null;
  }
}

const NOT_A_SHEET: BulkError = { row: 0, column: "", message: "That file couldn't be read — upload the .xlsx sample after filling it in." };

export interface PreparedMembers {
  errors: BulkError[];
  members: ParsedMember[];
}

export async function prepareMemberUpload(file: File, ctx: MemberValidationContext): Promise<PreparedMembers> {
  const sheet = await sheetFrom(file);
  if (!sheet) return { errors: [NOT_A_SHEET], members: [] };
  return validateMemberRows(sheet.headers, sheet.rows, ctx);
}

export interface PreparedStudents {
  errors: BulkError[];
  students: ParsedStudent[];
}

/** Loads every active program in full (batches, fees), then checks the sheet against them. */
export async function loadActivePrograms(facilityId: string): Promise<ProgramDetail[]> {
  const svc = getCoachingService();
  const page = await svc.listPrograms({ facilityId, filters: { status: "ACTIVE" }, limit: 100 });
  return Promise.all(page.programs.map((p) => svc.getProgram(p.id)));
}

export async function prepareStudentUpload(file: File, programs: ProgramDetail[]): Promise<PreparedStudents> {
  const sheet = await sheetFrom(file);
  if (!sheet) return { errors: [NOT_A_SHEET], students: [] };

  // The number of monthly payments comes from the database. A first pass notes which (start, end) pairs the
  // sheet needs, they are fetched once each, and the real pass then reads them from the map.
  const needed = new Map<string, [string, string | null]>();
  validateStudentRows(sheet.headers, sheet.rows, {
    programs,
    cyclesFor: (start, end) => {
      needed.set(`${start}|${end ?? ""}`, [start, end]);
      return 1;
    },
  });
  const cycles = new Map<string, number | null>();
  await Promise.all(
    [...needed].map(async ([k, [start, end]]) => {
      try {
        cycles.set(k, await getCoachingService().getBillingCycles(start, end));
      } catch {
        cycles.set(k, null);
      }
    }),
  );
  return validateStudentRows(sheet.headers, sheet.rows, {
    programs,
    cyclesFor: (start, end) => cycles.get(`${start}|${end ?? ""}`) ?? null,
  });
}
