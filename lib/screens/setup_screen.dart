import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
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

  bool _chargingAnimation = true;
  bool _notificationAlerts = false; // Default OFF: in-app playback only
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _chargingAnimation = _settings.chargingAnimationEnabled;
    _notificationAlerts = false; // strictly default to false on first launch
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

    return Scaffold(
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
                              'Tip: You can assign unique custom animations to individual apps or toggle alerts on/off anytime in the ALERTS tab.',
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
}
