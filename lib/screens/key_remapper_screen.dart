import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../models/key_action.dart';
import '../services/glyph_service.dart';
import '../services/key_action_service.dart';
import '../services/settings_service.dart';

class KeyRemapperScreen extends StatefulWidget {
  final bool showBackButton;

  const KeyRemapperScreen({super.key, this.showBackButton = false});

  @override
  State<KeyRemapperScreen> createState() => _KeyRemapperScreenState();
}

class _KeyRemapperScreenState extends State<KeyRemapperScreen>
    with WidgetsBindingObserver {
  final SettingsService _settings = SettingsService.instance;
  final GlyphService _glyph = GlyphService.instance;
  final KeyActionService _actionService = KeyActionService.instance;

  bool _remapEnabled = false;
  int? _keyCode;
  int? _scanCode;
  String? _keyName;

  // Actions
  String _singlePressAction = 'torch';
  String _doublePressAction = 'calculator';
  String _triplePressAction = 'ringer_mode';
  String _longPressAction = 'power_menu';

  // Timings
  int _multiPressGapMs = 350;
  int _longPressHoldMs = 500;

  // System HUD Overlay
  bool _overlayEnabled = true;
  String _overlayPositionSide = 'left';
  int _overlayPositionPercent = 45;
  int _overlayDurationMs = 2000;
  String _previewSelectedTrigger = 'single_press';

  // Status
  bool _isCheckingAdb = false;
  bool _packagesDisabled = false;
  bool _recorderDisabled = false;
  bool _spaceDisabled = false;
  bool _isAccessibilityEnabled = false;
  bool _isListeningForKey = false;
  StreamSubscription<Map<String, dynamic>>? _keySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
    _checkAdbStatus();
    _checkAccessibilityStatus();

    _keySubscription = _glyph.onHardwareKeyCaptured.listen((data) {
      if (!_isListeningForKey && !_remapEnabled) return;
      final isRejected = data['isRejected'] as bool? ?? false;
      final code = data['keyCode'] as int?;
      final scan = data['scanCode'] as int?;

      if (!mounted) return;

      if (isRejected || code == 24 || code == 25 || code == 26) {
        HapticFeedback.vibrate();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD32F2F),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: const Text(
              'Volume and Power buttons cannot be used as Essential Key.',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'ndot',
                fontSize: 12,
              ),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final isEssential =
          (scan == 250) ||
          (code == 0 && scan == 250) ||
          (data['isEssentialKey'] as bool? ?? false);

      if (isEssential) {
        HapticFeedback.heavyImpact();
        setState(() {
          _keyCode = 0;
          _scanCode = 250;
          _keyName = 'KEYCODE_UNKNOWN';
          _isListeningForKey = false;
        });
        _settings.setEssentialKeyCode(0);
        _settings.setEssentialScanCode(250);
        _settings.setEssentialKeyName('KEYCODE_UNKNOWN');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B5E20),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF4CAF50), width: 1),
            ),
            content: const Text(
              '✓ Essential Key Verified! (ScanCode: 250, KeyCode: 0)',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'ndot',
                fontSize: 12,
              ),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: cardColor,
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Key detected (ScanCode: $scan). Essential Key is ScanCode 250.',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'ndot',
                fontSize: 12,
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _loadState() {
    setState(() {
      _remapEnabled = _settings.isEssentialKeyRemapEnabled;
      _keyCode = _settings.essentialKeyCode;
      _scanCode = _settings.essentialScanCode;
      _keyName = _settings.essentialKeyName;
      _packagesDisabled = _settings.essentialPackagesDisabled;

      _singlePressAction = _settings.singlePressAction;
      _doublePressAction = _settings.doublePressAction;
      _triplePressAction = _settings.triplePressAction;
      _longPressAction = _settings.longPressAction;

      _multiPressGapMs = _settings.multiPressGapMs;
      _longPressHoldMs = _settings.longPressHoldMs;

      _overlayEnabled = _settings.isOverlayEnabled;
      _overlayPositionSide = _settings.overlayPositionSide;
      _overlayPositionPercent = _settings.overlayPositionPercent;
      _overlayDurationMs = _settings.overlayDurationMs;
    });
  }

  Future<void> _checkAdbStatus() async {
    setState(() => _isCheckingAdb = true);
    final res = await _glyph.checkEssentialPackagesDisabled();
    if (mounted) {
      setState(() {
        _isCheckingAdb = false;
        _packagesDisabled = res['allDisabled'] as bool? ?? false;
        _recorderDisabled = res['recorderDisabled'] as bool? ?? false;
        _spaceDisabled = res['spaceDisabled'] as bool? ?? false;
      });
      _settings.setEssentialPackagesDisabled(_packagesDisabled);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibilityStatus();
      _checkAdbStatus();
    }
  }

  Future<void> _checkAccessibilityStatus() async {
    final enabled = await _glyph.isAccessibilityServiceEnabled();
    if (mounted) {
      setState(() => _isAccessibilityEnabled = enabled);
    }
  }

  Future<void> _toggleRemapper(bool value) async {
    HapticFeedback.lightImpact();
    setState(() {
      _remapEnabled = value;
    });
    await _settings.setEssentialKeyRemapEnabled(value);

    if (value && !_isAccessibilityEnabled) {
      if (mounted) {
        _showAccessibilityRequiredDialog();
      }
    }
  }

  void _showAccessibilityRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.accessibility_new_rounded,
              color: selectedColor,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'ACCESSIBILITY NEEDED',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                fontFamily: 'ndot',
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        content: const Text(
          'To detect the Essential Key when the app is closed, in the background, or when the screen is locked, Android requires the "Glyph Key Remapper Service" accessibility permission.\n\nOpen Accessibility Settings now?',
          style: TextStyle(
            color: Color(0xFFCCCCCC),
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'LATER',
              style: TextStyle(
                color: Colors.white54,
                fontFamily: 'ndot',
                letterSpacing: 0.5,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _glyph.openAccessibilitySettings();
            },
            child: const Text(
              'OPEN SETTINGS',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'ndot',
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startKeyListening() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isListeningForKey = true;
    });
    await _glyph.startHardwareKeyListening();

    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isListeningForKey) {
        setState(() => _isListeningForKey = false);
        _glyph.stopHardwareKeyListening();
      }
    });
  }

  Future<void> _stopKeyListening() async {
    setState(() {
      _isListeningForKey = false;
    });
    await _glyph.stopHardwareKeyListening();
  }

  void _testAction(KeyActionType actionType, String triggerLabel) {
    _actionService.executeAction(
      actionType,
      triggerLabel: triggerLabel,
      context: context,
    );
  }

  void _openActionPicker(KeyTriggerType trigger) {
    HapticFeedback.selectionClick();
    String currentActionId;
    switch (trigger) {
      case KeyTriggerType.singlePress:
        currentActionId = _singlePressAction;
        break;
      case KeyTriggerType.doublePress:
        currentActionId = _doublePressAction;
        break;
      case KeyTriggerType.triplePress:
        currentActionId = _triplePressAction;
        break;
      case KeyTriggerType.longPress:
        currentActionId = _longPressAction;
        break;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ActionPickerSheet(
        trigger: trigger,
        currentActionId: currentActionId,
        onActionSelected: (selectedAction) async {
          Navigator.of(ctx).pop();
          HapticFeedback.mediumImpact();
          setState(() {
            switch (trigger) {
              case KeyTriggerType.singlePress:
                _singlePressAction = selectedAction.id;
                _settings.setSinglePressAction(selectedAction.id);
                break;
              case KeyTriggerType.doublePress:
                _doublePressAction = selectedAction.id;
                _settings.setDoublePressAction(selectedAction.id);
                break;
              case KeyTriggerType.triplePress:
                _triplePressAction = selectedAction.id;
                _settings.setTriplePressAction(selectedAction.id);
                break;
              case KeyTriggerType.longPress:
                _longPressAction = selectedAction.id;
                _settings.setLongPressAction(selectedAction.id);
                break;
            }
          });

          // Preview the chosen action immediately with HUD overlay and haptics!
          _testAction(selectedAction.type, trigger.label);
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keySubscription?.cancel();
    _glyph.stopHardwareKeyListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (_isListeningForKey && event is KeyDownEvent) {
          final logicalKey = event.logicalKey;
          final physicalKey = event.physicalKey;

          if (logicalKey == LogicalKeyboardKey.audioVolumeUp ||
              logicalKey == LogicalKeyboardKey.audioVolumeDown ||
              logicalKey == LogicalKeyboardKey.power) {
            HapticFeedback.vibrate();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Volume and Power buttons cannot be used as Essential Key.',
                  style: TextStyle(fontFamily: 'ndot', color: Colors.white),
                ),
                backgroundColor: Color(0xFFD32F2F),
              ),
            );
            return;
          }

          final isEssential =
              physicalKey.usbHidUsage == 250 || logicalKey.keyId == 0;
          if (isEssential) {
            HapticFeedback.heavyImpact();
            setState(() {
              _keyCode = 0;
              _scanCode = 250;
              _keyName = 'KEYCODE_UNKNOWN';
              _isListeningForKey = false;
            });
            _settings.setEssentialKeyCode(0);
            _settings.setEssentialScanCode(250);
            _settings.setEssentialKeyName('KEYCODE_UNKNOWN');
            _glyph.stopHardwareKeyListening();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: widget.showBackButton
              ? IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          title: const Text(
            'KEYMAPPER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'ndot',
              letterSpacing: 1.2,
            ),
          ),
          actions: [
            Transform.scale(
              scale: 0.75,
              child: CupertinoSwitch(
                value: _remapEnabled,
                activeTrackColor: selectedColor,
                onChanged: _toggleRemapper,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: bottomInset > 0 ? bottomInset + 20 : 32,
          ),
          children: [
            // Status Tag
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: selectedColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'NOTHING PHONE (3A) • ESSENTIAL KEY REMAPPER',
                    style: TextStyle(
                      color: selectedColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ndot',
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            if (_remapEnabled && !_isAccessibilityEnabled) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  await _glyph.openAccessibilitySettings();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C1515),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFE53935).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFE53935),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ACCESSIBILITY SERVICE DISABLED',
                              style: TextStyle(
                                color: Color(0xFFFF8A80),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'ndot',
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Required for remapped keys to work when app is closed. Tap to enable.',
                              style: TextStyle(
                                color: Color(0xFFCCCCCC),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Color(0xFFFF8A80),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Card 1: Key Registration Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selectedColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.smart_button_rounded,
                          color: selectedColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'HARDWARE KEY BINDING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _keyCode != null
                              ? const Color(0xFF1B3B22)
                              : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _keyCode != null ? 'BOUND ✓' : 'UNBOUND',
                          style: TextStyle(
                            color: _keyCode != null
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFF8E8E93),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_keyCode != null) ...[
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'KeyCode: ',
                              style: TextStyle(
                                color: Color(0xFF9EA0AA),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '$_keyCode',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'ndot',
                              ),
                            ),
                          ],
                        ),
                        if (_scanCode != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'ScanCode: ',
                                style: TextStyle(
                                  color: Color(0xFF9EA0AA),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '$_scanCode',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'ndot',
                                ),
                              ),
                            ],
                          ),
                        if (_keyName != null && _keyName!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Label: ',
                                style: TextStyle(
                                  color: Color(0xFF9EA0AA),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '$_keyName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      'Press the physical Essential Key on your Nothing Phone (3a) to capture its hardware keycode.',
                      style: TextStyle(
                        color: Color(0xFF9EA0AA),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _isListeningForKey
                          ? _stopKeyListening
                          : _startKeyListening,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _isListeningForKey
                              ? selectedColor
                              : Colors.white.withValues(alpha: 0.2),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isListeningForKey
                                ? Icons.radio_button_checked_rounded
                                : Icons.sensors_rounded,
                            size: 16,
                            color: _isListeningForKey
                                ? selectedColor
                                : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isListeningForKey
                                ? 'AWAITING KEY... (TAP TO CANCEL)'
                                : 'VERIFY HARDWARE KEY',
                            style: TextStyle(
                              color: _isListeningForKey
                                  ? selectedColor
                                  : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'ndot',
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Card 2: Timing & Sensitivity (Gap between presses & Long press hold needed)
            _buildTimingsCard(),

            const SizedBox(height: 18),

            // Section Header: ACTIONS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TRIGGER ACTIONS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  _remapEnabled ? 'ACTIVE' : 'DISABLED',
                  style: TextStyle(
                    color: _remapEnabled
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF8E8E93),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 4 Trigger Action Cards
            _buildTriggerCard(
              trigger: KeyTriggerType.singlePress,
              actionId: _singlePressAction,
            ),
            const SizedBox(height: 10),

            _buildTriggerCard(
              trigger: KeyTriggerType.doublePress,
              actionId: _doublePressAction,
            ),
            const SizedBox(height: 10),

            _buildTriggerCard(
              trigger: KeyTriggerType.triplePress,
              actionId: _triplePressAction,
            ),
            const SizedBox(height: 10),

            _buildTriggerCard(
              trigger: KeyTriggerType.longPress,
              actionId: _longPressAction,
            ),

            const SizedBox(height: 18),

            // Card 3: Global Accessibility Service (For outside-app key interception)
            _buildAccessibilityCard(),

            const SizedBox(height: 14),

            // Card 4: System HUD Overlay & Position Customization
            _buildOverlayPositionCard(),

            const SizedBox(height: 14),

            // Card 5: ADB Verification
            _buildAdbStatusCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.timer_rounded,
                  color: Color(0xFFFF9800),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'TIMING & SENSITIVITY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Slider 1: Multi-press Gap
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GAP BETWEEN PRESSES',
                style: TextStyle(
                  color: Color(0xFFB0B3BC),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '${_multiPressGapMs}ms',
                style: const TextStyle(
                  color: selectedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Maximum window between consecutive taps for double & triple press.',
            style: TextStyle(color: Color(0xFF7A7D87), fontSize: 11),
          ),
          CupertinoSlider(
            value: _multiPressGapMs.toDouble(),
            min: 200,
            max: 800,
            divisions: 24,
            activeColor: selectedColor,
            onChanged: (val) {
              final ms = val.round();
              setState(() => _multiPressGapMs = ms);
              _settings.setMultiPressGapMs(ms);
            },
          ),

          const SizedBox(height: 10),

          // Slider 2: Long press hold needed
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LONG PRESS HOLD TIME',
                style: TextStyle(
                  color: Color(0xFFB0B3BC),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '${_longPressHoldMs}ms',
                style: const TextStyle(
                  color: selectedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'How much continuous hold is needed to trigger the long press action.',
            style: TextStyle(color: Color(0xFF7A7D87), fontSize: 11),
          ),
          CupertinoSlider(
            value: _longPressHoldMs.toDouble(),
            min: 300,
            max: 2000,
            divisions: 34,
            activeColor: selectedColor,
            onChanged: (val) {
              final ms = val.round();
              setState(() => _longPressHoldMs = ms);
              _settings.setLongPressHoldMs(ms);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerCard({
    required KeyTriggerType trigger,
    required String actionId,
  }) {
    final action = KeyActions.findById(actionId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: appBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selectedColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  trigger.badge,
                  style: const TextStyle(
                    color: selectedColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trigger.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              // Test Button
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _testAction(action.type, trigger.label),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: appBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'TEST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'ndot',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Action Info Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: appBackgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selectedColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(action.icon, color: selectedColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _openActionPicker(trigger),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'CHANGE',
                    style: TextStyle(
                      color: selectedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF9C27B0).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.accessibility_new_rounded,
                  color: Color(0xFF9C27B0),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'GLOBAL ACCESSIBILITY SERVICE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isAccessibilityEnabled
                      ? const Color(0xFF1B3B22)
                      : const Color(0xFF38231E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isAccessibilityEnabled ? 'RUNNING ✓' : 'DISABLED',
                  style: TextStyle(
                    color: _isAccessibilityEnabled
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF9800),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Enables Essential Key actions (Lock Screen, Power Menu, Panels) to work system-wide even when the app is in the background or closed.',
            style: TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton(
              onPressed: () async {
                await _glyph.openAccessibilitySettings();
                Future.delayed(
                  const Duration(seconds: 1),
                  _checkAccessibilityStatus,
                );
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'OPEN ACCESSIBILITY SETTINGS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getActionForTrigger(String trigger) {
    switch (trigger) {
      case 'double_press':
        return _doublePressAction;
      case 'triple_press':
        return _triplePressAction;
      case 'long_press':
        return _longPressAction;
      case 'single_press':
      default:
        return _singlePressAction;
    }
  }

  String _getTriggerLabel(String trigger) {
    switch (trigger) {
      case 'double_press':
        return 'DOUBLE PRESS';
      case 'triple_press':
        return 'TRIPLE PRESS';
      case 'long_press':
        return 'LONG PRESS';
      case 'single_press':
      default:
        return 'SINGLE PRESS';
    }
  }

  Widget _buildOverlayPositionCard() {
    final previewActionId = _getActionForTrigger(_previewSelectedTrigger);
    final previewActionInfo = KeyActions.findById(previewActionId);
    final previewTriggerLabel = _getTriggerLabel(_previewSelectedTrigger);
    final isLeft = _overlayPositionSide == 'left';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selectedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dock_rounded,
                  color: selectedColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYSTEM HUD OVERLAY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'SYSTEM-WIDE • AROUND PHYSICAL KEY',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 9.5,
                        fontFamily: 'ndot',
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: CupertinoSwitch(
                  value: _overlayEnabled,
                  activeTrackColor: selectedColor,
                  onChanged: (val) async {
                    HapticFeedback.lightImpact();
                    setState(() => _overlayEnabled = val);
                    await _settings.setOverlayEnabled(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Displays an animated Nothing OS HUD pill directly on your screen beside the physical Essential Key, visible everywhere in Android even when the app is closed.',
            style: TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          if (_overlayEnabled) ...[
            const SizedBox(height: 16),

            // Live Nothing OS Pill Interactive Studio
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: appBackgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'LIVE PILL PREVIEW STUDIO',
                        style: TextStyle(
                          color: selectedColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'ndot',
                          letterSpacing: 0.8,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HOT RELOADABLE',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 8.5,
                            fontFamily: 'ndot',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Trigger Selector Chips for Preview
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildPreviewTriggerChip('single_press', '1X SINGLE'),
                        const SizedBox(width: 6),
                        _buildPreviewTriggerChip('double_press', '2X DOUBLE'),
                        const SizedBox(width: 6),
                        _buildPreviewTriggerChip('triple_press', '3X TRIPLE'),
                        const SizedBox(width: 6),
                        _buildPreviewTriggerChip('long_press', 'HOLD LONG'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Interactive Pill Stage (Simulates Bezel Anchor)
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      await _glyph.showSystemHudOverlay(
                        trigger: previewTriggerLabel,
                        action: previewActionId,
                        message: 'OVERLAY POSITION: $_overlayPositionPercent%',
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: isLeft
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left Anchor Bevel Pip
                          // if (isLeft)
                          //   Container(
                          //     width: 3.5,
                          //     height: 20,
                          //     margin: const EdgeInsets.only(right: 6),
                          //     decoration: BoxDecoration(
                          //       color: selectedColor,
                          //       borderRadius: BorderRadius.circular(2),
                          //     ),
                          //   ),

                          // Main Obsidian Capsule
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: appBackgroundColor,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Circular Glyph Core Badge
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: CupertinoColors.systemGreen,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        previewActionInfo.icon,
                                        color: Colors.black,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Text Column
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Title Row: Bold white action + status tag
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              previewActionInfo.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'ndot',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                              ),
                            ),
                          ),

                          // Right Anchor Bevel Pip
                          // if (!isLeft)
                          //   Container(
                          //     width: 3.5,
                          //     height: 20,
                          //     margin: const EdgeInsets.only(left: 6),
                          //     decoration: BoxDecoration(
                          //       color: selectedColor,
                          //       borderRadius: BorderRadius.circular(2),
                          //       boxShadow: [
                          //         BoxShadow(
                          //           color: selectedColor.withValues(alpha: 0.7),
                          //           blurRadius: 4,
                          //         ),
                          //       ],
                          //     ),
                          //   ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    'Tap the preview pill to fire the system overlay on your phone.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Key Side Selector (Left / Right frame)
            const Text(
              'PHYSICAL KEY EDGE',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'ndot',
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      setState(() => _overlayPositionSide = 'left');
                      await _settings.setOverlayPositionSide('left');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _overlayPositionSide == 'left'
                            ? selectedColor.withValues(alpha: 0.2)
                            : appBackgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _overlayPositionSide == 'left'
                              ? selectedColor
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'LEFT FRAME (3A KEY)',
                          style: TextStyle(
                            color: _overlayPositionSide == 'left'
                                ? Colors.white
                                : const Color(0xFF8E8E93),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      setState(() => _overlayPositionSide = 'right');
                      await _settings.setOverlayPositionSide('right');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _overlayPositionSide == 'right'
                            ? selectedColor.withValues(alpha: 0.2)
                            : appBackgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _overlayPositionSide == 'right'
                              ? selectedColor
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'RIGHT FRAME',
                          style: TextStyle(
                            color: _overlayPositionSide == 'right'
                                ? Colors.white
                                : const Color(0xFF8E8E93),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Vertical Alignment Slider with phone diagram
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VERTICAL POSITION ALIGNMENT',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '$_overlayPositionPercent% FROM TOP',
                  style: const TextStyle(
                    color: selectedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Phone frame mini diagram with sliding key indicator
                Container(
                  width: 50,
                  height: 90,
                  decoration: BoxDecoration(
                    color: appBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Screen area
                      Positioned.fill(
                        left: 4,
                        top: 4,
                        right: 4,
                        bottom: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      // Physical button indicator along frame edge
                      Positioned(
                        top: 8 + (70 * (_overlayPositionPercent / 100)),
                        left: _overlayPositionSide == 'left' ? 1 : null,
                        right: _overlayPositionSide == 'right' ? 1 : null,
                        child: Container(
                          width: 3.5,
                          height: 12,
                          decoration: BoxDecoration(
                            color: selectedColor,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: selectedColor.withValues(alpha: 0.8),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: selectedColor,
                          inactiveTrackColor: Colors.white.withValues(
                            alpha: 0.1,
                          ),
                          thumbColor: selectedColor,
                          overlayColor: selectedColor.withValues(alpha: 0.2),
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                        ),
                        child: Slider(
                          value: _overlayPositionPercent.toDouble(),
                          min: 10,
                          max: 90,
                          divisions: 80,
                          onChanged: (val) {
                            setState(
                              () => _overlayPositionPercent = val.round(),
                            );
                          },
                          onChangeEnd: (val) async {
                            HapticFeedback.selectionClick();
                            await _settings.setOverlayPositionPercent(
                              val.round(),
                            );
                          },
                        ),
                      ),
                      Text(
                        'Align with Nothing Phone (3a) Essential Key (approx 40%–50%)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Duration Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ON-SCREEN DURATION',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '${(_overlayDurationMs / 1000).toStringAsFixed(1)} SECONDS',
                  style: const TextStyle(
                    color: selectedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: selectedColor,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                thumbColor: selectedColor,
                overlayColor: selectedColor.withValues(alpha: 0.2),
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _overlayDurationMs.toDouble(),
                min: 1000,
                max: 4000,
                divisions: 15,
                onChanged: (val) {
                  setState(() => _overlayDurationMs = val.round());
                },
                onChangeEnd: (val) async {
                  HapticFeedback.selectionClick();
                  await _settings.setOverlayDurationMs(val.round());
                },
              ),
            ),

            const SizedBox(height: 10),

            // Live Preview Button
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  await _glyph.showSystemHudOverlay(
                    trigger: previewTriggerLabel,
                    action: previewActionId,
                    message: 'OVERLAY POSITION: $_overlayPositionPercent%',
                  );
                },
                icon: const Icon(
                  Icons.visibility_rounded,
                  size: 16,
                  color: selectedColor,
                ),
                label: const Text(
                  'PREVIEW HUD ON SCREEN NOW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: selectedColor.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewTriggerChip(String triggerKey, String label) {
    final isSelected = _previewSelectedTrigger == triggerKey;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _previewSelectedTrigger = triggerKey);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF8E8E93),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            fontFamily: 'ndot',
          ),
        ),
      ),
    );
  }

  Widget _buildAdbStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  color: Color(0xFF2196F3),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'NOTHING OS ADB STATUS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              IconButton(
                onPressed: _isCheckingAdb ? null : _checkAdbStatus,
                icon: _isCheckingAdb
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                tooltip: 'Re-verify ADB status',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildPackageRow(
            name: 'Essential Recorder',
            pkg: 'com.nothing.ntessentialrecorder',
            disabled: _recorderDisabled,
          ),
          const SizedBox(height: 6),
          _buildPackageRow(
            name: 'Essential Space',
            pkg: 'com.nothing.ntessentialspace',
            disabled: _spaceDisabled,
          ),
        ],
      ),
    );
  }

  Widget _buildPackageRow({
    required String name,
    required String pkg,
    required bool disabled,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: appBackgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  pkg,
                  style: const TextStyle(
                    color: Color(0xFF6E717B),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: disabled
                  ? const Color(0xFF1B3B22)
                  : const Color(0xFF38231E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              disabled ? 'DISABLED ✓' : 'ACTIVE',
              style: TextStyle(
                color: disabled
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF9800),
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'ndot',
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPickerSheet extends StatefulWidget {
  final KeyTriggerType trigger;
  final String currentActionId;
  final ValueChanged<KeyActionInfo> onActionSelected;

  const _ActionPickerSheet({
    required this.trigger,
    required this.currentActionId,
    required this.onActionSelected,
  });

  @override
  State<_ActionPickerSheet> createState() => _ActionPickerSheetState();
}

class _ActionPickerSheetState extends State<_ActionPickerSheet> {
  String _selectedCategory = 'All';
  String _searchQuery = '';

  final List<String> _categories = [
    'All',
    'Controls',
    'System',
    'Panels',
    'Tools',
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final filteredActions = KeyActions.all.where((action) {
      if (_selectedCategory != 'All' && action.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return action.title.toLowerCase().contains(q) ||
            action.description.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: appBackgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selectedColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.trigger.badge,
                    style: const TextStyle(
                      color: selectedColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ASSIGN ${widget.trigger.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ndot',
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF8E8E93),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search actions...',
                        hintStyle: TextStyle(
                          color: Color(0xFF6E717B),
                          fontSize: 12,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _searchQuery = ''),
                      child: const Icon(
                        Icons.clear_rounded,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Category Chips
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = _categories[idx];
                final isSel = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSel ? selectedColor : cardColor,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Center(
                      child: Text(
                        cat.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'ndot',
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Actions List
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: bottomInset > 0 ? bottomInset + 16 : 20,
              ),
              itemCount: filteredActions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final action = filteredActions[index];
                final isSelected = action.id == widget.currentActionId;

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onActionSelected(action),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? selectedColor
                            : Colors.white.withValues(alpha: 0.05),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? selectedColor.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            action.icon,
                            color: isSelected ? selectedColor : Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                action.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                action.description,
                                style: const TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: selectedColor,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
