import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/glyph_animation.dart';
import 'glyph_service.dart';

class AnimationService {
  AnimationService._();
  static final AnimationService instance = AnimationService._();

  final GlyphService _glyph = GlyphService.instance;

  final ValueNotifier<String?> currentPlayingIdNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);

  final ValueNotifier<List<GlyphAnimation>> customAnimationsNotifier =
      ValueNotifier<List<GlyphAnimation>>([]);

  final Map<String, GlyphAnimation> _cachedAnimations = {};
  List<GlyphAnimation>? _indexAnimations;
  List<GlyphAnimation> _customAnimations = [];
  bool _customAnimationsLoaded = false;

  bool _isDisposed = false;
  int _playbackSessionId = 0;

  Future<File> _getCustomAnimationsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/custom_animations.json');
  }

  /// Load custom animations created by the user
  Future<List<GlyphAnimation>> loadCustomAnimations() async {
    if (_customAnimationsLoaded) return _customAnimations;
    try {
      final file = await _getCustomAnimationsFile();
      if (!await file.exists()) {
        _customAnimations = [];
        _customAnimationsLoaded = true;
        customAnimationsNotifier.value = [];
        return [];
      }
      final str = await file.readAsString();
      final List<dynamic> list = json.decode(str) as List<dynamic>;
      _customAnimations = list.map((item) {
        final map = item as Map<String, dynamic>;
        final anim = GlyphAnimation.fromFullJson(
          map,
          path: '',
          isCustom: true,
        );
        _cachedAnimations[anim.id] = anim;
        return anim;
      }).toList();
      _customAnimationsLoaded = true;
      customAnimationsNotifier.value = List.unmodifiable(_customAnimations);
      return _customAnimations;
    } catch (e) {
      debugPrint('Error loading custom animations: $e');
      return [];
    }
  }

  /// Save or update a custom animation
  Future<bool> saveCustomAnimation(GlyphAnimation animation) async {
    try {
      final customAnim = animation.copyWith(isCustom: true);
      _cachedAnimations[customAnim.id] = customAnim;
      _customAnimations.removeWhere((a) => a.id == customAnim.id);
      _customAnimations.insert(0, customAnim);
      customAnimationsNotifier.value = List.unmodifiable(_customAnimations);

      final file = await _getCustomAnimationsFile();
      final jsonList = _customAnimations.map((a) => a.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
      return true;
    } catch (e) {
      debugPrint('Error saving custom animation: $e');
      return false;
    }
  }

  /// Delete a custom animation
  Future<bool> deleteCustomAnimation(String id) async {
    try {
      if (currentPlayingIdNotifier.value == id) {
        await stopAnimation();
      }
      _cachedAnimations.remove(id);
      _customAnimations.removeWhere((a) => a.id == id);
      customAnimationsNotifier.value = List.unmodifiable(_customAnimations);

      final file = await _getCustomAnimationsFile();
      final jsonList = _customAnimations.map((a) => a.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
      return true;
    } catch (e) {
      debugPrint('Error deleting custom animation: $e');
      return false;
    }
  }

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
    if (meta.frames.isNotEmpty) {
      _cachedAnimations[meta.id] = meta;
      return meta;
    }
    if (_cachedAnimations.containsKey(meta.id)) {
      return _cachedAnimations[meta.id];
    }
    if (meta.isCustom) {
      final custom = _customAnimations.firstWhere(
        (a) => a.id == meta.id,
        orElse: () => meta,
      );
      if (custom.frames.isNotEmpty) {
        _cachedAnimations[meta.id] = custom;
        return custom;
      }
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
        isCustom: false,
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

    // Increment session ID to cancel any in-flight playback sessions
    _playbackSessionId++;
    final currentSession = _playbackSessionId;

    currentPlayingIdNotifier.value = full.id;
    isPlayingNotifier.value = true;

    final framesData = full.frames
        .map((f) => {
              'durationMs': f.durationMs,
              'channels': f.channels.toList(),
              'brightness': f.brightness,
            })
        .toList();

    // Trigger native execution on dedicated high-priority thread for silky smooth playback
    final nativeStarted = await _glyph.playAnimationSequence(
      framesData,
      loop: full.loop,
    );

    if (nativeStarted) {
      if (!full.loop) {
        final totalDurationMs = full.frames.fold<int>(
          0,
          (sum, f) => sum + f.durationMs,
        );
        Future.delayed(Duration(milliseconds: totalDurationMs), () {
          if (_playbackSessionId == currentSession && isPlayingNotifier.value) {
            stopAnimation();
          }
        });
      }
      return;
    }

    // Drift-compensating fallback in Dart using renderFrame
    _runPlaybackLoopDart(full, currentSession);
  }

  void _runPlaybackLoopDart(GlyphAnimation animation, int sessionId) async {
    while (!_isDisposed &&
        _playbackSessionId == sessionId &&
        isPlayingNotifier.value) {
      for (final frame in animation.frames) {
        if (_isDisposed ||
            _playbackSessionId != sessionId ||
            !isPlayingNotifier.value) {
          return;
        }

        // Fire-and-forget renderFrame without await or notifying UI listeners
        _glyph.renderFrame(frame.channels, brightness: frame.brightness);

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
    await _glyph.stopAnimationSequence();
  }

  void dispose() {
    _isDisposed = true;
    stopAnimation();
  }
}

