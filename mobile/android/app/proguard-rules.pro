# R8 / ProGuard rules for the release build.
# Flutter's own rules are added automatically; these cover the plugins that use reflection or JavaScript bridges.

# ── Razorpay checkout (razorpay_flutter) ─────────────────────────────────────
-keepattributes *Annotation*
-keepattributes JavascriptInterface
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
# Razorpay's SDK references Google Pay classes it does not bundle.
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.**

# ── Firebase / Google Play services (messaging) ──────────────────────────────
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Keep line numbers in crash reports (de-obfuscated through the mapping file uploaded with the bundle) ──
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
