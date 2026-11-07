import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/key_action.dart';
import '../widgets/key_action_overlay.dart';
import 'glyph_service.dart';
import 'settings_service.dart';

class KeyActionService {
  KeyActionService._();
  static final KeyActionService instance = KeyActionService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final SettingsService _settings = SettingsService.instance;
  final GlyphService _glyph = GlyphService.instance;

  OverlayEntry? _currentOverlayEntry;
  StreamSubscription<Map<String, dynamic>>? _keyEventSub;
  StreamSubscription<Map<String, dynamic>>? _actionTriggeredSub;

  int _tapCount = 0;
  Timer? _multiTapTimer;
  Timer? _longPressTimer;
  bool _isKeyDown = false;
  bool _longPressFired = false;

  void init() {
    _keyEventSub?.cancel();
    _keyEventSub = _glyph.onEssentialKeyEvent.listen(_handleNativeKeyEvent);

    // Listen to native Accessibility Service trigger events so HUD overlay shows when app is open
    _actionTriggeredSub?.cancel();
    _actionTriggeredSub = _glyph.onActionTriggered.listen((data) {
      final actionId = data['action'] as String? ?? 'none';
      final trigger = data['trigger'] as String? ?? 'single_press';
      final action = KeyActions.findById(actionId);
      if (action.type != KeyActionType.none) {
        if (action.type == KeyActionType.torch) {
          _glyph.isTorchOnNotifier.value = !_glyph.isTorchOnNotifier.value;
        }
        showOverlay(
          action: action,
          triggerLabel: trigger.toUpperCase().replaceAll('_', ' '),
        );
      }
    });
  }

  void dispose() {
    _keyEventSub?.cancel();
    _actionTriggeredSub?.cancel();
    _multiTapTimer?.cancel();
    _longPressTimer?.cancel();
    _removeOverlay();
  }

  void _handleNativeKeyEvent(Map<String, dynamic> data) {
    if (!_settings.isEssentialKeyRemapEnabled) return;

    final actionType = data['action'] as String? ?? 'down';
    final repeatCount = data['repeatCount'] as int? ?? 0;
    final gapMs = _settings.multiPressGapMs;
    final holdMs = _settings.longPressHoldMs;

    if (actionType == 'down') {
      // Critical: Ignore key repeat events generated while holding down the button!
      if (repeatCount > 0) return;

      _isKeyDown = true;
      _longPressFired = false;
      _multiTapTimer?.cancel();

      // Start long-press detection
      _longPressTimer?.cancel();
      _longPressTimer = Timer(Duration(milliseconds: holdMs), () {
        if (_isKeyDown) {
          _longPressFired = true;
          _tapCount = 0;
          _triggerKeyAction(KeyTriggerType.longPress);
        }
      });
    } else if (actionType == 'up') {
      _isKeyDown = false;
      _longPressTimer?.cancel();

      // Only count tap if long press wasn't already triggered
      if (!_longPressFired) {
        _tapCount++;
        _multiTapTimer?.cancel();
        _multiTapTimer = Timer(Duration(milliseconds: gapMs), () {
          final count = _tapCount;
          _tapCount = 0;
          if (count == 1) {
            _triggerKeyAction(KeyTriggerType.singlePress);
          } else if (count == 2) {
            _triggerKeyAction(KeyTriggerType.doublePress);
          } else if (count >= 3) {
            _triggerKeyAction(KeyTriggerType.triplePress);
          }
        });
      }
    }
  }

  void _triggerKeyAction(KeyTriggerType trigger) {
    String actionId;
    switch (trigger) {
      case KeyTriggerType.singlePress:
        actionId = _settings.singlePressAction;
        break;
      case KeyTriggerType.doublePress:
        actionId = _settings.doublePressAction;
        break;
      case KeyTriggerType.triplePress:
        actionId = _settings.triplePressAction;
        break;
      case KeyTriggerType.longPress:
        actionId = _settings.longPressAction;
        break;
    }

    final action = KeyActions.findById(actionId);
    if (action.type != KeyActionType.none) {
      executeAction(action.type, triggerLabel: trigger.label);
    }
  }

  Future<void> executeAction(
    KeyActionType actionType, {
    String triggerLabel = 'ACTION',
    BuildContext? context,
  }) async {
    // 1. Trigger tactile haptic feedback
    HapticFeedback.heavyImpact();

    final actionInfo = KeyActions.findByType(actionType);
    if (actionInfo.type == KeyActionType.none) return;

    // 2. Local execution overrides (like Glyph torch)
    if (actionType == KeyActionType.torch) {
      _glyph.toggleTorch(brightness: _settings.torchBrightness);
    }

    // 3. Native Android execution
    String? nativeMessage;
    try {
      final res = await _glyph.executeKeyAction(actionInfo.id);
      if (res['message'] != null) {
        nativeMessage = res['message'] as String;
      }
    } catch (e) {
      debugPrint('Error executing key action natively: $e');
    }

    // 4. Surface floating Nothing OS HUD overlay
    if (context != null && !context.mounted) return;
    showOverlay(
      action: actionInfo,
      triggerLabel: triggerLabel,
      customMessage: nativeMessage,
      context: context,
    );
  }

  void showOverlay({
    required KeyActionInfo action,
    required String triggerLabel,
    String? customMessage,
    BuildContext? context,
  }) {
    _removeOverlay();

    OverlayState? overlayState;
    if (context != null) {
      overlayState = Overlay.maybeOf(context, rootOverlay: true);
    }
    overlayState ??= navigatorKey.currentState?.overlay;

    if (overlayState == null) return;

    final entry = OverlayEntry(
      builder: (ctx) => KeyActionOverlay(
        action: action,
        triggerLabel: triggerLabel,
        customMessage: customMessage,
        onDismiss: _removeOverlay,
      ),
    );

    _currentOverlayEntry = entry;
    overlayState.insert(entry);
  }

  void _removeOverlay() {
    _currentOverlayEntry?.remove();
    _currentOverlayEntry = null;
  }
}
