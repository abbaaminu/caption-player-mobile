# Vosk reaches its native library through JNA. JNA ships desktop-only code
# paths that reference java.awt, which does not exist on Android. R8 must not
# fail on those missing classes (they are never loaded on Android).
-dontwarn java.awt.**

# Keep every JNA class and member: Vosk resolves natives reflectively through
# JNA, so R8 cannot see those references and must not rename or strip them.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }

# Keep Vosk's JNI bridge and native method declarations.
-keep class org.vosk.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
