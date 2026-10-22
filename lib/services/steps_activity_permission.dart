import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Android 10+ physical activity — **no signing required** (unlike HealthKit).
class StepsActivityPermission {
  StepsActivityPermission._();

  static Future<PermissionStatus> status() async {
    if (!Platform.isAndroid) return PermissionStatus.granted;
    return Permission.activityRecognition.status;
  }

  static Future<bool> ensureGranted() async {
    if (!Platform.isAndroid) return true;
    var st = await Permission.activityRecognition.status;
    if (st.isGranted) return true;
    st = await Permission.activityRecognition.request();
    return st.isGranted;
  }

  static Future<void> openSettings() => openAppSettings();

  static String userMessage(PermissionStatus st) {
    if (st.isGranted) return '';
    if (st.isPermanentlyDenied) {
      return 'Physical activity permission is off. Open Settings to allow step tracking.';
    }
    return 'Allow physical activity so the phone can count your steps.';
  }
}
