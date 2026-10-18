import { programTotalSessions } from "@/features/coaching/billing-schedule";
import { composePhone } from "@/features/bulk-upload/phone";
import { memberExtras, type ParsedMember } from "@/features/bulk-upload/member-bulk";
import { studentNotes, type ParsedStudent } from "@/features/bulk-upload/student-bulk";
import { getCoachingService } from "@/services/coaching";
import { getMembershipService } from "@/services/memberships";
import { MemberAlreadyExistsError } from "@/services/memberships/supabase-membership.service";
import { ServiceError } from "@/services/shared/service-error";
import { charges } from "@/features/memberships/add-member-wizard";

/** What the success pages show for each uploaded person. Money is whole rupees (members) / paise (students). */
export interface MemberBulkResult {
  rowNumber: number;
  name: string;
  phone: string;
  planName: string;
  courtName: string;
  timings: string;
  amountInr: number;
  membershipId: string | null;
  shortUrl: string | null;
  /** Set when the member could not be created, or was created but the link failed. */
  error: string | null;
}

export interface StudentBulkResult {
  rowNumber: number;
  name: string;
  phone: string;
  programName: string;
  batchName: string;
  totalSessions: number | null;
  totalMinor: number;
  enrollmentId: string | null;
  shortUrl: string | null;
  error: string | null;
  /** Why no link was sent when that is by design (free / offline-only program). */
  note: string | null;
}

export type Progress = (done: number, total: number) => void;

function message(err: unknown, fallback: string): string {
  return err instanceof ServiceError && err.message ? err.message : fallback;
}

/**
 * Creates each member exactly as the single Add Member form does, then asks Razorpay for their payment link —
 * Razorpay texts it to the member itself. Rows are independent: one failing does not stop the rest.
 */
export async function createBulkMembers(facilityId: string, members: ParsedMember[], onProgress: Progress): Promise<MemberBulkResult[]> {
  const svc = getMembershipService();
  const results: MemberBulkResult[] = [];
  for (const m of members) {
    const base: MemberBulkResult = {
      rowNumber: m.rowNumber,
      name: m.draft.fullName.trim(),
      phone: m.draft.phone,
      planName: m.plan.name,
      courtName: m.courtName,
      timings: m.timings,
      amountInr: m.amountInr,
      membershipId: null,
      shortUrl: null,
      error: null,
    };
    try {
      const [firstSlot, ...extraSlots] = m.slots;
      const c = charges(m.draft);
      const { address, notes } = memberExtras(m.draft);
      const membership = await svc.createMembershipFull({
        facilityId,
        fullName: m.draft.fullName.trim(),
        phone: composePhone(m.draft.countryCode, m.draft.phone),
        email: m.draft.email.trim() || undefined,
        dateOfBirth: m.draft.dateOfBirth || undefined,
        gender: m.draft.gender || undefined,
        address,
        name: m.plan.name,
        membershipType: "INDIVIDUAL",
        maxFamilyMembers: 1,
        startDate: m.draft.startDate,
        durationDays: m.draft.durationDays,
        batchId: firstSlot?.batchId,
        membershipFeeInr: c.subTotal,
        registrationFeeInr: c.registration,
        gstPercent: m.draft.gstPercent,
        paymentMode: "PENDING",
        paymentMethods: [],
        recurring: true,
        notes,
      });
      base.membershipId = membership.id;
      for (const slot of extraSlots) await svc.assignMembershipToBatch(slot.batchId, membership.memberId, membership.id);
      try {
        base.shortUrl = (await svc.createMembershipSubscription(membership.id)).shortUrl ?? null;
        if (!base.shortUrl) base.error = "Member added, but Razorpay returned no payment link — generate it from the member's page.";
      } catch (err) {
        base.error = `Member added, but the payment link failed: ${message(err, "try again from the member's page.")}`;
      }
    } catch (err) {
      base.error = message(err, "Could not add this member.");
    }
    results.push(base);
    onProgress(results.length, members.length);
  }
  return results;
}

/** Creates each student's member record (or reuses the one with that phone), enrols them and asks Razorpay for the link. */
export async function createBulkStudents(facilityId: string, students: ParsedStudent[], onProgress: Progress): Promise<StudentBulkResult[]> {
  const members = getMembershipService();
  const coaching = getCoachingService();
  const results: StudentBulkResult[] = [];
  for (const s of students) {
    const base: StudentBulkResult = {
      rowNumber: s.rowNumber,
      name: s.fullName,
      phone: s.phone,
      programName: s.program.name,
      batchName: s.batchName,
      totalSessions: programTotalSessions(s.program),
      totalMinor: s.totalMinor,
      enrollmentId: null,
      shortUrl: null,
      error: null,
      note: null,
    };
    try {
      let memberId: string;
      try {
        memberId = (
          await members.createMember({
            facilityId,
            fullName: s.fullName,
            phone: s.phone,
            email: s.email,
            dateOfBirth: s.dateOfBirth,
            gender: s.gender,
            notes: studentNotes(s),
          })
        ).id;
      } catch (err) {
        if (err instanceof MemberAlreadyExistsError) memberId = err.existingMemberId;
        else throw err;
      }
      const enrollmentId = await coaching.createEnrollment({
        facilityId,
        memberId,
        programId: s.program.id,
        batchId: s.batchId,
        startDate: s.startDate,
        priceMinor: s.program.isMembershipIncluded ? 0 : s.totalMinor,
        pricingType: s.program.isMembershipIncluded ? "MEMBERSHIP_INCLUDED" : "STANDARD",
      });
      base.enrollmentId = enrollmentId;
      if (s.program.isMembershipIncluded || s.totalMinor <= 0) {
        base.note = "No payment due";
      } else if (s.program.paymentMode === "OFFLINE") {
        base.note = "Offline payment only";
      } else {
        try {
          base.shortUrl = (await coaching.createEnrollmentBilling(enrollmentId)).shortUrl ?? null;
          if (!base.shortUrl) base.error = "Student enrolled, but Razorpay returned no payment link — generate it from the student's page.";
        } catch (err) {
          base.error = `Student enrolled, but the payment link failed: ${message(err, "try again from the student's page.")}`;
        }
      }
    } catch (err) {
      base.error = message(err, "Could not enrol this student.");
    }
    results.push(base);
    onProgress(results.length, students.length);
  }
  return results;
}

// ── Hand-off to the success pages ──────────────────────────────────────────────────────────────────
export const MEMBERS_KEY = "bulk-upload:members";
export const STUDENTS_KEY = "bulk-upload:students";

export function saveBulkResults<T>(storageKey: string, results: T[]): void {
  try {
    sessionStorage.setItem(storageKey, JSON.stringify(results));
  } catch {
    // The success page then shows its empty state; the data itself is already saved.
  }
}

export function loadBulkResults<T>(storageKey: string): T[] | null {
  try {
    const raw = sessionStorage.getItem(storageKey);
    return raw ? (JSON.parse(raw) as T[]) : null;
  } catch {
    return null;
  }
}
