import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../services/glyph_service.dart';
import '../services/settings_service.dart';

class IslandScreen extends StatefulWidget {
  const IslandScreen({super.key});

  @override
  State<IslandScreen> createState() => _IslandScreenState();
}

class _IslandScreenState extends State<IslandScreen> {
  final SettingsService _settings = SettingsService.instance;
  final GlyphService _glyph = GlyphService.instance;

  bool _islandEnabled = true;
  bool _showOnCharging = true;
  int _topMargin = 10;
  int _cutoutDiameter = 32;
  int _pillWidth = 195;

  int _testBattery = 85;
  bool _isAutoDetected = false;
  bool _isDetecting = false;

  bool _isRealCharging = false;
  int _realBattery = 85;
  bool _testStayingActive = false;
  bool _hasPermission = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _detectCutout();
    _checkPermission();

    _isRealCharging = _glyph.batteryNotifier.value.isCharging;
    _realBattery = _glyph.batteryNotifier.value.level.clamp(1, 100);
    if (_isRealCharging) {
      _testBattery = _realBattery;
    }
    _glyph.batteryNotifier.addListener(_onBatteryChanged);
  }

  void _onBatteryChanged() {
    if (!mounted) return;
    setState(() {
      _isRealCharging = _glyph.batteryNotifier.value.isCharging;
      _realBattery = _glyph.batteryNotifier.value.level.clamp(1, 100);
      if (_isRealCharging) {
        _testBattery = _realBattery;
      }
    });
  }

  @override
  void dispose() {
    _glyph.batteryNotifier.removeListener(_onBatteryChanged);
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final hasAccessibility = await _glyph.isAccessibilityServiceEnabled();
    final hasOverlay = await _glyph.isOverlayPermissionGranted();
    if (mounted) {
      setState(() {
        _hasPermission = hasAccessibility || hasOverlay;
      });
    }
  }

  void _loadSettings() {
    setState(() {
      _islandEnabled = _settings.isIslandEnabled;
      _showOnCharging = _settings.isIslandShowOnCharging;
      _topMargin = _settings.islandTopMargin;
      _cutoutDiameter = _settings.islandCutoutDiameter;
      _pillWidth = _settings.islandPillWidth;
    });
  }

  Future<void> _detectCutout() async {
    setState(() => _isDetecting = true);
    final info = await _glyph.getCameraCutoutInfo();
    if (!mounted) return;

    if (info != null && info['hasCutout'] == true) {
      final top = (info['top'] as num?)?.toInt() ?? _topMargin;
      final diam = (info['height'] as num?)?.toInt() ?? _cutoutDiameter;
      setState(() {
        _topMargin = top;
        _cutoutDiameter = diam.clamp(24, 45);
        _isAutoDetected = true;
        _isDetecting = false;
      });
      await _settings.setIslandTopMargin(_topMargin);
      await _settings.setIslandCutoutDiameter(_cutoutDiameter);
    } else {
      setState(() {
        _isAutoDetected = false;
        _isDetecting = false;
      });
    }
  }

  Future<void> _togglePersistentIsland() async {
    HapticFeedback.mediumImpact();
    setState(() => _testStayingActive = !_testStayingActive);

    if (_testStayingActive) {
      await _glyph.showDynamicIsland(
        mode: 'charging',
        batteryPercent: _testBattery,
        isCharging: true,
        stayWhileCharging: true,
      );
    } else {
      await _glyph.dismissDynamicIsland();
    }
  }

  Future<void> _triggerTestIsland() async {
    HapticFeedback.mediumImpact();
    await _glyph.showDynamicIsland(
      mode: 'charging',
      batteryPercent: _testBattery,
      isCharging: true,
      stayWhileCharging: false,
      durationMs: 4000,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              if (!_hasPermission) ...[
                const SizedBox(height: 12),
                _buildPermissionBanner(),
              ],
              const SizedBox(height: 16),
              _buildLivePreviewStage(),
              const SizedBox(height: 16),
              _buildChargingSettingsCard(),
              const SizedBox(height: 16),
              _buildCutoutCalibrationCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF261214),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: selectedColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OVERLAY PERMISSION REQUIRED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Allow Glyph to draw over other apps so Dynamic Island displays across your entire phone.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              HapticFeedback.selectionClick();
              await _glyph.openOverlaySettings();
              await Future.delayed(const Duration(seconds: 1));
              await _checkPermission();
            },
            style: TextButton.styleFrom(
              backgroundColor: selectedColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'GRANT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'ndot',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selectedColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bubble_chart_rounded,
              color: selectedColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DYNAMIC ISLAND',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'CAMERA CUTOUT HUD • HARDWARE PILL',
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
              value: _islandEnabled,
              activeTrackColor: selectedColor,
              onChanged: (val) async {
                HapticFeedback.lightImpact();
                setState(() => _islandEnabled = val);
                await _settings.setIslandEnabled(val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreviewStage() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LIVE ISLAND STAGE',
                style: TextStyle(
                  color: selectedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isRealCharging
                      ? const Color(0xFF34C759).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isRealCharging
                        ? const Color(0xFF34C759)
                        : Colors.white.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRealCharging
                            ? const Color(0xFF34C759)
                            : const Color(0xFF8E8E93),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isRealCharging
                          ? 'CHARGING ACTIVE ($_realBattery%)'
                          : 'NOT CHARGING',
                      style: TextStyle(
                        color: _isRealCharging
                            ? const Color(0xFF34C759)
                            : const Color(0xFF8E8E93),
                        fontSize: 8.5,
                        fontFamily: 'ndot',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stage canvas simulating the top camera region
          GestureDetector(
            onTap: _triggerTestIsland,
            child: Container(
              width: double.infinity,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // Subtle top bezel indicator
                  Positioned(
                    top: 0,
                    left: 40,
                    right: 40,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),

                  // The Dynamic Island Pill enclosing the camera
                  Positioned(
                    top: _topMargin.toDouble().clamp(4, 28),
                    child: Container(
                      height: 38,
                      constraints: BoxConstraints(
                        minWidth: _pillWidth.toDouble().clamp(150, 240),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.8),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Left Wing: Battery Percentage
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_testBattery%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'ndot',
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(width: 12),

                          // Center: Camera Cutout hole punch
                          Container(
                            width: _cutoutDiameter.toDouble().clamp(22, 34),
                            height: _cutoutDiameter.toDouble().clamp(22, 34),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF050505),
                              border: Border.all(
                                color: const Color(0xFF1C1C22),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF0F1B29),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Right Wing: Green Lightning Bolt & Charging label
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '⚡',
                                style: TextStyle(
                                  color: Color(0xFF34C759),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'CHARGING',
                                style: TextStyle(
                                  color: Color(0xFF34C759),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'ndot',
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom hint
                  Positioned(
                    bottom: 8,
                    child: Text(
                      'TAP STAGE TO TEST NATIVE DYNAMIC ISLAND',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 8.5,
                        fontFamily: 'ndot',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Battery slider for previewing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TEST BATTERY LEVEL',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
              Text(
                '$_testBattery%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF34C759),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: const Color(0xFF34C759),
              trackHeight: 3,
            ),
            child: Slider(
              value: _testBattery.toDouble(),
              min: 1,
              max: 100,
              onChanged: (val) {
                setState(() => _testBattery = val.round());
              },
            ),
          ),

          // Test buttons row
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _togglePersistentIsland,
                    icon: Icon(
                      _testStayingActive
                          ? Icons.close_rounded
                          : Icons.push_pin_rounded,
                      size: 15,
                    ),
                    label: Text(
                      _testStayingActive ? 'DISMISS' : 'KEEP ON SCREEN',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                        letterSpacing: 0.6,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _testStayingActive
                          ? const Color(0xFF2E1215)
                          : const Color(0xFF142416),
                      foregroundColor: _testStayingActive
                          ? const Color(0xFFFF453A)
                          : const Color(0xFF34C759),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _testStayingActive
                              ? const Color(0xFFFF453A).withValues(alpha: 0.6)
                              : const Color(0xFF34C759).withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: _triggerTestIsland,
                    icon: const Icon(Icons.flash_on_rounded, size: 15),
                    label: const Text(
                      'PREVIEW 4S',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                        letterSpacing: 0.6,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChargingSettingsCard() {
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
                  color: const Color(0xFF34C759).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.battery_charging_full_rounded,
                  color: Color(0xFF34C759),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CHARGING ISLAND',
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
                      'TRIGGERS ON CHARGER CONNECT',
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
                  value: _showOnCharging,
                  activeTrackColor: const Color(0xFF34C759),
                  onChanged: (val) async {
                    HapticFeedback.lightImpact();
                    setState(() => _showOnCharging = val);
                    await _settings.setIslandShowOnCharging(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Automatically expands a horizontal pill around your camera cutout when plugged in, showing live charging percentage and status even when the app is closed.',
            style: TextStyle(
              color: Color(0xFF9EA0AA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCutoutCalibrationCard() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CAMERA CUTOUT CALIBRATION',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
              if (_isDetecting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isAutoDetected
                        ? const Color(0xFF34C759).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _isAutoDetected ? 'AUTO-DETECTED' : 'NOTHING PHONE (3A)',
                    style: TextStyle(
                      color: _isAutoDetected ? const Color(0xFF34C759) : const Color(0xFF8E8E93),
                      fontSize: 8.5,
                      fontFamily: 'ndot',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Top Margin Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOP MARGIN OFFSET',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
              Text(
                '$_topMargin DP',
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
              trackHeight: 3,
            ),
            child: Slider(
              value: _topMargin.toDouble(),
              min: 0,
              max: 35,
              divisions: 35,
              onChanged: (val) {
                setState(() => _topMargin = val.round());
              },
              onChangeEnd: (val) async {
                HapticFeedback.selectionClick();
                await _settings.setIslandTopMargin(val.round());
              },
            ),
          ),

          const SizedBox(height: 8),

          // Pill Width Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PILL WIDTH',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
              Text(
                '$_pillWidth DP',
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
              trackHeight: 3,
            ),
            child: Slider(
              value: _pillWidth.toDouble(),
              min: 160,
              max: 230,
              divisions: 14,
              onChanged: (val) {
                setState(() => _pillWidth = val.round());
              },
              onChangeEnd: (val) async {
                HapticFeedback.selectionClick();
                await _settings.setIslandPillWidth(val.round());
              },
            ),
          ),

          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _detectCutout,
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text(
              'RE-DETECT CAMERA CUTOUT',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'ndot',
                letterSpacing: 0.8,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

