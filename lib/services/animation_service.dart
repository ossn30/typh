import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/glyph_animation.dart';
import 'glyph_service.dart';

class AnimationService {
  AnimationService._();
  static final AnimationService instance = AnimationService._();

  final GlyphService _glyph = GlyphService.instance;

  final ValueNotifier<String?> currentPlayingIdNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);

  final Map<String, GlyphAnimation> _cachedAnimations = {};
  List<GlyphAnimation>? _indexAnimations;

  bool _isDisposed = false;
  int _playbackSessionId = 0;

  /// Load index of all available animations
  Future<List<GlyphAnimation>> loadAnimationsIndex() async {
    if (_indexAnimations != null) return _indexAnimations!;

    String? jsonStr;
    try {
      jsonStr = await rootBundle.loadString('assets/animations.json');
    } catch (_) {
      try {
        jsonStr =
            await rootBundle.loadString('assets/animations/animations.json');
      } catch (e) {
        debugPrint('Failed to load animations index: $e');
        return [];
      }
    }

    try {
      final List<dynamic> data = json.decode(jsonStr) as List<dynamic>;
      _indexAnimations = data
          .map((item) =>
              GlyphAnimation.fromIndexJson(item as Map<String, dynamic>))
          .toList();
      return _indexAnimations!;
    } catch (e) {
      debugPrint('Error parsing animations index: $e');
      return [];
    }
  }

  /// Load complete animation data with all frames
  Future<GlyphAnimation?> loadFullAnimation(GlyphAnimation meta) async {
    if (_cachedAnimations.containsKey(meta.id)) {
      return _cachedAnimations[meta.id];
    }

    try {
      final jsonStr = await rootBundle.loadString(meta.path);
      final Map<String, dynamic> data =
          json.decode(jsonStr) as Map<String, dynamic>;
      final fullAnim = GlyphAnimation.fromFullJson(
        data,
        path: meta.path,
        fallbackId: meta.id,
        fallbackName: meta.name,
        fallbackDescription: meta.description,
        fallbackIcon: meta.icon,
      );
      _cachedAnimations[meta.id] = fullAnim;
      return fullAnim;
    } catch (e) {
      debugPrint('Error loading full animation at ${meta.path}: $e');
      return null;
    }
  }

  /// Play an animation. If already playing, it will be stopped and the new one played.
  Future<void> playAnimation(GlyphAnimation meta) async {
    final full = await loadFullAnimation(meta);
    if (full == null || full.frames.isEmpty) return;

    // Increment session ID to cancel any in-flight playback loops
    _playbackSessionId++;
    final currentSession = _playbackSessionId;

    currentPlayingIdNotifier.value = full.id;
    isPlayingNotifier.value = true;

    _runPlaybackLoop(full, currentSession);
  }

  void _runPlaybackLoop(GlyphAnimation animation, int sessionId) async {
    while (!_isDisposed &&
        _playbackSessionId == sessionId &&
        isPlayingNotifier.value) {
      for (final frame in animation.frames) {
        if (_isDisposed ||
            _playbackSessionId != sessionId ||
            !isPlayingNotifier.value) {
          return;
        }

        await _glyph.setChannels(frame.channels, brightness: frame.brightness);

        final waitDuration = Duration(
          milliseconds: frame.durationMs.clamp(16, 5000),
        );
        await Future.delayed(waitDuration);
      }

      if (!animation.loop) {
        break;
      }
    }

    if (_playbackSessionId == sessionId) {
      stopAnimation();
    }
  }

  /// Stop current animation playback and turn off all lights
  Future<void> stopAnimation() async {
    _playbackSessionId++;
    currentPlayingIdNotifier.value = null;
    isPlayingNotifier.value = false;
    await _glyph.turnOffAll();
  }

  void dispose() {
    _isDisposed = true;
    stopAnimation();
  }
}

