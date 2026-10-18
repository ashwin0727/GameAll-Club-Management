"use client";

import { useRef } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { BulkUploadPanel } from "@/features/bulk-upload/components/bulk-upload-panel";
import { loadActivePrograms, prepareStudentUpload } from "@/features/bulk-upload/bulk-prepare";
import { createBulkStudents, saveBulkResults, STUDENTS_KEY } from "@/features/bulk-upload/bulk-run";
import { studentTemplateSpec, type ParsedStudent } from "@/features/bulk-upload/student-bulk";
import { buildTemplate, downloadWorkbook } from "@/features/bulk-upload/spreadsheet";
import type { ProgramDetail } from "@/features/coaching/types";

export const STUDENTS_SUCCESS_HREF = "/coaching/students/bulk-success";

interface Props {
  facilityId: string;
  /** Number of active programs, or null while they are still loading. */
  activeProgramCount: number | null;
}

/** Bulk Upload for the Add Student page. Off until there is at least one active program to enrol people in. */
export function StudentBulkUpload({ facilityId, activeProgramCount }: Props) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const parsed = useRef<ParsedStudent[]>([]);
  const programs = useRef<ProgramDetail[] | null>(null);

  async function programsLoaded(): Promise<ProgramDetail[]> {
    if (!programs.current) programs.current = await loadActivePrograms(facilityId);
    return programs.current;
  }

  const disabledReason =
    activeProgramCount === null
      ? "Loading programs…"
      : activeProgramCount === 0
        ? "Bulk upload needs at least one active coaching program. Create a program first, then come back."
        : null;

  return (
    <BulkUploadPanel
      noun="Students"
      disabledReason={disabledReason}
      onDownloadTemplate={async () => downloadWorkbook(await buildTemplate(studentTemplateSpec(await programsLoaded())), "students-bulk-upload-sample.xlsx")}
      onValidate={async (file) => {
        const result = await prepareStudentUpload(file, await programsLoaded());
        parsed.current = result.students;
        return { errors: result.errors, count: result.students.length };
      }}
      onUpload={async (onProgress) => {
        const results = await createBulkStudents(facilityId, parsed.current, onProgress);
        saveBulkResults(STUDENTS_KEY, results);
        void queryClient.invalidateQueries();
        router.push(STUDENTS_SUCCESS_HREF);
      }}
    />
  );
}
