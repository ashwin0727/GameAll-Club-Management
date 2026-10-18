"use client";

import { useRef } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { BulkUploadPanel } from "@/features/bulk-upload/components/bulk-upload-panel";
import { prepareMemberUpload } from "@/features/bulk-upload/bulk-prepare";
import { createBulkMembers, MEMBERS_KEY, saveBulkResults } from "@/features/bulk-upload/bulk-run";
import { memberTemplateSpec, type ParsedMember } from "@/features/bulk-upload/member-bulk";
import { buildTemplate, downloadWorkbook } from "@/features/bulk-upload/spreadsheet";
import { planSlotsFor } from "@/features/memberships/plan-slots";
import type { MembershipListRow, MembershipPlan } from "@/features/memberships/types";
import type { MembershipBatch } from "@/features/membership-sessions/types";

export const MEMBERS_SUCCESS_HREF = "/memberships/v1/new/bulk-success";

interface Props {
  facilityId: string;
  /** The active plans a member can join right now. */
  plans: MembershipPlan[];
  batches: MembershipBatch[];
  courtNames: ReadonlyMap<string, string>;
  existingRows: MembershipListRow[];
}

/** Bulk Upload for the Add New Member page. Off until there is at least one active plan to put people on. */
export function MemberBulkUpload({ facilityId, plans, batches, courtNames, existingRows }: Props) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const parsed = useRef<ParsedMember[]>([]);

  return (
    <BulkUploadPanel
      noun="Members"
      disabledReason={plans.length === 0 ? "Bulk upload needs at least one active membership plan. Create a plan first, then come back." : null}
      onDownloadTemplate={async () => downloadWorkbook(await buildTemplate(memberTemplateSpec(plans)), "members-bulk-upload-sample.xlsx")}
      onValidate={async (file) => {
        const slotsByPlan = new Map(plans.map((p) => [p.id, planSlotsFor(batches, p.id, courtNames)]));
        const result = await prepareMemberUpload(file, { plans, slotsByPlan, existingRows });
        parsed.current = result.members;
        return { errors: result.errors, count: result.members.length };
      }}
      onUpload={async (onProgress) => {
        const results = await createBulkMembers(facilityId, parsed.current, onProgress);
        saveBulkResults(MEMBERS_KEY, results);
        for (const key of ["membership-list", "member-schedules", "membership-summary", "membership-revenue", "membership-dashboard-rows"]) {
          void queryClient.invalidateQueries({ queryKey: [key] });
        }
        router.push(MEMBERS_SUCCESS_HREF);
      }}
    />
  );
}
