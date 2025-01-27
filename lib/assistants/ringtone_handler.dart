// lib/assistants/ringtone_handler.dart

import 'package:audioplayers/audioplayers.dart';

class RingtoneHandler {
  static final RingtoneHandler _instance = RingtoneHandler._internal();
  factory RingtoneHandler() => _instance;
  RingtoneHandler._internal() {
    _initAudioPlayer();
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  Future<void> _initAudioPlayer() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.setVolume(1.0);
  }

  Future<void> playRingtone() async {
    if (!_isPlaying) {
      try {
        // Reset the audio player state
        await _audioPlayer.stop();
        await _initAudioPlayer();

        _isPlaying = true;
        await _audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
      } catch (e) {
        print('Error playing ringtone: $e');
        _isPlaying = false;
        rethrow;
      }
    }
  }

  Future<void> stopRingtone() async {
    if (_isPlaying) {
      try {
        await _audioPlayer.stop();
        _isPlaying = false;
      } catch (e) {
        print('Error stopping ringtone: $e');
        rethrow;
      }
    }
  }

  Future<void> reset() async {
    await stopRingtone();
    _isPlaying = false;
    await _initAudioPlayer();
  }

  bool get isPlaying => _isPlaying;

  Future<void> dispose() async {
    await stopRingtone();
    await _audioPlayer.dispose();
  }
}