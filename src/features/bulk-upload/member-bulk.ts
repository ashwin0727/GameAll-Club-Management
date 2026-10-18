import {
  charges,
  composeAddress,
  composeNotes,
  fieldErrors,
  type WizardDraft,
} from "@/features/memberships/add-member-wizard";
import { findDuplicateMember, normalizePhone } from "@/features/memberships/duplicate-guards";
import { courtsOf, type PlanSlot } from "@/features/memberships/plan-slots";
import { formatSlot } from "@/features/memberships/slot-format";
import type { MembershipListRow, MembershipPlan } from "@/features/memberships/types";
import {
  missingColumnErrors,
  normaliseHeader,
  parseSheetDate,
  type BulkError,
  type SheetRow,
  type TemplateColumn,
  type TemplateSpec,
} from "@/features/bulk-upload/spreadsheet";

/** Most members one upload may carry — keeps a single run to a few minutes and the result page readable. */
export const MAX_BULK_ROWS = 200;

export const MEMBER_COLUMNS: TemplateColumn[] = [
  { header: "Full Name", required: true, example: "Rahul Sharma" },
  { header: "Phone Number", required: true, example: "9876543210" },
  { header: "Plan Name", required: true, example: "Monthly Badminton" },
  { header: "Court", required: false, example: "Court 1" },
  { header: "Start Date", required: true, example: "2026-11-01" },
  { header: "Email", required: false, example: "rahul@example.com" },
  { header: "Date Of Birth", required: false, example: "1995-04-21" },
  { header: "Gender", required: false, example: "Male" },
  { header: "Address", required: false, example: "12 MG Road" },
  { header: "City", required: false, example: "Bengaluru" },
  { header: "Pincode", required: false, example: "560001" },
  { header: "Emergency Contact Name", required: false, example: "Anita Sharma" },
  { header: "Emergency Contact Phone", required: false, example: "9876500000" },
];

export function memberTemplateSpec(plans: MembershipPlan[]): TemplateSpec {
  return {
    sheetName: "Members",
    columns: MEMBER_COLUMNS,
    lists: { Gender: ["Male", "Female", "Other"], "Plan Name": plans.map((p) => p.name) },
    instructions: [
      "Bulk Upload — Members",
      "Fill one member per row on the Members sheet, then upload the file. Columns marked * are mandatory.",
      "If even one mandatory value is missing or invalid, nothing is uploaded — fix the rows listed and upload again.",
      "Phone Number: 10-digit Indian mobile number starting with 6, 7, 8 or 9. Razorpay sends the payment link to this number by SMS.",
      "Plan Name: exactly as it appears in your active plans" + (plans.length ? ` (${plans.map((p) => p.name).join(", ")}).` : "."),
      "Court: needed only when the plan covers more than one court — a member plays on one court at a time, so name the one they will use.",
      "Start Date: yyyy-mm-dd (or dd/mm/yyyy).",
      "Gender: Male, Female or Other. Date Of Birth: yyyy-mm-dd.",
      `At most ${MAX_BULK_ROWS} members per upload.`,
    ],
  };
}

/** One validated row, ready to create. */
export interface ParsedMember {
  rowNumber: number;
  draft: WizardDraft;
  plan: MembershipPlan;
  /** The one court's slots the member joins (all of the plan's slots when it has a single court). */
  slots: PlanSlot[];
  courtName: string;
  timings: string;
  /** What the first payment link charges: the plan fee plus any joining fee. */
  amountInr: number;
}

export interface MemberValidationContext {
  plans: MembershipPlan[];
  slotsByPlan: ReadonlyMap<string, PlanSlot[]>;
  existingRows: MembershipListRow[];
  now?: Date;
}

export function emptyDraft(startDate = ""): WizardDraft {
  return {
    fullName: "",
    countryCode: "+91",
    phone: "",
    email: "",
    dateOfBirth: "",
    gender: "",
    address: "",
    city: "",
    pincode: "",
    emergencyName: "",
    emergencyCountryCode: "+91",
    emergencyPhone: "",
    sendWelcome: true,
    planId: "",
    planName: "",
    startDate,
    durationDays: 0,
    membershipFeeInr: 0,
    registrationFeeInr: 0,
    gstPercent: 0,
    paymentTab: "link",
    paymentAmount: 0,
    paymentDate: startDate,
    paymentMethod: "Cash",
    paymentReference: "",
    receivedFrom: "",
    collectedBy: "",
    paymentNotes: "",
  };
}

/** A phone as typed in a sheet → the 10 local digits ("+91 98765-43210" → "9876543210"). Others pass through as digits. */
export function localPhone(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(2);
  if (digits.length === 11 && digits.startsWith("0")) return digits.slice(1);
  return digits;
}

export function normaliseGender(raw: string): string | null {
  const g = raw.trim().toLowerCase();
  if (!g) return "";
  return g === "male" || g === "female" || g === "other" ? g : null;
}

const key = (h: string) => normaliseHeader(h);

/**
 * Checks every row of the sheet. All-or-nothing: the caller creates members only when `errors` is empty.
 */
export function validateMemberRows(
  headers: string[],
  rows: SheetRow[],
  ctx: MemberValidationContext,
): { errors: BulkError[]; members: ParsedMember[] } {
  const errors: BulkError[] = missingColumnErrors(headers, MEMBER_COLUMNS);
  if (errors.length) return { errors, members: [] };
  if (rows.length === 0) return { errors: [{ row: 0, column: "", message: "The sheet has no members in it." }], members: [] };
  if (rows.length > MAX_BULK_ROWS) {
    return { errors: [{ row: 0, column: "", message: `A single upload can have at most ${MAX_BULK_ROWS} members — this one has ${rows.length}.` }], members: [] };
  }

  const plansByName = new Map<string, MembershipPlan[]>();
  for (const p of ctx.plans) {
    const k = p.name.trim().toLowerCase();
    plansByName.set(k, [...(plansByName.get(k) ?? []), p]);
  }
  const seen = new Map<string, number>(); // phone|plan → first row
  const members: ParsedMember[] = [];

  for (const { rowNumber, values } of rows) {
    const get = (h: string) => (values[key(h)] ?? "").trim();
    const add = (column: string, message: string) => errors.push({ row: rowNumber, column, message });
    const before = errors.length;

    const draft = emptyDraft();
    draft.fullName = get("Full Name");
    draft.phone = localPhone(get("Phone Number"));
    draft.email = get("Email");
    draft.address = get("Address");
    draft.city = get("City");
    draft.pincode = get("Pincode");
    draft.emergencyName = get("Emergency Contact Name");
    draft.emergencyPhone = localPhone(get("Emergency Contact Phone"));

    const dobText = get("Date Of Birth");
    if (dobText) {
      const dob = parseSheetDate(dobText);
      if (dob) draft.dateOfBirth = dob;
      else add("Date Of Birth", "Use the format yyyy-mm-dd.");
    }
    const gender = normaliseGender(get("Gender"));
    if (gender === null) add("Gender", "Use Male, Female or Other.");
    else draft.gender = gender;

    // Every mandatory column, named — an empty cell is reported before any format check.
    if (!draft.fullName) add("Full Name", "Full name is required.");
    if (!get("Phone Number")) add("Phone Number", "Phone number is required.");
    const planName = get("Plan Name");
    if (!planName) add("Plan Name", "Plan name is required.");
    const startText = get("Start Date");
    if (!startText) add("Start Date", "Start date is required.");

    // Format rules shared with the single Add Member form.
    const step1 = fieldErrors(1, draft, ctx.now);
    const labelOf: Record<string, string> = {
      fullName: "Full Name",
      phone: "Phone Number",
      email: "Email",
      dateOfBirth: "Date Of Birth",
      city: "City",
      pincode: "Pincode",
      emergencyName: "Emergency Contact Name",
      emergencyPhone: "Emergency Contact Phone",
    };
    for (const [field, msg] of Object.entries(step1)) {
      const column = labelOf[field];
      if (!msg || !column) continue;
      if (errors.some((e) => e.row === rowNumber && e.column === column)) continue;
      add(column, msg);
    }

    const startDate = startText ? parseSheetDate(startText) : null;
    if (startText && !startDate) add("Start Date", "Use the format yyyy-mm-dd.");
    if (startDate) draft.startDate = startDate;

    let plan: MembershipPlan | undefined;
    let slots: PlanSlot[] = [];
    let courtName = "—";
    if (planName) {
      const matches = plansByName.get(planName.toLowerCase()) ?? [];
      if (matches.length === 0) add("Plan Name", `No active plan named “${planName}”.`);
      else if (matches.length > 1) add("Plan Name", `More than one active plan is named “${planName}”.`);
      else plan = matches[0];
    }
    if (plan) {
      draft.planId = plan.id;
      draft.planName = plan.name;
      draft.durationDays = plan.durationDays;
      draft.membershipFeeInr = plan.priceInr;
      draft.registrationFeeInr = plan.joiningFeeInr ?? 0;
      const planSlots = ctx.slotsByPlan.get(plan.id) ?? [];
      const courts = courtsOf(planSlots);
      const courtText = get("Court");
      if (courts.length > 1) {
        if (!courtText) {
          add("Court", `“${plan.name}” covers ${courts.map((c) => c.courtName).join(", ")} — name the one court this member will use.`);
        } else {
          const hit = courts.find((c) => c.courtName.trim().toLowerCase() === courtText.toLowerCase());
          if (!hit) add("Court", `“${courtText}” is not on this plan — choose from ${courts.map((c) => c.courtName).join(", ")}.`);
          else {
            slots = planSlots.filter((s) => s.courtId === hit.courtId);
            courtName = hit.courtName;
          }
        }
      } else {
        slots = planSlots;
        courtName = courts[0]?.courtName ?? "—";
        if (courtText && courts[0] && courts[0].courtName.trim().toLowerCase() !== courtText.toLowerCase()) {
          add("Court", `“${courtText}” is not on this plan — it is on ${courts[0].courtName}.`);
        }
      }
      const step2 = fieldErrors(2, draft, ctx.now);
      if (step2.planId && !errors.some((e) => e.row === rowNumber && e.column === "Plan Name")) add("Plan Name", step2.planId);

      if (draft.phone && draft.fullName) {
        const dup = findDuplicateMember(ctx.existingRows, { id: plan.id, name: plan.name }, draft.phone);
        if (dup) add("Phone Number", "This person is already on this plan.");
        const dupKey = `${normalizePhone(draft.phone)}|${plan.id}`;
        const first = seen.get(dupKey);
        if (first !== undefined) add("Phone Number", `Same phone number and plan as row ${first}.`);
        else seen.set(dupKey, rowNumber);
      }
    }

    if (errors.length === before && plan && startDate) {
      const total = charges(draft).total;
      draft.paymentAmount = total;
      members.push({
        rowNumber,
        draft,
        plan,
        slots,
        courtName,
        timings: slots.map((s) => formatSlot(s.daysOfWeek, s.startTime, s.endTime)).join("; ") || "—",
        amountInr: total,
      });
    }
  }

  return { errors, members: errors.length ? [] : members };
}

/** Address / notes exactly as the single Add Member form would store them. */
export function memberExtras(draft: WizardDraft): { address: string | undefined; notes: string | undefined } {
  return { address: composeAddress(draft), notes: composeNotes(draft) };
}
