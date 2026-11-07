import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GlyphDeviceStatus {
  final bool isPhone3a;
  final String deviceModel;
  final String manufacturer;
  final String deviceTarget;
  final bool isServiceConnected;
  final bool isSessionOpened;

  const GlyphDeviceStatus({
    this.isPhone3a = false,
    this.deviceModel = 'Unknown',
    this.manufacturer = 'Unknown',
    this.deviceTarget = 'A059',
    this.isServiceConnected = false,
    this.isSessionOpened = false,
  });

  factory GlyphDeviceStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const GlyphDeviceStatus();
    return GlyphDeviceStatus(
      isPhone3a: map['isPhone3a'] as bool? ?? false,
      deviceModel: map['deviceModel'] as String? ?? 'Unknown',
      manufacturer: map['manufacturer'] as String? ?? 'Unknown',
      deviceTarget: map['deviceTarget'] as String? ?? 'A059',
      isServiceConnected: map['isServiceConnected'] as bool? ?? false,
      isSessionOpened: map['isSessionOpened'] as bool? ?? false,
    );
  }
}

class BatteryStatus {
  final bool isCharging;
  final int level; // 0 to 100

  const BatteryStatus({this.isCharging = false, this.level = 0});

  factory BatteryStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const BatteryStatus();
    return BatteryStatus(
      isCharging: map['isCharging'] as bool? ?? false,
      level: (map['batteryLevel'] as int?) ?? (map['level'] as int? ?? 0),
    );
  }
}

class GlyphService {
  static const MethodChannel _channel = MethodChannel('com.nothing.glyph_3a');

  static final GlyphService instance = GlyphService._internal();
  GlyphService._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final ValueNotifier<GlyphDeviceStatus> statusNotifier =
      ValueNotifier<GlyphDeviceStatus>(const GlyphDeviceStatus());

  final ValueNotifier<BatteryStatus> batteryNotifier =
      ValueNotifier<BatteryStatus>(const BatteryStatus());

  final ValueNotifier<Set<int>> activeChannelsNotifier =
      ValueNotifier<Set<int>>(<int>{});

  final ValueNotifier<bool> isBusyNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isTorchOnNotifier = ValueNotifier<bool>(false);

  final StreamController<double> _shakeStreamController =
      StreamController<double>.broadcast();
  Stream<double> get onShakeDetected => _shakeStreamController.stream;

  final StreamController<Map<String, dynamic>> _hardwareKeyStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onHardwareKeyCaptured =>
      _hardwareKeyStreamController.stream;

  final StreamController<Map<String, dynamic>> _essentialKeyEventStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onEssentialKeyEvent =>
      _essentialKeyEventStreamController.stream;

  final StreamController<Map<String, dynamic>> _actionTriggeredStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onActionTriggered =>
      _actionTriggeredStreamController.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onStatusChanged') {
      final data = call.arguments as Map<dynamic, dynamic>?;
      statusNotifier.value = GlyphDeviceStatus.fromMap(data);
    } else if (call.method == 'onBatteryChanged') {
      final data = call.arguments as Map<dynamic, dynamic>?;
      batteryNotifier.value = BatteryStatus.fromMap(data);
    } else if (call.method == 'onShakeDetected') {
      final data = call.arguments as Map<dynamic, dynamic>?;
      final gForce = (data?['gForce'] as num?)?.toDouble() ?? 2.0;
      _shakeStreamController.add(gForce);
    } else if (call.method == 'onHardwareKeyCaptured') {
      final data = call.arguments as Map<dynamic, dynamic>?;
      if (data != null) {
        _hardwareKeyStreamController.add(Map<String, dynamic>.from(data));
      }
    } else if (call.method == 'onEssentialKeyEvent') {
      final data = call.arguments as Map<dynamic, dynamic>?;
      if (data != null) {
        _essentialKeyEventStreamController.add(Map<String, dynamic>.from(data));
      }
    } else if (call.method == 'onActionTriggered') {
      final data = call.arguments as Map<dynamic, dynamic>?;
      if (data != null) {
        _actionTriggeredStreamController.add(Map<String, dynamic>.from(data));
      }
    }
  }

  /// Initialize Glyph service connection and register for Phone (3a)
  Future<GlyphDeviceStatus> init() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'initGlyph',
      );
      final status = GlyphDeviceStatus.fromMap(res);
      statusNotifier.value = status;
      await getBatteryStatus();
      return status;
    } catch (e) {
      debugPrint('GlyphService init error: $e');
      return statusNotifier.value;
    }
  }

  /// Fetch updated battery status
  Future<BatteryStatus> getBatteryStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getBatteryStatus',
      );
      final status = BatteryStatus.fromMap(res);
      batteryNotifier.value = status;
      return status;
    } catch (e) {
      debugPrint('GlyphService getBatteryStatus error: $e');
      return batteryNotifier.value;
    }
  }

  /// Fetch updated device status
  Future<GlyphDeviceStatus> getDeviceStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceStatus',
      );
      final status = GlyphDeviceStatus.fromMap(res);
      statusNotifier.value = status;
      return status;
    } catch (e) {
      debugPrint('GlyphService getDeviceStatus error: $e');
      return statusNotifier.value;
    }
  }

  /// Set the active lights to an exact set of channel indices
  Future<bool> setChannels(Set<int> channels, {int brightness = 4000}) async {
    try {
      activeChannelsNotifier.value = Set<int>.from(channels);
      await _channel.invokeMethod('toggleChannels', {
        'channels': channels.toList(),
        'brightness': brightness,
      });
      return true;
    } catch (e) {
      debugPrint('GlyphService setChannels error: $e');
      return false;
    }
  }

  /// Fire-and-forget single frame rendering without notifying UI listeners
  void renderFrame(Set<int> channels, {int brightness = 4000}) {
    _channel
        .invokeMethod('toggleChannels', {
          'channels': channels.toList(),
          'brightness': brightness,
        })
        .catchError((e) {
          debugPrint('GlyphService renderFrame error: $e');
        });
  }

  /// Play a pre-compiled frame sequence on native Android thread for ultra-smooth 60fps playback
  Future<bool> playAnimationSequence(
    List<Map<String, dynamic>> frames, {
    bool loop = true,
  }) async {
    try {
      await _channel.invokeMethod('playAnimationSequence', {
        'frames': frames,
        'loop': loop,
      });
      return true;
    } catch (e) {
      debugPrint('GlyphService playAnimationSequence error: $e');
      return false;
    }
  }

  /// Stop any running native animation sequence and turn off lights
  Future<bool> stopAnimationSequence() async {
    try {
      activeChannelsNotifier.value = <int>{};
      await _channel.invokeMethod('stopAnimationSequence');
      return true;
    } catch (e) {
      debugPrint('GlyphService stopAnimationSequence error: $e');
      return false;
    }
  }

  /// Toggle a single channel on or off
  Future<bool> toggleChannel(int channelIndex, {int brightness = 4000}) async {
    final current = Set<int>.from(activeChannelsNotifier.value);
    if (current.contains(channelIndex)) {
      current.remove(channelIndex);
    } else {
      current.add(channelIndex);
    }
    return await setChannels(current, brightness: brightness);
  }

  /// Turn ONLY this single channel on (solo mode)
  Future<bool> soloChannel(int channelIndex, {int brightness = 4000}) async {
    final current = Set<int>.from(activeChannelsNotifier.value);
    if (current.length == 1 && current.contains(channelIndex)) {
      return await turnOffAll();
    }
    return await setChannels({channelIndex}, brightness: brightness);
  }

  /// Toggle or set a specific whole group ('A', 'B', 'C', or 'ALL')
  Future<bool> toggleGroup(String group) async {
    try {
      final upper = group.toUpperCase();
      Set<int> targetIndices;
      if (upper == 'A') {
        targetIndices = List.generate(11, (i) => 20 + i).toSet();
      } else if (upper == 'B') {
        targetIndices = List.generate(5, (i) => 31 + i).toSet();
      } else if (upper == 'C') {
        targetIndices = List.generate(20, (i) => i).toSet();
      } else {
        targetIndices = List.generate(36, (i) => i).toSet();
      }

      final current = activeChannelsNotifier.value;
      final allPresent = targetIndices.every((idx) => current.contains(idx));

      Set<int> next;
      if (allPresent) {
        next = current.difference(targetIndices);
      } else {
        next = current.union(targetIndices);
      }

      return await setChannels(next);
    } catch (e) {
      debugPrint('GlyphService toggleGroup error: $e');
      return false;
    }
  }

  /// Turn off all lights
  Future<bool> turnOffAll() async {
    try {
      activeChannelsNotifier.value = <int>{};
      isTorchOnNotifier.value = false;
      await _channel.invokeMethod('turnOff');
      return true;
    } catch (e) {
      debugPrint('GlyphService turnOffAll error: $e');
      return false;
    }
  }

  /// Turn torch on/off across all 36 channels
  Future<bool> setTorch(bool turnOn, {int brightness = 4000}) async {
    isTorchOnNotifier.value = turnOn;
    if (turnOn) {
      final allChannels = List.generate(36, (i) => i).toSet();
      return await setChannels(allChannels, brightness: brightness);
    } else {
      return await turnOffAll();
    }
  }

  /// Toggle torch on/off
  Future<bool> toggleTorch({int brightness = 4000}) async {
    return await setTorch(!isTorchOnNotifier.value, brightness: brightness);
  }

  /// Sync user settings to native Android background service so features
  /// keep working even when the app is closed or phone is restarted.
  Future<bool> syncBackgroundSettings(Map<String, dynamic> settings) async {
    try {
      await _channel.invokeMethod('syncBackgroundSettings', settings);
      return true;
    } catch (e) {
      debugPrint('GlyphService syncBackgroundSettings error: $e');
      return false;
    }
  }

  /// Query installed launchable applications from device
  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    try {
      final res = await _channel.invokeListMethod<dynamic>('getInstalledApps');
      if (res == null) return [];
      return res.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('GlyphService getInstalledApps error: $e');
      return [];
    }
  }

  /// Check if Notification Access permission is granted
  Future<bool> isNotificationAccessGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('isNotificationAccessGranted');
      return res ?? false;
    } catch (e) {
      debugPrint('GlyphService isNotificationAccessGranted error: $e');
      return false;
    }
  }

  /// Open Android System Settings for Notification Access
  Future<void> openNotificationAccessSettings() async {
    try {
      await _channel.invokeMethod('openNotificationAccessSettings');
    } catch (e) {
      debugPrint('GlyphService openNotificationAccessSettings error: $e');
    }
  }

  /// Open Android System Settings for Notification Sounds & App Notifications
  Future<void> openNotificationSoundSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSoundSettings');
    } catch (e) {
      debugPrint('GlyphService openNotificationSoundSettings error: $e');
    }
  }

  /// Sync notification alert animation rules to native NotificationListenerService
  Future<bool> syncNotificationRules(Map<String, dynamic> data) async {
    try {
      await _channel.invokeMethod('syncNotificationRules', data);
      return true;
    } catch (e) {
      debugPrint('GlyphService syncNotificationRules error: $e');
      return false;
    }
  }

  /// Enable or configure native accelerometer shake detection
  Future<bool> setShakeDetection({
    required bool enabled,
    double threshold = 2.0,
  }) async {
    try {
      await _channel.invokeMethod('setShakeDetection', {
        'enabled': enabled,
        'threshold': threshold,
      });
      return true;
    } catch (e) {
      debugPrint('GlyphService setShakeDetection error: $e');
      return false;
    }
  }

  /// Animate breathing effect on specific channels
  Future<bool> animateChannels(
    List<int> channels, {
    int period = 2000,
    int cycles = 3,
    int interval = 100,
  }) async {
    try {
      isBusyNotifier.value = true;
      await _channel.invokeMethod('animateChannels', {
        'channels': channels,
        'period': period,
        'cycles': cycles,
        'interval': interval,
      });
      return true;
    } catch (e) {
      debugPrint('GlyphService animateChannels error: $e');
      return false;
    } finally {
      isBusyNotifier.value = false;
    }
  }

  /// Display progress on the C-ring (0 - 100)
  Future<bool> displayProgress(int progress, {bool reverse = false}) async {
    try {
      await _channel.invokeMethod('displayProgress', {
        'progress': progress,
        'reverse': reverse,
      });
      return true;
    } catch (e) {
      debugPrint('GlyphService displayProgress error: $e');
      return false;
    }
  }

  /// Compute channels for charging animation based on percentage, selected arcs,
  /// direction, and whether to combine selected arcs into a single unified track.
  static Set<int> computeChargingChannels({
    required int percentage,
    required Set<String> selectedArcs,
    required bool isClockwise,
    bool isCombined = true,
  }) {
    if (selectedArcs.isEmpty) return <int>{};
    final Set<int> result = {};
    final pct = percentage.clamp(0, 100);

    // List segments for each arc in clockwise & anticlockwise directions:
    // Arc C (20 LEDs):
    //   CW: 0..19 (C1 bottom-left -> C20 top-right)
    //   ACW: 19..0 (C20 top-right -> C1 bottom-left)
    final arcCCw = List.generate(20, (i) => i);
    final arcCAcw = List.generate(20, (i) => 19 - i);

    final arcACw = List.generate(11, (i) => 20 + i);
    final arcAAcw = List.generate(11, (i) => 30 - i);

    // Arc B (5 LEDs):
    // CW: 31..35 (B1 bottom-right -> B5 top-left)
    // ACW: 35..31 (B5 top-left -> B1 bottom-right)
    final arcBCw = List.generate(5, (i) => 31 + i);
    final arcBAcw = List.generate(5, (i) => 35 - i);

    if (isCombined) {
      // COMBINED MODE:
      // Chains all selected arcs into a single sequential track
      final List<int> combinedTrack = [];
      if (isClockwise) {
        // Natural clockwise flow: Arc C (left arc) -> Arc A (top-right) -> Arc B (bottom-right)
        if (selectedArcs.contains('C')) combinedTrack.addAll(arcCCw);
        if (selectedArcs.contains('A')) combinedTrack.addAll(arcACw);
        if (selectedArcs.contains('B')) combinedTrack.addAll(arcBCw);
      } else {
        // Natural anticlockwise flow: Arc B (bottom-right) -> Arc A (top-right) -> Arc C (left arc)
        if (selectedArcs.contains('B')) combinedTrack.addAll(arcBAcw);
        if (selectedArcs.contains('A')) combinedTrack.addAll(arcAAcw);
        if (selectedArcs.contains('C')) combinedTrack.addAll(arcCAcw);
      }

      if (combinedTrack.isEmpty) return <int>{};
      final totalLeds = combinedTrack.length;
      final activeCount = ((totalLeds * pct) / 100).ceil();
      for (int i = 0; i < activeCount && i < totalLeds; i++) {
        result.add(combinedTrack[i]);
      }
    } else {
      // STANDALONE / PARALLEL MODE:
      // Each selected arc shows 0-100% progress simultaneously in parallel
      if (selectedArcs.contains('C')) {
        final count = ((20 * pct) / 100).ceil();
        final list = isClockwise ? arcCCw : arcCAcw;
        for (int i = 0; i < count && i < 20; i++) {
          result.add(list[i]);
        }
      }

      if (selectedArcs.contains('A')) {
        final count = ((11 * pct) / 100).ceil();
        final list = isClockwise ? arcACw : arcAAcw;
        for (int i = 0; i < count && i < 11; i++) {
          result.add(list[i]);
        }
      }

      if (selectedArcs.contains('B')) {
        final count = ((5 * pct) / 100).ceil();
        final list = isClockwise ? arcBCw : arcBAcw;
        for (int i = 0; i < count && i < 5; i++) {
          result.add(list[i]);
        }
      }
    }

    return result;
  }

  /// Close session on exit
  Future<void> closeSession() async {
    try {
      await _channel.invokeMethod('closeSession');
    } catch (e) {
      debugPrint('GlyphService closeSession error: $e');
    }
  }

  /// Check whether Nothing Phone (3a) Essential packages are disabled via ADB
  Future<Map<String, dynamic>> checkEssentialPackagesDisabled() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'checkEssentialPackagesDisabled',
      );
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('GlyphService checkEssentialPackagesDisabled error: $e');
    }
    return {
      'allDisabled': false,
      'recorderDisabled': false,
      'spaceDisabled': false,
    };
  }

  /// Start listening for hardware key events
  Future<bool> startHardwareKeyListening() async {
    try {
      final res =
          await _channel.invokeMethod<bool>('startHardwareKeyListening');
      return res ?? false;
    } catch (e) {
      debugPrint('GlyphService startHardwareKeyListening error: $e');
      return false;
    }
  }

  /// Stop listening for hardware key events
  Future<bool> stopHardwareKeyListening() async {
    try {
      final res = await _channel.invokeMethod<bool>('stopHardwareKeyListening');
      return res ?? false;
    } catch (e) {
      debugPrint('GlyphService stopHardwareKeyListening error: $e');
      return false;
    }
  }

  /// Execute an Essential Key action natively
  Future<Map<String, dynamic>> executeKeyAction(
    String action, [
    Map<String, dynamic>? params,
  ]) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'executeKeyAction',
        {'action': action, 'params': params ?? {}},
      );
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('GlyphService executeKeyAction error: $e');
    }
    return {'status': 'error'};
  }

  /// Set window / system brightness (0.0 to 1.0)
  Future<bool> setSystemBrightness(double brightness) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'setSystemBrightness',
        {'brightness': brightness.clamp(0.01, 1.0)},
      );
      return res ?? false;
    } catch (e) {
      debugPrint('GlyphService setSystemBrightness error: $e');
      return false;
    }
  }

  /// Get window / system brightness (0.0 to 1.0)
  Future<double> getSystemBrightness() async {
    try {
      final res = await _channel.invokeMethod<double>('getSystemBrightness');
      return res ?? 0.5;
    } catch (e) {
      debugPrint('GlyphService getSystemBrightness error: $e');
      return 0.5;
    }
  }

  /// Check whether GlyphAccessibilityService is running
  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final res =
          await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return res ?? false;
    } catch (e) {
      debugPrint('GlyphService isAccessibilityServiceEnabled error: $e');
      return false;
    }
  }

  /// Open Android Accessibility Settings
  Future<bool> openAccessibilitySettings() async {
    try {
      final res =
          await _channel.invokeMethod<bool>('openAccessibilitySettings');
      return res ?? false;
    } catch (e) {
      debugPrint('GlyphService openAccessibilitySettings error: $e');
      return false;
    }
  }

  /// Trigger preview of system-wide HUD overlay on screen
  Future<bool> showSystemHudOverlay({
    required String trigger,
    required String action,
    String? message,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('showSystemHudOverlay', {
        'trigger': trigger,
        'action': action,
        'message': message,
      });
      return res ?? true;
    } catch (e) {
      debugPrint('GlyphService showSystemHudOverlay error: $e');
      return false;
    }
  }
}
