# Shrink unused Java/Kotlin only — fitur OCR/kamera/Supabase tetap utuh.

# Play Core (deferred components) — not used, referenced by Flutter embedding
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ML Kit Text Recognition — optional script packs not bundled
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Camera / Play Services
-keep class androidx.camera.** { *; }
-keep class com.google.android.gms.common.** { *; }

# Flutter / plugins reflection
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.example.toko_kacamata_natan.** { *; }

# Supabase / OkHttp / Gson-style serializers
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
