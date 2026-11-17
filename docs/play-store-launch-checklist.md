# Play Store launch checklist — GameAll Venue and GameAll Play

Status on **14 Nov 2026**. Nobody can promise Google's approval, but these are the things that decide it. Tick them in this order. Items marked **YOU** can only be done by the account owner (Play Console, Supabase dashboard, keys); everything else is already in the code.

## A. Blockers — do these first

| # | What | Who | Why it matters |
|---|---|---|---|
| 1 | Set `PLAYER_OTP_REQUIRED=true` on the Supabase project and keep the SMS hook function deployed | **YOU** | Without it GameAll Play signs anyone in with just a mobile number (no code). It is a data-protection problem and a Play "user data" risk. |
| 2 | Add a reviewer **test phone number + fixed code** in Supabase (Auth → Phone → test numbers), and a reviewer login for the Venue app | **YOU** | A reviewer who cannot sign in rejects the app ("app access"). Details: `play-store-player-submission.md` Part 4, `play-store-submission.md` Part 4. |
| 3 | Deploy BOTH websites so the legal pages are live: the club site (`https://club.gameall.co/privacy`, `/terms`, `/refund-policy`, `/delete-account`) for GameAll Venue, and the Play site (`https://play.gameall.co/privacy`, `/terms`, `/refund-policy`, `/delete-account`, from `player_appweb`, with `player_app	ooldeploy-web.ps1 -Prod`) for GameAll Play | **YOU** | Google opens the privacy-policy and deletion URLs. A 404 is an automatic rejection. |
| 4 | Create the **upload keys** (one per app), outside OneDrive, and back them up | **YOU** | A bundle signed with the debug key is rejected. Steps: `play-store-release.md` and `play-store-player-release.md`. |
| 5 | Apply migrations through `0203` and deploy the changed functions: `verify-player-payment`, `create-player-booking-payment-link`, `create-player-coaching-billing`, `sync-player-payment`, `delete-account` | **YOU** | Payment sheet and player account deletion depend on them. |
| 6 | Razorpay: live keys, webhook URL and secret set; keep **test mode** for the review build or tell the reviewer to stop at the pay sheet | **YOU** | Reviewers must never be asked to pay real money. |

## B. Play Console account and the closed-test rule

- **Personal** developer accounts created after November 2023 must run a **closed test with at least 12 testers for 14 continuous days** before they can apply for production. **Organisation** accounts (with a D-U-N-S number) are exempt. If yours is personal, start the closed test the day the account is verified, for both apps: this is the main thing that decides whether a one-month launch is possible.
- Identity verification (and, for organisations, D-U-N-S) can take days: start it now.
- Fill in for each app: Store listing, Content rating, Target audience (18+), Data safety, App access, Ads (none), Financial features, Government/News/Health (no), Privacy policy URL, Account deletion URL. The exact answers are in `play-store-submission.md` (Venue) and `play-store-player-submission.md` (Play).
- Upload the **.aab** (not an APK). After a successful review the first review usually takes a few days; changes to the policy forms can add days.

## C. What is already done in the code

- **Legal pages, one set per app:** GameAll Venue at `club.gameall.co`, GameAll Play at `play.gameall.co` (static pages in `player_app/web`). Each has the Privacy Policy, Terms & Conditions, Cancellation & Refund Policy and Delete account, covering payments, location, retention and deletion.
- **Linked from inside both apps**: Venue → Profile (Privacy, Terms, Delete account) and sign-up; Play → sign-in screen (Terms, Privacy) and Profile → Support & Legal (Terms, Privacy, Refunds, Delete my account).
- **In-app account deletion in both apps** (typed confirmation, server-side delete, cancels Auto Pay) and a public web page. For players it now also cancels the player's own Auto Pay mandates (migration `0203`).
- **Release signing** for both apps from `android/key.properties` (Play app added); the Venue app also shrinks and obfuscates; both use `tool/build-release.ps1`.
- **No cloud backup** of the signed-in session (`allowBackup=false` + data-extraction rules) in both apps.
- **Permissions**: Venue — internet, notifications. Play — internet, notifications, *approximate* location (optional). Precise location removed.
- **Payments**: in-app Razorpay checkout (UPI apps listed on the phone) for bookings and Auto Pay; payments verified on the server (signature + Razorpay lookup) with the webhook as backup. Court time, coaching and memberships are physical services, so Google Play billing is not required. Neither app sells a digital good or a venue plan.
- **Security fixes**: `npm audit fix` applied (the critical Next.js advisory and the other high-severity web packages except `zod` and `postcss`, which need a major upgrade; neither ships in the Android apps).

## D. Known, accepted items (not blockers)

- `zod` (website only): high advisory about very large arrays; our inputs are small. Upgrade to zod 4 when convenient.
- `exceljs`→`uuid` and the nested `postcss` (website only): no fix without a breaking change.
- The Play app's R8 shrinking is **not** enabled (the Venue app has it). Play does not require it; enabling it should be done together with a test of the payment sheet on a phone.
- `download-transaction-receipt` fails a strict `deno check` on a type that newer Deno made stricter; it deploys and runs.
- Google's forms use their own wording; map the meaning of each answer in the two submission documents.

## E. Before each release

1. `flutter analyze` and `flutter test` in `mobile/` and `player_app/`; `npx tsc --noEmit`, `npm test` for the web; `deno test supabase/functions/_shared`.
2. Raise the version code in `pubspec.yaml` (`+N`).
3. Build with the script, install the signed build on a phone, run the checks in `play-store-player-release.md` §4 (and the Venue equivalent).
4. Upload to **Closed testing**, then **Production** only when the closed test is clean.

## F. Likely reasons Google says no, and where each is handled

| Reason | Where |
|---|---|
| Reviewer cannot sign in | A2 |
| Privacy-policy or deletion URL missing or not matching the app | A3, C |
| Data-safety form does not match what the app does | the two submission documents |
| No way to delete the account in the app | C |
| Permissions not justified | C; approximate location only, explained in the manifest and the listing |
| Misleading listing / mentions plans or prices (Venue) | `play-store-submission.md` Part 3 |
| Crashes on launch | E3, Crashlytics (Venue) |
| Payments policy | C — physical services only |
