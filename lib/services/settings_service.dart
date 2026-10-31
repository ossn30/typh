import 'package:shared_preferences/shared_preferences.dart';

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

  /// Initialize SharedPreferences on app startup
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // --- Charging Animation Settings ---

  bool get chargingAnimationEnabled =>
      _prefs?.getBool(_kChargingEnabled) ?? true;

  Future<bool> setChargingAnimationEnabled(bool value) async {
    return await _prefs?.setBool(_kChargingEnabled, value) ?? false;
  }

  Set<String> get selectedArcs {
    final list = _prefs?.getStringList(_kSelectedArcs);
    if (list == null || list.isEmpty) {
      return {'C'};
    }
    return list.toSet();
  }

  Future<bool> setSelectedArcs(Set<String> arcs) async {
    return await _prefs?.setStringList(_kSelectedArcs, arcs.toList()) ?? false;
  }

  bool get isClockwise => _prefs?.getBool(_kIsClockwise) ?? true;

  Future<bool> setIsClockwise(bool value) async {
    return await _prefs?.setBool(_kIsClockwise, value) ?? false;
  }

  bool get isCombinedProgress => _prefs?.getBool(_kIsCombined) ?? true;

  Future<bool> setIsCombinedProgress(bool value) async {
    return await _prefs?.setBool(_kIsCombined, value) ?? false;
  }

  bool get isDurationAlways => _prefs?.getBool(_kIsDurationAlways) ?? true;

  Future<bool> setIsDurationAlways(bool value) async {
    return await _prefs?.setBool(_kIsDurationAlways, value) ?? false;
  }

  int get timerDurationSeconds =>
      _prefs?.getInt(_kTimerDurationSeconds) ?? 3;

  Future<bool> setTimerDurationSeconds(int seconds) async {
    return await _prefs?.setInt(_kTimerDurationSeconds, seconds) ?? false;
  }

  int get chargingBrightness =>
      _prefs?.getInt(_kChargingBrightness) ?? 4000;

  Future<bool> setChargingBrightness(int brightness) async {
    return await _prefs?.setInt(_kChargingBrightness, brightness) ?? false;
  }

  // --- Shake for Glyph Torch Settings ---

  bool get shakeTorchEnabled => _prefs?.getBool(_kShakeTorchEnabled) ?? false;

  Future<bool> setShakeTorchEnabled(bool value) async {
    return await _prefs?.setBool(_kShakeTorchEnabled, value) ?? false;
  }

  double get shakeThreshold =>
      _prefs?.getDouble(_kShakeThreshold) ?? 2.0;

  Future<bool> setShakeThreshold(double threshold) async {
    return await _prefs?.setDouble(_kShakeThreshold, threshold) ?? false;
  }

  int get torchBrightness => _prefs?.getInt(_kTorchBrightness) ?? 4000;

  Future<bool> setTorchBrightness(int brightness) async {
    return await _prefs?.setInt(_kTorchBrightness, brightness) ?? false;
  }
}

