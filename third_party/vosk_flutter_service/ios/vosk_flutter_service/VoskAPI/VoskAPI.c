// This translation unit exists only because SwiftPM (tools version 5.9) does
// not support header-only Clang targets.
//
// The Vosk implementation is provided by the `Vosk` binary target
// (Frameworks/vosk.xcframework). This target re-exports the public C API to
// Swift through include/vosk_api.h, so plugin code can `import VoskAPI`.
#include "vosk_api.h"
