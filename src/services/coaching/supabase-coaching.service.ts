"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { ServiceError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";
import type {
  ActiveBatchWithStudents,
  CoachAvailabilityWindow,
  CoachCandidate,
  CoachDetail,
  CoachFilters,
  CoachInput,
  CoachOption,
  CoachPage,
  CoachSort,
  CoachingEvent,
  CoachingInsights,
  CoachingOverview,
  CoachingReports,
  CreateEnrollmentInput,
  CreateProgramInput,
  CreateSessionInput,
  EnrollmentDetail,
  EnrollmentFilters,
  EnrollmentPage,
  ProgramBatch,
  ProgramDetail,
  ProgramInsights,
  ProgramOption,
  ProgramPage,
  ProgramRow,
  RescheduleSessionInput,
  SessionDetail,
  SessionFilters,
  SessionPage,
  UpdateEnrollmentInput,
  UpdateProgramInput,
} from "@/features/coaching/types";

function mapError(error: unknown): ServiceError {
  console.error("[coaching-service] request failed", error);
  const message = (error as { message?: string } | null)?.message ?? "";
  const code = (error as { code?: string } | null)?.code ?? "";
  if (code === "42501" || /permission/i.test(message)) {
    return new ServiceError("COACHING_ACCESS_DENIED", message || undefined);
  }
  if (code === "23505" || /already (exists|has|enrolled)/i.test(message)) {
    return new ServiceError("COACHING_DUPLICATE", message || undefined);
  }
  if (code === "P0002" || /not found/i.test(message)) {
    return new ServiceError("COACHING_NOT_FOUND", message || undefined);
  }
  // Slot conflicts / capacity / availability — the RPC raises a plain,
  // user-safe message. Surface it verbatim.
  if (
    /already (booked|has a session|uses this court)|not available|under maintenance|reserved for|is full|operating hours/i.test(
      message,
    )
  ) {
    return new ServiceError("COACHING_CONFLICT", message);
  }
  if (message) return new ServiceError("COACHING_RULE_ERROR", message);
  return new ServiceError("COACHING_DATA_ERROR");
}

export class SupabaseCoachingService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  // ── Overview / reports ───────────────────────────────────────────────────
  async getOverview(facilityId: string): Promise<CoachingOverview> {
    const { data, error } = await this.supabase.rpc("get_coaching_overview", { p_facility_id: facilityId });
    if (error || !data) throw mapError(error);
    return data as unknown as CoachingOverview;
  }

  /** The Coaching Insights panel's own Last 30/60/90 Days figures — independent of the KPI row's
   *  fixed calendar-month numbers above it. */
  async getInsights(facilityId: string, days: 30 | 60 | 90): Promise<CoachingInsights> {
    const { data, error } = await this.supabase.rpc("get_coaching_insights", { p_facility_id: facilityId, p_days: days });
    if (error || !data) throw mapError(error);
    return data as unknown as CoachingInsights;
  }

  async getReports(input: {
    facilityId: string;
    preset?: string | null;
    startDate?: string | null;
    endDate?: string | null;
  }): Promise<CoachingReports> {
    const { data, error } = await this.supabase.rpc("get_coaching_reports", {
      p_facility_id: input.facilityId,
      p_preset: input.preset ?? null,
      p_start_date: input.startDate ?? null,
      p_end_date: input.endDate ?? null,
    });
    if (error || !data) throw mapError(error);
    return data as unknown as CoachingReports;
  }

  async listEvents(input: { facilityId: string; event?: string | null; limit?: number; offset?: number }): Promise<{
    events: CoachingEvent[];
    totalCount: number;
  }> {
    const { data, error } = await this.supabase.rpc("list_coaching_events", {
      p_facility_id: input.facilityId,
      p_event: input.event ?? null,
      p_limit: input.limit ?? 30,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      events: (data ?? []).map((e) => ({
        id: e.id,
        event: e.event,
        summary: e.summary,
        actorName: e.actor_name,
        detail: e.detail,
        createdAt: e.created_at,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  // ── Coaches ──────────────────────────────────────────────────────────────
  async listCoaches(input: {
    facilityId: string;
    filters?: CoachFilters;
    sort?: CoachSort;
    limit?: number;
    offset?: number;
  }): Promise<CoachPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_coaches", {
      p_facility_id: input.facilityId,
      p_search: f.search?.trim() || null,
      p_status: f.status ?? null,
      p_specialization: f.specialization?.trim() || null,
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
      p_sport_id: f.sportId ?? null,
      p_sort: input.sort ?? "name_asc",
    });
    if (error) throw mapError(error);
    return {
      coaches: (data ?? []).map((r) => ({
        id: r.id,
        userId: r.user_id,
        fullName: r.full_name,
        email: r.email,
        phone: r.phone,
        avatarUrl: r.avatar_url,
        specialization: r.specialization,
        experienceYears: r.experience_years,
        status: r.status,
        expertiseLevels: r.expertise_levels ?? [],
        rating: r.rating,
        sports: (r.sports as { id: string; name: string }[] | null) ?? [],
        programCount: r.program_count,
        sessionCount: r.session_count,
        studentCount: r.student_count,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getCoach(coachId: string): Promise<CoachDetail> {
    const { data, error } = await this.supabase.rpc("get_coach", { p_coach_id: coachId });
    if (error || !data) throw mapError(error);
    return data as unknown as CoachDetail;
  }

  async listCoachCandidates(facilityId: string): Promise<CoachCandidate[]> {
    const { data, error } = await this.supabase.rpc("list_coach_candidates", { p_facility_id: facilityId });
    if (error) throw mapError(error);
    return (data ?? []).map((r) => ({
      userId: r.user_id,
      fullName: r.full_name,
      email: r.email,
      phone: r.phone,
      avatarUrl: r.avatar_url,
      title: r.title,
    }));
  }

  async listCoachOptions(facilityId: string): Promise<CoachOption[]> {
    const { data, error } = await this.supabase.rpc("list_coach_options", { p_facility_id: facilityId });
    if (error) throw mapError(error);
    return (data ?? []).map((r) => ({ id: r.id, name: r.name, specialization: r.specialization }));
  }

  async addCoach(facilityId: string, userId: string, input: CoachInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("add_coach", {
      p_facility_id: facilityId,
      p_user_id: userId,
      p_specialization: input.specialization ?? null,
      p_experience_years: input.experienceYears ?? null,
      p_certifications: input.certifications ?? null,
      p_bio: input.bio ?? null,
      p_hourly_rate_minor: input.hourlyRateMinor ?? null,
      p_status: input.status ?? "ACTIVE",
      p_joined_on: input.joinedOn ?? null,
      p_sport_ids: input.sportIds ?? null,
      p_expertise_levels: input.expertiseLevels ?? null,
      p_default_session_duration_minutes: input.defaultSessionDurationMinutes ?? null,
      p_date_of_birth: input.dateOfBirth ?? null,
    });
    if (error || !data) throw mapError(error);
    return data.id;
  }

  async updateCoach(coachId: string, input: CoachInput): Promise<void> {
    const { error } = await this.supabase.rpc("update_coach", {
      p_coach_id: coachId,
      p_specialization: input.specialization ?? null,
      p_experience_years: input.experienceYears ?? null,
      p_certifications: input.certifications ?? null,
      p_bio: input.bio ?? null,
      p_hourly_rate_minor: input.hourlyRateMinor ?? null,
      p_status: input.status ?? null,
      p_joined_on: input.joinedOn ?? null,
      p_sport_ids: input.sportIds ?? null,
      p_expertise_levels: input.expertiseLevels ?? null,
      p_default_session_duration_minutes: input.defaultSessionDurationMinutes ?? null,
      p_date_of_birth: input.dateOfBirth ?? null,
      p_rating: input.rating ?? null,
    });
    if (error) throw mapError(error);
  }

  async setCoachAvailability(coachId: string, windows: CoachAvailabilityWindow[]): Promise<void> {
    const { error } = await this.supabase.rpc("set_coach_availability", {
      p_coach_id: coachId,
      p_windows: windows.map((w) => ({ dayOfWeek: w.dayOfWeek, startTime: w.startTime, endTime: w.endTime })),
    });
    if (error) throw mapError(error);
  }

  async setCoachAvailabilityException(input: {
    coachId: string;
    date: string;
    isAvailable: boolean;
    startTime?: string | null;
    endTime?: string | null;
    reason?: string | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("set_coach_availability_exception", {
      p_coach_id: input.coachId,
      p_exception_date: input.date,
      p_is_available: input.isAvailable,
      p_start_time: input.startTime ?? null,
      p_end_time: input.endTime ?? null,
      p_reason: input.reason ?? null,
    });
    if (error) throw mapError(error);
  }

  async deleteCoachAvailabilityException(exceptionId: string): Promise<void> {
    const { error } = await this.supabase.rpc("delete_coach_availability_exception", { p_exception_id: exceptionId });
    if (error) throw mapError(error);
  }

  // ── Programs ─────────────────────────────────────────────────────────────
  async listPrograms(input: {
    facilityId: string;
    filters?: {
      search?: string | null;
      status?: ProgramPage["programs"][number]["status"] | null;
      facilitySportId?: string | null;
      programType?: ProgramRow["programType"] | null;
      level?: string | null;
    };
    limit?: number;
    offset?: number;
  }): Promise<ProgramPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_coaching_programs", {
      p_facility_id: input.facilityId,
      p_search: f.search?.trim() || null,
      p_status: f.status ?? null,
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
      p_facility_sport_id: f.facilitySportId ?? null,
      p_program_type: f.programType ?? null,
      p_level: f.level ?? null,
    });
    if (error) throw mapError(error);
    return {
      programs: (data ?? []).map((r) => ({
        id: r.id,
        name: r.name,
        level: r.level,
        ageGroup: r.age_group,
        category: r.category,
        defaultDurationMinutes: r.default_duration_minutes,
        defaultCapacity: r.default_capacity,
        sessionCount: r.session_count,
        defaultPriceMinor: r.default_price_minor,
        isMembershipIncluded: r.is_membership_included,
        status: r.status,
        imageUrl: r.image_url,
        programType: r.program_type,
        sessionsPerWeek: r.sports_per_week,
        studentCount: r.student_count,
        scheduledSessionCount: r.scheduled_session_count,
        batchCount: r.batch_count,
        facilitySportId: r.facility_sport_id,
        startDate: r.start_date,
        endDate: r.end_date,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getProgramInsights(facilityId: string): Promise<ProgramInsights> {
    const { data, error } = await this.supabase.rpc("get_program_insights", { p_facility_id: facilityId });
    if (error || !data) throw mapError(error);
    return data as unknown as ProgramInsights;
  }

  async getProgram(programId: string): Promise<ProgramDetail> {
    const { data, error } = await this.supabase.rpc("get_coaching_program", { p_program_id: programId });
    if (error || !data) throw mapError(error);
    return data as unknown as ProgramDetail;
  }

  async listProgramOptions(facilityId: string): Promise<ProgramOption[]> {
    const { data, error } = await this.supabase.rpc("list_coaching_program_options", { p_facility_id: facilityId });
    if (error) throw mapError(error);
    return (data ?? []).map((r) => ({
      id: r.id,
      name: r.name,
      defaultCapacity: r.default_capacity,
      defaultDurationMinutes: r.default_duration_minutes,
      defaultPriceMinor: r.default_price_minor,
      isMembershipIncluded: r.is_membership_included,
      sessionCount: r.session_count,
    }));
  }

  private programCreateArgs(input: CreateProgramInput) {
    return {
      p_facility_id: input.facilityId,
      p_name: input.name,
      p_level: input.level ?? "All Levels",
      p_age_group: input.ageGroup ?? "All Ages",
      p_category: input.category ?? "General",
      p_description: input.description ?? null,
      p_facility_sport_id: input.facilitySportId ?? null,
      p_default_duration_minutes: input.defaultDurationMinutes ?? 60,
      p_default_capacity: input.defaultCapacity ?? 1,
      p_session_count: input.sessionCount ?? null,
      p_default_price_minor: input.defaultPriceMinor ?? null,
      p_is_membership_included: input.isMembershipIncluded ?? false,
      p_image_url: input.imageUrl ?? null,
      p_program_type: input.programType ?? "GROUP",
      p_min_capacity: input.minCapacity ?? null,
      p_program_structure: input.programStructure ?? [],
      p_session_format: input.sessionFormat ?? null,
      p_sessions_per_week: input.sessionsPerWeek ?? null,
      p_start_date: input.startDate ?? null,
      p_end_date: input.endDate ?? null,
      p_payment_mode: input.paymentMode ?? "OFFLINE",
      p_early_bird_discount_minor: input.earlyBirdDiscountMinor ?? null,
      p_discount_valid_till: input.discountValidTill ?? null,
      p_tax_percent: input.taxPercent ?? null,
      p_payment_notes: input.paymentNotes ?? null,
      p_allow_waitlist: input.allowWaitlist ?? true,
      p_allow_trial_session: input.allowTrialSession ?? false,
      p_auto_enroll_next_batch: input.autoEnrollNextBatch ?? false,
      p_send_notifications: input.sendNotifications ?? true,
      p_visible_in_booking: input.visibleInBooking ?? false,
      p_enrollment_deadline: input.enrollmentDeadline ?? null,
      p_status: input.status ?? "ACTIVE",
    };
  }

  async createProgram(input: CreateProgramInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_coaching_program", this.programCreateArgs(input));
    if (error || !data) throw mapError(error);
    return data.id;
  }

  /** Program + its initial batches, atomically — the wizard's "Create Program" submit. */
  async createProgramFull(input: CreateProgramInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_coaching_program_full", {
      ...this.programCreateArgs(input),
      p_batches: (input.batches ?? []).map((b) => ({
        courtId: b.courtId,
        coachId: b.coachId ?? null,
        name: b.name,
        daysOfWeek: b.daysOfWeek,
        startTime: b.startTime,
        endTime: b.endTime,
        capacity: b.capacity,
      })),
    });
    if (error || !data) throw mapError(error);
    return data.id;
  }

  async updateProgram(input: UpdateProgramInput): Promise<void> {
    const { error } = await this.supabase.rpc("update_coaching_program", {
      p_program_id: input.programId,
      p_name: input.name ?? null,
      p_level: input.level ?? null,
      p_age_group: input.ageGroup ?? null,
      p_category: input.category ?? null,
      p_description: input.description ?? null,
      p_facility_sport_id: input.facilitySportId ?? null,
      p_default_duration_minutes: input.defaultDurationMinutes ?? null,
      p_default_capacity: input.defaultCapacity ?? null,
      p_session_count: input.sessionCount ?? null,
      p_default_price_minor: input.defaultPriceMinor ?? null,
      p_is_membership_included: input.isMembershipIncluded ?? null,
      p_status: input.status ?? null,
      p_image_url: input.imageUrl ?? null,
      p_program_type: input.programType ?? null,
      p_min_capacity: input.minCapacity ?? null,
      p_program_structure: input.programStructure ?? null,
      p_session_format: input.sessionFormat ?? null,
      p_sessions_per_week: input.sessionsPerWeek ?? null,
      p_start_date: input.startDate ?? null,
      p_end_date: input.endDate ?? null,
      p_payment_mode: input.paymentMode ?? null,
      p_early_bird_discount_minor: input.earlyBirdDiscountMinor ?? null,
      p_discount_valid_till: input.discountValidTill ?? null,
      p_tax_percent: input.taxPercent ?? null,
      p_payment_notes: input.paymentNotes ?? null,
      p_allow_waitlist: input.allowWaitlist ?? null,
      p_allow_trial_session: input.allowTrialSession ?? null,
      p_auto_enroll_next_batch: input.autoEnrollNextBatch ?? null,
      p_send_notifications: input.sendNotifications ?? null,
      p_visible_in_booking: input.visibleInBooking ?? null,
      p_enrollment_deadline: input.enrollmentDeadline ?? null,
    });
    if (error) throw mapError(error);
  }

  async uploadProgramImage(file: File): Promise<string> {
    const { data: auth } = await this.supabase.auth.getUser();
    const uid = auth.user?.id;
    if (!uid) throw new ServiceError("COACHING_ACCESS_DENIED", "You must be signed in to upload a photo.");
    const path = `${uid}/${crypto.randomUUID()}-${file.name}`;
    const { error } = await this.supabase.storage.from("program-images").upload(path, file, { contentType: file.type });
    if (error) throw new ServiceError("COACHING_DATA_ERROR", "Could not upload this image. Please try again.");
    return this.supabase.storage.from("program-images").getPublicUrl(path).data.publicUrl;
  }

  // ── Program batches ──────────────────────────────────────────────────────
  async listProgramBatches(programId: string): Promise<ProgramBatch[]> {
    const { data, error } = await this.supabase.rpc("list_coaching_program_batches", { p_program_id: programId });
    if (error) throw mapError(error);
    return (data ?? []).map((r) => ({
      id: r.id,
      name: r.name,
      daysOfWeek: r.days_of_week,
      startTime: r.start_time,
      endTime: r.end_time,
      capacity: r.capacity,
      status: r.status as "ACTIVE" | "INACTIVE",
      courtId: r.court_id,
      courtName: r.court_name,
      coachId: r.coach_id,
      coachName: r.coach_name,
      enrolledCount: Number(r.enrolled_count),
    }));
  }

  async listActiveBatchesWithStudents(facilityId: string): Promise<ActiveBatchWithStudents[]> {
    const { data, error } = await this.supabase.rpc("list_active_coaching_batches_with_students", { p_facility_id: facilityId });
    if (error) throw mapError(error);
    return (data ?? []).map((r) => ({
      id: r.id,
      programId: r.program_id,
      programName: r.program_name,
      batchName: r.batch_name,
      daysOfWeek: r.days_of_week,
      startTime: r.start_time,
      endTime: r.end_time,
      courtName: r.court_name,
      coachName: r.coach_name,
      enrolledCount: Number(r.enrolled_count),
      capacity: r.capacity,
    }));
  }

  async createProgramBatch(input: {
    programId: string;
    courtId: string;
    coachId?: string | null;
    name: string;
    daysOfWeek: number[];
    startTime: string;
    endTime: string;
    capacity: number;
  }): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_coaching_program_batch", {
      p_program_id: input.programId,
      p_court_id: input.courtId,
      p_name: input.name,
      p_days_of_week: input.daysOfWeek,
      p_start_time: input.startTime,
      p_end_time: input.endTime,
      p_capacity: input.capacity,
      p_coach_id: input.coachId ?? null,
    });
    if (error || !data) throw mapError(error);
    return data.id;
  }

  async updateProgramBatch(input: {
    batchId: string;
    name?: string;
    courtId?: string;
    coachId?: string | null;
    daysOfWeek?: number[];
    startTime?: string;
    endTime?: string;
    capacity?: number;
    status?: "ACTIVE" | "INACTIVE";
  }): Promise<void> {
    const { error } = await this.supabase.rpc("update_coaching_program_batch", {
      p_batch_id: input.batchId,
      p_name: input.name ?? null,
      p_court_id: input.courtId ?? null,
      p_coach_id: input.coachId ?? null,
      p_days_of_week: input.daysOfWeek ?? null,
      p_start_time: input.startTime ?? null,
      p_end_time: input.endTime ?? null,
      p_capacity: input.capacity ?? null,
      p_status: input.status ?? null,
    });
    if (error) throw mapError(error);
  }

  async deleteProgramBatch(batchId: string): Promise<void> {
    const { error } = await this.supabase.rpc("delete_coaching_program_batch", { p_batch_id: batchId });
    if (error) throw mapError(error);
  }

  // ── Sessions ─────────────────────────────────────────────────────────────
  async listSessions(input: {
    facilityId: string;
    filters?: SessionFilters;
    limit?: number;
    offset?: number;
  }): Promise<SessionPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_coaching_sessions", {
      p_facility_id: input.facilityId,
      p_from: f.from ?? null,
      p_to: f.to ?? null,
      p_coach_id: f.coachId ?? null,
      p_program_id: f.programId ?? null,
      p_court_id: f.courtId ?? null,
      p_status: f.status ?? null,
      p_limit: input.limit ?? 200,
      p_offset: input.offset ?? 0,
    });
    if (error) throw mapError(error);
    return {
      sessions: (data ?? []).map((r) => ({
        id: r.id,
        programId: r.program_id,
        programName: r.program_name,
        coachId: r.coach_id,
        coachName: r.coach_name,
        courtId: r.court_id,
        courtName: r.court_name,
        startAt: r.start_at,
        endAt: r.end_at,
        capacity: r.capacity,
        enrolledCount: r.enrolled_count,
        status: r.status,
        sessionType: r.session_type,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getSession(sessionId: string): Promise<SessionDetail> {
    const { data, error } = await this.supabase.rpc("get_coaching_session", { p_session_id: sessionId });
    if (error || !data) throw mapError(error);
    return data as unknown as SessionDetail;
  }

  async createSession(input: CreateSessionInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_coaching_session", {
      p_facility_id: input.facilityId,
      p_program_id: input.programId ?? null,
      p_coach_id: input.coachId,
      p_court_id: input.courtId,
      p_start_at: input.startAt,
      p_end_at: input.endAt,
      p_capacity: input.capacity ?? null,
      p_notes: input.notes ?? null,
      p_objective: input.objective ?? null,
      p_status: input.status ?? "SCHEDULED",
      p_auto_enroll: input.autoEnroll ?? true,
      p_title: input.title ?? null,
      p_description: input.description ?? null,
      p_level: input.level ?? null,
      p_facility_sport_id: input.facilitySportId ?? null,
      p_session_type: input.sessionType ?? "GROUP",
      p_price_per_student_minor: input.pricePerStudentMinor ?? null,
      p_visible_for_booking: input.visibleForBooking ?? true,
      p_send_notification: input.sendNotification ?? true,
      p_allow_waitlist: input.allowWaitlist ?? false,
    });
    if (error || !data) throw mapError(error);
    return data.id;
  }

  async rescheduleSession(input: RescheduleSessionInput): Promise<void> {
    const { error } = await this.supabase.rpc("reschedule_coaching_session", {
      p_session_id: input.sessionId,
      p_coach_id: input.coachId ?? null,
      p_court_id: input.courtId ?? null,
      p_start_at: input.startAt ?? null,
      p_end_at: input.endAt ?? null,
      p_capacity: input.capacity ?? null,
      p_notes: input.notes ?? null,
      p_objective: input.objective ?? null,
    });
    if (error) throw mapError(error);
  }

  async setSessionStatus(sessionId: string, status: "CONFIRMED" | "IN_PROGRESS" | "COMPLETED"): Promise<void> {
    const { error } = await this.supabase.rpc("set_coaching_session_status", { p_session_id: sessionId, p_status: status });
    if (error) throw mapError(error);
  }

  async completeSession(sessionId: string, notes?: string | null, objectiveResult?: string | null): Promise<void> {
    const { error } = await this.supabase.rpc("complete_coaching_session", {
      p_session_id: sessionId,
      p_notes: notes ?? null,
      p_objective_result: objectiveResult ?? null,
    });
    if (error) throw mapError(error);
  }

  async cancelSession(sessionId: string, reason: string): Promise<void> {
    const { error } = await this.supabase.rpc("cancel_coaching_session", { p_session_id: sessionId, p_reason: reason });
    if (error) throw mapError(error);
  }

  async addSessionStudent(sessionId: string, enrollmentId: string): Promise<void> {
    const { error } = await this.supabase.rpc("add_session_student", {
      p_session_id: sessionId,
      p_enrollment_id: enrollmentId,
    });
    if (error) throw mapError(error);
  }

  async removeSessionStudent(sessionId: string, enrollmentId: string): Promise<void> {
    const { error } = await this.supabase.rpc("remove_session_student", {
      p_session_id: sessionId,
      p_enrollment_id: enrollmentId,
    });
    if (error) throw mapError(error);
  }

  // ── Enrollments ──────────────────────────────────────────────────────────
  async listEnrollments(input: {
    facilityId: string;
    filters?: EnrollmentFilters;
    limit?: number;
    offset?: number;
  }): Promise<EnrollmentPage> {
    const f = input.filters ?? {};
    const { data, error } = await this.supabase.rpc("list_coaching_enrollments", {
      p_facility_id: input.facilityId,
      p_search: f.search?.trim() || null,
      p_program_id: f.programId ?? null,
      p_status: f.status ?? null,
      p_limit: input.limit ?? 20,
      p_offset: input.offset ?? 0,
      p_coach_id: f.coachId ?? null,
      p_level: f.level ?? null,
    });
    if (error) throw mapError(error);
    return {
      enrollments: (data ?? []).map((r) => ({
        id: r.id,
        memberId: r.member_id,
        studentName: r.student_name,
        studentPhone: r.student_phone,
        studentAge: r.student_age,
        programId: r.program_id,
        programName: r.program_name,
        programLevel: r.program_level,
        coachId: r.coach_id,
        coachName: r.coach_name,
        coachAvatarUrl: r.coach_avatar_url,
        startDate: r.start_date,
        endDate: r.end_date,
        sessionsTotal: r.sessions_total,
        priceMinor: r.price_minor,
        paidMinor: r.paid_minor,
        status: r.status,
        paymentStatus: r.payment_status,
        batchId: r.batch_id,
        batchName: r.batch_name,
      })),
      totalCount: data?.[0]?.total_count ?? 0,
    };
  }

  async getEnrollment(enrollmentId: string): Promise<EnrollmentDetail> {
    const { data, error } = await this.supabase.rpc("get_coaching_enrollment", { p_enrollment_id: enrollmentId });
    if (error || !data) throw mapError(error);
    return data as unknown as EnrollmentDetail;
  }

  async createEnrollment(input: CreateEnrollmentInput): Promise<string> {
    const { data, error } = await this.supabase.rpc("create_coaching_enrollment", {
      p_facility_id: input.facilityId,
      p_member_id: input.memberId,
      p_program_id: input.programId,
      p_coach_id: input.coachId ?? null,
      p_start_date: input.startDate ?? null,
      p_end_date: input.endDate ?? null,
      p_sessions_total: input.sessionsTotal ?? null,
      p_price_minor: input.priceMinor ?? null,
      p_pricing_type: input.pricingType ?? null,
      p_notes: input.notes ?? null,
      p_batch_id: input.batchId ?? null,
    });
    if (error || !data) throw mapError(error);
    return data.id;
  }

  async updateEnrollment(input: UpdateEnrollmentInput): Promise<void> {
    const { error } = await this.supabase.rpc("update_coaching_enrollment", {
      p_enrollment_id: input.enrollmentId,
      p_coach_id: input.coachId ?? null,
      p_start_date: input.startDate ?? null,
      p_end_date: input.endDate ?? null,
      p_sessions_total: input.sessionsTotal ?? null,
      p_price_minor: input.priceMinor ?? null,
      p_notes: input.notes ?? null,
    });
    if (error) throw mapError(error);
  }

  async setEnrollmentStatus(
    enrollmentId: string,
    status: "ACTIVE" | "PAUSED" | "COMPLETED" | "CANCELLED",
    reason?: string | null,
  ): Promise<void> {
    const { error } = await this.supabase.rpc("set_coaching_enrollment_status", {
      p_enrollment_id: enrollmentId,
      p_status: status,
      p_reason: reason ?? null,
    });
    if (error) throw mapError(error);
  }

  // ── Progress ─────────────────────────────────────────────────────────────
  async addProgressNote(input: {
    enrollmentId: string;
    note: string;
    skillOrGoal?: string | null;
    progressStatus?: string;
    sessionId?: string | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("add_progress_note", {
      p_enrollment_id: input.enrollmentId,
      p_note: input.note,
      p_skill_or_goal: input.skillOrGoal ?? null,
      p_progress_status: input.progressStatus ?? "ON_TRACK",
      p_session_id: input.sessionId ?? null,
    });
    if (error) throw mapError(error);
  }

  async updateProgressNote(input: {
    noteId: string;
    note?: string | null;
    skillOrGoal?: string | null;
    progressStatus?: string | null;
  }): Promise<void> {
    const { error } = await this.supabase.rpc("update_progress_note", {
      p_note_id: input.noteId,
      p_note: input.note ?? null,
      p_skill_or_goal: input.skillOrGoal ?? null,
      p_progress_status: input.progressStatus ?? null,
    });
    if (error) throw mapError(error);
  }

  async deleteProgressNote(noteId: string): Promise<void> {
    const { error } = await this.supabase.rpc("delete_progress_note", { p_note_id: noteId });
    if (error) throw mapError(error);
  }
}
