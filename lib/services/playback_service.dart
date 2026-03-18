import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class PlaybackService extends ChangeNotifier {
  static final PlaybackService _instance = PlaybackService._internal();
  factory PlaybackService() => _instance;
  PlaybackService._internal() {
    _player.onPositionChanged.listen((p) {
      _position = p;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _player.onPlayerStateChanged.listen((s) {
      _playerState = s;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) {
      _playerState = PlayerState.completed;
      _position = Duration.zero;
      notifyListeners();
    });

    // Configure audio context for playback
    // Configure audio context for playback
    _player.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {},
        ),
      ),
    );
  }

  final AudioPlayer _player = AudioPlayer();

  String? _currentlyPlayingPath;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  String? get currentlyPlayingPath => _currentlyPlayingPath;
  Duration get position => _position;
  Duration get duration => _duration;
  PlayerState get playerState => _playerState;
  bool get isPlaying => _playerState == PlayerState.playing;
  bool get isPaused => _playerState == PlayerState.paused;
  Stream<Duration> get positionStream => _player.onPositionChanged;

  Future<void> play(String filePath) async {
    try {
      if (!await File(filePath).exists()) {
        debugPrint('Error: File does not exist at $filePath');
        _currentlyPlayingPath = null;
        _playerState = PlayerState.stopped;
        notifyListeners();
        return;
      }

      if (_currentlyPlayingPath == filePath &&
          _playerState == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.stop();
        _currentlyPlayingPath = filePath;
        await _player.play(DeviceFileSource(filePath));
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      _playerState = PlayerState.stopped;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentlyPlayingPath = null;
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
