import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  bool _isRinging = false;

  Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;

    // Start playing ringtone
    try {
      await FlutterRingtonePlayer().stop(); // Ensure any previous ringtone is stopped
    } catch (_) {}
    
    // Safety check in case stop was called while awaiting
    if (!_isRinging) return;
    
    FlutterRingtonePlayer().playRingtone();

    // Start vibration
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(
        pattern: [500, 1000, 500, 1000],
        repeat: 0, // Repeat until stopped
      );
    }
  }

  void stopRinging() {
    _isRinging = false;

    // Stop ringtone and vibration regardless of internal state to be safe
    try {
      FlutterRingtonePlayer().stop();
      Vibration.cancel();
    } catch (_) {}
  }
}
