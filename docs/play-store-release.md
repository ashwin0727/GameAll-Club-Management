# Releasing GameAll Venue to Google Play

Everything below is about the Android app in `mobile/`. Support contact for the listing: admin@gameall.co · gameall.co · 9360428761.

## 1. One-time: the upload key

Google signs the app users receive; you sign what you upload with an **upload key**. Create it once, **outside OneDrive** (a synced folder can lock or leak it):

```powershell
mkdir C:\Users\umash\keys
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore C:\Users\umash\keys\gameall-venue-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Choose a strong password and **store the .jks file and the password in two safe places**. If you lose them you must ask Google to reset the upload key.

Then copy `mobile/android/key.properties.example` to `mobile/android/key.properties` (it is git-ignored) and fill in the passwords and the `storeFile` path (forward slashes, e.g. `C:/Users/umash/keys/gameall-venue-upload.jks`). Without that file a release build is signed with the debug key and **Google Play will reject it**.

## 2. Build the bundle

One command builds the signed bundle and checks it:

```powershell
powershell -ExecutionPolicy Bypass -File mobile\tool\build-release.ps1
```

It copies the app to `C:\GameAllBuild\venue-src` and builds there. **Do not build inside the OneDrive folder**: OneDrive and editor file watchers lock Gradle's build folder and the build fails with "Unable to delete directory". The script finishes by printing the file to upload, for example `C:\GameAllBuild\GameAll-Venue-1.0.0+1.aab`, and stops with an error if the bundle is signed with the debug key.

It needs `mobile\env.json` (Supabase address and anon key; without it the app shows "Missing Supabase configuration") and `mobile\android\key.properties`.

Raise the version before every upload: `version: 1.0.0+1` in `mobile/pubspec.yaml`. The number after `+` (the version code) must be higher each time.

To make a build that includes the hidden "Send test crash" link (for checking Crashlytics only, never for upload), add `--dart-define=CRASH_TEST=true` to a `flutter build apk --release` run from the copy.

## 3. App name and package id

The app is **GameAll Venue**, package id **`gameall.venue`**. The id is permanent once published. It is registered in the Firebase project `gameall-tournament-management` (Android app `gameall.venue`), and its `google-services.json` is in `mobile/android/app/`. Keep that file in sync if you ever add another app to the project.

## 4. Before the first upload

- Run migrations through `0166` and deploy `delete-account`, `notification-worker`, `razorpay-webhook`, `create-plan-subscription`.
- Create a reviewer login with demo data (Play reviewers cannot receive the phone-call code). Enter it in Play Console → App content → App access.
- Fill in Data safety, Content rating, Target audience, Financial features. Privacy policy: `https://club.gameall.co/privacy`. Account deletion URL: `https://club.gameall.co/delete-account`.
- Crashlytics is enabled for the `gameall.venue` app in the Firebase console and has been verified with a test crash.

## 5. Plans on Android

The app never sells a plan (Google Play billing rules). A club created in the app starts a 90-day free trial automatically (`start_free_trial`, migration 0163); the plan is chosen and paid for on the web, where the trial carries over. The app only shows the plan's status.
