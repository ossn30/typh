import 'package:shared_preferences/shared_preferences.dart';
import 'glyph_service.dart';

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;

  // Keys
  static const String _kChargingEnabled = 'charging_animation_enabled';
  static const String _kSelectedArcs = 'charging_selected_arcs';
  static const String _kIsClockwise = 'charging_is_clockwise';
  static const String _kIsCombined = 'charging_is_combined';
  static const String _kIsDurationAlways = 'charging_is_duration_always';
  static const String _kTimerDurationSeconds = 'charging_timer_duration_seconds';
  static const String _kChargingBrightness = 'charging_brightness';
  static const String _kShakeTorchEnabled = 'shake_torch_enabled';
  static const String _kShakeThreshold = 'shake_threshold';
  static const String _kTorchBrightness = 'torch_brightness';
  static const String _kHasCompletedOnboarding = 'has_completed_onboarding';

  /// Whether user has completed the first-time setup screen
  bool get hasCompletedOnboarding =>
      _prefs?.getBool(_kHasCompletedOnboarding) ?? false;

  Future<bool> setHasCompletedOnboarding(bool completed) async {
    return await _prefs?.setBool(_kHasCompletedOnboarding, completed) ?? false;
  }

  /// Initialize SharedPreferences on app startup and sync with native background service
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    syncToNative();
  }

  Map<String, dynamic> toMap() {
    return {
      _kChargingEnabled: chargingAnimationEnabled,
      _kSelectedArcs: selectedArcs.toList(),
      _kIsClockwise: isClockwise,
      _kIsCombined: isCombinedProgress,
      _kIsDurationAlways: isDurationAlways,
      _kTimerDurationSeconds: timerDurationSeconds,
      _kChargingBrightness: chargingBrightness,
      _kShakeTorchEnabled: shakeTorchEnabled,
      _kShakeThreshold: shakeThreshold,
      _kTorchBrightness: torchBrightness,
    };
  }

  void syncToNative() {
    GlyphService.instance.syncBackgroundSettings(toMap()).catchError((_) {
      return false;
    });
  }

  // --- Charging Animation Settings ---

  bool get chargingAnimationEnabled =>
      _prefs?.getBool(_kChargingEnabled) ?? true;

  Future<bool> setChargingAnimationEnabled(bool value) async {
    final res = await _prefs?.setBool(_kChargingEnabled, value) ?? false;
    syncToNative();
    return res;
  }

  Set<String> get selectedArcs {
    final list = _prefs?.getStringList(_kSelectedArcs);
    if (list == null || list.isEmpty) {
      return {'C'};
    }
    return list.toSet();
  }

  Future<bool> setSelectedArcs(Set<String> arcs) async {
    final res = await _prefs?.setStringList(_kSelectedArcs, arcs.toList()) ?? false;
    syncToNative();
    return res;
  }

  bool get isClockwise => _prefs?.getBool(_kIsClockwise) ?? true;

  Future<bool> setIsClockwise(bool value) async {
    final res = await _prefs?.setBool(_kIsClockwise, value) ?? false;
    syncToNative();
    return res;
  }

  bool get isCombinedProgress => _prefs?.getBool(_kIsCombined) ?? true;

  Future<bool> setIsCombinedProgress(bool value) async {
    final res = await _prefs?.setBool(_kIsCombined, value) ?? false;
    syncToNative();
    return res;
  }

  bool get isDurationAlways => _prefs?.getBool(_kIsDurationAlways) ?? true;

  Future<bool> setIsDurationAlways(bool value) async {
    final res = await _prefs?.setBool(_kIsDurationAlways, value) ?? false;
    syncToNative();
    return res;
  }

  int get timerDurationSeconds =>
      _prefs?.getInt(_kTimerDurationSeconds) ?? 3;

  Future<bool> setTimerDurationSeconds(int seconds) async {
    final res = await _prefs?.setInt(_kTimerDurationSeconds, seconds) ?? false;
    syncToNative();
    return res;
  }

  int get chargingBrightness =>
      _prefs?.getInt(_kChargingBrightness) ?? 4000;

  Future<bool> setChargingBrightness(int brightness) async {
    final res = await _prefs?.setInt(_kChargingBrightness, brightness) ?? false;
    syncToNative();
    return res;
  }

  // --- Shake for Glyph Torch Settings ---

  bool get shakeTorchEnabled => _prefs?.getBool(_kShakeTorchEnabled) ?? false;

  Future<bool> setShakeTorchEnabled(bool value) async {
    final res = await _prefs?.setBool(_kShakeTorchEnabled, value) ?? false;
    syncToNative();
    return res;
  }

  double get shakeThreshold =>
      _prefs?.getDouble(_kShakeThreshold) ?? 2.0;

  Future<bool> setShakeThreshold(double threshold) async {
    final res = await _prefs?.setDouble(_kShakeThreshold, threshold) ?? false;
    syncToNative();
    return res;
  }

  int get torchBrightness => _prefs?.getInt(_kTorchBrightness) ?? 4000;

  Future<bool> setTorchBrightness(int brightness) async {
    final res = await _prefs?.setInt(_kTorchBrightness, brightness) ?? false;
    syncToNative();
    return res;
  }
}

