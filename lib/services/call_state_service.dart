import 'package:flutter/foundation.dart';
import 'package:phone_state/phone_state.dart';
import 'dart:async';
import '../models/call_record.dart';
import 'database_service.dart';
import 'crm_service.dart';
import 'native_call_service.dart';
import 'ringtone_service.dart';
import 'contact_service.dart';
import 'recording_service.dart';

// Call state enum
enum CallState { idle, dialing, ringing, active, disconnected }

/// Determined at the moment the call ends.
enum CallStatus { completed, missed, rejected, unknown }

class CallStateService extends ChangeNotifier {
  static final CallStateService _instance = CallStateService._internal();
  factory CallStateService() => _instance;
  CallStateService._internal();

  CallState _callState = CallState.idle;
  String? _phoneNumber;
  CallType? _callType;
  DateTime? _callStartTime;
  StreamSubscription<PhoneState>? _phoneStateSubscription;
  final NativeCallService _nativeCallService = NativeCallService();
  final RingtoneService _ringtoneService = RingtoneService();
  final ContactService _contactService = ContactService();
  final RecordingService _recordingService = RecordingService();
  final CRMService _crmService = CRMService();
  bool _isDefaultDialer = false;
  String? _callerName;

  // CRM context for tracking active call
  String? _clientType;
  String? _calledBy;
  String? _clientId;

  // --- Call status tracking ---
  bool _wasConnected = false;   // true once state hits 'active'
  bool _wasRejected  = false;   // true when native sends 'rejected'
  CallStatus _finalCallStatus = CallStatus.unknown;
  
  bool _isEndingCall = false;

  CallState get callState => _callState;
  String? get phoneNumber => _phoneNumber;
  String? get callerName => _callerName;
  CallType? get callType => _callType;
  DateTime? get callStartTime => _callStartTime;
  bool get isDefaultDialer => _isDefaultDialer;
  /// Returns the final status of the last call after it ends.
  CallStatus get finalCallStatus => _finalCallStatus;

  // Active means anything where the screen should be up
  bool get isCallActive =>
      _callState == CallState.active ||
      _callState == CallState.dialing ||
      _callState == CallState.ringing;

  Future<void> initialize() async {
    try {
      // Initialize contact service for name resolution in the background
      // Do not await this, as loading thousands of contacts can block UI/trigger ANR on some devices
      _contactService.initialize();

      // Initialize Native Call Service listeners
      _nativeCallService.onCallAdded = (number) {
        // Native call added (incoming or outgoing)
        // We do NOT set state here because we don't know if it's incoming or outgoing yet.
        // We wait for onCallStateChanged to tell us 'ringing' or 'dialing'.
        print('Native call added: $number');
      };

      _nativeCallService.onCallStateChanged = (number, stateStr) {
        _handleNativeStateChange(number, stateStr);
      };

      _nativeCallService.onCallRemoved = (number) {
        _handleCallEnded();
      };

      // Silence ringer event from native (Volume keys)
      _nativeCallService.onSilenceRinger = () {
        silenceIncomingRinger();
      };

      // Listen to phone state changes (backup/legacy)
      _phoneStateSubscription = PhoneState.stream.listen(
        (PhoneState state) {
          _handlePhoneStateChange(state);
        },
        onError: (error) {
          print('Error in phone state stream: $error');
        },
      );

      // Check initial default dialer status
      _isDefaultDialer = await _nativeCallService.isDefaultDialer();

      print('Call state monitoring initialized');
    } catch (e) {
      print('Error initializing call state service: $e');
    }
  }

  void _handleNativeStateChange(String number, String stateStr) {
    print('Native state change: $stateStr - $number');

    // Always ensure we have the latest number if available
    if (number.isNotEmpty && number != 'Unknown') {
      _phoneNumber = number;
    }

    // Map native state to our CallState
    // states: active, ringing, dialing, disconnected, holding
    switch (stateStr) {
      case 'dialing':
        if (_callState != CallState.dialing) {
          _callState = CallState.dialing;
          _callType = CallType.outgoing;
          // Reset status tracking for new call
          _wasConnected = false;
          _wasRejected  = false;
          _finalCallStatus = CallStatus.unknown;
          notifyListeners();
        }
        break;
      case 'ringing':
        if (_callState != CallState.ringing) {
          _handleIncomingCall(number);
        }
        break;
      case 'active':
        _handleCallStarted();
        break;
      case 'rejected':
        // Caller explicitly rejected before connecting
        _wasRejected = true;
        _handleCallEnded();
        break;
      case 'disconnected':
        _handleCallEnded();
        break;
    }
  }

  // Handle phone state changes
  void _handlePhoneStateChange(PhoneState phoneState) {
    print(
      'Phone state changed: ${phoneState.status} - Number: ${phoneState.number}',
    );

    switch (phoneState.status) {
      case PhoneStateStatus.NOTHING:
        if (_isDefaultDialer) {
           print('Ignoring PhoneState NOTHING because Native InCallService is authoritative.');
        } else {
           _handleCallEnded();
        }
        break;

      case PhoneStateStatus.CALL_INCOMING:
        _handleIncomingCall(phoneState.number);
        break;

      case PhoneStateStatus.CALL_STARTED:
        if (_isDefaultDialer) {
           print('Ignoring PhoneState CALL_STARTED because Native InCallService is authoritative. Waiting for real active connection.');
        } else {
           print('PhoneState reported CALL_STARTED - Waiting for Native Service active state');
           // FALLBACK: If NativeCallService fails to report 'active' (e.g. not set as default dialer),
           // we should at least capture the number and start time so we don't drop the log entirely.
           if (_callState == CallState.idle && phoneState.number != null && phoneState.number!.isNotEmpty) {
             _phoneNumber = phoneState.number;
             _callStartTime = DateTime.now();
             // We tentatively set to active to ensure _handleCallEnded processes it
             _callState = CallState.active; 
             _wasConnected = true; 
             print('FALLBACK: Forced active state for $_phoneNumber because NativeCallService binds failed');
           }
        }
        break;

      case PhoneStateStatus.CALL_ENDED:
        if (_isDefaultDialer) {
           print('Ignoring PhoneState CALL_ENDED because Native InCallService is authoritative. Waiting for Native disconnect event instead.');
        } else {
           _handleCallEnded();
        }
        break;

      case PhoneStateStatus.CALL_OUTGOING:
        print('PhoneState reported CALL_OUTGOING: ${phoneState.number}');
        if (_callState == CallState.idle && phoneState.number != null && phoneState.number!.isNotEmpty) {
           _phoneNumber = phoneState.number;
           _callType = CallType.outgoing;
        }
        break;
    }
  }

  // Handle incoming call
  void _handleIncomingCall(String? number) {
    // Prevent re-entry if already ringing or active
    // IMPORTANT: If we are already ringing, we just update info, do NOT restart ringtone
    if (_callState == CallState.ringing) {
      print('Incoming call update (already ringing): $number');
      return;
    }

    if (_callState == CallState.active || _callState == CallState.dialing) {
      return;
    }

    // 1. IMMEDIATE AUDIO TRIGGER (Optimistic)
    if (_isDefaultDialer) {
      _ringtoneService.startRinging();
    }

    _callState = CallState.ringing;
    _phoneNumber = number ?? 'Unknown';
    _callType = CallType.incoming;
    _callStartTime = null;
    // Reset status tracking for new incoming call
    _wasConnected = false;
    _finalCallStatus = CallStatus.unknown;
    
    // Note: If CRM intent data exists for incoming calls, it must be set here
    // or passed from the activity. Currently relying on global updates if available.

    notifyListeners();
    print('Incoming call from: $_phoneNumber');

    // 2. Resolve Name (Async) allows UI/Audio to start first
    if (number != null) {
      Future.microtask(() {
        final name = _contactService.getNameByNumber(number);
        // Only update calls if name is found and different
        if (name != null && name != _callerName) {
          _callerName = name;
          notifyListeners();
        }
      });
    } else {
      _callerName = null;
    }
  }

  // Handle call started (answered or outgoing connected)
  void _handleCallStarted() {
    if (_callState == CallState.active) return;

    _callState = CallState.active;
    _callStartTime = DateTime.now();
    _wasConnected = true; // Mark that a connection was established

    notifyListeners();
    print('Call started at: $_callStartTime');

    // Stop ringing
    _ringtoneService.stopRinging();

    // Auto-enable Speakerphone on connect
    _nativeCallService.toggleSpeaker(true);

    _checkAndStartAutoRecord();
  }

  Future<void> _checkAndStartAutoRecord() async {
    // STRICT CHECK: Only record if call is actually active/connected
    if (_callState != CallState.active) {
      print('Auto-record skipped: Call state is $_callState (not active)');
      return;
    }

    try {
      // Auto-record is now enforced by default for all calls
      const shouldRecord = true;
      if (shouldRecord && _phoneNumber != null) {
        print('Auto-recording STARTING for $_phoneNumber');
        await _recordingService.startRecording(
          phoneNumber: _phoneNumber!,
          callType: _callType ?? CallType.outgoing,
        );
      } else {
        print('Auto-recording SKIPPED (No Number)');
      }
    } catch (e) {
      print('Error checking auto-record: $e');
    }
  }

  // Handle call ended
  Future<void> _handleCallEnded() async {
    if (_isEndingCall || _callState == CallState.disconnected) {
      print('Call is already ending or disconnected. Ignoring duplicate call end event');
      return;
    }
    _isEndingCall = true;

    try {
      print('Call ended: $_phoneNumber (State was $_callState)');

      // 1. STOP AUDIO IMMEDIATELY
      _ringtoneService.stopRinging();

      if (_callState == CallState.idle) {
        _isEndingCall = false;
        return;
      }

    // 2. Determine final call status from transition flags
    if (_wasConnected) {
      _finalCallStatus = CallStatus.completed;
    } else if (_wasRejected) {
      _finalCallStatus = CallStatus.rejected;
    } else {
      // Disconnected without connecting and without explicit rejection → missed
      _finalCallStatus = CallStatus.missed;
    }
    print('Final call status: $_finalCallStatus');

    _callState = CallState.disconnected;
    notifyListeners();

    // End recording
    CallRecord? record;
    if (_recordingService.isRecording) {
      print('Stopping recording via service...');
      record = await _recordingService.stopRecording();
      if (record != null) {
        print('Recording service returned record with ID: ${record.id}');
        // INJECT missing CRM variables if the RecordingService dropped them
        record = record.copyWith(
           clientType: record.clientType ?? _clientType,
           calledBy: record.calledBy ?? _calledBy,
           clientId: record.clientId ?? _clientId,
        );
      } else {
        print('Recording service returned NULL record!');
      }
    } else {
      print('Recording service isNOTRecording flag was false.');
    }

    // If recording failed or was skipped but we have an active/finished call, we still log it.
    if (record == null && _phoneNumber != null && _phoneNumber!.isNotEmpty) {
      print('Creating provisional record without audio...');
      int duration = 0;
      if (_callStartTime != null) {
        duration = DateTime.now().difference(_callStartTime!).inSeconds;
      }
      
      final contactName = _callerName ?? _contactService.getNameByNumber(_phoneNumber!);
      
      final provisionalRecord = CallRecord(
        phoneNumber: _phoneNumber!,
        contactName: contactName,
        timestamp: _callStartTime ?? DateTime.now(),
        duration: duration,
        callType: _callType ?? CallType.outgoing,
        uploadStatus: UploadStatus.pending,
        clientType: _clientType,
        calledBy: _calledBy,
        clientId: _clientId,
        callStatus: _finalCallStatus.toString().split('.').last,
      );
      
      print('Inserting provisional record to DB...');
      try {
        final id = await DatabaseService().insertCallRecord(provisionalRecord);
        print('Provisional record inserted with ID: $id');
        record = provisionalRecord.copyWith(id: id);
      } catch (e) {
        print('Exception inserting provisional record: $e');
      }
    }

    if (record != null) {
      print('Updating DB with final status $_finalCallStatus...');
      // Update the callStatus to the final determined status
      final updatedRecord = record.copyWith(callStatus: _finalCallStatus.toString().split('.').last);
      await DatabaseService().updateCallRecord(updatedRecord);
      
      print('Triggering CRM autoUploadRecording...');
      // Auto-upload
      _crmService.autoUploadRecording(updatedRecord);
    } else {
      print('CRITICAL: record is null after end pipeline. No upload triggered!');
    }

    // Reset after a short delay
    print('[_handleCallEnded] Scheduling state reset after delay.');
    Future.delayed(const Duration(seconds: 1), () {
      _callState = CallState.idle;
      _phoneNumber = null;
      _callerName = null;
      _callType = null;
      _callStartTime = null;
      
      // Wipe CRM data cache to prevent leaking into next calls
      _clientType = null;
      _calledBy = null;
      _clientId = null;
      
      _isEndingCall = false; // Release the lock
      // Note: _finalCallStatus is intentionally NOT reset here so callers can read it after the call
      notifyListeners();
      print('[_handleCallEnded] State reset complete. Lock released.');
    });
    print('[_handleCallEnded] Exiting try block.');
  } catch (e) {
    print('[_handleCallEnded] Error during call ending: $e');
    _isEndingCall = false; // Ensure lock is released even on error
  }
  }

  // Manually set call info (for when making outgoing calls)
  void setOutgoingCall(String number, {String? contactName, String? clientType, String? calledBy, String? clientId}) {
    _callState = CallState.dialing;
    _phoneNumber = number;
    _callType = CallType.outgoing;
    _callStartTime = null;
    // Reset status tracking
    _wasConnected = false;
    _wasRejected  = false;
    _finalCallStatus = CallStatus.unknown;

    // Save CRM data locally for fallback if recording fails
    _callerName = contactName;
    _clientType = clientType;
    _calledBy = calledBy;
    _clientId = clientId;

    // Cache these for the recording service when it starts
    _recordingService.setCallMetadata(contactName: contactName, clientType: clientType, calledBy: calledBy, clientId: clientId);

    notifyListeners();
    print('Outgoing call to: $number (Dialing)');
  }

  // Get call duration
  Duration? getCallDuration() {
    if (_callStartTime != null && _callState == CallState.active) {
      return DateTime.now().difference(_callStartTime!);
    }
    return null;
  }

  // Update default dialer status
  void updateDefaultDialerStatus(bool isDefault) {
    if (_isDefaultDialer != isDefault) {
      _isDefaultDialer = isDefault;
      notifyListeners();
    }
  }

  // Silence the incoming ringer (e.g. volume button pressed)
  void silenceIncomingRinger() {
    if (_callState == CallState.ringing) {
      print('Silencing incoming ringer');
      _ringtoneService.stopRinging();
      // We do NOT change state, just stop audio.
    }
  }

  // Dispose
  @override
  void dispose() {
    _phoneStateSubscription?.cancel();
    _ringtoneService.stopRinging();
    super.dispose();
  }
}
