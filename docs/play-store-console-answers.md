# Play Console: App access, Data safety and screenshot shot list

Copy-paste answers for GameAll (`com.gameall.gameall_play`) and GameAll Venue (`gameall.venue`). They match the privacy policies on play.gameall.co and club.gameall.co and the permissions in each app. If an app changes what it collects, update this page and the policy together.

Store graphics are in `store-assets/play` and `store-assets/venue` (`icon-512.png`, `feature-graphic-1024x500.png`).

---

## 1. App access (Play Console → App content → App access)

Choose **"All or some functionality is restricted"** for both apps, then **Add new instructions**.

### GameAll

- Name: `Reviewer login`
- Username / phone: `9000012345`
- Password: leave blank
- Any other information:

```
GameAll signs in with a mobile number and a one-time code. For review, use this test number, no SMS is sent:
1. Open the app and tap Continue with mobile number.
2. Enter 9000012345.
3. Enter the code 000000.
The account already has bookings, memberships and coaching so every screen has data. City: Chennai.
Payments are LIVE (real money). Please do not complete a payment: you can review the whole booking flow up to the Razorpay payment sheet, then close it. The demo account already has paid bookings, memberships and coaching to look at.
Account deletion: Profile > Support & Legal > Delete my account.
```

Razorpay is in live mode, so a reviewer who completes a payment spends real money. The wording above tells them to stop at the pay sheet. For stronger protection, run `supabase/scripts/demo_venues_bookings_off.sql` before you submit (the demo venues stay visible and bookable, but any payment at them is refused; `demo_venues_bookings_on.sql` switches payments back on), and remove or deactivate the demo venues once the review is done.

Before submitting: add `919000012345=000000` under Supabase → Authentication → Providers → Phone → Test phone numbers, sign in once with it, and run `supabase/scripts/seed_playstore_screenshots.sql` with `v_player_phone := '9000012345'`.

### GameAll Venue

- Name: `Reviewer login`
- Username: the reviewer email you create (for example `reviewer@gameall.co`)
- Password: the password you set
- Any other information:

```
GameAll Venue is for sports venue owners and staff. Sign in with the email and password above (no one-time code).
The account manages a demo venue in Chennai with courts, bookings, memberships, coaching, payments and reports.
Payments are LIVE (real money). Please do not complete a payment or start Auto Pay: you can review every screen without paying. The demo venue already has paid bookings, memberships and coaching to look at.
Account deletion: Profile > Delete account.
```

Before submitting: the reviewer account must be set up, approved and on an active plan, or the reviewer lands on onboarding or the plan screen. Change the password after the review.

---

## 2. Data safety

### Answers that are the same for both apps

| Question | Answer |
|---|---|
| Does the app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes (HTTPS) |
| Do you provide a way for users to request that their data is deleted? | Yes |
| Account deletion URL | Play: `https://play.gameall.co/delete-account`. Venue: `https://club.gameall.co/delete-account` |
| Independent security review | No |
| Ads | None. Neither app shows ads or shares data for advertising |
| Sold to third parties | No |

"Shared" in Google's form means sent to a third party for its own purposes. Our processors (Supabase, Razorpay, Firebase) act on our behalf, so they are **not** counted as sharing. Razorpay receives payment details on its own screen. Say so in the Play Console description of the payments row.

### GameAll: data types

| Category → type | Collected | Purpose | Optional | Notes |
|---|---|---|---|---|
| Personal info → Name | Yes | App functionality, Account management | Required | Shown to the venue you book with. Also the emergency contact's name (optional) |
| Personal info → Phone number | Yes | App functionality, Account management | Required | It is the sign-in, verified by SMS code. Also the emergency contact's number (optional) |
| Personal info → Email address | Yes | Account management | Optional | Only if the player adds it |
| Personal info → User IDs | Yes | App functionality, Account management | Required | The account ID |
| Personal info → Address | Yes | App functionality | Optional | Profile address (street, city, state, pincode) |
| Personal info → Other info | Yes | App functionality | Optional | Date of birth and gender in the profile |
| Health and fitness → Health info | Yes | App functionality | Optional | Blood group in the profile |
| Photos and videos → Photos | Yes | App functionality | Optional | Profile picture and ID proof image |
| Financial info → Purchase history | Yes | App functionality | Required | Bookings, memberships, coaching and their payments and refunds |
| Financial info → Payment info | **No** | | | Card, UPI and bank details are typed on Razorpay's screen and never reach us |
| Location → Approximate location | Yes (recommended; on-device only) | App functionality | Optional | Read on the phone to suggest a city and sort venues. Never uploaded. Not sharing, processed ephemerally |
| App activity → App interactions | Yes | App functionality | Required | Bookings, schedules and attendance |
| Device or other IDs | Yes | App functionality | Required | Notification token (Firebase) |
| App info and performance → Crash logs, Diagnostics | Yes | Analytics | Required | Firebase Crashlytics (added in 1.0.0+1 build of 24 Nov 2026) |

Not collected: precise location, contacts, messages, audio, files and docs, calendar, web browsing history.

### GameAll Venue: data types

| Category → type | Collected | Purpose | Optional | Notes |
|---|---|---|---|---|
| Personal info → Name | Yes | App functionality, Account management | Required | Owner, staff, and the customers a venue records |
| Personal info → Email address | Yes | Account management | Required | The owner's and staff members' sign-in |
| Personal info → Phone number | Yes | App functionality | Required | Venue phone and customer phone numbers |
| Personal info → Address | Yes | App functionality | Required | The venue's address |
| Financial info → Purchase history | Yes | App functionality | Required | Payments, expenses, refunds, daily closing |
| Financial info → Payment info | **No** | | | Handled by Razorpay |
| Photos and videos → Photos | Yes | App functionality | Optional | Venue and court photos the owner uploads |
| App activity → In-app actions | Yes | App functionality | Required | Bookings, memberships, coaching, attendance |
| Device or other IDs | Yes | App functionality | Required | Notification token (Firebase) |
| App info and performance → Crash logs, Diagnostics | Yes | Analytics | Required | Firebase Crashlytics |

Not collected: location (the Venue app asks for no location permission), contacts, files, calendar, audio, health.

### Other forms

- **Target audience:** 18 and over. Not designed for children.
- **Content rating:** no violence, no user-generated public content, no gambling. Real-money payments are for physical services (court time, coaching, memberships), so Google Play billing is not required.
- **Financial features:** none (no loans, banking or crypto).
- **News, Health, Government apps:** No.
- **Ads:** none.

---

## 3. Screenshot shot list

Use a phone of about 1080 x 2400 (or any phone emulator). Take 6 to 8 screenshots per app, portrait, no status-bar clutter, battery full, time 9:41. Sign in as the reviewer accounts above after the seed scripts have run. The first 2 or 3 matter most because they show before a user taps "more".

### GameAll (player)

| # | Screen | What must be visible |
|---|---|---|
| 1 | Home, city Chennai | The list of Chennai venues with photos and the nearest first |
| 2 | Venue detail (Smash Arena Sports Hub) | Photos, indoor tag, the five amenities, courts and prices |
| 3 | Book a court | Date and time slots with free and busy slots |
| 4 | Payment choice | Pay 50% or full, with the cancellation and refund rule |
| 5 | My Bookings | Upcoming paid bookings, one with balance due, plus a past one |
| 6 | Memberships | An active membership with days and timings |
| 7 | Coaching | A programme with attendance and the Auto Pay status |
| 8 | Profile, Support & Legal | Terms, Privacy, Refunds, Delete my account |

### GameAll Venue (owner)

| # | Screen | What must be visible |
|---|---|---|
| 1 | Dashboard | Today's bookings, revenue and occupancy with believable numbers |
| 2 | Bookings grid | A busy day, courts across and times down |
| 3 | Create booking | The guest booking steps |
| 4 | Memberships | Active members, plans and the sessions dashboard |
| 5 | Coaching | Programmes, batches and attendance |
| 6 | Finance | Daily closing or the ledger with expenses |
| 7 | Reports | Revenue or membership report with a chart |
| 8 | Staff and roles | Roles and permissions |

Rules for every shot: only Chennai places and made-up names (the seed data already follows this), no real customer name or number, no "SEED", "test" or "demo" label visible, no error banners, and no plan prices on the Venue shots (the Venue listing must not mention plans or prices).

Frame them if you like with a short caption above each (for example "Book a court in seconds"). Keep captions in plain words and avoid claims you cannot prove, such as "fastest" or "number 1".
