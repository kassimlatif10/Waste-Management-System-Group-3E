import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays in-app audio alerts — normal chime and loud collector alarm.
class SoundService {
  SoundService._();

  static final _player = AudioPlayer();
  static final _alarmPlayer = AudioPlayer();
  static bool _initialized = false;
  static Timer? _alarmStopTimer;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      // iOS: set audio session to playback so sounds are audible even when the
      // device ringer is muted, and use mixWithOthers so we don't interrupt
      // other apps (e.g. music). Without this, iOS defaults to soloAmbient
      // which gets silenced by the ringer switch.
      if (Platform.isIOS) {
        await AudioPlayer.global.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ));
      }
      await _player.setReleaseMode(ReleaseMode.stop);
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.setVolume(1.0);
      await _player.setVolume(1.0);
      _initialized = true;
    } catch (e) {
      debugPrint('SoundService init error: $e');
    }
  }

  /// Standard notification chime for customers and general alerts.
  static Future<void> playNotification() async {
    if (!_initialized) await initialize();
    try {
      await stopAlarm();
      await _player.stop();
      await _player.setVolume(0.9);
      await _player.play(AssetSource('sounds/notification.wav'));
    } catch (e) {
      debugPrint('SoundService play error: $e');
    }
  }

  /// Loud repeating alarm for new collector pickup requests.
  static Future<void> playCollectorAlarm({Duration duration = const Duration(seconds: 12)}) async {
    if (!_initialized) await initialize();
    try {
      await _player.stop();
      _alarmStopTimer?.cancel();
      await _alarmPlayer.stop();
      await _alarmPlayer.setVolume(1.0);
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.play(AssetSource('sounds/alarm.wav'));
      _alarmStopTimer = Timer(duration, stopAlarm);
    } catch (e) {
      debugPrint('SoundService alarm error: $e');
    }
  }

  /// Short alert — routes to normal notification sound.
  static Future<void> playAlert() => playNotification();

  static Future<void> stopAlarm() async {
    _alarmStopTimer?.cancel();
    _alarmStopTimer = null;
    try {
      await _alarmPlayer.stop();
    } catch (_) {}
  }

  static Future<void> stop() async {
    await stopAlarm();
    try {
      await _player.stop();
    } catch (_) {}
  }

  static void dispose() {
    _alarmStopTimer?.cancel();
    _player.dispose();
    _alarmPlayer.dispose();
    _initialized = false;
  }
}
