# Releasing GameAll Venue to Google Play

Everything below is about the Android app in `mobile/`. Support contact for the listing: admin@gameall.co · gameall.co · 9360428761.

## 1. One-time: the upload key

Google signs the app users receive; you sign what you upload with an **upload key**. Create it once, **outside OneDrive** (a synced folder can lock or leak it):

```powershell
mkdir C:\Users\umash\keys
keytool -genkey -v -keystore C:\Users\umash\keys\gameall-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Choose a strong password and **store the .jks file and the password in two safe places**. If you lose them you must ask Google to reset the upload key.

Then copy `mobile/android/key.properties.example` to `mobile/android/key.properties` (it is git-ignored) and fill in the passwords and the `storeFile` path. Without that file a release build is signed with the debug key and **Google Play will reject it**.

## 2. Build the bundle

```powershell
cd mobile
flutter build appbundle --release --dart-define-from-file=env.json
```

Upload `mobile/build/app/outputs/bundle/release/app-release.aab`. (`env.json` supplies the Supabase address and anon key; without it the app shows "Missing Supabase configuration".)

If Gradle says it cannot delete a folder, OneDrive is locking `mobile/build`: run `android\gradlew --stop`, delete `mobile/build`, and build again.

Raise the version before every upload: `version: 1.0.0+1` in `mobile/pubspec.yaml` — the number after `+` (the version code) must be higher each time.

## 3. App name and package id

The app is **GameAll Venue**, package id **`gameall.venue`**. The id is permanent once published. It is registered in the Firebase project `gameall-tournament-management` (Android app `gameall.venue`), and its `google-services.json` is in `mobile/android/app/`. Keep that file in sync if you ever add another app to the project.

## 4. Before the first upload

- Run migrations through `0163` and deploy `delete-account`, `notification-worker`, `razorpay-webhook`, `create-plan-subscription`.
- Create a reviewer login with demo data (Play reviewers cannot receive the phone-call code). Enter it in Play Console → App content → App access.
- Fill in Data safety, Content rating, Target audience, Financial features. Privacy policy: `https://club.gameall.co/privacy`. Account deletion URL: `https://club.gameall.co/delete-account`.
- Turn on Crashlytics in the Firebase console (Release & Monitor → Crashlytics).

## 5. Plans on Android

The app never sells a plan (Google Play billing rules). A club created in the app starts a 90-day free trial automatically (`start_free_trial`, migration 0163); the plan is chosen and paid for on the web, where the trial carries over. The app only shows the plan's status.
