# R8 rules for Barcode Deck release builds.
#
# The optimize configuration comes from proguard-android-optimize.txt
# (wired in app/build.gradle.kts). Room, Compose and CameraX ship their
# own consumer keep rules — nothing custom needed for them.
#
# --- ML Kit barcode scanning ---
# Known issue (googlesamples/mlkit#1001, #1007, #1018): the library's
# Firebase-component registrars and internal DI classes are not covered
# by its consumer rules, so R8 optimization strips them and
# BarcodeScanning.getClient() NPEs on a null internal registry.
# Confirmed-workaround rules from the issue thread:
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
