# GameAll Play — Play Console answers and store listing

Written from what the app actually does (checked against the code and the release build's permissions on 14 Nov 2026). Re-check it if the app changes. Google's forms change wording now and then, so match the meaning, not the exact words. The Venue app's version of this document is `play-store-submission.md`; the legal pages are shared by both apps.

App name **GameAll Play**, package id **`com.gameall.gameall_play`** (permanent once published).

---

## Part 1 — App content declarations

| Declaration | Answer |
|---|---|
| App or game | **App** |
| Free or paid | **Free**. Players pay venues for courts, memberships and coaching (physical services); GameAll sells no digital goods in the app. |
| Privacy policy URL | `https://club.gameall.co/privacy` |
| Ads | **No** |
| App access | **Restricted — login needed.** Give the reviewer test number and code (Part 4). |
| Target audience | **18 and over.** Not designed for children. |
| News / Government / Health apps | No / No / No |
| Advertising ID | **No** (the app does not use it) |
| Financial features | None that Google lists: the app does not lend, hold balances or move money between people. Players pay venues through Razorpay, a licensed payment gateway. If a "payments" option is offered, choose "none of the above". |
| Content rating category | **Utility / Sports-related booking app**. Answer **No** to violence, sexual content, profanity, drugs, gambling, fear. Answer **No** to "users can communicate with each other or share content". |

**Payments policy:** Google Play billing is only required for digital goods. Court time, coaching sessions and club memberships are physical-world services, so paying a venue through Razorpay inside the app is allowed. The listing must not describe anything as a digital purchase.

**Sensitive permissions** (none needs a declaration form):
- `ACCESS_COARSE_LOCATION` — optional, "Use my current location" in the city picker. Approximate location only; the position is used on the phone and not sent to GameAll. The precise-location permission is deliberately not requested.
- `POST_NOTIFICATIONS` — Android 13+, booking and payment reminders.
- `INTERNET`, `ACCESS_NETWORK_STATE`, and ones that come from libraries (`VIBRATE`, `WAKE_LOCK`, `NFC` optional hardware from the payment sheet, `READ_BASIC_PHONE_STATE` from the payment sheet).
- No SMS, contacts, camera, microphone, call log, background location or storage permission.

---

## Part 2 — Data safety form

**Top-level**

| Question | Answer |
|---|---|
| Does the app collect or share required user data types? | **Yes** |
| Is all user data encrypted in transit? | **Yes** (HTTPS) |
| Can users request deletion? | **Yes** |
| Deletion link (web) | `https://club.gameall.co/delete-account` |
| In the app | Profile → Support & Legal → **Delete my account** |

**Data types**

| Category | Type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|---|
| Personal info | Name | Yes | No | Required | App functionality, account management |
| Personal info | Email address | Yes | No | **Optional** | App functionality, communications (receipts) |
| Personal info | Phone number | Yes | No | Required (it is the sign-in) | App functionality, account management, fraud prevention and security |
| Personal info | User IDs | Yes | No | Required | App functionality, account management |
| Financial info | Payment info | Yes | **Yes, with Razorpay** | Required to pay online | App functionality. Entered on Razorpay's screen; not stored by GameAll. |
| Financial info | Purchase history | Yes | No | Required | App functionality (bookings, memberships, receipts) |
| App activity | Other user-generated content / in-app actions (bookings, enrolments) | Yes | No | Required | App functionality |
| App info and performance | Crash logs, Diagnostics | Yes | No | Required | Analytics (app stability) |
| Device or other IDs | Push token | Yes | No | Required for notifications | App functionality |

**Location:** answer **Not collected**. The approximate position is read on the phone to sort venues and is never transmitted or stored by GameAll. (If Google's wording asks about data "processed ephemerally on device", that is not a collection.)

**Not collected:** photos/videos, files, contacts, calendar, audio, messages, health, web history, installed apps, advertising ID.

**Shared:** Google counts a service provider that only processes data for you as **not** shared. Providers: Supabase (database, sign-in), Razorpay (payments), Google Firebase (notifications, crash reports), 2Factor (one-time codes by SMS). Razorpay is marked "shared" for payment info because the player gives it directly to Razorpay.

**Security practices:** encrypted in transit **Yes**; deletion requestable **Yes**; Families policy **No**; independent security review **No**.

---

## Part 3 — Store listing

**App name** (max 30): `GameAll Play`

**Short description** (max 80): `Find sports venues near you. Book courts, join memberships and coaching.`

**Full description** (max 4,000):

```
GameAll Play helps you find and book sports venues in a few taps.

FIND A VENUE
Browse venues in your city, see their sports, courts, timings, photos and amenities, and sort by what is nearest.

BOOK A COURT
Pick a sport, a date and a time, see the price up front, and pay online by UPI or card. Longer slots can be secured with a 50% advance.

JOIN A MEMBERSHIP
Choose a plan and the weekly timings you will play, and pay once or set up UPI Auto Pay. See your membership, its timings and your payments in one place.

JOIN COACHING
Find programmes and batches, enrol, and pay the fee. See your batches and sessions.

CANCEL WITH CLARITY
Before you cancel a booking the app shows exactly how much you get back. Refunds go to the same UPI app or card.

YOUR HISTORY AND RECEIPTS
All your bookings, memberships, coaching and payments with downloadable receipts.

REMINDERS
Get a notification before your booking, and when a payment succeeds.

Sign in with just your mobile number and a one-time code. You control your data: delete your account any time from the app.

Need help? admin@gameall.co or visit gameall.co.
```

**Release notes for 1.0.0** (max 500):
```
First release of GameAll Play: find venues, book courts, join memberships and coaching, pay by UPI or card, and see your bookings and receipts.
```

**Category:** Sports (alternative: Lifestyle). **Tags:** Sports, Booking.

**Contact:** email `admin@gameall.co`, website `https://gameall.co`, phone `9360428761`.

**Graphics to prepare**
- App icon 512 × 512 PNG.
- Feature graphic 1024 × 500 PNG.
- Phone screenshots, 2 to 8 (9:16): Home, Venue list, Venue detail, Guest Booking, Pay sheet, My Bookings, Membership, Coaching, Profile. Use the QA seed venues, not real people's data.
- Do **not** show or mention the club-owner plans, prices, "free trial" or anything about buying a plan.

---

## Part 4 — Reviewer access (the most common reason for rejection)

Google's reviewer must be able to get past the sign-in. The app signs in with a mobile number and a one-time code by SMS, which the reviewer cannot receive. Do this **before** you submit:

1. In the Supabase dashboard → Authentication → Providers → Phone → **Test phone numbers**, add a number and a fixed code, e.g. `9000000099` → `123456` (Supabase accepts it without sending an SMS).
2. Sign in once with that number in the app and give it a name, so it has a profile.
3. Run `supabase/scripts/seed_qa_edge_cases.sql` in the project (see `docs/qa/PLAYER_APP_QA_TEST_PLAN.md`) so the venue list is not empty, or make sure at least one real venue is live with courts and prices.
4. In Play Console → App content → App access choose "All or some functionality is restricted" and enter: *Phone number: 9000000099, one-time code: 123456. The code is fixed for this test number. Payments run on Razorpay; use UPI success@razorpay or card 4111 1111 1111 1111 only if the account is in test mode.*
5. **Production payments:** reviewers must not be asked to pay real money. Either keep Razorpay in test mode for the review build or tell the reviewer to stop at the payment sheet (it opens correctly and the order is created).
6. Keep the test number and its data working while the app is in review.

> **Launch blocker:** the `player-login` function can sign anyone in with just a mobile number, with no code, when the secret `PLAYER_OTP_REQUIRED` is not `true`. With that switch off, anybody who types a number is signed in as that person and sees their bookings. **Set `PLAYER_OTP_REQUIRED=true` (and keep the SMS hook function deployed) before publishing**, then do step 1 above so reviewers can still sign in. See the header comment of `supabase/functions/player-login/index.ts`.
