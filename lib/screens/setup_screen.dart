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

class _SetupScreenState extends State<SetupScreen> {
  final SettingsService _settings = SettingsService.instance;
  final NotificationRuleService _rules = NotificationRuleService.instance;
  final GlyphService _glyph = GlyphService.instance;

  bool _chargingAnimation = true;
  bool _notificationAlerts = false; // Default OFF: in-app playback only
  bool _remapEssentialKey = false;
  bool _isSaving = false;

  // Essential Key State
  int? _detectedKeyCode;
  int? _detectedScanCode;
  String? _detectedKeyName;
  bool _isListeningForKey = false;
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
    _chargingAnimation = _settings.chargingAnimationEnabled;
    _notificationAlerts = false; // strictly default to false on first launch

    _keySubscription = _glyph.onHardwareKeyCaptured.listen((data) {
      if (!_remapEssentialKey || !_isListeningForKey) return;
      final code = data['keyCode'] as int?;
      final scan = data['scanCode'] as int?;
      final name = data['keyName'] as String?;

      if (code != null && mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _detectedKeyCode = code;
          _detectedScanCode = scan;
          _detectedKeyName = name;
          _isListeningForKey = false;
        });
      }
    });
  }

  @override
  void dispose() {
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
          HapticFeedback.heavyImpact();
          setState(() {
            _detectedKeyCode = logicalKey.keyId;
            _detectedScanCode = physicalKey.usbHidUsage;
            _detectedKeyName = logicalKey.keyLabel;
            _isListeningForKey = false;
          });
          _glyph.stopHardwareKeyListening();
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

          // Step 2: Press & Listen for Essential Key
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
                'PRESS ESSENTIAL KEY',
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
            'Press the physical Essential Key on the side of your Nothing Phone (3a) to detect and save its hardware keycode.',
            style: TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Hardware Key Listening Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: appBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _detectedKeyCode != null
                    ? const Color(0xFF4CAF50)
                    : (_isListeningForKey
                        ? selectedColor
                        : Colors.white.withValues(alpha: 0.1)),
                width: 1.2,
              ),
            ),
            child: Column(
              children: [
                if (_detectedKeyCode != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF4CAF50), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ESSENTIAL KEY REGISTERED',
                              style: TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'ndot',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'KeyCode: $_detectedKeyCode${_detectedScanCode != null ? ' • ScanCode: $_detectedScanCode' : ''}${_detectedKeyName != null ? ' • Label: $_detectedKeyName' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: OutlinedButton(
                      onPressed: _startListeningForKey,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'PRESS AGAIN TO RE-CAPTURE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'ndot',
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ] else if (_isListeningForKey) ...[
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: selectedColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'LISTENING... PRESS ESSENTIAL KEY NOW',
                          style: TextStyle(
                            color: selectedColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Listening for hardware button click event...',
                    style: TextStyle(
                      color: Color(0xFF7A7D87),
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(Icons.touch_app_outlined,
                          color: Color(0xFF8E8E93), size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Awaiting configuration',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _startListeningForKey,
                        child: const Text(
                          'START LISTENING',
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
                ],
              ],
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
