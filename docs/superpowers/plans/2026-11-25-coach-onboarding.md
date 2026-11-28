# Coach Onboarding (5-step) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-screen Add Coach form (web + Flutter) with a 5-step, resumable-draft onboarding where the venue owner fills every step, including KYC/payout and legal confirmation.

**Architecture:** `add_coach` is reused to create the coach (as INACTIVE) at the end of Step 1. Steps 1-3 + legal live in a new `coach_profiles` table; KYC/payout lives in `coach_payout_details` (RLS: no direct access, RPC-only, masked on read, gated by a new permission). Four SECURITY DEFINER RPCs do all writes/reads. Web and Flutter each get a step-by-step wizard shell (one step visible at a time, same look as the Program wizards) driven by one state holder.

**Tech Stack:** Next.js/React + vitest, Flutter/riverpod + flutter_test, Supabase Postgres (migration 0211, applied by the owner, never by us).

**Spec:** `docs/superpowers/specs/2026-11-25-coach-onboarding-design.md`

## Global Constraints

- Migration is **written, not applied**; do not deploy anything, do not build an APK, **do not commit** (owner commits). Verification = `npx tsc --noEmit`, `npx eslint` on touched files, `npx vitest run src/features/coaching src/services/coaching`, `dart analyze` + `flutter test test/features` from `mobile/`.
- Currency INR only; money stored as integer paise (`*_minor`), entered as whole rupees.
- IFSC `^[A-Z]{4}0[A-Z0-9]{6}$`; PAN `^[A-Z]{5}[0-9]{4}[A-Z]$`; GSTIN `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`; UPI `^[A-Za-z0-9.\-_]{2,256}@[A-Za-z]{2,64}$`; phone 10 digits; account number 9-18 digits, entered twice.
- Certificates: JPG/PNG/WEBP/PDF, <= 5 MB, private bucket `coach-credentials`. Profile photo keeps the existing 2 MB JPG/PNG/WEBP rule.
- Payout methods: `BANK_TRANSFER`, `UPI`. (Stripe/Razorpay payouts are out of scope; do not add them.)
- Payouts permission key: `COACHING_MANAGE_COACH_PAYOUTS`. Everything else uses `COACHING_MANAGE_COACHES`.
- Step names (exact copy): "Identity & Basic Profile", "Expertise & Credentials", "Services, Pricing & Availability", "Payments, Payouts & KYC", "Review & Agreements".
- Draft label: "Draft – step N of 5". Draft coaches are `coaches.status = 'INACTIVE'` until completion, so session pickers (`status: ACTIVE`) never offer them.
- **Web: no side panel.** Adding a coach is always a full-page navigation to `/coaching/coaches/add` (each step on that page, `?coach=<id>&step=<n>` for resume). The right-hand slide-over (`AddCoachSheet`) must not be used or kept anywhere, including Overview, Coaches list and Quick Actions.
- Cover web AND the phone layout; test 390 px and 320 px. No whole-folder `dart format`; use `dart analyze`.
- Follow the repo's existing patterns (Field/Chip/PageHeader from `coaching/components/shared`, `ProgramWizardPage` stepper, Flutter `PrimaryButton`/`AppDropdown`).

## Review Focus

- Resuming a draft after reload/reopen shows saved values on the right step (not a blank form); test the hook's `load(coachId)`.
- Double-tapping "Save & continue" on Step 1 must not create two coaches or two staff accounts (busy lock + `add_coach` unique violation is treated as "resume", not an error).
- IFSC/PAN pasted lower-case or with spaces is normalised (upper-case, spaces stripped) before validating; mismatching account-number confirmation blocks Step 4.
- `get_coach_onboarding` never returns the raw account number or tax ID (masked `XXXX1234`), and a user without `COACHING_MANAGE_COACH_PAYOUTS` can still finish steps 1-3 and 5 (Step 4 shown locked, payout status stays PENDING).
- Weekly availability slot with end <= start, rate 0/negative/decimal, package with 0 sessions, and a certificate > 5 MB are all rejected client-side and in SQL.

---

### Task 1: Migration 0211 + SQL test

**Files:**
- Create: `supabase/migrations/0211_coach_onboarding.sql`
- Create: `supabase/tests/coach_onboarding.test.sql` (follow the style of existing files in `supabase/tests/`; it is never run locally)
- Modify: `src/features/access/catalog.generated.ts` and any other place the most recent permission-adding migration touched (follow how `COACHING_MANAGE_COACHES` is declared in `0082_coaching_foundation.sql` line ~31, `0155_page_access_matrix.sql`, `src/features/staff/types.ts:32`, `src/features/access/catalog.generated.ts:26`; the owner role must receive it the same way other permissions are granted to owners)

**Interfaces:**
- Produces (all `security definer`, `set search_path = public`, `grant execute ... to authenticated`):
  - `start_coach_onboarding(p_facility_id uuid, p_user_id uuid, p_data jsonb) returns uuid` — checks `has_permission(...,'COACHING_MANAGE_COACHES')`; calls `add_coach(p_facility_id, p_user_id, ..., p_status => 'INACTIVE', p_date_of_birth => (p_data->>'dateOfBirth')::date)`; inserts `coach_profiles` (`onboarding_status 'DRAFT'`, `current_step 2`, step-1 fields from `p_data`: `displayName, location, timezone, languages[], shortBio`; bio also copied to `coaches.bio`). If the user already has a coach row **with a DRAFT profile**, return that coach id instead of raising; if it has a COMPLETE profile or a legacy coach, raise the existing "already has a coaching profile" error.
  - `save_coach_onboarding_step(p_coach_id uuid, p_step int, p_data jsonb) returns void` — step 1: update identity fields; 2: `niche, subSpecialties[], experienceYears, targetAudience[], methodology, certificates[{name,issuer,year,path}], sportIds[], expertiseLevels[]` (sports/levels/experience/certifications text mirrored into `coaches` via `update_coach`; read `update_coach` first to confirm that NULL means "don't touch"); 3: `sessionFormats[] ('ONE_TO_ONE','GROUP','ASYNC'), sessionDurations int[], defaultSessionDurationMinutes, singleSessionRateMinor, packages[{name,sessions,priceMinor,validityDays}], maxActiveClients, availability[{dayOfWeek,startTime,endTime}]` (availability goes through the existing `set_coach_availability`); 4: payout fields below, requires `COACHING_MANAGE_COACH_PAYOUTS`, upserts `coach_payout_details`, sets `coach_profiles.payout_status='COMPLETE'`. Validates every pattern in Global Constraints, `end > start`, rate > 0, package sessions >= 1, max clients >= 1; raises plain user-safe messages (`errcode 22023`). Also advances `current_step = greatest(current_step, p_step + 1)` capped at 5 and records `steps_done`.
  - `get_coach_onboarding(p_coach_id uuid) returns jsonb` — identity/expertise/services/availability, `currentStep`, `onboardingStatus`, `payoutStatus`, `canManagePayouts boolean`, and `payout` with `accountNumberMasked`, `taxIdMasked` (last 4 only) plus the non-secret fields; `payout` is null when caller lacks the payouts permission.
  - `complete_coach_onboarding(p_coach_id uuid, p_legal jsonb) returns void` — requires steps 1-3 done and `p_legal` has `terms, ethics, privacy, commission` all `true`; sets `coach_profiles.onboarding_status='COMPLETE'`, `legal_accepted_at=now()`, `legal_accepted_by=auth.uid()`, `coaches.status='ACTIVE'`; calls `log_coaching_event`.
  - `list_coach_onboarding_drafts(p_facility_id uuid) returns table (coach_id uuid, full_name text, current_step int)`.
- Tables: `coach_profiles(coach_id uuid pk references coaches on delete cascade, facility_id uuid not null, onboarding_status text check in ('DRAFT','COMPLETE') default 'DRAFT', current_step int default 1, steps_done int[] default '{}', payout_status text check in ('PENDING','COMPLETE') default 'PENDING', display_name, location, timezone default 'Asia/Kolkata', languages text[] default '{}', niche, sub_specialties text[], target_audience text[], methodology, certificates jsonb default '[]', session_formats text[], session_durations int[], single_session_rate_minor int, packages jsonb default '[]', max_active_clients int, legal_accepted_at timestamptz, legal_accepted_by uuid, created_at, updated_at)`; `coach_payout_details(coach_id uuid pk references coaches on delete cascade, facility_id uuid not null, entity_type text check in ('INDIVIDUAL','BUSINESS'), legal_name, business_address, tax_id, payout_method text check in ('BANK_TRANSFER','UPI'), account_holder_name, account_number, ifsc, upi_id, currency text default 'INR', payout_frequency text check in ('WEEKLY','BIWEEKLY','MONTHLY'), cancellation_policy text, updated_at)`. Both `enable row level security` with **no** policies (RPC-only).
- Storage: private bucket `coach-credentials`; policies allow insert/select/delete when the first path segment is a facility id and `has_permission(that facility, 'COACHING_MANAGE_COACHES')`.

- [ ] **Step 1: Write `supabase/tests/coach_onboarding.test.sql`** asserting: draft created by `start_coach_onboarding` has `coaches.status='INACTIVE'`; second `start` returns same id; `save_coach_onboarding_step(…,4,…)` with IFSC `abc` raises; `get_coach_onboarding` returns `accountNumberMasked` = `XXXXXX1234` and no raw number; `complete_coach_onboarding` raises without `terms:true`, succeeds with all four and flips status to `ACTIVE`; a user lacking the payouts permission gets `payout` null.
- [ ] **Step 2: Write the migration** per Interfaces above (same header-comment style as `0099`).
- [ ] **Step 3: Add the permission** everywhere the catalog requires and run `npx vitest run src/features/access src/features/staff` — Expected: PASS (catalog tests pass with the new key).
- [ ] **Step 4: Re-read the migration once** against `update_coach`/`set_coach_availability` signatures (`0095`, `0099`, later overrides: `grep -l "function update_coach" supabase/migrations/*`) and fix mismatches. No DB is available; state this in the final report.

### Task 2: Web validation module

**Files:**
- Create: `src/features/coaching/coach-onboarding-validation.ts`
- Test: `src/features/coaching/coach-onboarding-validation.test.ts`

**Interfaces:**
- Consumes: `isValidEmail`, `isValidPhoneDigits`, `isValidDateOfBirth` from `add-coach-validation.ts`.
- Produces: `normalizeIfsc(s): string` (trim, strip spaces, upper-case); `normalizePan(s)`; `normalizeGstin(s)`; `isValidIfsc(s): boolean`; `isValidPan`; `isValidGstin`; `isValidUpi`; `isValidAccountNumber(s): boolean` (9-18 digits); `isValidRupees(s: string): boolean` (positive whole number, no decimals); `rupeesToMinor(s: string): number`; `isValidSlot(start: string, end: string): boolean`; `validateCertificateFile(f: {type: string; size: number}): string | null` (returns error copy or null).

- [ ] **Step 1: Write failing tests** with these exact assertions: `isValidIfsc("sbin0001234")` is false before `normalizeIfsc` and `isValidIfsc(normalizeIfsc(" sbin 0001234 "))` is true; `isValidIfsc("SBIN1001234")` false (5th char must be 0); `isValidPan("ABCDE1234F")` true, `"ABCDE12345"` false; `isValidGstin("22ABCDE1234F1Z5")` true; `isValidUpi("name@okhdfc")` true, `"name@"` false; `isValidAccountNumber("12345678")` false, `"123456789"` true, `"1234567890123456789"` false; `isValidRupees("500")` true, `"0"`, `"-5"`, `"10.5"`, `""` false; `rupeesToMinor("500") === 50000`; `isValidSlot("09:00","09:00")` false, `("09:00","10:00")` true; `validateCertificateFile({type:"application/pdf",size:6*1024*1024})` returns the "larger than 5MB" message, `{type:"image/gif",size:1}` returns the file-type message, a 1 MB PDF returns null.
- [ ] **Step 2:** `npx vitest run src/features/coaching/coach-onboarding-validation.test.ts` — Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the module per Interfaces.
- [ ] **Step 4:** same command — Expected: PASS.

### Task 3: Web types + service layer

**Files:**
- Modify: `src/features/coaching/types.ts` (append), `src/services/coaching/index.ts` (service interface + any mock), `src/services/coaching/supabase-coaching.service.ts`, `src/types/database.types.ts` (hand-add the 5 RPCs under `Functions`, since it is generated and the migration is not applied)
- Test: `src/services/coaching/supabase-coaching.service.test.ts` (extend; mirror how `addCoach` is tested)

**Interfaces:**
- Produces in `types.ts`: `COACH_ONBOARDING_STEPS` (the five exact names, `as const`), `CoachOnboardingData` (identity: `displayName, location, timezone, languages: string[], shortBio`; expertise: `niche, subSpecialties, experienceYears: number|null, targetAudience, methodology, certificates: CoachCertificate[], sportIds, expertiseLevels`; services: `sessionFormats, sessionDurations: number[], defaultSessionDurationMinutes, singleSessionRateMinor: number|null, packages: CoachPackage[], maxActiveClients: number|null, availability: CoachAvailabilityWindow[]`), `CoachCertificate {name; issuer; year: number|null; path: string}`, `CoachPackage {name; sessions; priceMinor; validityDays}`, `CoachPayoutInput` (fields of `coach_payout_details`, raw), `CoachPayoutMasked` (non-secret fields + `accountNumberMasked`, `taxIdMasked`), `CoachOnboarding {coachId; currentStep: number; onboardingStatus: "DRAFT"|"COMPLETE"; payoutStatus: "PENDING"|"COMPLETE"; canManagePayouts: boolean; data: CoachOnboardingData; payout: CoachPayoutMasked|null}`, `CoachOnboardingDraft {coachId; fullName; currentStep}`.
- Produces on `CoachingService`: `startCoachOnboarding(facilityId: string, userId: string, identity: Pick<CoachOnboardingData,"displayName"|"location"|"timezone"|"languages"|"shortBio"> & {dateOfBirth: string|null}): Promise<string>`; `saveCoachOnboardingStep(coachId: string, step: 1|2|3|4, data: Record<string, unknown>): Promise<void>`; `getCoachOnboarding(coachId: string): Promise<CoachOnboarding>`; `completeCoachOnboarding(coachId: string, legal: {terms: boolean; ethics: boolean; privacy: boolean; commission: boolean}): Promise<void>`; `listCoachOnboardingDrafts(facilityId: string): Promise<CoachOnboardingDraft[]>`; `uploadCoachCertificate(facilityId: string, coachId: string, file: File): Promise<CoachCertificate["path"]>` (storage `coach-credentials`, path `${facilityId}/${coachId}/${uuid}-${file.name}`, runs `validateCertificateFile` first).

- [ ] **Step 1: Write failing service tests** (mock supabase `rpc` as the existing tests do): `startCoachOnboarding` calls `rpc("start_coach_onboarding", {p_facility_id, p_user_id, p_data})` and returns the id; `getCoachOnboarding` maps `accountNumberMasked`; `saveCoachOnboardingStep` surfaces an RPC error message through `mapError`.
- [ ] **Step 2:** `npx vitest run src/services/coaching` — Expected: FAIL.
- [ ] **Step 3: Implement** types, interface entries, and service methods; map snake/camel as the other methods do.
- [ ] **Step 4:** same command + `npx tsc --noEmit` — Expected: PASS / no errors.

### Task 4: Web onboarding state hook

**Files:**
- Create: `src/features/coaching/components/use-coach-onboarding.ts`
- Test: `src/features/coaching/components/use-coach-onboarding.test.ts`

**Interfaces:**
- Consumes: Task 2 validators, Task 3 service methods, `getStaffService().createStaff/uploadAvatar/listRoles` and the existing candidate/role loading logic from `use-add-coach-form.ts` (copy that logic; it is deleted in Task 8).
- Produces: `useCoachOnboarding(facilityId: string | null, resumeCoachId: string | null)` returning `{ step: 1|2|3|4|5; setStep; coachId: string|null; draft: <form state for all five steps>; patch(partial); stepValid(step): boolean; canManagePayouts; payoutStatus; busy; error; credentials: {loginEmail; password}|null; saveAndContinue(): Promise<void>; saveDraftAndExit(): Promise<void>; complete(): Promise<void>; loading }`, plus pure exported `isStepValid(step, draft, ctx): boolean`.
- Behaviour: `saveAndContinue` on step 1 creates the staff account if `mode==="new"` (storing credentials in state for the success screen) then calls `startCoachOnboarding`; guarded by `busy` so it cannot run twice; steps 2-4 call `saveCoachOnboardingStep`; step 4 is skippable (`skipPayout()` moves to 5 without saving) and locked when `!canManagePayouts`. With `resumeCoachId`, loads `getCoachOnboarding` into `draft` and opens `currentStep` (clamped 1-5).

- [ ] **Step 1: Write failing tests on `isStepValid` and the reducer-style helpers**: step 1 invalid without name/valid email/10-digit phone, valid for a picked existing staff member; step 2 needs ≥1 sport, ≥1 expertise level, niche, `experienceYears >= 0`; step 3 needs ≥1 format, ≥1 duration, valid rupee rate, every package `sessions >= 1`, every availability slot `isValidSlot`; step 4 needs normalized-valid IFSC/PAN (or GSTIN for BUSINESS), matching account-number confirmation, account holder name; step 5 needs all four agreements true. Plus: `load` of a saved onboarding at `currentStep: 3` yields `step === 3` with saved values.
- [ ] **Step 2:** `npx vitest run src/features/coaching/components/use-coach-onboarding.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** the hook per Interfaces.
- [ ] **Step 4:** same command — Expected: PASS.

### Task 5: Web wizard UI (five step components + page + entry points)

**Files:**
- Create: `src/features/coaching/components/coach-onboarding-page.tsx` (stepper shell: breadcrumb Coaching › Coaches › Add Coach, `PageHeader`, the pill stepper copied from `program-wizard-page.tsx:227-248`, one `<Card>` per step, footer with Back / Save draft / Save & continue), `coach-onboarding-step-identity.tsx`, `-expertise.tsx`, `-services.tsx`, `-payout.tsx`, `-review.tsx`
- Modify: `src/app/(dashboard)/coaching/coaches/add/page.tsx` (render the new page; accepts `?coach=<id>&step=<n>`), `coaches-list-panel.tsx` + `overview-page.tsx` + `coaches-page.tsx` (every "Add Coach" button navigates to `/coaching/coaches/add` instead of opening `AddCoachSheet`; list panel shows a "Drafts" strip from `listCoachOnboardingDrafts` with "Draft – step N of 5" and a Resume link to `/coaching/coaches/add?coach=<id>`), `coach-details-page.tsx` (a draft coach shows the same Draft badge + Resume button; completed coach shows payout status "KYC pending" / "KYC complete" and masked payout on screen only for users with the payouts permission)
- Reuse: `coach-added-content.tsx` as the success view after step 5 (shows temp credentials when present, otherwise the note "Existing staff member — sign-in unchanged"; when the owner resumed a draft in a new session, credentials are gone: show "Lost the password? Staff › Reset Password")

**Interfaces:**
- Consumes: Task 4 hook (`useCoachOnboarding`). Each step component takes `{ form: ReturnType<typeof useCoachOnboarding> }`.
- Step content (exact fields): **1** staff mode toggle (existing staff / new person), photo, legal full name, display name, email, phone, location (city), timezone select (default Asia/Kolkata), languages multi-chip, short bio (≤ 500), date of birth; **2** niche select/text, sub-specialties chips, sports (facility sports chips), expertise levels, years of experience, target audience chips (Kids, Teens, Adults, Seniors, Beginners, Competitive), methodology textarea, certifications list (add row: name, issuer, year, file upload with the Task 2 file rules, remove); **3** session formats (1:1, Group, Async) checkboxes, durations chips (30/45/60/90/120) + default, single-session rate (₹), packages list (name, sessions, price ₹, validity days), max active clients, weekly availability editor (reuse `coach-availability-editor.tsx`); **4** entity type, legal name, business address (BUSINESS only), tax ID (PAN; GSTIN also for BUSINESS), payout method (Bank Transfer / UPI), account holder, account number + confirm (hidden digits), IFSC (auto-upper), UPI id, currency fixed "INR", payout frequency, cancellation/refund policy textarea; masked values displayed when previously saved with "Change" to re-enter; a "Finish later" button; locked panel when `!canManagePayouts`; **5** read-only review cards (reuse the `ReviewSection`/`ReviewRow` style) each with Edit → that step, four agreement checkboxes (Terms of service, Coach code of ethics, Privacy & confidentiality, Platform commission acknowledgement — copy: "I confirm the coach has agreed to …"), final "Submit & Activate Coach".

- [ ] **Step 1: Update/replace tests first**: rewrite `add-coach-page.test.tsx` for the new page (renders step 1 title "Identity & Basic Profile", Next disabled until valid, step pills for the five names, jumping to step 2 with `?coach=` loads saved data via a mocked service); fix `coaches-list-panel.test.tsx` and `overview-page.test.tsx` for navigation instead of the sheet, and add a test that a draft row shows "Draft – step 3 of 5". Run `npx vitest run src/features/coaching` — Expected: FAIL.
- [ ] **Step 2: Build the shell and five step components** per Interfaces; one step visible at a time; footer sticky on phone widths; no horizontal overflow at 320 px.
- [ ] **Step 3: Wire entry points + draft strip + detail-page changes** per Files.
- [ ] **Step 4:** `npx vitest run src/features/coaching src/services/coaching`, `npx tsc --noEmit`, `npx eslint` on touched files — Expected: all PASS. (Do not run `next build` while `next dev` may be running.)

### Task 6: Flutter models, validators, repository

**Files:**
- Modify: `mobile/lib/data/models/coaching.dart` (add models mirroring Task 3 types), `mobile/lib/features/coaching/add_coach_validation.dart` (add the Task 2 validators with identical names in lowerCamel Dart: `normalizeIfsc`, `isValidIfsc`, `normalizePan`, `isValidPan`, `isValidGstin`, `isValidUpi`, `isValidAccountNumber`, `isValidRupees`, `rupeesToMinor`, `isValidSlot`, `validateCertificate(String name, int bytes)`), `mobile/lib/data/repositories/coaching_repository.dart`
- Test: `mobile/test/features/coach_onboarding_validation_test.dart` (create), extend the existing coaching repository test if one exists

**Interfaces:**
- Produces on `CoachingRepository`: `startCoachOnboarding({facilityId, userId, displayName, location, timezone, languages, shortBio, dateOfBirth}) → Future<String>`, `saveCoachOnboardingStep(String coachId, int step, Map<String, dynamic> data) → Future<void>`, `getCoachOnboarding(String coachId) → Future<CoachOnboarding>`, `completeCoachOnboarding(String coachId, {required bool terms, ethics, privacy, commission}) → Future<void>`, `listCoachOnboardingDrafts(String facilityId) → Future<List<CoachOnboardingDraft>>`, `uploadCoachCertificate({facilityId, coachId, bytes, fileName, contentType}) → Future<String>` (same RPC names/param keys as the web service; follow the `try { … } catch (e) { throw _map(e); }` style).

- [ ] **Step 1: Write failing tests** with the same assertions as Task 2 Step 1 (Dart syntax).
- [ ] **Step 2:** `flutter test test/features/coach_onboarding_validation_test.dart` (from `mobile/`) — Expected: FAIL.
- [ ] **Step 3: Implement** validators, models (`fromJson`), repository methods.
- [ ] **Step 4:** same test + `dart analyze lib/data lib/features/coaching` — Expected: PASS / No issues.

### Task 7: Flutter onboarding screen(s)

**Files:**
- Create: `mobile/lib/features/coaching/coach_onboarding_screen.dart` (shell: AppBar "Add Coach", step indicator "Step N of 5 · <name>", one step body at a time in a `SmoothSwitcher`, bottom bar Back / Save draft / Save & continue) and `mobile/lib/features/coaching/coach_onboarding_steps.dart` (the five step widgets + state holder `CoachOnboardingState` with a pure `isStepValid(step)`)
- Modify: `mobile/lib/core/routing/app_router.dart` (the existing Add Coach route builds `CoachOnboardingScreen(resumeCoachId: state.extra as String?)`), `coaches_screen.dart` / `coaching_hub_screen.dart` / `hub_widgets.dart` entry points keep pushing the same route; `coaches_screen.dart` gets a Drafts section with "Draft – step N of 5" → push route with `extra: coachId`; `coach_detail_screen.dart` shows Draft badge/Resume and KYC status as in Task 5
- Test: `mobile/test/features/coach_onboarding_state_test.dart`

**Interfaces:**
- Consumes: Task 6 repository + validators; existing `pickPhoto`, `AppDropdown`, `PrimaryButton`, `StaffCredentialsCard`, `staffRepositoryProvider.createStaff/uploadAvatar/listRoles`, the success-actions UI from `coach_form_screen.dart` (move `_success` into the new file unchanged in look).
- Field content, validation, skippable/locked Step 4, resume-at-`currentStep`, busy-lock against double submit, and copy: identical to Task 5. Use sheet-style dropdowns and chips like the rest of the app; numeric fields use `FilteringTextInputFormatter`; IFSC/PAN fields uppercase as typed; account number obscured with a confirm field; certificate picker accepts JPG/PNG/WEBP/PDF via the existing file/photo picker utility (use `file_picker` only if already a dependency, else photo picker for images + a note that PDFs are web-only — decide by reading `pubspec.yaml` and say which in the report).

- [ ] **Step 1: Write failing tests** for `CoachOnboardingState.isStepValid` (same cases as Task 4) and that loading a saved onboarding at `currentStep: 3` selects step 3.
- [ ] **Step 2:** `flutter test test/features/coach_onboarding_state_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** state holder, five step widgets, shell, router, entry points, drafts section per Files.
- [ ] **Step 4:** `dart analyze lib` and `flutter test test/features test/data` (if "failed to delete build\unit_test_assets", delete that folder and rerun) — Expected: No issues / all PASS. Check layouts at 390 px and 320 px widths with a widget test pumping `Size(320, 640)` for step 4 (no overflow exceptions).

### Task 8: Remove the old form and full verification

**Files:**
- Delete: `src/features/coaching/components/add-coach-sheet.tsx`, `add-coach-form-fields.tsx`, `use-add-coach-form.ts`; `mobile/lib/features/coaching/coach_form_screen.dart` (after confirming nothing imports them: `grep -r "add-coach-sheet\|add-coach-form-fields\|use-add-coach-form\|coach_form_screen"`)
- Keep: `add-coach-validation.ts`, `coach-added-content.tsx`, `add_coach_validation.dart`

- [ ] **Step 1:** Delete the files, remove stale imports and tests that only covered them.
- [ ] **Step 2:** Run: `npx tsc --noEmit`; `npx eslint src/features/coaching src/services/coaching`; `npx vitest run`; from `mobile/`: `dart analyze` and `flutter test`. Expected: all clean/green (report any pre-existing unrelated failures separately, with output).
- [ ] **Step 3: Final report** to the owner: what was built, that migration 0211 + the new permission are **unapplied and the SQL never executed**, the `coach-credentials` bucket is created by the migration, no deploy/APK/commit was done, and the known limits (Stripe/Razorpay payouts and non-INR not built; staff temp password only visible in the session that created the account; PDF certificate upload status on Flutter).
