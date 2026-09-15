-keep class io.flutter.** { *; }
-keep class com.ryanheise.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Flutter deferred components reference Play Core, which we don't ship.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
