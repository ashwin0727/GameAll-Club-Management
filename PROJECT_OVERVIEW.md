# GameAll Club Management — Project Overview

*Last updated: 2026-09-07*

## What this is

GameAll Club Management is the operating system for a multi-sport facility —
the software an owner or staff member uses to run court bookings, members,
guests, and money in one place instead of a paper register, a WhatsApp
payment thread, and a spreadsheet.

There are **two clients on one backend**:

- **Web dashboard** (`/src`) — Next.js. Where a facility gets onboarded and
  where the deepest admin/finance screens live.
- **Mobile app** (`/mobile`) — Flutter. The same operations (bookings,
  guests, memberships, finance) for staff who are on the courts, not at a
  desk. At capability parity with the web app as of the 2026-09-03 audit
  (`docs/superpowers/specs/2026-09-03-web-flutter-parity-audit.md`).

Both talk to the **same Supabase (Postgres) project** — a booking made from
the phone shows up on the web dashboard without anyone refreshing. The app
only ever ships the Supabase **anon key**; every table is protected by
Row-Level Security, so RLS — not client code — decides what a signed-in user
can read or write.

## The problem it replaces

A facility running on paper has the same failure mode every time: the
booking book and the cashbook don't agree, a membership renewal gets missed
until a member is turned away at the gate, and nobody can say — without
adding it up by hand — how much of this month's revenue came from bookings
versus memberships. GameAll makes a booking, a membership renewal, a
Razorpay payment, and a refund all the same kind of record, reconciled
automatically and visible on one finance dashboard.

## Feature modules

Built in the order a facility actually adopts them — set up once, then run
day to day:

| Module | What it does | Web route | Mobile screen |
|---|---|---|---|
| **Onboarding** | Facility details, which sports, how many courts, operating hours, per-court pricing. Nothing else works until this is done. | `/onboarding/*` | `features/onboarding` |
| **Bookings** | Court schedule (day-strip + per-court timeline), a no-login public link for walk-in guests to book themselves. | `/bookings`, `/book/[facilityId]` | `features/bookings` |
| **Guests** | Walk-in players tracked without an account; per-booking action set (edit, reschedule, record payment, cancel, invoice). | `/guests`, `/guest-bookings/[bookingId]` | `features/guests` |
| **Memberships** | Recurring plans, public join link, revenue trend, access-day rules. | `/memberships/[membershipId]`, `/join/[facilityId]` | `features/memberships` |
| **Membership Sessions** | The recurring-class engine — standing time-slot batches with a roster/capacity, released guest seats, activity log. | `/membership-sessions/[batchId]` | `features/membership_sessions` |
| **Payments** | Every payment (booking, subscription, session seat) goes through the same Razorpay order → verify → reconcile → settle pipeline. | edge functions | `features/payments` |
| **Refunds** | Cancellation-triggered refunds, settlement-exception handling. | `/refunds` | `features/refunds` |
| **Finance** | Transactions, expenses, pending payments — the owner's "how did we do this month?" view. | `/finance/*` | `features/finance` |

## Tech stack

**Web** (`/src`) — Next.js (App Router), TypeScript, Tailwind, Radix UI,
Vitest. Scripts (`package.json`):

```
npm run dev        # next dev --turbopack
npm run build       # next build
npm run lint        # next lint
npm run typecheck   # tsc --noEmit
npm run test         # vitest run
```

**Mobile** (`/mobile`) — Flutter (Dart SDK ^3.13.1), Riverpod for state,
go_router for navigation, `supabase_flutter` for backend access, Razorpay
Flutter SDK for payments.

**Backend** (`/supabase`) — Postgres + RLS, 55 migrations
(`supabase/migrations/0001…0055`), business logic lives in SQL functions
(RPCs) called from both clients — e.g. `create_booking`,
`create_membership_subscription`, `cancel-booking` (edge function),
`settle-payment` (edge function).

## Running it locally

### Web

```
npm install
npm run dev
```
Needs `.env.local` with the Supabase project URL/anon key (same project the
mobile app points at).

### Mobile

```
cd mobile
flutter pub get
cp env.example.json env.json   # then fill in SUPABASE_URL / SUPABASE_ANON_KEY
flutter run --dart-define-from-file=env.json
```

**Never put the service-role key in `env.json`** — it's git-ignored on
purpose, and only the anon key belongs in a client app; the service-role key
bypasses every RLS policy and must stay server-side only.

Useful mobile commands:

```
flutter analyze                                   # static analysis — keep clean
flutter test                                       # unit/widget tests
flutter build apk --debug --dart-define-from-file=env.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

An `integration_test/` suite also exists
(`mobile/integration_test/seed_test_data_test.dart`) for driving the real
app against a real device — prefer it over ad-hoc `adb`-driven UI testing
when real end-to-end verification is needed.

### Database

Migrations are plain numbered SQL files in `supabase/migrations/` — apply
them in order against a Supabase project via the Supabase CLI or dashboard
SQL editor. `supabase/finance_sample_data.sql` seeds example finance rows
for local testing.

## Architecture notes worth knowing

- **Time handling**: every booking time is stored as Postgres `timestamptz`.
  The mobile app converts to UTC on write (`.toUtc()`) and back to local on
  read (`.toLocal()`, applied once in `Booking.fromJson`) — never send or
  read a naive local `DateTime` against a `timestamptz` column, or Postgres
  will silently treat your local wall-clock time as UTC and every time will
  be off by your device's UTC offset.
- **Bookings timeline**: `mobile/lib/features/bookings/bookings_screen.dart`
  renders each court's day as a real horizontal timeline (blocks sized to
  their *actual* duration, not snapped to a slot grid) rather than a
  fixed-size chip grid — drawn from the real `Booking` rows, not the
  availability grid, so a booking's rendered block is always accurate.
- **Pricing resolution**: `resolvePrice()` (web:
  `src/features/pricing/validation.ts`, mobile:
  `_resolvePriceMinor` in `guest_booking_screen.dart`) picks the most
  specific matching rule — court-specific beats sport-level, a windowed
  rule beats a full-day one, a day-scoped rule (WEEKDAYS/WEEKENDS) beats
  ALL_DAYS.
- **Design system**: `mobile/lib/core/theme/app_colors.dart` — brand green
  `#00F08A` in both themes, dark is the primary visual direction (see the
  file's own doc comment for the light/dark token split).

## What's still open

From the 2026-09-03 web↔Flutter parity audit — the last known gaps, ranked
by severity:

1. **Guest booking invoice export** (`G5`, low) — no PDF/print story on
   mobile yet for a guest booking's invoice, unlike the web app.
2. Multi-court **online payment** in the mobile Guest Booking wizard is
   disabled when more than one court is selected — Razorpay checkout only
   supports a single-booking order today; multi-court bookings must use
   "pay at venue."

Everything else audited in that doc (auth, onboarding, dashboard, bookings,
guests, memberships, membership sessions, refunds, the full finance module)
is at parity between web and mobile.

## Where to look next

- `docs/superpowers/specs/` — design docs for recent features (facility
  onboarding, membership time slots, the Flutter finance rework, the
  parity audit).
- `docs/superpowers/plans/` — implementation plans for the same.
- `mobile/lib/core/routing/app_routes.dart` — canonical list of every
  mobile route.
- `src/app/` — canonical list of every web route (Next.js App Router,
  folder = route).
