# GameAll Venue — Play Console answers and store listing

Everything here is written from what the app actually does (checked against the code and the release build's permissions on 29 Oct 2026). Re-check it if the app changes. Google's forms change wording now and then, so match each answer to the option that means the same thing.

---

## Part 1 — App content declarations

| Declaration | Answer |
|---|---|
| App or game | **App** |
| Free or paid | **Free** (the app has no in-app purchases) |
| Privacy policy URL | `https://club.gameall.co/privacy` |
| Ads | **No**, the app contains no ads |
| App access | **Restricted — login needed.** Enter the reviewer account (see Part 4). Explain: "Sign-up needs a one-time email code and a phone-call code, so reviewers cannot create their own account. Use this ready-made account." |
| Target audience | **18 and over.** Not designed for children. |
| News app | No |
| Government app | No |
| Health / COVID-19 | No |
| Advertising ID | **No.** The app does not use it, and its manifest does not request the permission. |
| Financial features | See the note below |
| Content rating category | **Utility / Productivity** (business tool) |

**Content rating questionnaire:** answer **No** to violence, sexual content, profanity, drugs, gambling and fear/horror. Answer **No** to "users can share content or communicate with other users publicly" (staff only see their own facility's data) and **No** to location sharing. Expect an "Everyone" style rating.

**Financial features:** the app does not lend money, hold balances, or move money between people. It records and displays payments that a facility's customers make through Razorpay, a licensed payment gateway. Choose the option that says the app **provides no financial features** unless Google's list has a clearly matching item. If you are unsure, pick "payments" only if the list describes processing payments for others, and read Google's help text beside each option.

**Sensitive permissions:** none need a declaration form. The app asks for notifications (Android 13+) and, only when you choose "Take a photo", the camera. No SMS, call log, location, contacts or background services.

**Permissions from libraries** (the release build also lists these; none are sensitive): INTERNET, ACCESS_NETWORK_STATE, POST_NOTIFICATIONS, VIBRATE, WAKE_LOCK, NFC (optional hardware, not required), READ_BASIC_PHONE_STATE and READ_EXTERNAL_STORAGE (added by the payment and file libraries), and the push-notification receive permission.

---

## Part 2 — Data safety form

**Top-level questions**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (all traffic uses HTTPS) |
| Do you provide a way for users to request that their data is deleted? | **Yes** |
| Deletion link (web) | `https://club.gameall.co/delete-account` |
| In the app | Profile → **Delete account** |

**Data types** (for each: collected = yes; "optional" means the user can use the app without providing it)

| Category | Data type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|---|
| Personal info | Name | Yes | No | Required | App functionality, account management |
| Personal info | Email address | Yes | No | Required | App functionality, account management, communications |
| Personal info | Phone number | Yes | No | Required | App functionality, account management, fraud prevention and security |
| Personal info | User IDs | Yes | No | Required | App functionality, account management |
| Personal info | Address | Yes | No | Optional | App functionality (facility address; customer address if entered) |
| Personal info | Other info (date of birth, gender) | Yes | No | Optional | App functionality (member records entered by a facility) |
| Financial info | Payment info | Yes | **Yes, with Razorpay** | Required to pay online | App functionality (taking payments). Entered in Razorpay's checkout; not stored by us. |
| Financial info | Purchase history | Yes | No | Required | App functionality, analytics of the facility's own business |
| Financial info | Other financial info (bank account or UPI ID for payouts) | Yes | No | Required to receive payouts | App functionality |
| Photos and videos | Photos | Yes | No | Optional | App functionality (profile, logo, coach, program images) |
| App info and performance | Crash logs | Yes | No | Required | Analytics (app stability) |
| App info and performance | Diagnostics | Yes | No | Required | Analytics (app stability) |
| Device or other IDs | Device or other IDs (push token, installation ID) | Yes | No | Required for notifications | App functionality (push notifications), analytics |

**Not collected:** location, contacts (the phone's address book), calendar, audio, files and docs, messages (SMS or in-app chat), health and fitness, web browsing, search history, installed apps.

**About "shared":** Google counts a transfer to a service provider that only processes data on your behalf as **not** shared. We use these providers: Supabase (database and sign-in), Resend (email), 2Factor (phone-call codes), Google Firebase (notifications and crash reports). Razorpay is shown as shared for payment info because it handles card, UPI and bank details under its own terms with the customer; this is the cautious choice. If you prefer, read Google's definition and decide whether Razorpay counts as your service provider.

**Security practices**
- Data is encrypted in transit: **Yes**
- You can request data deletion: **Yes**
- Committed to the Play Families Policy: **No** (not for children)
- Independent security review: **No**

---

## Part 3 — Store listing

**App name** (max 30): `GameAll Venue`

**Short description** (max 80 characters, 67 used):
`Run your sports venue: bookings, memberships, coaching and payments.`

**Full description** (max 4,000):

```
GameAll Venue helps sports venue owners and their teams run the whole day from their phone.

Whether you run a badminton hall, a turf, a multi-court club or a coaching academy, GameAll Venue keeps bookings, members, coaches and money in one place, so you spend less time on paperwork and more time on the court.

TODAY AT A GLANCE
See today's bookings, collections and what needs your attention the moment you open the app.

BOOKINGS AND CALENDAR
View every court on a live calendar. Take walk-in and guest bookings, move or cancel them in a tap, and let customers pay online with UPI or card.

MEMBERSHIPS
Create membership plans, enrol members, schedule their weekly court slots and track every payment and renewal.

COACHING
Set up programs and batches, add students and coaches, plan sessions and collect fees.

FINANCE AND REPORTS
Record expenses, close the day, see profit and loss, and review reports on bookings, revenue, court use and members.

YOUR TEAM, YOUR RULES
Add staff and decide, page by page, who can only view and who can edit. Everyone sees only what you allow.

TIMELY ALERTS
Get a notification when a guest booking is about to start or end, when a membership is created or renewed, when a payment succeeds or fails, and a monthly reminder to check your report.

SIMPLE AND SECURE
Photos from your camera or gallery, exports you can share, and your facility's data protected so only you and your staff can see it.

Features you see depend on your venue's setup. Need help? Contact admin@gameall.co or visit gameall.co.
```

**Release notes for version 1.0.0** (max 500):
```
First release of GameAll Venue: bookings and calendar, memberships, coaching, finance and reports, staff access controls, and notifications for bookings and payments.
```

**Category:** Business (alternative: Sports). **Tags:** pick Business tools / Productivity if offered.

**Contact details**
- Email: `admin@gameall.co`
- Website: `https://gameall.co`
- Phone: `9360428761`

**Graphics to prepare**
- App icon 512 x 512 PNG (the GameAll logo on white).
- Feature graphic 1024 x 500 PNG: the logo, the name "GameAll Venue" and the line "Run your venue from your phone".
- Phone screenshots, 2 to 8, 16:9 or 9:16, at least 320 px on the short side. Suggested order: Today dashboard, Calendar, a booking, Memberships list, Coaching, Finance, Reports, Profile. Use a demo venue with realistic data and no real customers' names or numbers.

**Do not put in the listing or screenshots:** plan names, prices, "free trial", "upgrade", "buy", or any link to buy a plan on the website. Google's payments policy forbids steering people to another payment method from the app and its listing.

---

## Part 4 — Reviewer account

Google's reviewers cannot receive the phone-call code, so give them a ready-made login:
1. On the web (`club.gameall.co`) or in the app, sign up with an email and phone you control, and finish setup: a venue with a few courts, sports, prices and operating hours.
2. Add demo data: a membership plan, a member, a coaching program with a student, a guest booking.
3. Choose a password you can share. Do not reuse a personal one.
4. In Play Console → App content → App access, enter that email and password and explain that sign-up needs a phone-call code.
5. Keep the account working while the app is in review.
