-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**
-keep class notification.listener.service.** { *; }
-dontwarn notification.listener.service.**

# Google ML Kit Text Recognition
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google_mlkit_text_recognition.** { *; }
-dontwarn com.google_mlkit_text_recognition.**
