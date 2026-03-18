import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'dart:async';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/call_state_service.dart';
import '../services/recording_service.dart';

import '../services/native_call_service.dart';
import '../models/call_record.dart';
import '../widgets/incoming_call_overlay.dart';
import '../widgets/bouncing_button.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with TickerProviderStateMixin {
  final CallStateService _callStateService = CallStateService();
  final RecordingService _recordingService = RecordingService();
  final NativeCallService _nativeCallService = NativeCallService();


  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _autoRecord = false;
  bool _autoRecordTriggered = false;
  bool _isPopped = false;
  String? _callerName;

  @override
  void initState() {
    super.initState();
    _callStateService.addListener(_onCallStateChanged);
    _recordingService.addListener(_onRecordingStateChanged);

    // Listen for native audio state changes (from notification actions)
    _nativeCallService.onCallAudioStateChanged = (isMuted, isSpeakerOn) {
      if (mounted) {
        setState(() {
          _isMuted = isMuted;
          _isSpeakerOn = isSpeakerOn;
        });
      }
    };

    _loadSettings();
    _startDurationTimer();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoRecord = prefs.getBool('auto_record') ?? false;
    });
    // Check initial state in case we missed the transition
    _checkAutoRecord();
  }

  @override
  void dispose() {
    _callStateService.removeListener(_onCallStateChanged);
    _recordingService.removeListener(_onRecordingStateChanged);
    _nativeCallService.onCallAudioStateChanged = null; // Clean up listener
    _durationTimer?.cancel();
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!_callStateService.isCallActive && mounted) {
      // Call ended - handle cleanup
      _handleCallEnded();
    } else {
      // Check for state updates (e.g. dialing -> active)
      if (mounted) {
        setState(() {
          _callerName = _callStateService.callerName;
        });
      }
      _checkAutoRecord();
    }
  }

  void _checkAutoRecord() {
    // If call is active (connected), auto record is on, and we haven't started yet
    if (_callStateService.callState == CallState.active &&
        _autoRecord &&
        !_recordingService.isRecording &&
        !_autoRecordTriggered) {
      _autoRecordTriggered = true;
      _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final phoneNumber = _callStateService.phoneNumber ?? 'Unknown';
    final callType = _callStateService.callType ?? CallType.outgoing;

    final success = await _recordingService.startRecording(
      phoneNumber: phoneNumber,
      callType: callType,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Auto-recording started')));
    }
  }

  void _onRecordingStateChanged() {
    setState(() {}); // Rebuild to update recording button state
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_callStateService.callState == CallState.active) {
            // Get actual duration from start time to now
            final duration = _callStateService.getCallDuration();
            _callDuration = duration ?? Duration.zero;
          } else {
            // While dialing/ringing, keep it at zero
            _callDuration = Duration.zero;
          }
        });
      }
    });
  }

  Future<void> _handleCallEnded() async {
    if (_isPopped) return;
    _isPopped = true;

    // Do NOT stop the recording here! 
    // `CallStateService._handleCallEnded()` runs globally and handles stopping, 
    // saving to the DB, and uploading to CRM in the background. 
    // Waiting for the physical file write here causes the UI screen to freeze endlessly.

    // Navigate back with guard
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        } else if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_recordingService.isRecording) {
      // Stop recording
      final record = await _recordingService.stopRecording();
      if (record != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Recording saved')));
        }
      }
    } else {
      // Start recording
      final phoneNumber = _callStateService.phoneNumber ?? 'Unknown';
      final callType = _callStateService.callType ?? CallType.outgoing;

      final success = await _recordingService.startRecording(
        phoneNumber: phoneNumber,
        callType: callType,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recording started')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start recording')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  Future<void> _toggleMute() async {
    services.HapticFeedback.lightImpact();
    final newMuteState = !_isMuted;
    final success = await _nativeCallService.toggleMute(newMuteState);
    if (success) {
      setState(() {
        _isMuted = newMuteState;
      });
    }
  }

  Future<void> _toggleSpeaker() async {
    services.HapticFeedback.lightImpact();
    final newSpeakerState = !_isSpeakerOn;
    final success = await _nativeCallService.toggleSpeaker(newSpeakerState);
    if (success) {
      setState(() {
        _isSpeakerOn = newSpeakerState;
      });
    }
  }

  Future<void> _terminateCall() async {
    services.HapticFeedback.mediumImpact();
    // Trigger native end call
    final success = await _nativeCallService.endCall();
    if (!success && mounted) {
      // If native side says no call exists, force close the UI
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Call ended (Force close)')));
      _handleCallEnded();
    }
  }

  Future<void> _answerCall() async {
    services.HapticFeedback.mediumImpact();
    await _nativeCallService.answerCall();
    // State will update to 'active' via listener
  }

  Future<void> _rejectCall() async {
    services.HapticFeedback.mediumImpact();
    await _nativeCallService.rejectCall();
    // State will update to 'idle'/shared via listener
  }

  @override
  Widget build(BuildContext context) {
    final phoneNumber = _callStateService.phoneNumber ?? 'Unknown';
    final isRecording = _recordingService.isRecording;
    final callState = _callStateService.callState;

    // If incoming call (ringing), show the full-screen overlay
    if (callState == CallState.ringing) {
      return IncomingCallOverlay(
        callerName: _callerName ?? 'Unknown',
        phoneNumber: phoneNumber,
        onAnswer: _answerCall,
        onDecline: _rejectCall,
      );
    }

    String statusText;
    switch (callState) {
      case CallState.dialing:
        statusText = 'Dialing...';
        break;
      case CallState.ringing:
        statusText = 'Ringing...';
        break;
      case CallState.active:
        statusText = 'Connected';
        break;
      case CallState.disconnected:
        statusText = 'Ended';
        break;
      default:
        statusText = _callStateService.callType == CallType.incoming
            ? 'Incoming Call'
            : 'Outgoing Call';
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background with vibrant premium gradient or themed surface
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? null : Theme.of(context).scaffoldBackgroundColor,
              gradient: Theme.of(context).brightness == Brightness.dark
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F172A), // Deep Slate
                        Color(0xFF3B82F6), // Vibrant Blue
                        Color(0xFF1E1B4B), // Deep Indigo
                      ],
                      stops: [0.0, 0.5, 1.0],
                    )
                  : null,
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 48),

                // Recording indicator (Pill shape)
                if (isRecording)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _BlinkingRedDot(),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'RECORDING',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                const Spacer(flex: 1),

                // Contact Info (Glassmorphic Card)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 40,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                size: 54,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _callerName ?? phoneNumber,
                              style: TextStyle(
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                fontFamily: 'Inter',
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_callerName != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                phoneNumber,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 1.0,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 24),
                            // Status & Duration Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    statusText.toUpperCase(),
                                    style: TextStyle(
                                      color: callState == CallState.active
                                          ? Colors.greenAccent.shade400
                                          : Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.7) ?? Colors.black87,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  if (callState == CallState.active) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _formatDuration(_callDuration),
                                      style: TextStyle(
                                        color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Control Grid (Glassmorphic)
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.05) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.15) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildControlButton(
                            icon: _isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            label: 'Mute',
                            isActive: _isMuted,
                            onTap: _toggleMute,
                          ),
                          _buildControlButton(
                            icon: isRecording
                                ? Icons.stop_rounded
                                : Icons.fiber_manual_record_rounded,
                            label: 'Record',
                            isActive: isRecording,
                            activeColor: Colors.redAccent,
                            onTap: _toggleRecording,
                          ),
                          _buildControlButton(
                            icon: _isSpeakerOn
                                ? Icons.volume_up_rounded
                                : Icons.volume_down_rounded,
                            label: 'Speaker',
                            isActive: _isSpeakerOn,
                            onTap: _toggleSpeaker,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // End Call Button
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: BouncingButton(
                    onTap: _terminateCall,
                    scaleFactor: 0.9,
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.redAccent.shade400,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    final themeColor = activeColor ?? Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BouncingButton(
          onTap: onTap,
          scaleFactor: 0.85,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? themeColor.withValues(alpha: 0.2)
                  : Colors.transparent,
              border: Border.all(
                color: isActive
                    ? themeColor.withValues(alpha: 0.5)
                    : (isDark ? Colors.white.withValues(alpha: 0.2) : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? themeColor : (isDark ? Colors.white70 : Colors.black87),
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: isActive ? themeColor : (isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _BlinkingRedDot extends StatefulWidget {
  const _BlinkingRedDot();

  @override
  State<_BlinkingRedDot> createState() => _BlinkingRedDotState();
}

class _BlinkingRedDotState extends State<_BlinkingRedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.redAccent, blurRadius: 4, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}
