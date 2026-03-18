// import 'package:record/record.dart'; // Removed legacy dependency
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'cache_manager.dart';
import 'database_service.dart';
import 'native_call_service.dart';
import 'contact_service.dart';
import '../models/call_record.dart';

// Enum for recording state
enum RecordingState { idle, recording, paused, stopped }

class RecordingService extends ChangeNotifier {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  // final AudioRecorder _recorder = AudioRecorder(); // Removed
  final CacheManager _cacheManager = CacheManager();
  final DatabaseService _dbService = DatabaseService();
  final NativeCallService _nativeCallService = NativeCallService();
  final ContactService _contactService = ContactService();

  RecordingState _state = RecordingState.idle;
  bool _isAccessibilityEnabled = false;

  RecordingState get state => _state;
  bool get isAccessibilityEnabled => _isAccessibilityEnabled;
  bool _enableSpeakerphoneOnRecord = true;

  bool get enableSpeakerphoneOnRecord => _enableSpeakerphoneOnRecord;

  void setEnableSpeakerphoneOnRecord(bool value) {
    _enableSpeakerphoneOnRecord = value;
    notifyListeners();
  }

  DateTime? _recordingStartTime;
  String? _currentPhoneNumber;
  CallType? _currentCallType;
  String? _currentFilePath;

  bool get isRecording => _state == RecordingState.recording;
  String? get currentFilePath => _currentFilePath;

  String? _clientName;
  String? _clientType;
  String? _calledBy;
  String? _clientId;

  void setCallMetadata({String? contactName, String? clientType, String? calledBy, String? clientId}) {
    _clientName = contactName;
    _clientType = clientType;
    _calledBy = calledBy;
    _clientId = clientId;
  }

  // Start recording
  Future<bool> startRecording({
    required String phoneNumber,
    required CallType callType,
  }) async {
    try {
      if (_state == RecordingState.recording) {
        debugPrint('Already recording');
        return false;
      }

      // Check permission
      // Permissions should be handled by PermissionService in main.dart or native service
      // We proceed optimistically or add a check via NativeCallService if needed.
      // For now, assuming granted as per app flow.

      // Generate file path
      _recordingStartTime = DateTime.now();
      _currentPhoneNumber = phoneNumber;
      _currentCallType = callType;
      _currentFilePath = await _cacheManager.getFilePath(
        phoneNumber,
        _recordingStartTime!,
      );

      // Configure recording settings - REMOVED (Handled natively)

      // Auto-enable speakerphone if configured
      if (_enableSpeakerphoneOnRecord) {
        // slight delay to ensure call is fully active and audio focus is settled
        await Future.delayed(const Duration(milliseconds: 500));
        await _nativeCallService.toggleSpeaker(true);
      }

      // Start recording natively
      final success = await _nativeCallService.startRecord(_currentFilePath!);

      if (!success) {
        throw Exception('Native recording failed to start');
      }

      _state = RecordingState.recording;
      notifyListeners();

      debugPrint('Recording started: $_currentFilePath');
      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _state = RecordingState.idle;
      notifyListeners();
      return false;
    }
  }

  // Stop recording and save to database
  Future<CallRecord?> stopRecording() async {
    if (_state != RecordingState.recording) {
      debugPrint('Not currently recording (State: $_state)');
      return null;
    }

    try {
      // Set state immediately to prevent multiple stop calls
      _state = RecordingState.stopped;
      notifyListeners();

      // Stop the recorder
      // final path = await _recorder.stop();
      final success = await _nativeCallService.stopRecord();

      // Since native recorder saves to the path we gave it, we use _currentFilePath
      final path = _currentFilePath;

      if (!success) {
        debugPrint(
          'Native recording stop return false, but file might still be there.',
        );
      }

      if (path == null ||
          _currentPhoneNumber == null ||
          _recordingStartTime == null) {
        debugPrint('Recording stopped but no file path available');
        _state = RecordingState.idle;
        notifyListeners();
        return null;
      }

      // Verify file exists and has size
      try {
        final file = File(path);
        if (await file.exists()) {
          final size = await file.length();
          debugPrint('Recording file saved. Path: $path, Size: $size bytes');
        } else {
          debugPrint('Recording file NOT found at $path');
        }
      } catch (e) {
        debugPrint('Error checking recording file: $e');
      }

      // Calculate duration
      final duration = DateTime.now()
          .difference(_recordingStartTime!)
          .inSeconds;

      // Lookup contact name, fallback to CRM populated _clientName if available
      final contactName = _clientName ?? _contactService.getNameByNumber(_currentPhoneNumber!);

      // Create call record
      final record = CallRecord(
        phoneNumber: _currentPhoneNumber!,
        contactName: contactName,
        timestamp: _recordingStartTime!,
        duration: duration,
        filePath: path,
        callType: _currentCallType ?? CallType.outgoing,
        uploadStatus: UploadStatus.pending,
        clientType: _clientType,
        calledBy: _calledBy,
        clientId: _clientId,
        callStatus: 'Unknown', // This will be updated by CallStateService later
      );

      // Save to database
      final id = await _dbService.insertCallRecord(record);
      final savedRecord = record.copyWith(id: id);

      // Reset state
      _state = RecordingState.stopped;
      _currentFilePath = null;
      _currentPhoneNumber = null;
      _recordingStartTime = null;
      _currentCallType = null;

      notifyListeners();

      debugPrint('Recording saved: ${savedRecord.filePath}');
      return savedRecord;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _state = RecordingState.idle;
      notifyListeners();
      return null;
    }
  }

  // Pause recording (NOT SUPPORTED NATIVELY YET)
  Future<void> pauseRecording() async {
    debugPrint('Pause recording not supported in native implementation yet');
  }

  // Resume recording (NOT SUPPORTED NATIVELY YET)
  Future<void> resumeRecording() async {
    debugPrint('Resume recording not supported in native implementation yet');
  }

  // Cancel recording without saving
  Future<void> cancelRecording() async {
    try {
      await _nativeCallService.stopRecord();

      // Delete the file if it exists
      if (_currentFilePath != null) {
        await _cacheManager.deleteFile(_currentFilePath!);
      }

      _state = RecordingState.idle;
      _currentFilePath = null;
      _currentPhoneNumber = null;
      _recordingStartTime = null;
      _currentCallType = null;

      notifyListeners();
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }

  // Get recording duration (while recording)
  Duration? getRecordingDuration() {
    if (_recordingStartTime != null && _state == RecordingState.recording) {
      return DateTime.now().difference(_recordingStartTime!);
    }
    return null;
  }

  // Update accessibility status
  Future<void> updateAccessibilityStatus() async {
    _isAccessibilityEnabled = await _nativeCallService
        .isAccessibilityServiceEnabled();
    notifyListeners();
  }

  // Open accessibility settings
  Future<void> openAccessibilitySettings() async {
    await _nativeCallService.openAccessibilitySettings();
  }

  // Dispose
  @override
  void dispose() {
    // _recorder.dispose();
    super.dispose();
  }
}
