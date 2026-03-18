import 'package:flutter/services.dart';

class NativeCallService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.call_record/call_service',
  );

  // Singleton pattern
  static final NativeCallService _instance = NativeCallService._internal();
  factory NativeCallService() => _instance;
  NativeCallService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  // Callbacks
  Function(String number)? onCallAdded;
  Function(String number)? onCallRemoved;
  Function(String number, String state)? onCallStateChanged;
  Function(bool isMuted, bool isSpeakerOn)? onCallAudioStateChanged;
  Function(bool isDefault)? onDefaultDialerResult;
  VoidCallback? onSilenceRinger;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('NativeCallService received: ${call.method} args: ${call.arguments}');
    try {
      final args = (call.arguments as Map<dynamic, dynamic>?) ?? {};
      final phoneNumber = args['phoneNumber'] as String? ?? 'Unknown';

      switch (call.method) {
        case 'call_added':
          onCallAdded?.call(phoneNumber);
          break;
        case 'call_removed':
          onCallRemoved?.call(phoneNumber);
          break;
        case 'call_state_changed':
          final state = args['state'] as String? ?? 'unknown';
          onCallStateChanged?.call(phoneNumber, state);
          break;
        case 'call_audio_state_changed':
          final isMuted = args['isMuted'] as bool? ?? false;
          final isSpeakerOn = args['isSpeakerOn'] as bool? ?? false;
          onCallAudioStateChanged?.call(isMuted, isSpeakerOn);
          break;
        case 'default_dialer_result':
          final isDefault = args['isDefault'] as bool? ?? false;
          onDefaultDialerResult?.call(isDefault);
          break;
        case 'silence_ringer':
          onSilenceRinger?.call();
          break;
        default:
          print('Unknown method ${call.method}');
      }
    } catch (e) {
      print('Error handling method call: $e');
    }
  }

  // Public methods to interact with native
  Future<bool> answerCall() async {
    try {
      return await _channel.invokeMethod('answerCall');
    } catch (e) {
      print('Error answering call: $e');
      return false;
    }
  }

  Future<bool> rejectCall() async {
    try {
      return await _channel.invokeMethod('rejectCall');
    } catch (e) {
      print('Error rejecting call: $e');
      return false;
    }
  }

  Future<bool> endCall() async {
    try {
      return await _channel.invokeMethod('endCall');
    } catch (e) {
      print('Error ending call: $e');
      return false;
    }
  }

  Future<bool> toggleSpeaker(bool isOn) async {
    try {
      return await _channel.invokeMethod('toggleSpeaker', {'isOn': isOn});
    } catch (e) {
      print('Error toggling speaker: $e');
      return false;
    }
  }

  Future<bool> toggleMute(bool isMuted) async {
    try {
      return await _channel.invokeMethod('toggleMute', {'isMuted': isMuted});
    } catch (e) {
      print('Error toggling mute: $e');
      return false;
    }
  }

  Future<void> requestDefaultDialer() async {
    try {
      await _channel.invokeMethod('requestDefaultDialer');
    } catch (e) {
      print('Error requesting default dialer: $e');
    }
  }

  Future<bool> isDefaultDialer() async {
    try {
      return await _channel.invokeMethod('isDefaultDialer') ?? false;
    } catch (e) {
      print('Error checking default dialer: $e');
      return false;
    }
  }

  Future<bool> makeCall(String phoneNumber) async {
    try {
      return await _channel.invokeMethod('makeCall', {
        'phoneNumber': phoneNumber,
      });
    } catch (e) {
      print('Error making native call: $e');
      return false;
    }
  }

  Future<String?> getInitialNumber() async {
    try {
      return await _channel.invokeMethod('getInitialNumber');
    } catch (e) {
      print('Error getting initial number: $e');
      return null;
    }
  }

  /// Returns lead context passed from CRM app: lead_id, lead_name, contact_number, client_type, called_by
  Future<Map<String, String?>> getLeadData() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getLeadData');
      return {
        'lead_id': result?['lead_id'] as String?,
        'lead_name': result?['lead_name'] as String?,
        'contact_number': result?['contact_number'] as String?,
        'client_type': result?['client_type'] as String?,
        'called_by': result?['called_by'] as String?,
      };
    } catch (e) {
      print('Error getting lead data: $e');
      return {'lead_id': null, 'lead_name': null, 'contact_number': null, 'client_type': null, 'called_by': null};
    }
  }

  Future<void> clearLeadData() async {
    try {
      await _channel.invokeMethod('clearLeadData');
    } catch (e) {
      print('Error clearing lead data: $e');
    }
  }

  Future<List<dynamic>> getCallLogsBatch(int limit, int offset) async {
    try {
      return await _channel.invokeMethod('getCallLogs', {
            'limit': limit,
            'offset': offset,
          }) ??
          [];
    } catch (e) {
      print('Error getting call logs batch: $e');
      return [];
    }
  }

  Future<int> deleteCallLogs(List<String> ids) async {
    try {
      return await _channel.invokeMethod('deleteCallLogs', {'ids': ids}) ?? 0;
    } catch (e) {
      print('Error deleting call logs: $e');
      return 0;
    }
  }

  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      return await _channel.invokeMethod('isAccessibilityServiceEnabled') ??
          false;
    } catch (e) {
      print('Error checking accessibility service: $e');
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      print('Error opening accessibility settings: $e');
    }
  }

  Future<void> requestRole(String role) async {
    try {
      await _channel.invokeMethod('requestRole', {'role': role});
    } catch (e) {
      print('Error requesting role $role: $e');
    }
  }

  Future<void> openDefaultAppsSettings() async {
    try {
      await _channel.invokeMethod('openDefaultAppsSettings');
    } catch (e) {
      print('Error opening default apps settings: $e');
    }
  }

  Future<bool> startRecord(String path) async {
    try {
      return await _channel.invokeMethod('startRecord', {'path': path}) ??
          false;
    } catch (e) {
      print('Error starting native record: $e');
      return false;
    }
  }

  Future<bool> stopRecord() async {
    try {
      return await _channel.invokeMethod('stopRecord') ?? false;
    } catch (e) {
      print('Error stopping native record: $e');
      return false;
    }
  }
}
