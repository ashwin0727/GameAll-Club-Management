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
export type ProgramStatus = "ACTIVE" | "INACTIVE";
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
  programCount: number;
  sessionCount: number;
  studentCount: number;
}

export interface CoachPage {
  coaches: CoachRow[];
  totalCount: number;
}

export interface CoachFilters {
  search?: string | null;
  status?: CoachStatus | null;
  specialization?: string | null;
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
}

export interface CoachCandidate {
  userId: string;
  fullName: string;
  email: string | null;
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
  studentCount: number;
  scheduledSessionCount: number;
}

export interface ProgramPage {
  programs: ProgramRow[];
  totalCount: number;
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
  createdAt: string;
  stats: {
    activeStudents: number;
    totalEnrollments: number;
    scheduledSessions: number;
    completedSessions: number;
  };
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
}

export interface UpdateProgramInput extends Partial<Omit<CreateProgramInput, "facilityId">> {
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
  programId: string;
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
  programId: string;
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
  programId: string;
  coachId: string;
  courtId: string;
  startAt: string;
  endAt: string;
  capacity?: number | null;
  notes?: string | null;
  objective?: string | null;
  status?: "SCHEDULED" | "CONFIRMED";
  autoEnroll?: boolean;
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
  programId: string;
  programName: string;
  coachName: string | null;
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
  status?: EnrollmentStatus | null;
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
