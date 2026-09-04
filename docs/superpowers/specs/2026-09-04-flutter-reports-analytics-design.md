# Flutter Reports & Analytics — porting the web module to `mobile/`

**Date:** 2026-09-04
**Status:** Draft — Phase 9 of the Reports & Analytics project
**Related:** web spec `2026-09-03-reports-analytics-design.md`; web commits `17bb3e1`…`c9bc1a8` (P1–P7); migrations `0056`–`0063` (all reused unchanged); the Flutter finance rework pattern (`project_flutter_finance_rework` memory).

## Problem

The web has a full Reports & Analytics module — six reports (Overview, Bookings, Court Utilization, Revenue, Memberships, Guest Bookings) over ~29 Postgres RPCs. `mobile/` has nothing. Flutter must reach functional parity, reusing the **same backend RPCs unchanged** (spec §39 — "Flutter should not implement independent analytics formulas").

## Approach

Mirror the Flutter finance rework 1:1: a `ReportsRepository` (read layer over the RPCs, mirrors `src/services/reports/supabase-reports.service.ts`), `analytics.dart` models (mirror `src/features/reports/types.ts`), and one screen per report under `lib/features/reports/`. Charts are hand-painted `CustomPainter`s like `revenue_trend_chart.dart` — **no chart package added**. Tests are source-string RPC-contract assertions + real `fromJson` model-mapping calls, following `finance_repository_source_test.dart` — **no mocking dependency added**.

**Sub-phases** (each = plan + one commit, one per session):

| Phase | Scope |
|---|---|
| **9.1 — Foundation** | `analytics.dart` (all models + `AnalyticsPreset` + `AnalyticsFilter`), the **complete** `ReportsRepository` (all ~29 RPC methods — mechanical mirror of the tested web service), `reportsRepositoryProvider`, routes, the "Reports" entry in the More menu, a `ReportsHubScreen` (six cards linking to each report), the shared `AnalyticsFilterControls` widget (date / sport / court picker chips + bottom sheets), and shared `ReportBarList` / `ReportDataTable` widgets. Repository source tests + model mapping tests. |
| **9.2 — Overview** | `ReportsOverviewScreen` — headline KPI row (`AppMetricCard` with deltas), revenue-trend chart (reuse `RevenueTrendChart`), top-courts list, peak-hours preview. |
| **9.3 — Bookings** | `BookingReportScreen` — status KPIs, booking-trend chart, by-sport bars + table, source split. |
| **9.4 — Court Utilization** | `CourtUtilizationReportScreen` — overall gauge, by-court (sortable) + by-sport, peak-hours chart, demand `Heatmap` widget. |
| **9.5 — Revenue** | `RevenueReportScreen` — trend, breakdown + method rows, by-sport / by-court; scoped mode. |
| **9.6 — Memberships** | `MembershipReportScreen` — member KPIs, payment completion, by-type, session panel, guest-release panel. |
| **9.7 — Guest Bookings** | `GuestBookingReportScreen` — volume/status KPIs, by-sport / by-court, peak guest hours, collection. |

## Constraints

- **No revenue/analytics math on the client.** The repository has no method that sums, averages, or derives a figure — every number is an RPC response field. The `finance_repository_source_test.dart` "does no math" guard extends here.
- **Date ranges are never resolved on the client.** `AnalyticsFilter` carries a preset name (+ explicit `CUSTOM` dates); `resolve_finance_date_range` turns it into real timestamps in the facility timezone. `AnalyticsPreset` = the web's nine values incl. `THIS_QUARTER` / `THIS_YEAR`.
- **Single facility.** `SessionController` tracks one facility (`getFacility()`), so the Flutter filter has **no facility selector** — just date / sport / court. `facilityId` still goes to every RPC and RLS still gates it.
- **`AnalyticsFilter` → RPC args** built by one private `_scopedArgs` helper (mirrors the web's `dateRangeArgs` + `scopeArgs`): `p_facility_id`, `p_preset`, `p_start_date`, `p_end_date`, `p_facility_sport_id`, `p_court_id`. The four Finance RPCs the Revenue screen reuses (`get_finance_summary` etc.) take only the date subset — a second `_dateArgs` helper for those.
- **Error mapping** — a new `AppErrorCode.reportsAccessDenied` + `AppErrorCode.reportsDataError`, plus the existing `AppErrorCode.invalidDateRange`. `_mapError` mirrors the web `mapError`.
- **Design system** — `AppCard`, `AppMetricCard`, `PickerChip`, `LoadingView` (skeleton), `ErrorView`, `EmptyStateView`, `Formatters.currencyInr`, `AppColors` / `context.tokens`, `AppSpacing` / `AppTypography`. No new shared widget beyond `ReportBarList`, `ReportDataTable`, `Heatmap`, and the per-report charts.
- **Money** — RPC amounts are minor units (paise). Flutter's `Formatters.currencyInr` takes **whole rupees**, so display is `Formatters.currencyInr((amountMinor / 100).round())` — a unit conversion for display only (same as `financeAmount` in `finance_presentation.dart`).
- **Routing** — `AppRoutes.reports` = `/reports`, `AppRoutes.reportsOverview` = `/reports` (hub is overview? no — hub is its own; overview at `/reports/overview`)… **decision:** `/reports` = the hub (six cards); `/reports/bookings`, `/reports/court-utilization`, `/reports/revenue`, `/reports/memberships`, `/reports/guest-bookings`, `/reports/overview`. Mirrors web paths except web's `/reports` is the overview — Flutter adds a hub because there's no sidebar. Drill-down uses `context.push` with the filter encoded in query params (same keys as web: `preset`, `from`, `to`, `sport`, `court`).
- **Per phase:** `cd mobile && flutter analyze` clean, `flutter test` green. **No APK build** (per `feedback_no_unsolicited_apk_builds`).
- **Migrations 0056–0063 are already committed on `feat/reports-analytics`** and must be applied to Supabase for any screen to show data (the user applies them).

## Out of scope

- Web Phase 8 (a11y polish) — separate, web-only.
- CSV export on mobile — deferred; `share_plus` is available if wanted later (like the finance PDF receipt), but not in 9.1–9.7.
- Any migration or RPC change.
