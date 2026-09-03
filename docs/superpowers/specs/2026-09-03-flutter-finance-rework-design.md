# Flutter Finance Rework — bringing `mobile/` up to the web's 0046–0055 finance module

**Date:** 2026-09-03
**Status:** Approved, implementation in progress
**Related:** memberships rework pattern (`project_memberships_rework` memory); web commits `d19c172`..`c5e734c`; migrations `0046`–`0055` (all applied + `download-transaction-receipt` deployed)

## Problem

The Flutter finance module is frozen at migration `0024` ("Phase 7"): dashboard, transactions list,
and a transaction-details bottom sheet, all over `payments`/`refunds` only. Since then the web
rebuilt finance from the ground up and none of it reached `mobile/`:

- **Expenses** (`0046`) — the outgoing side; `net_revenue` now means gross − refunds − expenses.
- **Payment-method breakdown** (`0047`).
- **Unified ledger** (`0049`) — transactions = income + expense + refund in one list.
- **Pending Payments** (`0052`/`0053`) — every unpaid booking/membership in one queue.
- **Record Payment anywhere** (`0052`) — idempotent `record_obligation_payment`.
- **Transaction Details page + PDF receipt** (`0055`, `download-transaction-receipt` edge fn).
- Guest-booking partial payments (`0054`), guest-revenue classification (`0051`).

`FinanceSummary` also gained `expenses_minor` and `outstanding_minor`.

## Approach

Mirror the web module 1:1, the same way the current `finance_repository.dart` / `finance.dart`
mirror the Phase-7 service. Continue the existing numbering: **Phases 8–14**. Each phase is a
vertical slice (models → repository → screen → tests) that compiles and ships on its own.

**Principles**

- Every monetary figure is server-computed. No phase adds client-side revenue math. The
  `finance_repository_source_test.dart` "does no revenue math" guard extends to every new method.
- The one ported piece of client logic is `canRecordPayment` (pre-submit validation), as
  `lib/features/finance/money.dart` + `money_test.dart` mirroring `src/features/finance/money.ts`
  / `money.test.ts`. `obligation.ts` is **not** ported — the list RPC already returns `status`.
- **Functional parity, existing mobile design language.** Reuse `AppCard`, `_MetricGrid`,
  `PickerChip`, `StatusBadge`, `SectionHeader`, `ResponsivePage`, the bottom-sheet form pattern
  (`guest_form_sheet.dart`). **No donut charts** — revenue breakdown and payment-method split
  render as labelled-amount rows (current `_buildBreakdown` style).
- Error mapping stays generic (`AppErrorCode.financeDataError` / `financeAccessDenied` /
  `invalidDateRange`) — matches the web `ServiceError` behaviour.
- `finance_repository.dart` gains write methods; its "pure read layer" doc comment is updated to
  "read layer plus the three owner-entered writes (create/void expense, record payment)".
- Tests follow the existing pattern: source-string assertions for RPC contracts +
  real model-mapping calls. No mocking dependency is added.
- All migrations are already applied. Only **Phase 12** adds Flutter package deps
  (`share_plus`, `path_provider`).

**Enum note:** the ledger and obligations use `BOOKING | GUEST_BOOKING | MEMBERSHIP`
(`ObligationSource`), which is *not* `PaymentSourceType` (`MEMBERSHIP | MEMBER_BOOKING |
GUEST_BOOKING`). A new `ObligationSource` enum is required; do not reuse `PaymentSourceType`.

## Phases

### Phase 8 — Expenses (the outgoing side)

Backend: `create_expense` / `void_expense` (owner/manager only), `list_expenses`,
`expense_categories` table (RLS-scoped select: shared defaults + this facility's own).

- **Models** (`finance.dart`): `ExpenseCategory {id, name}`, `ExpenseStatus` (`RECORDED`/`VOID`),
  `ExpenseRow {id, categoryId, categoryName, amountMinor, currency, paymentMethod, spentOn,
  vendor, reference, notes, status}`, `ExpensePage {expenses, totalCount}`.
- **Repository**: `listExpenseCategories(facilityId)` — `.from('expense_categories').select('id,
  name').eq('is_active', true).or('facility_id.is.null,facility_id.eq.<id>').order('sort_order')`.
  `listExpenses({facilityId, dateRange, categoryId?, limit?, offset?})` — `list_expenses` with
  `..._dateRangeArgs`, `p_category_id`, `p_limit` (25), `p_offset` (0); `totalCount` from
  `data[0].total_count`. `createExpense({...})` — `create_expense` (`p_amount_minor`,
  `p_spent_on`, `p_payment_method`, `p_vendor`, `p_reference`, `p_notes`). `voidExpense(id,
  {reason})` — `void_expense`.
- **UI**: `expenses_screen.dart` — `AppBar('Expenses')`, `FinanceDateRangePicker`, optional
  category `PickerChip`, "Total on this page" `AppCard` (server rows only — sum is display of a
  filtered list of server values; **guard: no `fold`/`reduce` on amounts in the repo**, but the
  screen may total a page for display exactly as web's `recordedTotal` does — acceptable, it is
  not a headline figure and not in the repo). List of `AppCard` rows: category chip, vendor,
  date, amount, Void button (RECORDED) / "Void" badge. Pagination via existing `_Pagination`
  pattern. Add-expense bottom sheet (`AddExpenseSheet`, `guest_form_sheet.dart` shape): category
  dropdown, amount, date, payment-mode chips (`Cash/UPI/Card/Bank Transfer`), vendor, reference,
  notes. FAB or app-bar action to open it.
- **Routing**: `AppRoutes.financeExpenses = '/finance/expenses'`; `GoRoute` in `app_router.dart`.
- **Tests**: `expenses_repository` contract cases in `finance_repository_source_test.dart` (or a
  new `finance_expenses_repository_source_test.dart`); `ExpenseRow.fromJson` mapping;
  `ExpensePage` total-count-not-length.

**Open decision resolved:** the "total on this page" card sums server-provided row values on the
screen (not the repo), matching web `expenses-page.tsx`. The repo stays math-free.

### Phase 9 — Unified ledger Transactions

Backend: `list_finance_ledger` (INCOME|EXPENSE|REFUND, category/method/status/search filters,
`total_count` in-row), `list_finance_payment_methods`.

- **Models**: `LedgerTxnType` (`INCOME`/`EXPENSE`/`REFUND`), `LedgerEntry {id, reference,
  occurredAt, description, category, txnType, paymentMethod, amountMinor, currency, status,
  sourceType, bookingId, membershipId, expenseId}`, `LedgerFilters {txnType?, category?,
  paymentMethod?, status?, search?}`, `LedgerPage {entries, totalCount}`.
- **Repository**: `listLedger({facilityId, dateRange, filters?, limit?, offset?})` —
  `list_finance_ledger` (`p_txn_type`, `p_category`, `p_payment_method`, `p_status`, `p_search`,
  `p_limit` 10, `p_offset` 0); `totalCount` from `data[0].total_count`. `listPaymentMethods
  (facilityId)` — `list_finance_payment_methods` → `List<String>`.
- **UI**: rewrite `transactions_screen.dart` over the ledger. Filters: type / category (static
  list from web `CATEGORIES`) / payment-mode (`listPaymentMethods`) as `PickerChip`s + date
  range + search. Rows: description, reference, date, category chip, ±amount (`−` prefix for
  EXPENSE/REFUND), status badge. INCOME rows tap → Transaction Details (Phase 12; until then,
  keep the current sheet or a stub). Pagination unchanged.
- **Dashboard** keeps `listTransactions` for "recent" (web does too — `finance-dashboard.tsx`).
- **Tests**: `listLedger` contract (`p_*` args, `total_count` not length), `LedgerEntry.fromJson`,
  `LedgerTxnType` round-trip.

### Phase 10 — Pending Payments

Backend: `list_pending_payments` (with `p_source_id` single-lookup mode), `get_pending_payments_summary`.

- **Models**: `ObligationSource` (`GUEST_BOOKING`/`BOOKING`/`MEMBERSHIP`), `ObligationStatus`
  (`PENDING`/`PARTIALLY_PAID`/`OVERDUE`/`PAID`), `ObligationSort` (`DUE_DATE`/`AMOUNT`/
  `CUSTOMER`/`NEWEST`), `PaymentObligation {sourceType, sourceId, reference, customerName,
  customerPhone, description, facilityName, courtName, startsAt, endsAt, totalMinor, paidMinor,
  outstandingMinor, status, paymentMethod, dueOn}`, `PendingPaymentFilters {search?, sourceType?,
  status? (incl. 'ALL_OUTSTANDING'), from?, to?, sort?}`, `PendingPaymentsPage {obligations,
  totalCount}`, `PendingPaymentsSummary {outstandingMinor, pendingMinor, partiallyPaidMinor,
  overdueMinor, obligationCount}`.
- **Repository**: `listPendingPayments({facilityId, filters?, limit?, offset?, sourceId?})` —
  `list_pending_payments` (`p_search`, `p_source_type`, `p_status` default `'ALL_OUTSTANDING'`,
  `p_from`, `p_to`, `p_sort` default `'DUE_DATE'`, `p_limit` 20, `p_offset` 0, `p_source_id`);
  `totalCount` from `data[0].total_count`. `getPaymentObligation(facilityId, sourceId)` →
  `listPendingPayments(sourceId: …, limit: 1).obligations.firstOrNull`.
  `getPendingPaymentsSummary(facilityId, {from, to})` — `get_pending_payments_summary`.
- **UI**: `pending_payments_screen.dart` — 4 KPI tiles (`_MetricGrid`), status / source / sort
  `PickerChip`s, search field, obligation `AppCard`s (customer, source, reference, description,
  total / paid / outstanding, status badge, due date, "Record" → Phase 11), pagination.
  Empty state = "You're all caught up".
- **Routing**: `AppRoutes.financePendingPayments = '/finance/pending-payments'`.
- **Tests**: `listPendingPayments` contract, `PaymentObligation.fromJson`, summary mapping,
  enum serialisation.

### Phase 11 — Record Payment (standalone, works anywhere)

Backend: `record_obligation_payment` (idempotent via `p_idempotency_key`, raises `23514` for
over-payment / already-settled).

- **`lib/features/finance/money.dart`**: `canRecordPayment({amountMinor, outstandingMinor})` →
  sealed result (`Ok` / `Invalid(reason)`); `toMajor(amountMinor)`. Mirrors `money.ts`.
  `money_test.dart` mirrors `money.test.ts` cases.
- **Repository**: `recordObligationPayment({sourceType, sourceId, amountMinor, method, paidOn?,
  reference?, notes?, idempotencyKey})` — `record_obligation_payment` (`p_*` args); returns
  `{duplicate, outstandingMinor?}` from the jsonb.
- **UI**: `record_payment_screen.dart` — takes `sourceId`, loads the obligation via
  `getPaymentObligation` (survives reload, shows balance as it stands now). Details `AppCard`
  (reference, customer, phone, facility, description, source, total, already-paid, **Amount Due**,
  status badge). Payment form: amount (prefilled to outstanding/100), payment-mode dropdown,
  date, reference (hint: Cash→optional / else→recommended), notes. Remainder preview when
  `amountMinor < outstandingMinor`. Submit disabled unless `canRecordPayment` ok. One
  `idempotencyKey` per screen instance (`Uuid().v4()`, `'<sourceId>:<uuid>'`). Settled state =
  "already paid in full". On success → pop back to Pending Payments and refresh.
- **Routing**: `AppRoutes.financeRecordPayment = '/finance/pending-payments/:sourceId/record'`
  (path param).
- **Unify memberships**: `memberships_screen.dart` `_recordPayment` → `context.push` the Record
  Payment route with the membership id as `sourceId`; delete the `record_membership_payment`
  call and its repo method if now unused (check `membership_repository.dart` + its tests).
- **Tests**: `money_test.dart`; `recordObligationPayment` contract; membership-row still offers
  Record Payment when `paymentIncomplete`.

### Phase 12 — Transaction Details page + PDF receipt

Backend: `get_transaction_details` (jsonb, includes `history[]`), `download-transaction-receipt`
edge fn (POST `{transactionId}` → `application/pdf` bytes).

- **New deps** (`pubspec.yaml`): `share_plus`, `path_provider`.
- **Models**: `TransactionPaymentHistoryRow {id, paidAt, amountMinor, paymentMethod, reference,
  status, isThisOne}`, `TransactionDetails {id, reference, sourceType, category, type ('INCOME'),
  amountMinor, currency, status, paymentMethod, occurredAt, createdAt, recordedBy, description,
  sourceReference, customerName, customerPhone, facilityName, facilityId, bookingId,
  membershipId, refundedMinor, netMinor, history}`.
- **Repository**: `getTransactionDetails(transactionId)` — `get_transaction_details` (jsonb map).
  `downloadTransactionReceipt(transactionId)` — `_client.functions.invoke(
  'download-transaction-receipt', body: {transactionId})`; return `Uint8List` bytes (handle
  `FunctionException` → `financeDataError`).
- **UI**: `transaction_details_screen.dart` replaces `transaction_details_sheet.dart`. Sections:
  Transaction Information (`_DetailRow` list), Related Information (booking/membership/customer/
  facility with optional "View"), Payment History (`AppCard` rows; the `isThisOne` row
  highlighted; "Total collected" when `history.length > 1` — display-only sum of server values,
  as web). App-bar "Download Receipt" action → fetch bytes → write to a temp file via
  `path_provider` → `Share.shareXFiles`.
- **Routing**: `AppRoutes.financeTransactionDetails = '/finance/transactions/:transactionId'`.
  Update every current `showTransactionDetailsSheet` caller (`finance_screen.dart`,
  `transactions_screen.dart`) to `context.push`. Delete `transaction_details_sheet.dart`.
- **Tests**: `getTransactionDetails` contract, `TransactionDetails.fromJson` incl. `history`,
  `downloadTransactionReceipt` invokes the right function name.

### Phase 13 — Dashboard rebuild

Backend: `get_finance_summary` (now with `expenses_minor`, `outstanding_minor`),
`get_payment_method_breakdown`.

- **Models**: `FinanceSummary` gains `expensesMinor` / `outstandingMinor` (parse
  `json['..'] ?? 0` — web does `?? 0`; keeps `finance_repository_source_test.dart`'s existing
  `fromJson` fixture valid). New `PaymentMethodSlice {paymentMethod, amountMinor, paymentCount}`.
- **Repository**: `getPaymentMethodBreakdown(facilityId, dateRange)` —
  `get_payment_method_breakdown` → `List<PaymentMethodSlice>`.
- **UI**: `finance_screen.dart` — replace the three preset cards with four range-driven stat
  cards: **Total Revenue** (`grossRevenueMinor`), **Total Expenses** (`expensesMinor`),
  **Net Revenue** (`netRevenueMinor`), **Pending Payments** (`outstandingMinor`, tappable →
  Phase 10). Period-over-period delta text: fetch a second `getSummary` for the previous
  equivalent range (map `TODAY→YESTERDAY`, `THIS_WEEK→LAST_WEEK`, `THIS_MONTH→LAST_MONTH`;
  custom → shift the window back by its own length), show `±%` ("vs last period" when the prior
  figure is 0). A missing comparison must not fail the page. Trend granularity `PickerChip`
  (`By Day` / `By Week` / `By Month`). Revenue breakdown + **Payment Methods** both as
  labelled-row `AppCard`s. Recent transactions unchanged (still `listTransactions`).
- **Tests**: `FinanceSummary.fromJson` with and without the two new keys;
  `getPaymentMethodBreakdown` contract + `PaymentMethodSlice.fromJson`; previous-range mapping
  helper (pure function, unit-tested).

### Phase 14 — Finance nav grouping

Web groups Finance nav into an expandable section (Dashboard / Transactions / Expenses / Pending
Payments). Mobile equivalent:

- The bottom-nav "Finance" tab lands on `finance_screen.dart` (unchanged). Add a compact
  in-screen nav row / section on the dashboard linking to Transactions, Expenses, Pending
  Payments (Transactions already has a link; add the other two).
- Update the dashboard quick-action grid (`dashboard_screen.dart:1356`) if a dedicated
  Pending Payments / Expenses action is wanted.
- No new routes; wiring only. Smallest phase.

## Testing strategy

- **Per phase:** `cd mobile && flutter test` green; `flutter analyze` clean.
- Repository contract tests assert exact RPC name + `p_`-prefixed args + parallel list/count
  where applicable + `total_count`-not-`.length` + no client math.
- Model tests: real `fromJson` calls, snake_case → field mapping, enum round-trips.
- Pure-logic tests: `money_test.dart` (mirrors `money.test.ts`), previous-range mapping.
- No widget/integration tests beyond what the module already has (none) unless a phase's logic
  warrants one.

## Out of scope

- Donut / chart rendering (functional parity uses rows).
- `obligation.ts` port (RPC returns `status`).
- Reworking `refunds_screen.dart` (settlement exceptions already link there).
- Any migration or edge-function change (all applied/deployed).
- APK builds (per `feedback_no_unsolicited_apk_builds`).

## Rollout

One phase per working session, committed independently, in order 8 → 14. The user applies
nothing (backend is ready); they review each commit. Memory `project_flutter_finance_rework`
tracks phase status.
