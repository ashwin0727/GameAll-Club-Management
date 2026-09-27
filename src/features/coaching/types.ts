// ═══════════════════════════════════════════════════════════════════════════
// Coaching Management — the shapes the UI works with.
//
// Coaching is an integration module: a coach is an existing staff member, a
// student is an existing member, a session reserves a real court through the
// existing availability engine, and a coaching fee is an obligation settled
// through the one payment path. Every authorization decision is the
// database's (has_permission + RLS). Money is in minor units (paise).
// ═══════════════════════════════════════════════════════════════════════════

export type CoachStatus = "ACTIVE" | "INACTIVE" | "ON_LEAVE";
export type ProgramStatus = "DRAFT" | "ACTIVE" | "PAUSED" | "COMPLETED" | "ARCHIVED" | "INACTIVE";
export type ProgramType = "GROUP" | "ONE_ON_ONE" | "TRIAL";
export type ProgramPaymentMode = "OFFLINE" | "ONLINE" | "BOTH";
export type SessionStatus = "SCHEDULED" | "CONFIRMED" | "IN_PROGRESS" | "COMPLETED" | "CANCELLED";
export type EnrollmentStatus = "ACTIVE" | "PAUSED" | "COMPLETED" | "CANCELLED";
export type EnrollmentPaymentStatus = "INCLUDED" | "PAID" | "PARTIAL" | "PENDING";
export type PricingType = "STANDARD" | "CUSTOM" | "MEMBERSHIP_INCLUDED";
export type ProgressStatus = "ON_TRACK" | "NEEDS_WORK" | "EXCELLING" | "AT_RISK";

// ── Overview ───────────────────────────────────────────────────────────────
export interface CoachingOverview {
  kpis: {
    activeStudents: number;
    activePrograms: number;
    activeCoaches: number;
    coachesOnLeave: number;
    sessionsThisMonth: number;
    upcomingSessions: number;
    revenueThisMonthMinor: number;
  };
  upcomingSessions: {
    id: string;
    startAt: string;
    endAt: string;
    programName: string;
    coachName: string;
    courtName: string;
    enrolled: number;
    capacity: number;
    status: SessionStatus;
  }[];
  activePrograms: {
    id: string;
    name: string;
    level: string;
    studentCount: number;
    sessionCount: number;
    status: ProgramStatus;
  }[];
  studentsByProgram: { programId: string; programName: string; students: number }[];
  studentGrowth: { month: string; monthKey: string; students: number }[];
  recentEnrollments: {
    id: string;
    studentName: string;
    programName: string;
    enrolledAt: string;
    status: EnrollmentStatus;
  }[];
}

/** A coach's teachable sport, from `coach_sports` joined to `facility_sports`. */
export interface CoachSport {
  id: string; // facility_sport_id
  name: string;
}

/** The fixed expertise-level vocabulary — same list `program-wizard-page.tsx`'s LEVELS uses. */
export const COACH_EXPERTISE_LEVELS = ["Beginner", "Intermediate", "Advanced", "All Levels"] as const;
export type CoachExpertiseLevel = (typeof COACH_EXPERTISE_LEVELS)[number];

// ── Coaches ────────────────────────────────────────────────────────────────
export interface CoachRow {
  id: string;
  userId: string;
  fullName: string;
  email: string | null;
  phone: string | null;
  avatarUrl: string | null;
  specialization: string | null;
  experienceYears: number | null;
  status: CoachStatus;
  expertiseLevels: string[];
  /** A manual, facility-set rating out of 5 — null until staff sets one on the Coach Profile. */
  rating: number | null;
  sports: CoachSport[];
  programCount: number;
  sessionCount: number;
  studentCount: number;
}

export interface CoachPage {
  coaches: CoachRow[];
  totalCount: number;
}

export type CoachSort = "name_asc" | "name_desc" | "experience_desc" | "sessions_desc";

export interface CoachFilters {
  search?: string | null;
  status?: CoachStatus | null;
  specialization?: string | null;
  sportId?: string | null;
}

export interface CoachAvailabilityWindow {
  id?: string;
  dayOfWeek: number; // 0 = Sun … 6 = Sat
  startTime: string; // "HH:MM" or "HH:MM:SS"
  endTime: string;
}

export interface CoachAvailabilityException {
  id: string;
  date: string;
  isAvailable: boolean;
  startTime: string | null;
  endTime: string | null;
  reason: string | null;
}

export interface CoachDetail {
  id: string;
  userId: string;
  fullName: string;
  email: string | null;
  phone: string | null;
  avatarUrl: string | null;
  specialization: string | null;
  experienceYears: number | null;
  certifications: string | null;
  bio: string | null;
  hourlyRateMinor: number | null;
  status: CoachStatus;
  joinedOn: string | null;
  title: string | null;
  expertiseLevels: string[];
  sports: CoachSport[];
  defaultSessionDurationMinutes: number | null;
  dateOfBirth: string | null;
  rating: number | null;
  stats: { sessionsThisMonth: number; activeStudents: number; programs: number };
  todaySchedule: {
    id: string;
    startAt: string;
    endAt: string;
    programName: string;
    courtName: string;
    status: SessionStatus;
  }[];
  programs: { id: string; name: string; level: string }[];
  students: { enrollmentId: string; memberId: string; name: string; programName: string; status: EnrollmentStatus }[];
  availability: CoachAvailabilityWindow[];
  availabilityExceptions: CoachAvailabilityException[];
}

export interface CoachInput {
  specialization?: string | null;
  experienceYears?: number | null;
  certifications?: string | null;
  bio?: string | null;
  hourlyRateMinor?: number | null;
  status?: CoachStatus | null;
  joinedOn?: string | null;
  /** `undefined` = don't touch; an array (possibly empty) replaces the coach's whole set. */
  sportIds?: string[];
  expertiseLevels?: string[];
  defaultSessionDurationMinutes?: number | null;
  dateOfBirth?: string | null;
  /** Manual, facility-set rating out of 5 — set from the Coach Profile, never during onboarding. */
  rating?: number | null;
}

/** The Coaching landing page's "Coaching Insights" panel, for the Last 30/60/90 Days dropdown. */
export interface CoachingInsights {
  windowDays: 30 | 60 | 90;
  totalStudents: number;
  /** Completed ÷ concluded (completed + cancelled) sessions in the window, as a percentage — a
   *  proxy for per-student attendance, which no check-in system exists to track. Null when no
   *  session in the window has concluded yet. */
  sessionAttendancePct: number | null;
  coachingRevenueMinor: number;
  /** Average of every active coach's manual `rating`; null until at least one is set. */
  averageRating: number | null;
}

export interface CoachCandidate {
  userId: string;
  fullName: string;
  email: string | null;
  phone: string | null;
  avatarUrl: string | null;
  title: string | null;
}

export interface CoachOption {
  id: string;
  name: string;
  specialization: string | null;
}

// ── Programs ───────────────────────────────────────────────────────────────
export interface ProgramRow {
  id: string;
  name: string;
  level: string;
  ageGroup: string;
  category: string;
  defaultDurationMinutes: number;
  defaultCapacity: number;
  sessionCount: number | null;
  defaultPriceMinor: number | null;
  isMembershipIncluded: boolean;
  status: ProgramStatus;
  imageUrl: string | null;
  programType: ProgramType;
  sessionsPerWeek: number | null;
  studentCount: number;
  scheduledSessionCount: number;
  batchCount: number;
  facilitySportId: string | null;
  startDate: string | null;
  endDate: string | null;
}

export interface ProgramPage {
  programs: ProgramRow[];
  totalCount: number;
}

/** The Coaching Programs list page's KPI row, Featured Program card and Program Insights panel. */
export interface ProgramInsights {
  totalPrograms: number;
  newProgramsThisMonth: number;
  enrolledStudents: number;
  /** Null when there were no enrollments in the prior 30-day period to compare against. */
  enrolledStudentsPctChange: number | null;
  /** Average (active enrollments / capacity) across active programs, as a percentage. */
  avgCompletionPct: number | null;
  averageRating: number | null;
  activeBatches: number;
  featuredProgram: {
    id: string;
    name: string;
    imageUrl: string | null;
    level: string;
    ageGroup: string;
    defaultCapacity: number;
    studentCount: number;
    defaultPriceMinor: number | null;
    isMembershipIncluded: boolean;
    durationWeeks: number | null;
  } | null;
}

/** One recurring weekly time slot under a program — court/coach/days/time/capacity, its own
 *  independent schedule (a program can have several). */
export interface ProgramBatch {
  id: string;
  name: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
  status: "ACTIVE" | "INACTIVE";
  courtId: string;
  courtName: string;
  coachId: string | null;
  coachName: string | null;
  /** Only populated by list_coaching_program_batches; get_coaching_program's embedded batches
   *  don't carry this (it's the program-wide count, not per-batch). */
  enrolledCount?: number;
}

/** A facility-wide, active batch that has at least one enrolled student — the raw material for
 *  Manage Students' "Upcoming Coaching Sessions" card, which projects each one's next weekly
 *  occurrence client-side (there's no per-occurrence session row for the ordinary recurring
 *  schedule, only for the separate Coach Scheduler ad-hoc flow). */
export interface ActiveBatchWithStudents {
  id: string;
  programId: string;
  programName: string;
  batchName: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  courtName: string;
  coachName: string | null;
  enrolledCount: number;
  capacity: number;
}

export interface ProgramDetail {
  id: string;
  facilityId: string;
  name: string;
  level: string;
  ageGroup: string;
  category: string;
  description: string | null;
  facilitySportId: string | null;
  defaultDurationMinutes: number;
  defaultCapacity: number;
  sessionCount: number | null;
  defaultPriceMinor: number | null;
  isMembershipIncluded: boolean;
  status: ProgramStatus;
  imageUrl: string | null;
  programType: ProgramType;
  minCapacity: number | null;
  programStructure: string[];
  sessionFormat: string | null;
  sessionsPerWeek: number | null;
  startDate: string | null;
  endDate: string | null;
  paymentMode: ProgramPaymentMode;
  earlyBirdDiscountMinor: number | null;
  discountValidTill: string | null;
  taxPercent: number | null;
  paymentNotes: string | null;
  allowWaitlist: boolean;
  allowTrialSession: boolean;
  autoEnrollNextBatch: boolean;
  sendNotifications: boolean;
  visibleInBooking: boolean;
  enrollmentDeadline: string | null;
  batches: ProgramBatch[];
  createdAt: string;
  stats: {
    activeStudents: number;
    totalEnrollments: number;
    scheduledSessions: number;
    completedSessions: number;
  };
}

/** A batch as drafted client-side, before the program (and therefore a real programId) exists —
 *  sent as part of CreateProgramInput's `batches` and turned into real rows atomically by
 *  create_coaching_program_full. */
export interface DraftProgramBatch {
  name: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
  capacity: number;
  courtId: string;
  coachId?: string | null;
}

export interface CreateProgramInput {
  facilityId: string;
  name: string;
  level?: string;
  ageGroup?: string;
  category?: string;
  description?: string | null;
  facilitySportId?: string | null;
  defaultDurationMinutes?: number;
  defaultCapacity?: number;
  sessionCount?: number | null;
  defaultPriceMinor?: number | null;
  isMembershipIncluded?: boolean;
  imageUrl?: string | null;
  programType?: ProgramType;
  minCapacity?: number | null;
  programStructure?: string[];
  sessionFormat?: string | null;
  sessionsPerWeek?: number | null;
  startDate?: string | null;
  endDate?: string | null;
  paymentMode?: ProgramPaymentMode;
  earlyBirdDiscountMinor?: number | null;
  discountValidTill?: string | null;
  taxPercent?: number | null;
  paymentNotes?: string | null;
  allowWaitlist?: boolean;
  allowTrialSession?: boolean;
  autoEnrollNextBatch?: boolean;
  sendNotifications?: boolean;
  visibleInBooking?: boolean;
  enrollmentDeadline?: string | null;
  status?: ProgramStatus;
  /** Only accepted by createProgramFull — ignored by plain createProgram. */
  batches?: DraftProgramBatch[];
}

export interface UpdateProgramInput extends Partial<Omit<CreateProgramInput, "facilityId" | "batches" | "status">> {
  programId: string;
  status?: ProgramStatus | null;
}

export interface ProgramOption {
  id: string;
  name: string;
  defaultCapacity: number;
  defaultDurationMinutes: number;
  defaultPriceMinor: number | null;
  isMembershipIncluded: boolean;
  sessionCount: number | null;
}

// ── Sessions ───────────────────────────────────────────────────────────────
export interface SessionRow {
  id: string;
  programId: string | null;
  /** The program's name, or the session's own `title` for a program-less (Coach Scheduler) session. */
  programName: string;
  coachId: string;
  coachName: string;
  courtId: string;
  courtName: string;
  startAt: string;
  endAt: string;
  capacity: number;
  enrolledCount: number;
  status: SessionStatus;
  sessionType: ProgramType;
}

export interface SessionPage {
  sessions: SessionRow[];
  totalCount: number;
}

export interface SessionFilters {
  from?: string | null;
  to?: string | null;
  coachId?: string | null;
  programId?: string | null;
  courtId?: string | null;
  status?: SessionStatus | null;
}

export interface SessionStudent {
  enrollmentId: string;
  memberId: string;
  name: string;
  phone: string | null;
  status: "ENROLLED" | "REMOVED";
  enrollmentStatus: EnrollmentStatus;
}

export interface SessionDetail {
  id: string;
  facilityId: string;
  programId: string | null;
  programName: string;
  programLevel: string;
  coachId: string;
  coachName: string;
  courtId: string;
  courtName: string;
  startAt: string;
  endAt: string;
  capacity: number;
  status: SessionStatus;
  notes: string | null;
  objective: string | null;
  objectiveResult: string | null;
  completedAt: string | null;
  cancelReason: string | null;
  title: string | null;
  description: string | null;
  sessionType: ProgramType;
  facilitySportId: string | null;
  pricePerStudentMinor: number | null;
  visibleForBooking: boolean;
  sendNotification: boolean;
  allowWaitlist: boolean;
  enrolledCount: number;
  students: SessionStudent[];
  progressNotes:
    | {
        id: string;
        memberName: string;
        skillOrGoal: string | null;
        note: string;
        progressStatus: ProgressStatus;
        createdAt: string;
      }[]
    | null;
  events: { id: string; event: string; summary: string; actorName: string | null; createdAt: string }[];
}

export interface CreateSessionInput {
  facilityId: string;
  /** Omitted for a standalone Coach Scheduler session — no coaching program owns it. */
  programId?: string | null;
  coachId: string;
  courtId: string;
  startAt: string;
  endAt: string;
  capacity?: number | null;
  notes?: string | null;
  objective?: string | null;
  status?: "SCHEDULED" | "CONFIRMED";
  autoEnroll?: boolean;
  title?: string | null;
  description?: string | null;
  level?: string | null;
  facilitySportId?: string | null;
  sessionType?: ProgramType;
  pricePerStudentMinor?: number | null;
  visibleForBooking?: boolean;
  sendNotification?: boolean;
  allowWaitlist?: boolean;
}

export interface RescheduleSessionInput {
  sessionId: string;
  coachId?: string | null;
  courtId?: string | null;
  startAt?: string | null;
  endAt?: string | null;
  capacity?: number | null;
  notes?: string | null;
  objective?: string | null;
}

// ── Enrollments ────────────────────────────────────────────────────────────
export interface EnrollmentRow {
  id: string;
  memberId: string;
  studentName: string;
  studentPhone: string | null;
  studentAge: number | null;
  programId: string;
  programName: string;
  programLevel: string;
  coachId: string | null;
  coachName: string | null;
  coachAvatarUrl: string | null;
  batchId: string | null;
  batchName: string | null;
  startDate: string;
  endDate: string | null;
  sessionsTotal: number | null;
  priceMinor: number;
  paidMinor: number;
  status: EnrollmentStatus;
  paymentStatus: EnrollmentPaymentStatus;
}

export interface EnrollmentPage {
  enrollments: EnrollmentRow[];
  totalCount: number;
}

export interface EnrollmentFilters {
  search?: string | null;
  programId?: string | null;
  /** `"NOT_ACTIVE"` groups every non-ACTIVE status — the "Inactive" tab. */
  status?: EnrollmentStatus | "NOT_ACTIVE" | null;
  coachId?: string | null;
  level?: string | null;
}

export interface EnrollmentDetail {
  id: string;
  facilityId: string;
  memberId: string;
  studentName: string;
  studentPhone: string | null;
  studentEmail: string | null;
  programId: string;
  programName: string;
  programLevel: string;
  coachId: string | null;
  coachName: string | null;
  batchId: string | null;
  batchName: string | null;
  startDate: string;
  endDate: string | null;
  sessionsTotal: number | null;
  priceMinor: number;
  paidMinor: number;
  outstandingMinor: number;
  pricingType: PricingType;
  status: EnrollmentStatus;
  notes: string | null;
  cancelReason: string | null;
  createdAt: string;
  sessions: {
    id: string;
    startAt: string;
    endAt: string;
    programName: string;
    courtName: string;
    status: SessionStatus;
  }[];
  payments: { id: string; amountMinor: number; paidAt: string; method: string | null; reference: string | null }[];
  progressNotes:
    | {
        id: string;
        skillOrGoal: string | null;
        note: string;
        progressStatus: ProgressStatus;
        coachName: string | null;
        sessionId: string | null;
        createdAt: string;
      }[]
    | null;
}

export interface CreateEnrollmentInput {
  facilityId: string;
  memberId: string;
  programId: string;
  coachId?: string | null;
  batchId?: string | null;
  startDate?: string | null;
  endDate?: string | null;
  sessionsTotal?: number | null;
  priceMinor?: number | null;
  pricingType?: PricingType | null;
  notes?: string | null;
}

export interface UpdateEnrollmentInput {
  enrollmentId: string;
  coachId?: string | null;
  startDate?: string | null;
  endDate?: string | null;
  sessionsTotal?: number | null;
  priceMinor?: number | null;
  notes?: string | null;
}

// ── Reports ────────────────────────────────────────────────────────────────
export interface CoachingReports {
  kpis: {
    activeStudents: number;
    activePrograms: number;
    sessionsInRange: number;
    completedSessionsInRange: number;
    coachingRevenueMinor: number;
    avgCapacityUtilization: number;
  };
  programPerformance: {
    programId: string;
    programName: string;
    activeStudents: number;
    sessions: number;
    capacityUtilization: number;
    revenueMinor: number;
  }[];
  coachUtilization: {
    coachId: string;
    coachName: string;
    scheduledHours: number;
    weeklyAvailableHours: number;
    sessions: number;
  }[];
  studentGrowth: { month: string; monthKey: string; students: number }[];
}

export interface CoachingEvent {
  id: string;
  event: string;
  summary: string;
  actorName: string | null;
  detail: Record<string, unknown>;
  createdAt: string;
}
