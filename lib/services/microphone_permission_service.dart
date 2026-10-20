import 'package:permission_handler/permission_handler.dart';

/// Abstraction over permission_handler for testability and to keep the UI free
/// of platform-specific permission branching.
abstract interface class MicrophonePermissionService {
  Future<bool> request();

  Future<bool> openSettings();
}

class PermissionHandlerMicrophonePermissionService
    implements MicrophonePermissionService {
  @override
  Future<bool> request() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
