import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as open_handler;
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  // Request all required permissions
  static Future<Map<String, bool>> requestAllPermissions() async {
    final permissions = <String, bool>{};

    // Skip permissions on Web
    if (kIsWeb) {
      return {'web': true};
    }

    // Phone permissions
    permissions['phone'] = await _requestPermission(Permission.phone);
    permissions['readCallLog'] = await _requestPermission(
      Permission.phone,
    ); // Phone group covers call log
    permissions['contacts'] = await _requestPermission(Permission.contacts);

    // Audio recording
    permissions['microphone'] = await _requestPermission(Permission.microphone);

    // Storage (for Android < 13)
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidVersion = await _getAndroidVersion();
      if (androidVersion < 13) {
        permissions['storage'] = await _requestPermission(Permission.storage);
      }
    }

    // Notifications (for Android 13+)
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidVersion = await _getAndroidVersion();
      if (androidVersion >= 13) {
        permissions['notification'] = await _requestPermission(
          Permission.notification,
        );
      }
    }

    return permissions;
  }

  // Request specific permission
  static Future<bool> _requestPermission(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }

  // Check if all critical permissions are granted
  static Future<bool> areAllPermissionsGranted() async {
    if (kIsWeb) return true;
    final phoneStatus = await Permission.phone.isGranted;
    // final callLogStatus = await Permission.callLog.isGranted; // Not avail, covered by phone
    final contactsStatus = await Permission.contacts.isGranted;
    final microPhoneStatus = await Permission.microphone.isGranted;

    return phoneStatus && contactsStatus && microPhoneStatus;
  }

  // Check specific permission
  static Future<bool> checkPermission(Permission permission) async {
    if (kIsWeb) return true;
    return await permission.isGranted;
  }

  // Open app settings
  static Future<void> openSystemSettings() async {
    await open_handler.openAppSettings();
  }

  // Get Android version (SDK level)
  static Future<int> _getAndroidVersion() async {
    // This is a simplified approach
    // In production, you might want to use platform channels for accurate version
    return 34; // Default to Android 14
  }

  // Check if app is default phone app (Android 9+)
  static Future<bool> isDefaultPhoneApp() async {
    if (kIsWeb) return false;
    // This would require platform channel implementation
    // For now, return true as a placeholder
    return true;
  }

  // Request to set as default phone app
  static Future<void> requestDefaultPhoneApp() async {
    if (kIsWeb) return;
    // This requires platform channel to call...
    // Placeholder for now
  }
}
