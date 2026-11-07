# Player app + Club app — end-to-end QA test plan

Data for this plan: `supabase/scripts/seed_qa_edge_cases.sql` (adds it), `verify_qa_edge_cases.sql` (checks it), `cleanup_qa_edge_cases.sql` (removes it).
Everything it adds is named **QA …** (slugs `qa-…`). Run it in a **test** Supabase project, with Razorpay in **test mode**.

---

## 0. Setup (once)

| # | Step | Done when |
|---|------|-----------|
| 1 | Supabase project is the TEST one; secrets `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` are `rzp_test_…`; `RAZORPAY_WEBHOOK_SECRET` is the **test-mode** webhook secret and the test-mode webhook points at the `razorpay-webhook` function | a ₹1 test payment settles |
| 2 | Migrations applied through **0179** (0178 / 0179 are optional: the app falls back without them, but the per-length prices, hours and "latest programme per sport" only come from them) | `select to_regprocedure('list_public_coaching_programs(text,text)')` is not null |
| 3 | A club-owner account exists (the e-mail in `v_owner_email`) | you can log in to the Club app |
| 4 | A **test player**: sign in to the Player app once with a test phone, note the 10 digits, put them in `v_player_phone` | Home loads for that player |
| 5 | Run `seed_qa_edge_cases.sql`, then `verify_qa_edge_cases.sql` and compare every **EXPECT** line | all blocks match |
| 6 | Player app: `flutter run -d web-server --release …` or the deployed site. **Hard-refresh / use a fresh Incognito window** after every deploy (the old service worker cached stale files) | icons all render |

Test cards / UPI for Razorpay **test mode**: card `4111 1111 1111 1111` (any future date, any CVV) = success; `4000 0000 0000 0002` = declined; UPI `success@razorpay` = success, `failure@razorpay` = failure. AutoPay (mandate) uses the same test UPI ids on the test page.

---

## 1. The data and what each venue is for

| Venue (slug) | Why it exists | Shows in |
|---|---|---|
| **QA Multi-Sport Arena** `qa-multi-sport-arena` | 6 sports, 7 courts, 3 photos, all amenities, plans that differ **by sport**, coaching in 4 sports, an OLD programme that must lose to a newer one, a coach with a very long certification, a coach with no photo/rating, a batch with no coach, a programme with no description | Venues, Memberships, Coaching |
| **QA Single Court Studio** | 1 sport / 1 court / 1 plan, no photo, indoor-outdoor unset, no amenities | Venues, Memberships |
| **QA Extraordinarily Long Venue Name…** | very long venue / area / court / plan / coach / programme names and a very long description | all lists, venue page, booking |
| **QA Café & Co. — “Ñandú” Courts 🏸** | quotes, `<b>`, `<script>`, `&`, ₹, Tamil / Hindi / Kannada / Japanese / Arabic, emoji | all lists, venue page |
| **QA 24x7 Turf** | open 24 hours, outdoor, 2 courts, no plans, no coaching | Venues only |
| **QA Premium Padel Club** | ₹12,500/hr, plan ₹1,50,000 (Indian digit grouping), 1-to-1 coaching ₹1,50,000 | Venues, Memberships, Coaching |
| **QA Budget Courts** | ₹50/hr, 10-day pass, 45-day plan (no price tile), a ₹0 free plan, an **inactive** plan (must not show) | Venues, Memberships |
| **QA Memberships Full House** | a slot with **1 seat, 1 member** (full) and a slot with 3 seats free | Enroll Membership |
| **QA Coaching Showcase** | early-bird discount running; discount expired + enrolment deadline passed; free TRIAL with no coach; programme with no batches; ended and inactive programmes (hidden) | Coaching |
| **QA Inactive Venue** / **QA Half Set Up** | must appear **nowhere** | — |
| **QA No Bookable Court** | all courts archived / inactive / booking-disabled but it sells plans | Memberships only (NOT Venues) |
| **QA Maintenance Court** | Court 1 has an active maintenance block (3 days) | Guest Booking |
| **QA Fully Booked Tomorrow** | every hour 06–22 booked tomorrow; 5 hours the day after | Guest Booking |
| **QA Late Night Courts** | 18:00–02:00 (crosses midnight), closed Sundays | venue page hours, Guest Booking |
| **QA Split Shift / QA No Hours Set** | two time windows a day / no hours at all | venue page hours |
| **QA Broken Hero Image / QA Price Not Set** | hero URL that 404s / court price ₹0 | cards, booking |
| **QA Bengaluru Spelling / QA Missing State** | "Bengaluru" vs "Bangalore", state in capitals, state blank | city filter |
| **QA Chennai Courts / Turf** (+ **QA Hyderabad Court**) | other cities; Hyderabad has no plans or coaching | city switching, empty states |
| **QA Many Plans** | 12 plans over 4 lengths | price tiles (only the lowest per length) |
| **QA Load Venue 001–060** | 60 venues, mixed sports / prices / amenities / some without photos | list performance |

Test player (if you set the phone) at **QA Multi-Sport Arena**: eight memberships and seven guest bookings in every payment state (see §6).

---

## 2. Functional cases

Notation: **TC-area-n**. "Expect" is the pass condition.

### 2.1 Venues page (`/#/explore`)
| ID | Steps | Expect |
|---|---|---|
| V-1 | Open Venues, city Bangalore | banner, 3 highlights, city + sport dropdown + search + grid/list switch on **one line**, filters left, cards. No "Quick Actions". Inactive / Half Set Up / No Bookable Court venues are **absent** |
| V-2 | Compare "N Venues Found" with `verify` block 2 | counts match |
| V-3 | Price range slider; drag both handles | list narrows; label reads "₹a – ₹b"; "Apply Filters (N)" equals the number shown |
| V-4 | Tick Indoor, then Outdoor, then both | one = only that type; both = all; **venues with no type** (Single Court Studio, Broken Hero, Price Not Set…) appear only when neither or both is ticked |
| V-5 | Each facility box | the count in brackets equals the number of venues that have it; ticking narrows to those |
| V-6 | Sport dropdown → Padel (and Badminton, Football…) | only venues with that sport; the dropdown shows the choice and its icon (badminton and padel use the shuttlecock picture) |
| V-7 | Search: `qa multi`, `ñandú`, `🏸`, `<script>`, `'; drop table`, 300 characters, only spaces | results by name / area / sport; nothing breaks; **no script runs**; no error page |
| V-8 | Clear All | every filter and the search box reset; grid / list choice stays |
| V-9 | Heart a venue, refresh the page | stays saved; "Saved venues only" lists it |
| V-10 | Grid ↔ list switch | grid: equal-height cards, "View & Book" aligned at the bottom; list: one wide row each |
| V-11 | Cards of **QA Extraordinarily Long…**, **Café & Co.**, **Broken Hero Image**, **Single Court Studio** | long text truncates with "…" (no overflow); emoji / quotes render; broken image → drawn court placeholder; no photo → placeholder; no type badge when type is unset |
| V-12 | Switch city to Chennai, Hyderabad, then a city with nothing | Chennai: 2 QA venues; Hyderabad: 1; empty city: "No venues in … yet" message |
| V-13 | "Bangalore" and "Bengaluru" | identical lists |

### 2.2 Venue page (`/#/venue/<id>`)
| ID | Steps | Expect |
|---|---|---|
| VP-1 | Open **Multi-Sport Arena** | name + verified tick (if location verified), place, 6 sport chips, gallery with 3 photos (arrows, thumbnails), stats bar: 7 courts, hours, players, amenities + View All |
| VP-2 | "Book a Court", "Memberships", "Coaching" buttons | each opens its page; Memberships / Coaching buttons appear only when the venue has them (none on **24x7 Turf**) |
| VP-3 | **No Hours Set**, **Late Night**, **Split Shift**, **24x7** | hours stat hidden / "6 PM – 2 AM" / shows the full span / "Open 24 hours" — never "null" or blank |
| VP-4 | **Long name**, **Café & Co.** | wraps, no horizontal scroll |
| VP-5 | Phone (390 px) | back arrow + logo, gallery on top, At a Glance, Facilities, location card |

### 2.3 Guest Booking (`/#/guest-booking`, then a venue's **Book a Court**)
| ID | Steps | Expect |
|---|---|---|
| GB-1 | Open `/#/guest-booking` (and Home's "Book a Court" / "Find a Court" / promo card) | the **Venues page** (not "Coming soon"); "Venues" lit in the top bar |
| GB-2 | Pick a venue → Book a Court | the venue's content (photos, name, place, chips, stats) is **above** the steps; breadcrumb Venues › venue › Book a Court |
| GB-3 | Steps: Sport → Date → Court → Time Slot | a venue with one sport skips "Select Sport"; slots follow the court and the date |
| GB-4 | **Fully Booked Tomorrow**: pick tomorrow | every hour is booked / none free; the day after shows 5 booked hours (7, 8, 18, 19, 20) |
| GB-5 | **Maintenance Court**: Court 1 on the next 3 days | no slots offered; Court 2 normal |
| GB-6 | **Late Night**: a Sunday | closed / no slots; Monday–Saturday slots only 18:00 onward including after midnight |
| GB-7 | Pick several consecutive hours | summary merges them ("7:00 PM – 9:00 PM (2 hr)"); non-consecutive are listed; total = sum; **Price Not Set** shows "—" for the amount |
| GB-8 | Book Now | opens GameAll's booking page for that venue (payment is finished there) |
| GB-9 | Phone | Continue → Booking Summary screen → Book Now; back keeps the choices |

### 2.4 Memberships list (`/#/memberships`)
| ID | Expect |
|---|---|
| M-1 | Banner "Explore **Memberships**" with the shuttlecock art; same search card as Venues; filters: Membership Duration (counts), Time Slot, Days (counts) |
| M-2 | Row cards (list view, wide) / stacked cards (grid, phone): photo, name + verified tick, place, sport / courts / hours, **lowest price of each length** (Monthly, 3 Months, 6 Months, Yearly), cheapest highlighted, **View Plans** |
| M-3 | **No Bookable Court** is listed; **Inactive** and **Half Set Up** are not |
| M-4 | **Budget Courts**: tiles for the 30-day ₹99 plan only (10-day, 45-day and free plans make no tile; "Retired Plan" absent) |
| M-5 | **Many Plans**: exactly 4 tiles with the **lowest** price per length (₹1,500 / ₹3,900 / ₹8,000 / ₹12,000) |
| M-6 | **Premium Club**: ₹1,50,000 and ₹24,999 with Indian grouping |
| M-7 | **Multi-Sport Arena** has **sport chips on the card**; tap Padel → tiles change to Padel's (₹3,200 monthly, ₹17,000 6-month); Football → ₹2,800 / ₹7,500; a venue with plans in one sport has no chips |
| M-8 | Choose a sport in the search card → every card with that sport switches to it; tap another chip on one card → only that card changes |
| M-9 | Duration filter "6 Months" with sport Padel → only venues with a Padel 6-month plan |
| M-10 | Time Slot "Evening" → venues open between 5 and 10 PM (**No Hours Set** drops out); Days "Mon – Sat" → venues whose batches cover Mon–Sat |
| M-11 | Hyderabad (no plans) | "No memberships in Hyderabad yet" message |

### 2.5 Enroll Membership (`/#/enroll/<id>`)
| ID | Expect |
|---|---|
| EM-1 | **Select Sport is always the first step**, even for a one-sport venue (one chip selected) |
| EM-2 | From a Memberships card with Padel chosen → the page opens **on Padel** (the choice is used once; a later visit starts on the first sport) |
| EM-3 | Slots → plans: a slot shows only the plans made for it; a slot with one plan pre-selects it |
| EM-4 | **Memberships Full House**: the 18:00 slot is **full** and cannot be chosen; 06:00 shows 3 seats free |
| EM-5 | Summary (Sport, Time Slot, Plan, Start/End date, Plan Amount, Total Payable) updates live; empty = "—" |
| EM-6 | Pay & Enrol → UPI AutoPay page opens (test mode); return to the app; Home shows the membership as "Payment Incomplete" until approved, then "Active" |
| EM-7 | Not signed in | asks to sign in first, then continues; signed-in user with an existing membership at that venue sees it ("resume" if unpaid, not a duplicate) |

### 2.6 Coaching list (`/#/coaching`)
| ID | Expect |
|---|---|
| C-1 | Banner "Explore **Coaching Programs**" with the coach art and **4** highlights; filters: Coaching Level, Coaching Type, Preferred Time, Days |
| C-2 | **One card per venue**; **Multi-Sport Arena** has sport chips Badminton / Tennis / Padel / Football; Badminton shows **Beginner Program** (the newer), never "Badminton Advanced Squad" |
| C-3 | Tap Tennis → coach (Meera, ITF Level 2), programme, level, **fee** change on the same card |
| C-4 | Card content: venue photo + name + place + heart + arrow; coach photo (or initials), "Coach Arjun" + tick, certification, ★ rating, "8+ Years Experience"; programme box (sport – name, 2-line description, Group Batch / level / Max N); price "₹2,999 / month" or "₹4,999 one-time"; **View & Enroll** |
| C-5 | Missing data: **Football Juniors** = "Coach Details are not available" (no icon) and no description; **Bare Bones** coach = name only; **Newbie** = no "years" pill, rating 3.0 |
| C-6 | **Early Bird Monthly** shows ₹3,399 (discount applied); **Tennis Closed Enrolment** shows ₹4,500 (discount expired) and cannot be enrolled in; **Free Cricket Trial** = ₹0; **Football Coming Soon** has no times; the Pickleball ended / inactive programmes are **absent** |
| C-7 | **Premium Club** 1-to-1 = "Individual" chip, Max 1, ₹1,50,000 one-time |
| C-8 | Level filter: "All Levels" programmes match every level; Type "Individual Training" → only 1-to-1; Preferred Time / Days use the batch times and weekdays |
| C-9 | All cards in a row are the **same height**; "View & Enroll" aligned at the bottom |

### 2.7 Coaching enrolment (`/#/coaching-enroll/<id>`)
| ID | Expect |
|---|---|
| CE-1 | Sport → coaching type → time slot → programme slider (arrows when several) with radio selection; the card is also selectable |
| CE-2 | One-time vs monthly labelled; early-bird shown; enrolment closed programme cannot be paid |
| CE-3 | Payment Link (one-time) / UPI AutoPay (monthly) open in test mode; return → Home shows "Payment Incomplete" until settled |
| CE-4 | Resume: leave before paying, come back → the same pending enrolment, not a second one |

### 2.8 Home and payments (signed in as the test player)
| ID | Expect |
|---|---|
| H-1 | Home shows the schedule across the full width; **no Quick Actions** card |
| H-2 | Prompts exactly as `verify` block 9: PENDING (amber) for Padel Monthly and Tennis Monthly (balance ₹1,000), FAILED (red) for Football Monthly and the AutoPay-halted Pickleball; none for the paid and AutoPay-active ones; expired / pending-status memberships are not listed |
| H-3 | Guest bookings: the unpaid +3 d, +4 d and +45 d bookings give "Payment pending for Guest Booking at QA Multi-Sport Arena — Complete the payment"; the cancelled, past and paid ones give none |
| H-4 | "Pay" opens the Razorpay page; after paying, return to the app: the prompt disappears by itself (Home reloads on resume) |
| H-5 | Cards: unpaid items carry the amber **Payment Incomplete** tag, never "Active" / "Enrolled" |
| H-6 | Failed payment (use `failure@razorpay`): prompt turns red with "Retry payment" |

### 2.9 Account, navigation, routing
| ID | Expect |
|---|---|
| N-1 | Refresh on every page (`/#/explore`, `/memberships`, `/coaching`, `/guest-booking`, `/venue/<id>`, `/book/<id>`, `/enroll/<id>`, `/coaching-enroll/<id>`) | stays on that page, not Home |
| N-2 | Browser Back / Forward, deep link opened in a new tab | sensible page, no blank screen |
| N-3 | Wrong venue id (`/#/venue/00000000-0000-0000-0000-000000000000`) and an inactive venue's id | "venue not found" message with a way back |
| N-4 | Sign out → the same pages for a visitor: lists work, paying / enrolling asks to sign in |
| N-5 | City pill in the top bar and the search-card city stay in step |

### 2.10 Club (management) app — checks against the same data
| ID | Expect |
|---|---|
| CL-1 | The QA venues show for the owner; Dashboard / Reports handle venues with no bookings, no plans, no hours |
| CL-2 | **Courts**: archived / inactive / booking-disabled courts of **No Bookable Court** show their state and are not bookable |
| CL-3 | **Maintenance**: the ticket and ACTIVE block on **Maintenance Court** show; creating a clashing block is refused (no overlap) |
| CL-4 | **Memberships**: plans, batches, rosters; the full batch of **Memberships Full House** shows 1/1 and refuses a second member |
| CL-5 | **Coaching**: programmes, batches, coaches (long name, no photo, no rating); changing a programme price / status changes what the Player app shows after a refresh |
| CL-6 | **Finance**: the test player's paid / failed / part-paid rows appear in Payments and Pending Payments with the right amounts |
| CL-7 | Create a **new** plan / programme in the Club app → it appears in the Player lists (latest programme per sport rule) |

---

## 3. Non-functional cases

### 3.1 Performance
| ID | Test | Target |
|---|---|---|
| P-1 | Venues page with the 60 load venues + 25 QA venues (≈85 cards): first paint after data arrives, scrolling, switching grid ↔ list, typing in search | no jank; filters respond < 100 ms (all work on the loaded list) |
| P-2 | Load time of `play.gameall.co` cold and warm (DevTools → Network, "Slow 4G") | usable < 4 s warm; `main.dart.js` is ~3.4 MB, check it is gzip/brotli-compressed |
| P-3 | Memberships / Coaching when 0178 / 0179 are **not** installed (one extra request per venue) | still < 3 s for ~25 venues; install 0178 / 0179 for the single-call path |
| P-4 | 12-plan venue and 10-photo gallery | no layout jump; images fade in |
| P-5 | Memory over 5 minutes of tab-switching between Venues / Memberships / Coaching | no growth that persists after navigating away |

### 3.2 Responsiveness and layout
Test at **320, 360, 390, 768, 1024, 1280, 1600, 1920** px and with the browser / OS text size at **100 %, 130 %, 150 %**.
Pass: no overflow stripes, no clipped buttons (the **View & Enroll / View & Book / View Plans** buttons always fully visible), cards in a row equal height, filters panel becomes a bottom sheet on phones, the three banners keep their art sharp.

### 3.3 Accessibility
Keyboard-only: tab through the search card, chips, filters, cards (every card and button reachable, visible focus). Screen reader: sport chips announce name + selected, hearts "Save / Remove … from saved", icons have labels, price tiles read "Monthly ₹1,500". Colour contrast on the violet / amber / red chips and prompts (≥ 4.5:1 for text). Respect "reduce motion".

### 3.4 Network and failure handling
| ID | Test | Expect |
|---|---|---|
| NW-1 | DevTools → Offline, then reload a list | friendly error with **Try again**; no blank page |
| NW-2 | Block `list_public_coaching_programs` (404) | falls back to the venue-by-venue answers, still shows cards |
| NW-3 | Slow / timed-out slot request in Guest Booking | the slots error panel with Retry |
| NW-4 | Close the payment tab, come back | Home reloads; a settled payment clears its prompt, an unsettled one stays |
| NW-5 | Razorpay webhook delayed 2 minutes | the item stays "Payment Incomplete" then flips by itself after the webhook; no double charge |

### 3.5 Security and data safety
| ID | Test | Expect |
|---|---|---|
| S-1 | Call the public list functions anonymously | only public venue data (no owner e-mail, phone, member data) |
| S-2 | Signed in as player A, request B's membership / booking payment link (`create-player-booking-payment-link` with B's booking id) | refused (ownership check) |
| S-3 | XSS strings in names (the **Café & Co.** venue) | rendered as text, never executed |
| S-4 | Search with SQL-like input | treated as text |
| S-5 | Inactive / half-set-up venue ids opened directly | not found; not listed anywhere |
| S-6 | RLS: a player cannot read another venue's members, payments or coaching rows | confirmed with the anon / player keys |
| S-7 | Secrets: no `rzp_*` secret or service key in the web bundle (search `main.dart.js`) | only the public Supabase URL / anon key |

### 3.6 Data integrity and concurrency
| ID | Test | Expect |
|---|---|---|
| D-1 | Two players take the **last seat** of the 2-seat slot at nearly the same moment | one succeeds, the other is told the slot is full |
| D-2 | Double-tap **Pay** / **Book Now** | one order / one link only (idempotent) |
| D-3 | Press Back during payment and re-open | the same pending membership / enrolment, not a duplicate |
| D-4 | Two players book the same slot in Guest Booking | the second is refused |
| D-5 | Change a plan price in the Club app while a player has the page open | the player is charged the price at the moment of payment, and sees the new price after refresh |
| D-6 | Early-bird discount ends at midnight IST | price changes at midnight IST, not UTC |

### 3.7 Time zones and dates
Use a device / browser set to UTC, IST and UTC-8. All times (slots, batches, hours, "today") must show **IST**. Test just before and after midnight IST (the day change moves the Guest Booking "today", the early-bird cut-off and "ended" programmes).

### 3.8 Compatibility
Chrome, Edge, Firefox, Safari (desktop + iOS), Android Chrome, the Android app. Check the shuttlecock icon (tinted picture), fonts, the date picker and the bottom sheets on each.

### 3.9 Caching and deploys
After a deploy: first load shows the new build (no blank icons); `flutter_service_worker.js` is `no-cache`; `/assets/*` is re-validated. Reload twice and in a fresh profile; compare.

### 3.10 Localisation / content
Unicode names and descriptions in the cards, summary and Home prompts; very long single words (no spaces) do not overflow; right-to-left text in a description does not break the layout.

---

## 4. Payment cases (Razorpay test mode)

| ID | Flow | Steps | Expect |
|---|---|---|---|
| PAY-1 | Guest booking, advance | pay with `4111 1111 1111 1111` | booking confirmed, payment row `paid`, prompt gone |
| PAY-2 | Guest booking, declined | `4000 0000 0000 0002` | payment row `failed`, red prompt with Retry; retry succeeds |
| PAY-3 | Membership AutoPay | approve with `success@razorpay` | subscription `authenticated` → `active`; Home "Active" |
| PAY-4 | Membership AutoPay refused | `failure@razorpay` | membership stays "Payment Incomplete" / FAILED prompt |
| PAY-5 | Coaching one-time (Payment Link) | pay the link | enrolment active; link reused if you press Pay twice |
| PAY-6 | Coaching monthly (AutoPay) | approve | first cycle charged by the webhook; next cycles scheduled |
| PAY-7 | Part payment | pay ₹1,000 of ₹2,000 (Club app "Record payment") | prompt shows the balance ₹1,000 |
| PAY-8 | Refund / cancel | cancel a paid booking in the Club app | refund created; the Player's booking shows cancelled |
| PAY-9 | Link expiry | wait for / simulate an expired link | prompt turns FAILED "link ran out"; a new link can be made |
| PAY-10 | Webhook replay | replay a `payment.captured` event | no double credit (idempotent) |

---

## 5. Not covered by the data (do by hand)

* **Coaching enrolments** are not seeded (their tables carry billing state the app creates itself) — create them through the Player app's enrol flow (CE-3 / PAY-5 / PAY-6).
* **Player sign-up / OTP** — accounts cannot be created from SQL; use the app's login (test phone).
* **Ratings / reviews** — there is no reviews feature yet, so cards show a coach rating only when the club set one.
* **Notifications, e-mail / SMS** — need the notification worker and provider keys.

## 6. The test player's payment states (QA Multi-Sport Arena)

| # | Membership | Total | Payments | AutoPay | Home shows |
|---|---|---|---|---|---|
| 1 | Badminton Monthly | ₹1,500 | paid ₹1,500 | – | **Active**, no prompt |
| 2 | Padel Monthly | ₹3,200 | none | – | **Payment Incomplete** + PENDING prompt ₹3,200 |
| 3 | Football Monthly | ₹2,800 | **failed** ₹2,800 | – | FAILED prompt (red), Retry |
| 4 | Tennis Monthly | ₹2,000 | paid ₹1,000 | – | PENDING prompt for ₹1,000 |
| 5 | Pickleball Monthly | ₹1,800 | none | **halted** | FAILED prompt |
| 6 | Badminton Quarterly | ₹4,000 | none | **active** | **Active** (mandate approved), no prompt |
| 7 | Badminton Yearly | ₹12,000 | paid | – | not shown (expired) |
| 8 | Padel Half-Year | ₹17,000 | none | – | not shown (status pending) |

Guest bookings (same phone): +2 d paid · **+3 d unpaid (prompt)** · **+4 d ₹1,200 unpaid (prompt)** · +5 d cancelled · −3 d completed paid · −1 d completed unpaid (no prompt) · **+45 d unpaid (far future, also a prompt)** — so 3 booking prompts in all.

## 7. Exit criteria

* Every case above passes, or has a logged defect with severity.
* **No Sev-1/2 open**: payment taken twice, wrong amount charged, a hidden venue visible, a player seeing another player's data, a page that cannot be left, a button not visible.
* Non-functional targets in §3.1 met on the load dataset; §3.2 clean at all widths.
* Cleanup run (`cleanup_qa_edge_cases.sql`) leaves no `QA …` venue behind.

### Defect log template
`ID · page / flow · data used (venue) · steps · expected · actual · severity (1–4) · screenshot · browser / device · build (commit / deploy time)`
