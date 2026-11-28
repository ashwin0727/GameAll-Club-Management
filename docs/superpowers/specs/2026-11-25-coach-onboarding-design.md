# Coach Onboarding (5-step) — short design

Status: approved by the venue owner in conversation (2026-11-25).

## Intent
Replace the one-screen Add Coach form (web + Flutter) with a 5-step onboarding, one page/screen per step, in the existing wizard UI. The venue owner fills every step, including KYC and payout, on the coach's behalf. Drafts are saved so any step can be finished later.

## Goals
- Steps: 1 Identity, 2 Expertise & credentials, 3 Services/pricing/availability, 4 Payments/payouts/KYC, 5 Review & legal.
- Step 1 keeps "existing staff member / new person" (a coach is always a staff member; new person creates the staff login and shows temp credentials at the end).
- Draft coach appears in the Coaches list as "Draft – step N of 5"; reopening resumes at the first incomplete step.
- Validation: phone 10 digits, email, IFSC `^[A-Z]{4}0[A-Z0-9]{6}$` (account number entered twice), PAN `^[A-Z]{5}[0-9]{4}[A-Z]$`, GSTIN, UPI id, whole-rupee rates, slot end after start.

## Non-goals
- Automatic payouts through Razorpay/Stripe (details are recorded only).
- Non-INR currencies. No coach login/self-service.
- Merging coach rates with Programs fees.

## Approaches
1. Extend the coaches row — rejected: sensitive data readable by every coaching screen.
2. **Chosen:** separate `coach_profiles` (steps 1-3, legal) + `coach_payout_details` (step 4) behind a new permission, masked after save; draft = status on the profile.
3. One JSON blob — rejected: no validation or protection.

## Constraints
- Migration is written, not applied (the owner applies). No APK build or commit unless asked. Verify with tsc/lint/vitest and dart analyze.
- Reuse existing staff/coaching services, `COACHING_MANAGE_COACHES` permission, wizard components.

## Left to the builder
Exact column names, RPC shapes, step-bar component reuse, storage bucket for certificates (private, image/PDF <= 5 MB).
