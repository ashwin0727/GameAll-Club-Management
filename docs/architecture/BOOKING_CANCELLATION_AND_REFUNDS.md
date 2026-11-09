# Court bookings: the 50% / full payment choice, cancellation rules and automatic refunds

Migration `0188_booking_payment_option_and_cancellation.sql`. Applies to every channel: the Player app, the public `/book/<venue>` page, and the club (web and mobile).

## 1. The payment choice

Once the court and time are chosen, the guest picks how to pay **online**:

| Choice | Paid now | The rest |
| --- | --- | --- |
| **Pay 50% now** (`ADVANCE`) | half, rounded up | collected at the venue before the booking ends (the existing "Pay balance" prompt in the Player app) |
| **Pay full amount** (`FULL`) | everything | nothing |

- Stored on the booking: `bookings.payment_option`. A booking made before this has `null` and keeps the old rule (50% when longer than an hour, otherwise full).
- Every booking made with a choice is a 30-minute **hold** (`PENDING`) until that first payment arrives; an unpaid hold is released automatically.
- The server decides the amount (`booking_due_now_minor`): clients only show it.
- Staff booking at the club desk: the wizard records the same choice (`set_booking_payment_option`) and creates a payment link for that amount. "Pay at venue" (cash) is still available for bookings of one hour or less, as before.

## 2. Cancellation: one fixed schedule for every club

Time left is measured from the moment of cancelling to the booking start. A boundary hour (exactly 11 h) belongs to the band with the smaller deduction.

| Time left | Deducted | | Time left | Deducted |
| --- | --- | --- | --- | --- |
| 12 h or more | 5% | | 6 – 7 h | 45% |
| 11 – 12 h | 10% | | 5 – 6 h | 50% |
| 10 – 11 h | 15% | | 4 – 5 h | 70% |
| 9 – 10 h | 20% | | 3 – 4 h | 75% |
| 8 – 9 h | 30% | | 2 – 3 h | 80% |
| 7 – 8 h | 40% | | 1 – 2 h | 90% |
| | | | under 1 h, or started | 100% |

- **Fully paid** booking: refund = what was paid minus the deduction.
- **Only the 50% advance paid**: **no refund**. The club owner can override this for one cancellation (see 3).
- **Nothing paid**: nothing to refund.
- The old per-club 24 h / 2 h policy no longer applies to court bookings.
- A booking that has started cannot be cancelled by the player or the guest online (they are asked to contact the club); the club can still cancel it.

## 3. What each person sees

Before anything happens, every cancel screen shows the hours left, the % deducted, the amount paid, the deduction and **"You get back ₹…"**, in one sentence written by the database (`booking_cancellation_quote.message`):

- **Player app** (Guest Booking → Cancel Booking) – `cancel-player-booking`
- **Public page** (booking confirmation → Cancel Booking, with the booking id + the mobile number it was made with) – `public-cancel-booking`
- **Club web and club mobile** (bookings calendar, bookings list, Guest Bookings) – `cancel-booking`. The club may tick *"Change the refund for this cancellation"*, enter a refund % (0–100) and a reason; the screen then shows the amounts for that %.

The refund rules are also shown to the guest **before they pay**, next to the 50% / full choice.

## 4. How the money moves

1. `booking_cancel_apply` cancels the booking, works out the refund and writes one `refunds` row per online payment of the booking (a booking paid as advance + balance has two payments; the refund is split across them so the parts add up exactly). Status `REQUESTED`.
2. The edge function (`cancel-booking`, `cancel-player-booking`, `public-cancel-booking`) submits each `REQUESTED` row to Razorpay's Refund API (`claim_refund_for_submission` makes a double submit impossible) and returns the outcome.
3. Razorpay's `refund.created` / `refund.processed` / `refund.failed` webhooks move the row to `PROCESSED` / `FAILED` (`razorpay-webhook`, already handling `refund.*`).
4. Money paid in **cash at the club** cannot be refunded by Razorpay. It is recorded as `offline_refund_due_minor` on `booking_cancellations` and listed under **Refunds → Cash Refunds Due at the Club**, where the club marks it handed back.
5. Every cancellation leaves one audit row in `booking_cancellations` (hours left, rule, %, amounts, who, which channel).

Refunds go back to the original payment method. Razorpay normally takes 5–7 working days for UPI / cards.

## 5. What you have to set up

**Database**
```
supabase db push        # applies 0188 (and the other unapplied migrations before it)
```

**Edge functions** (deploy the changed and the new ones)
```
supabase functions deploy cancel-booking
supabase functions deploy cancel-player-booking
supabase functions deploy public-cancel-booking
supabase functions deploy create-player-booking
supabase functions deploy public-guest-booking
supabase functions deploy public-booking-checkout
```
`cancel-player-booking` and `public-cancel-booking` use the secrets the project already has (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `PUBLIC_BOOKING_IP_SALT`). `public-cancel-booking` needs no sign-in, so deploy it the same way as `public-guest-booking`.

**Razorpay dashboard** (Settings → Webhooks, test mode and live mode separately)
- Webhook URL: `https://<project-ref>.supabase.co/functions/v1/razorpay-webhook`, secret = `RAZORPAY_WEBHOOK_SECRET`.
- Tick these events: `payment_link.paid`, `payment.captured`, `payment.failed`, `refund.created`, `refund.processed`, `refund.failed` (plus the `subscription.*` ones you already use).
- Refunds are made through the Refund API with your existing key id and secret: nothing else to enable. Make sure the account has **Refunds** switched on and enough balance in the settlement to cover refunds (Razorpay debits refunds from your balance).
- Use a **test key** first: book with a test card / UPI, cancel, and check that the refund appears under Razorpay → Transactions → Refunds and that the booking's refund row reaches `PROCESSED`.

**Test it end to end (test mode)**
1. Player app: book a court for tomorrow, choose *Pay full amount*, pay with a Razorpay test method.
2. Cancel it from the Guest Booking page: the dialog should say 95% back; confirm; the refund appears in Razorpay and in Refunds.
3. Book again, choose *Pay 50% now*, pay, cancel: the dialog should say the advance is not refundable.
4. As the club, cancel a 50%-paid booking and tick *Change the refund*, enter 100 and a reason: the full advance is refunded.

## 6. Tests

- `supabase/tests/pglite/scenarios.mjs`: the schedule band by band, the quotes, two-payment refunds, cash + online, owner override, player and public cancellation, the payment choice and the cash-refunds list.
- `player_app/test/player_home/payment_option_test.dart`, `my_bookings_test.dart`, `venue_detail_test.dart`: the choice sheet, the cancel dialog and the booking flow.
- `src/features/public-booking/picks.test.ts`: the amounts for each choice on the public page.
