# Onboarding Welcome Screen — Design

## Purpose

After a new account signs in / verifies email, land on a branded welcome
screen that explains what GameAll does before the multi-step facility setup.
Shown on every relaunch until onboarding is `completed`.

## Screen

New file: `mobile/lib/features/onboarding/onboarding_welcome_screen.dart`
`OnboardingWelcomeScreen` — `ConsumerWidget`.

Shell: `AuthGradientBackground` > `SafeArea` > `ResponsivePage(scrollable: true)`
> `Column(crossAxisAlignment: start)`.

| Element | Spec |
|---|---|
| Icon badge | 64x64, `tokens.primary` fill, radius `AppRadius.lg`, `Icons.schedule`, `tokens.onPrimary`, size 34 |
| Headline | `"One place to\nrun the club"` — fontSize 34, `w800`, height 1.1, `tokens.textPrimary` |
| Subtitle | `"Courts, guests, memberships and money in one app. No booking register, no payment thread, no spreadsheet that never agrees with the cashbook."` — fontSize 15, `tokens.textSecondary`, height 1.45 |
| Feature cards | 3x `_FeatureCard`, `tokens.surface1` fill, `tokens.borderColor` border, radius `AppRadius.lg`, padding 16, 12px gap between |
| CTA | `AuthGradientButton(label: 'Set up my facility  ›')` |
| Footnote | centered `"Takes about 6 minutes. You can stop and come back."` — fontSize 13, `tokens.textSecondary` |

Feature card content:
1. green tile, `Icons.calendar_today` — "Every court, live" / "Book a slot on the court side and the front desk sees it instantly."
2. violet tile, `Icons.people_outline` — "Members and guests" / "Recurring plans, coaching batches and walk-ins on one roster."
3. green tile, `Icons.credit_card` — "Money that reconciles" / "Payments, refunds and expenses land on one finance view automatically."

`_FeatureCard` (private): Row [44x44 tinted tile: radius `AppRadius.md`, `color` @ 15% alpha bg, `Icon(color, size 22)`] + 12px + Expanded Column [title fontSize 15 `w700` `textPrimary`; 4px; description fontSize 13 `textSecondary` height 1.4].

Vertical rhythm: `xl` after badge, `md` after headline, `xl` after subtitle, `xxl` before CTA, `md` before footnote, `lg` tail.

## Routing

- `AppRoutes.onboardingWelcome = '/onboarding/welcome'`.
- `app_router.dart`: register `GoRoute` -> `OnboardingWelcomeScreen`.
- `OnboardingRouteResolver.entryRouteFor(Facility?)`: `onboardingWelcome`
  unless `onboardingStep == completed` (-> `dashboard`). Existing `routeFor`
  unchanged, still used for step-to-step advancement.
- redirect(): the two sites calling `routeFor` (post-auth/splash landing;
  `path == dashboard && step != completed`) switch to `entryRouteFor`.
- Welcome CTA: `context.go(OnboardingRouteResolver.routeFor(session.facility))`.
  Step routes are not intercepted -> no redirect loop.

No persistence, no new dependencies.
