# Captions run through whisper.cpp over dart:ffi, which resolves native symbols
# by name at runtime. R8 must not rename or strip Java/Kotlin native method
# declarations, because FFI and JNI lookups depend on those exact names.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
