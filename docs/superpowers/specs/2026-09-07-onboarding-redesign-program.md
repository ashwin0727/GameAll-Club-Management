# Onboarding Redesign — Program Overview

Full visual + structural redesign of the mobile onboarding wizard to match
the 2026 dark mockups. **Mobile only** for now; the Next.js web app keeps
running on the shared Postgres enum.

## Locked decisions

- **Restructure the steps** to: `FACILITY_DETAILS -> SPORTS_COURTS -> PRICING
  -> OPERATING_HOURS -> PAYMENTS -> COMPLETED`. (Was: facility, sports,
  courts, operating-hours, pricing, complete.)
- **Fully wire** new data, except:
  - **Payments (screen 5):** full screen UI + "Do this later". "Connect
    Razorpay" is a placeholder (opens Razorpay dashboard URL via
    url_launcher). No Route/linked-account backend. Step is skippable and
    still marks onboarding complete. Real integration = separate future
    project.
  - **Map pin (screen 1):** no Google Maps SDK. The "Drop a map pin" card is
    a text field where the owner pastes a Google Maps location URL; stored
    as `facilities.location_url` (new column). `latitude`/`longitude`
    columns already exist and stay unused for now.
- **Logo upload (screen 1):** wired. `facilities.logo_url` column already
  exists. Needs a Supabase Storage bucket + RLS + `image_picker`.
- **Holidays/closures (screen 4):** wired. New `facility_closures` table +
  migration + RLS + repo.
- **Booking link (screen 6):** `facilities.slug` already exists — surface it
  as `https://gameall.in/<slug>` with copy-to-clipboard.
- **Pace:** one screen at a time, user approves each screen's design before
  implementation, then build + install before moving on.

## Sub-projects (in order)

| # | Name | Deliverable |
|---|---|---|
| 0 | Foundation | Step-enum restructure (DB `ALTER TYPE ADD VALUE` + backfill; mobile `OnboardingStep`, resolver, router, model), shared onboarding UI kit (segmented progress header + Skip, `− n +` stepper, big time box, toggle row, checklist row, info banner) |
| 1 | Screen 1 — Facility details | "Where do you play?" redesign + logo upload + paste-location-link card |
| 2 | Screen 2 — Sports & courts | "What can people play?" merged screen: sport chips + per-sport stepper generating court chips |
| 3 | Screen 3 — Pricing | "Set your pricing" redesigned to mockup card style |
| 4 | Screen 4 — Operating hours | "When are you open?" redesign + holidays/closures |
| 5 | Screen 5 — Connect payments | "Get paid online" — Razorpay placeholder + checklist + "Do this later" |
| 6 | Screen 6 — Setup complete | "You're open for business" + booking link + next-step rows |

Each sub-project gets its own design section (approved in chat) and is
implemented, analyzed, tested, built and installed before the next begins.

## Enum migration note

`onboarding_step` is a Postgres enum. Postgres cannot drop/reorder enum
values, only add. Migration adds `SPORTS_COURTS` and `PAYMENTS`; old values
`SPORTS`/`COURTS`/`PRICING`/`OPERATING_HOURS` remain valid. Backfill:
facilities currently on `SPORTS` or `COURTS` -> `SPORTS_COURTS`. Mobile step
order is driven by the Dart enum + resolver, not SQL ordering, so no reorder
needed. Web resolver may not recognise `SPORTS_COURTS`/`PAYMENTS` — accepted
risk (near-zero users mid-onboarding; web redesign is a later project).
