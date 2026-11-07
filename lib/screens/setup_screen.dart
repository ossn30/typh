import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../services/glyph_service.dart';
import '../services/notification_rule_service.dart';
import '../services/settings_service.dart';
import 'main_navigation_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  final SettingsService _settings = SettingsService.instance;
  final NotificationRuleService _rules = NotificationRuleService.instance;
  final GlyphService _glyph = GlyphService.instance;

  bool _chargingAnimation = true;
  bool _notificationAlerts = false; // Default OFF: in-app playback only
  bool _remapEssentialKey = true;
  bool _isSaving = false;

  // Essential Key State
  int? _detectedKeyCode = 0;
  int? _detectedScanCode = 250;
  String? _detectedKeyName = 'KEYCODE_UNKNOWN';
  bool _isListeningForKey = false;
  bool _isKeyVerified = false;
  String? _keyVerificationError;
  bool _isAccessibilityEnabled = false;
  StreamSubscription<Map<String, dynamic>>? _keySubscription;

  // ADB Verification State
  bool _isVerifyingAdb = false;
  bool _packagesVerified = false;
  bool _recorderDisabled = false;
  bool _spaceDisabled = false;
  String? _adbVerificationMessage;

  final FocusNode _focusNode = FocusNode();

  static const String _cmdRecorder =
      'adb shell pm disable-user --user 0 com.nothing.ntessentialrecorder';
  static const String _cmdSpace =
      'adb shell pm disable-user --user 0 com.nothing.ntessentialspace';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chargingAnimation = _settings.chargingAnimationEnabled;
    _notificationAlerts = false; // strictly default to false on first launch
    _remapEssentialKey = _settings.isEssentialKeyRemapEnabled;
    _checkAccessibility();

    _keySubscription = _glyph.onHardwareKeyCaptured.listen((data) {
      if (!_remapEssentialKey || !_isListeningForKey) return;
      final isRejected = data['isRejected'] as bool? ?? false;
      final code = data['keyCode'] as int?;
      final scan = data['scanCode'] as int?;

      if (!mounted) return;

      // Reject volume or power buttons
      if (isRejected || code == 24 || code == 25 || code == 26) {
        HapticFeedback.vibrate();
        setState(() {
          _keyVerificationError =
              'Volume and Power buttons cannot be used as Essential Key. Please press the physical Essential Key.';
        });
        return;
      }

      final isEssential = (scan == 250) ||
          (code == 0 && scan == 250) ||
          (data['isEssentialKey'] as bool? ?? false);

      if (isEssential) {
        HapticFeedback.heavyImpact();
        setState(() {
          _detectedKeyCode = 0;
          _detectedScanCode = 250;
          _detectedKeyName = 'KEYCODE_UNKNOWN';
          _isKeyVerified = true;
          _keyVerificationError = null;
          _isListeningForKey = false;
        });
      } else {
        HapticFeedback.mediumImpact();
        setState(() {
          _keyVerificationError =
              'Pressed key (ScanCode: $scan). Essential Key is ScanCode 250.';
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibility();
      if (_remapEssentialKey) {
        _verifyAdbPackages();
      }
    }
  }

  Future<void> _checkAccessibility() async {
    final enabled = await _glyph.isAccessibilityServiceEnabled();
    if (mounted) {
      setState(() => _isAccessibilityEnabled = enabled);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keySubscription?.cancel();
    _glyph.stopHardwareKeyListening();
    _focusNode.dispose();
    super.dispose();
  }

  void _onToggleRemapKey(bool enabled) {
    HapticFeedback.lightImpact();
    setState(() {
      _remapEssentialKey = enabled;
    });
    if (enabled) {
      _startListeningForKey();
      _verifyAdbPackages();
      _checkAccessibility();
    } else {
      _stopListeningForKey();
    }
  }

  Future<void> _startListeningForKey() async {
    setState(() => _isListeningForKey = true);
    await _glyph.startHardwareKeyListening();
  }

  Future<void> _stopListeningForKey() async {
    setState(() => _isListeningForKey = false);
    await _glyph.stopHardwareKeyListening();
  }

  Future<void> _verifyAdbPackages() async {
    setState(() {
      _isVerifyingAdb = true;
      _adbVerificationMessage = null;
    });
    HapticFeedback.selectionClick();

    final res = await _glyph.checkEssentialPackagesDisabled();
    if (!mounted) return;

    final allDisabled = res['allDisabled'] as bool? ?? false;
    final recorderDis = res['recorderDisabled'] as bool? ?? false;
    final spaceDis = res['spaceDisabled'] as bool? ?? false;

    setState(() {
      _isVerifyingAdb = false;
      _packagesVerified = allDisabled;
      _recorderDisabled = recorderDis;
      _spaceDisabled = spaceDis;
      _adbVerificationMessage = allDisabled
          ? '✓ Both packages disabled! Essential Key is free.'
          : 'Packages still active. Run the ADB commands above.';
    });
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: selectedColor, width: 1),
        ),
        content: Text(
          '$label copied to clipboard',
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

  Future<void> _completeSetup() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    HapticFeedback.heavyImpact();

    try {
      // 1. Mark setup as completed
      await _settings.setHasCompletedOnboarding(true);

      // 2. Save charging animation setting
      await _settings.setChargingAnimationEnabled(_chargingAnimation);

      // 3. Save notification alert lights setting (default OFF)
      await _rules.setAlertsEnabled(_notificationAlerts);

      // 4. Save Essential Key Remapper settings
      await _settings.setEssentialKeyRemapEnabled(_remapEssentialKey);
      if (_remapEssentialKey) {
        if (_detectedKeyCode != null) {
          await _settings.setEssentialKeyCode(_detectedKeyCode);
        }
        if (_detectedScanCode != null) {
          await _settings.setEssentialScanCode(_detectedScanCode);
        }
        if (_detectedKeyName != null) {
          await _settings.setEssentialKeyName(_detectedKeyName);
        }
        await _settings.setEssentialPackagesDisabled(_packagesVerified);
      }

      await _glyph.stopHardwareKeyListening();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (context, animation, secondaryAnimation) =>
                const MainNavigationScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving initial setup: $e');
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (_remapEssentialKey && _isListeningForKey && event is KeyDownEvent) {
          final logicalKey = event.logicalKey;
          final physicalKey = event.physicalKey;

          if (logicalKey == LogicalKeyboardKey.audioVolumeUp ||
              logicalKey == LogicalKeyboardKey.audioVolumeDown ||
              logicalKey == LogicalKeyboardKey.power) {
            HapticFeedback.vibrate();
            setState(() {
              _keyVerificationError =
                  'Volume and Power buttons cannot be used as Essential Key.';
            });
            return;
          }

          final isEssential =
              physicalKey.usbHidUsage == 250 || logicalKey.keyId == 0;
          if (isEssential) {
            HapticFeedback.heavyImpact();
            setState(() {
              _detectedKeyCode = 0;
              _detectedScanCode = 250;
              _detectedKeyName = 'KEYCODE_UNKNOWN';
              _isKeyVerified = true;
              _keyVerificationError = null;
              _isListeningForKey = false;
            });
            _glyph.stopHardwareKeyListening();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // Nothing OS Brand Dot Matrix Tag
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
                    const Text(
                      'NOTHING PHONE (3A) • INITIAL SETUP',
                      style: TextStyle(
                        color: selectedColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Title
                const Text(
                  'HARDWARE SETUP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 12),

                // Scrollable Options Cards
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // Option 1: Charging Animation
                      _buildSetupCard(
                        icon: Icons.bolt_rounded,
                        iconColor: const Color(0xFF4CAF50),
                        title: 'CHARGING ANIMATION',
                        subtitle:
                            'Track real-time battery percentage on the rear Glyphs while the phone is connected to power.',
                        value: _chargingAnimation,
                        onChanged: (val) {
                          HapticFeedback.lightImpact();
                          setState(() => _chargingAnimation = val);
                        },
                      ),

                      const SizedBox(height: 14),

                      // Option 2: Notification Glyph Lights (Default OFF)
                      _buildSetupCard(
                        icon: Icons.notifications_active_rounded,
                        iconColor: selectedColor,
                        title: 'NOTIFICATION GLYPH LIGHTS',
                        subtitle:
                            'Light up rear Glyphs for incoming notifications from your apps.\n\nKeep OFF to allow in-app animation playback only (composer & tests).',
                        tag: 'DEFAULT: OFF (IN-APP PLAY ONLY)',
                        value: _notificationAlerts,
                        onChanged: (val) {
                          HapticFeedback.lightImpact();
                          setState(() => _notificationAlerts = val);
                        },
                      ),

                      const SizedBox(height: 14),

                      // Option 3: Essential Key Remapper
                      _buildSetupCard(
                        icon: Icons.smart_button_rounded,
                        iconColor: const Color(0xFF2196F3),
                        title: 'REMAP ESSENTIAL KEY (3A)',
                        subtitle:
                            'Remap the physical Essential Key on Nothing Phone (3a) to custom shortcuts & Glyph actions.',
                        tag: 'NOTHING PHONE (3A) HARDWARE',
                        value: _remapEssentialKey,
                        onChanged: _onToggleRemapKey,
                      ),

                      // Expandable Essential Key Setup Wizard
                      if (_remapEssentialKey) ...[
                        const SizedBox(height: 14),
                        _buildEssentialKeyWizard(),
                      ],

                      const SizedBox(height: 14),

                      // Quick Tip Box
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF8A8A8E),
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Tip: You can reconfigure alerts, charging animations, and the Essential Key anytime from the app.',
                                style: TextStyle(
                                  color: Color(0xFFA0A2AA),
                                  fontSize: 11.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

                // Bottom Continue Button
                Padding(
                  padding: EdgeInsets.only(
                    top: 12,
                    bottom: bottomInset > 0 ? bottomInset + 8 : 20,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _completeSetup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedColor,
                        disabledBackgroundColor: selectedColor.withValues(
                          alpha: 0.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'START USING GLYPH',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'ndot',
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? tag,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
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
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: CupertinoSwitch(
                  value: value,
                  activeTrackColor: selectedColor,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          if (tag != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: appBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  color: Color(0xFFB0B3BC),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'ndot',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEssentialKeyWizard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selectedColor.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 1: ADB Instructions
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '1',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'DISABLE SYSTEM APPS (ADB)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect your phone to a laptop with ADB and execute these two commands to disable default Nothing OS listeners:',
            style: TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),

          // Command 1
          _buildCommandBox(
            label: 'Command 1 (Recorder)',
            command: _cmdRecorder,
          ),
          const SizedBox(height: 8),

          // Command 2
          _buildCommandBox(
            label: 'Command 2 (Space)',
            command: _cmdSpace,
          ),
          const SizedBox(height: 12),

          // ADB Verification Button & Status Badges
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isVerifyingAdb ? null : _verifyAdbPackages,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2196F3), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: _isVerifyingAdb
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_outlined,
                                color: Color(0xFF2196F3), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'VERIFY ADB STATUS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'ndot',
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),

          if (_adbVerificationMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: appBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _packagesVerified
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: _packagesVerified
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF9800),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _adbVerificationMessage!,
                      style: TextStyle(
                        color: _packagesVerified
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF9800),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildAdbPkgStatus(
              name: 'Essential Recorder',
              disabled: _recorderDisabled,
            ),
            const SizedBox(height: 4),
            _buildAdbPkgStatus(
              name: 'Essential Space',
              disabled: _spaceDisabled,
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: Color(0xFF222222), height: 1),
          ),

          // Step 2: Verify Essential Key
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '2',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'VERIFY ESSENTIAL KEY (3A)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'The Nothing Phone (3a) Essential Key reports KeyCode 0, ScanCode 250 (KEYCODE_UNKNOWN). Press the physical button to verify detection.',
            style: TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Hardware Key Verification Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: appBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isKeyVerified
                    ? const Color(0xFF4CAF50)
                    : (_isListeningForKey
                        ? selectedColor
                        : Colors.white.withValues(alpha: 0.1)),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isKeyVerified
                          ? Icons.check_circle_rounded
                          : (_isListeningForKey
                              ? Icons.radio_button_checked_rounded
                              : Icons.smart_button_rounded),
                      color: _isKeyVerified
                          ? const Color(0xFF4CAF50)
                          : (_isListeningForKey
                              ? selectedColor
                              : const Color(0xFF2196F3)),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isKeyVerified
                                ? 'ESSENTIAL KEY VERIFIED ✓'
                                : (_isListeningForKey
                                    ? 'LISTENING... PRESS KEY NOW'
                                    : 'NOTHING PHONE (3A) KEY'),
                            style: TextStyle(
                              color: _isKeyVerified
                                  ? const Color(0xFF4CAF50)
                                  : (_isListeningForKey
                                      ? selectedColor
                                      : Colors.white),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'ndot',
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'KeyCode: 0 • ScanCode: 250 • KEYCODE_UNKNOWN',
                            style: TextStyle(
                              color: Color(0xFF9EA0AA),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_keyVerificationError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3E1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFE53935),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFE53935),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _keyVerificationError!,
                            style: const TextStyle(
                              color: Color(0xFFFF8A80),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: OutlinedButton(
                    onPressed: _isListeningForKey
                        ? _stopListeningForKey
                        : _startListeningForKey,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _isListeningForKey
                            ? selectedColor
                            : (_isKeyVerified
                                ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                                : Colors.white.withValues(alpha: 0.25)),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      _isListeningForKey
                          ? 'CANCEL LISTENING'
                          : (_isKeyVerified
                              ? 'TEST / RE-VERIFY KEY'
                              : 'VERIFY HARDWARE KEY'),
                      style: TextStyle(
                        color: _isListeningForKey ? selectedColor : Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'ndot',
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: Color(0xFF222222), height: 1),
          ),

          // Step 3: Accessibility Service for Background Remapping
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '3',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'ENABLE ACCESSIBILITY (BACKGROUND)',
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _isAccessibilityEnabled
                      ? const Color(0xFF1B3B22)
                      : const Color(0xFF3E1A1A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isAccessibilityEnabled ? 'RUNNING ✓' : 'REQUIRED',
                  style: TextStyle(
                    color: _isAccessibilityEnabled
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF8A80),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Required by Android for Essential Key shortcuts to work when the app is closed, in the background, or when the screen is locked.',
            style: TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                await _glyph.openAccessibilitySettings();
              },
              icon: Icon(
                _isAccessibilityEnabled
                    ? Icons.check_circle_rounded
                    : Icons.accessibility_new_rounded,
                size: 16,
                color: _isAccessibilityEnabled
                    ? const Color(0xFF4CAF50)
                    : selectedColor,
              ),
              label: Text(
                _isAccessibilityEnabled
                    ? 'ACCESSIBILITY SERVICE ENABLED'
                    : 'OPEN ACCESSIBILITY SETTINGS',
                style: TextStyle(
                  color: _isAccessibilityEnabled
                      ? const Color(0xFF4CAF50)
                      : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.6,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: _isAccessibilityEnabled
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                      : selectedColor,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandBox({
    required String label,
    required String command,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  label,
                  style: const TextStyle(
                    color: Color(0xFF6E717B),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'ndot',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  command,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _copyToClipboard(command, label),
            icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
            tooltip: 'Copy command',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildAdbPkgStatus({
    required String name,
    required bool disabled,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: appBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: disabled
                  ? const Color(0xFF1B3B22)
                  : const Color(0xFF38231E),
              borderRadius: BorderRadius.circular(4),
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
