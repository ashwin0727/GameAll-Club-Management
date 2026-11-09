# Player app: how the UI, the API calls and the database fit together

One Flutter code base (`player_app/`) builds the web app (play.gameall.co) and the Android app. A change is made once and appears in both,
unless it is deliberately web-only. Phone layouts are tested at 390 px and 320 px (with 1.4x text) next to the wide layout.

## 1. UI rules (what "aligned" means here)

- One page = one scroll column on a phone, two columns on a wide window. A column never has a fixed height.
- Shared building blocks, not copies: `DetailsCard` and `PillTabs` (details pages), the service card (Home), the payment progress and
  success pages. A fix to one fixes every page that uses it.
- Nothing is cut with an ellipsis if it can wrap: titles wrap to two lines, chips go under their title on a narrow card.
- Every page is tested for overflow on a 320 px phone with large text.

## 2. How the app calls the backend

| Call | Rule | Why |
| --- | --- | --- |
| Reads (`get_my_*`, `get_player_dashboard`) | one RPC per page, `retryTransient`: 3 tries, 15 s cut-off, 0.4 s / 0.8 s waits plus jitter | a dropped connection or a cancelled slow query is fixed by a second try; jitter stops a crowd retrying together |
| Writes (book, pay, enrol) | never retried by the client | repeating a payment or a booking is not harmless |
| Several callers want the same data | `InFlight` shares the running call (Home refresh) | resume + payment + page close used to send three identical requests |
| Waiting for a payment | checks every 3 s for 2 min, then 9 s, then 18 s; "I've paid" and returning to the app check at once | a player who walks away should not cost the server a call every 3 s for ten minutes |
| Failure | the page shows its own "Try again"; the old data stays on screen on a failed refresh | no blank screens |

## 3. Security model

- **Identity is never taken from the app.** The player's name and phone come from their own session (`get_my_player`) inside the server;
  the app sends only ids. Amounts are always worked out in the database from the booking, the plan or the enrolment.
- **Ownership is checked in the database.** Every `get_my_*` function matches rows to the signed-in player's phone / login and returns
  nothing for anyone else (checked in `supabase/tests/pglite/qa_seed_check.mjs`: a stranger and an anonymous caller see none of it).
- **Least privilege.** Player functions are `SECURITY DEFINER` with a pinned `search_path`, revoked from `public` and `anon`, granted to
  `authenticated` only. Money-moving functions (`apply_*`, `settle_payment`, `create_booking_balance_order`, `check_rate_limit`) are
  `service_role` only, called by edge functions that first check ownership under the caller's own JWT.
- **Payments are confirmed by Razorpay, not by the app.** Only the webhook, or the server-side sync that asks Razorpay directly, can mark
  something paid. The browser or app saying "I paid" changes nothing.
- **A page-access check protects staff routines.** `create-player-booking` therefore books with the same anonymous path as the public
  page, after reading the player's identity from their JWT.

### Threats considered

| Threat | Mitigation |
| --- | --- |
| Someone reads another player's bookings / receipts by guessing an id | ownership match by phone inside each function; "not found" for both missing and not-yours |
| Forged amount or identity in a request | neither is read from the request |
| Booking spam / holding every slot | per-phone and per-IP attempt limit (0065) and a 30-minute unpaid hold that releases itself; max 4 unpaid bookings per guest |
| Payment-link or Razorpay-API hammering (a client stuck in a loop) | `check_rate_limit` in `sync-player-payment` (12/min per item) and `create-player-booking-payment-link` (8/min per booking); throttled sync answers from the database |
| One slow query tying up connections | `statement_timeout` 8 s on player reads, 5 s on public reads |
| Whole-table scans per page view as data grows | expression indexes on `normalize_phone(...)` for members, guest_players, bookings (0185) |
| A limiter outage blocking payments | the limiter fails open; it protects capacity, it must never stop a payment |
| Replayed webhooks / double payment | Razorpay payment ids are unique on `payment_orders` and `payments`; the webhook functions are idempotent |

## 4. Capacity: what is and is not known

Measured here: the SQL runs and returns the right data on a small data set (in-memory Postgres, 106 checks); retry, back-off and
sharing logic is unit-tested.

**Not measured:** requests per second on your Supabase plan. Nothing in this repo has been load-tested. Before a launch, run a load
test against a staging project with realistic data (thousands of members, a player with 50 bookings) and watch p95 of
`get_player_dashboard`, `get_my_guest_bookings` and `get_my_coaching_details`, the connection count, and the edge-function error rate.
The knobs, in order of use: the indexes above, the per-function `statement_timeout`, the limiter numbers, the poll intervals, and the
Supabase compute size / connection pooler.
