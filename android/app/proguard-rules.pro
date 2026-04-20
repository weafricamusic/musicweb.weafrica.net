# Project-specific ProGuard/R8 rules for Android release builds.
# Flutter and most plugins ship their own keep rules; keep this file minimal.

# Keep annotations (often used by Firebase/AndroidX).
-keepattributes *Annotation*

# Avoid stripping exceptions line info too aggressively (helps crash reports).
-keepattributes SourceFile,LineNumberTable
