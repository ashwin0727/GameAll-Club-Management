# Releasing GameAll Play to Google Play

Everything below is about the Android app in `player_app/` (package id **`com.gameall.gameall_play`**, permanent once published). The Venue app is in `play-store-release.md`. Support contact for the listing: admin@gameall.co · gameall.co · 9360428761.

## 1. One-time: the upload key (a different one from the Venue app)

Create it **outside OneDrive**:

```powershell
mkdir C:\Users\umash\keys
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore C:\Users\umash\keys\gameall-play-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Store the `.jks` and its password in **two** safe places. Then copy `player_app/android/key.properties.example` to `player_app/android/key.properties` (git-ignored) and fill in the passwords and `storeFile` (forward slashes). Without that file the release build is signed with the debug key, which Google Play rejects.

Enrol in **Play App Signing** when you create the app in Play Console (the default): Google keeps the real signing key and you only keep the upload key.

## 2. Build the bundle

```powershell
powershell -ExecutionPolicy Bypass -File player_app\tool\build-release.ps1
```

It copies the app to `C:\GameAllBuild\player-src` (OneDrive locks Gradle's build folder, so never build inside OneDrive), builds the `.aab`, checks it is signed with your upload key and prints the file to upload: `C:\GameAllBuild\GameAll-Play-<version>.aab`. It needs `player_app\env.json` (Supabase address and anon key) and `player_app\android\app\google-services.json`.

Raise the version before every upload: `version: 1.0.0+1` in `player_app/pubspec.yaml`. The number after `+` must be higher each time.

## 3. Before the first upload

- Apply migrations through `0203` and deploy the functions the Player app uses: `create-player-booking`, `create-player-booking-payment-link`, `create-membership-subscription`, `create-player-coaching-billing`, `verify-player-payment`, `sync-player-payment`, `cancel-player-booking`, `delete-account`, `razorpay-webhook`, `player-login`, `notification-worker`.
- **Set `PLAYER_OTP_REQUIRED=true`** on the project (see Part 4 of `play-store-player-submission.md`) and add the reviewer test phone number.
- The Android app `com.gameall.gameall_play` is registered in the Firebase project and its `google-services.json` is in `player_app/android/app/` (it is, today).
- Razorpay: keys are the live ones for production; the webhook URL and secret are set and the events listed in `supabase/functions/razorpay-webhook/index.ts` are enabled.
- Fill in Data safety, Content rating, Target audience, App access exactly as in `play-store-player-submission.md`. Privacy policy `https://play.gameall.co/privacy`; account deletion URL `https://play.gameall.co/delete-account`.

## 4. Test it on a real phone before you upload

The release build, signed with your upload key, installed on a phone (`bundletool` or just the APK from `flutter build apk --release`):

1. Sign in with the reviewer number.
2. Book a court and pay in Razorpay test mode: the Razorpay sheet must show the phone's UPI apps; the success page must open.
3. Cancel that booking: the quote and the refund must match `/refund-policy`.
4. Join a membership with AutoPay; open Profile → Support & Legal and open Terms, Privacy, Refunds.
5. Delete the account (use a throwaway number).
