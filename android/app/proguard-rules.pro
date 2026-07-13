# R8 strips classes it can't see being used. These are all reached reflectively
# or from native code, so they have to be kept explicitly or the release build
# crashes where the debug build works.

# flutter_local_notifications serialises its scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.errorprone.annotations.**

# Play Core is referenced by the Flutter engine's deferred-components support,
# which this app doesn't use.
-dontwarn com.google.android.play.core.**
