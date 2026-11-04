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
  static const String _kTimerDurationSeconds =
      'charging_timer_duration_seconds';
  static const String _kChargingBrightness = 'charging_brightness';
  static const String _kShakeTorchEnabled = 'shake_torch_enabled';
  static const String _kShakeThreshold = 'shake_threshold';
  static const String _kTorchBrightness = 'torch_brightness';
  static const String _kHasCompletedOnboarding = 'has_completed_onboarding';

  // Essential Key Remapper
  static const String _kEssentialKeyRemapEnabled =
      'essential_key_remap_enabled';
  static const String _kEssentialKeyCode = 'essential_key_code';
  static const String _kEssentialScanCode = 'essential_scan_code';
  static const String _kEssentialKeyName = 'essential_key_name';
  static const String _kEssentialPackagesDisabled =
      'essential_packages_disabled';
  static const String _kSinglePressAction = 'essential_action_single_press';
  static const String _kDoublePressAction = 'essential_action_double_press';
  static const String _kTriplePressAction = 'essential_action_triple_press';
  static const String _kLongPressAction = 'essential_action_long_press';
  static const String _kMultiPressGapMs = 'essential_timing_multi_press_gap_ms';
  static const String _kLongPressHoldMs =
      'essential_timing_long_press_hold_ms';

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
      _kEssentialKeyRemapEnabled: isEssentialKeyRemapEnabled,
      _kEssentialKeyCode: essentialKeyCode,
      _kSinglePressAction: singlePressAction,
      _kDoublePressAction: doublePressAction,
      _kTriplePressAction: triplePressAction,
      _kLongPressAction: longPressAction,
      _kMultiPressGapMs: multiPressGapMs,
      _kLongPressHoldMs: longPressHoldMs,
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
    final res =
        await _prefs?.setStringList(_kSelectedArcs, arcs.toList()) ?? false;
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

  int get timerDurationSeconds => _prefs?.getInt(_kTimerDurationSeconds) ?? 3;

  Future<bool> setTimerDurationSeconds(int seconds) async {
    final res = await _prefs?.setInt(_kTimerDurationSeconds, seconds) ?? false;
    syncToNative();
    return res;
  }

  int get chargingBrightness => _prefs?.getInt(_kChargingBrightness) ?? 4000;

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

  double get shakeThreshold => _prefs?.getDouble(_kShakeThreshold) ?? 2.0;

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

  // --- Essential Key Remapper Settings ---

  bool get isEssentialKeyRemapEnabled =>
      _prefs?.getBool(_kEssentialKeyRemapEnabled) ?? false;

  Future<bool> setEssentialKeyRemapEnabled(bool value) async {
    return await _prefs?.setBool(_kEssentialKeyRemapEnabled, value) ?? false;
  }

  int? get essentialKeyCode => _prefs?.getInt(_kEssentialKeyCode);

  Future<bool> setEssentialKeyCode(int? code) async {
    if (code == null) {
      return await _prefs?.remove(_kEssentialKeyCode) ?? false;
    }
    return await _prefs?.setInt(_kEssentialKeyCode, code) ?? false;
  }

  int? get essentialScanCode => _prefs?.getInt(_kEssentialScanCode);

  Future<bool> setEssentialScanCode(int? code) async {
    if (code == null) {
      return await _prefs?.remove(_kEssentialScanCode) ?? false;
    }
    return await _prefs?.setInt(_kEssentialScanCode, code) ?? false;
  }

  String? get essentialKeyName => _prefs?.getString(_kEssentialKeyName);

  Future<bool> setEssentialKeyName(String? name) async {
    if (name == null) {
      return await _prefs?.remove(_kEssentialKeyName) ?? false;
    }
    return await _prefs?.setString(_kEssentialKeyName, name) ?? false;
  }

  bool get essentialPackagesDisabled =>
      _prefs?.getBool(_kEssentialPackagesDisabled) ?? false;

  Future<bool> setEssentialPackagesDisabled(bool value) async {
    return await _prefs?.setBool(_kEssentialPackagesDisabled, value) ?? false;
  }

  // Action assignments for triggers
  String get singlePressAction =>
      _prefs?.getString(_kSinglePressAction) ?? 'torch';

  Future<bool> setSinglePressAction(String action) async {
    final res = await _prefs?.setString(_kSinglePressAction, action) ?? false;
    syncToNative();
    return res;
  }

  String get doublePressAction =>
      _prefs?.getString(_kDoublePressAction) ?? 'calculator';

  Future<bool> setDoublePressAction(String action) async {
    final res = await _prefs?.setString(_kDoublePressAction, action) ?? false;
    syncToNative();
    return res;
  }

  String get triplePressAction =>
      _prefs?.getString(_kTriplePressAction) ?? 'ringer_mode';

  Future<bool> setTriplePressAction(String action) async {
    final res = await _prefs?.setString(_kTriplePressAction, action) ?? false;
    syncToNative();
    return res;
  }

  String get longPressAction =>
      _prefs?.getString(_kLongPressAction) ?? 'power_menu';

  Future<bool> setLongPressAction(String action) async {
    final res = await _prefs?.setString(_kLongPressAction, action) ?? false;
    syncToNative();
    return res;
  }

  // Timings: Gap between presses (200 - 800 ms, default 350)
  int get multiPressGapMs => _prefs?.getInt(_kMultiPressGapMs) ?? 350;

  Future<bool> setMultiPressGapMs(int ms) async {
    final res = await _prefs?.setInt(_kMultiPressGapMs, ms) ?? false;
    syncToNative();
    return res;
  }

  // Timings: Long press hold needed (300 - 2000 ms, default 500)
  int get longPressHoldMs => _prefs?.getInt(_kLongPressHoldMs) ?? 500;

  Future<bool> setLongPressHoldMs(int ms) async {
    final res = await _prefs?.setInt(_kLongPressHoldMs, ms) ?? false;
    syncToNative();
    return res;
  }
}
