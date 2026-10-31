import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../services/animation_service.dart';
import '../services/glyph_service.dart';
import '../widgets/animation_player_cards.dart';
import '../widgets/charging_cards.dart';
import '../widgets/timer_duration_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlyphService _glyph = GlyphService.instance;
  final AnimationService _animService = AnimationService.instance;

  // Charging Animation Settings
  bool _chargingAnimationEnabled = true;
  final Set<String> _selectedArcs = {'C'}; // 'C', 'A', 'B' (multiple allowed)
  bool _isClockwise = true; // true = Clockwise, false = Anticlockwise
  bool _isCombinedProgress =
      true; // true = Combined single track, false = Standalone
  bool _isDurationAlways = true; // true = Always, false = Timer
  int _timerDurationSeconds = 3; // Default 3s
  int _chargingBrightness = 4000; // Brightness controller (400..4000)
  Timer? _chargingTimer;
  bool _simulateCharging = false;
  int _simulationPercent = 75;

  @override
  void initState() {
    super.initState();
    _glyph.init();
    _glyph.batteryNotifier.addListener(_onBatteryStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyChargingAnimationIfNeeded();
    });
  }

  @override
  void dispose() {
    _glyph.batteryNotifier.removeListener(_onBatteryStateChanged);
    _chargingTimer?.cancel();
    _animService.stopAnimation();
    super.dispose();
  }

  void _onBatteryStateChanged() {
    if (_chargingAnimationEnabled && !_simulateCharging) {
      _applyChargingAnimationIfNeeded();
    }
  }

  void _applyChargingAnimationIfNeeded() {
    // If an animation is playing, do not override unless charging animation is actively changed
    if (_animService.isPlayingNotifier.value) {
      _animService.stopAnimation();
    }

    if (!_chargingAnimationEnabled) {
      _chargingTimer?.cancel();
      return;
    }

    final battery = _glyph.batteryNotifier.value;
    final isCharging = _simulateCharging || battery.isCharging;
    final level = _simulateCharging ? _simulationPercent : battery.level;

    if (isCharging) {
      final channels = GlyphService.computeChargingChannels(
        percentage: level,
        selectedArcs: _selectedArcs,
        isClockwise: _isClockwise,
        isCombined: _isCombinedProgress,
      );
      _glyph.setChannels(channels, brightness: _chargingBrightness);

      _chargingTimer?.cancel();
      if (!_isDurationAlways && _timerDurationSeconds > 0) {
        _chargingTimer = Timer(Duration(seconds: _timerDurationSeconds), () {
          if (mounted && !_isDurationAlways) {
            _glyph.turnOffAll();
          }
        });
      }
    } else {
      _chargingTimer?.cancel();
      _glyph.turnOffAll();
    }
  }

  void _toggleChargingAnimation(bool enabled) {
    HapticFeedback.mediumImpact();
    setState(() {
      _chargingAnimationEnabled = enabled;
    });

    if (enabled) {
      _applyChargingAnimationIfNeeded();
    } else {
      _chargingTimer?.cancel();
      _glyph.turnOffAll();
    }
  }

  void _toggleArcSelection(String arc) {
    if (!_chargingAnimationEnabled) return;
    setState(() {
      if (_selectedArcs.contains(arc)) {
        if (_selectedArcs.length > 1) {
          _selectedArcs.remove(arc);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('At least one arc must remain selected'),
              duration: Duration(seconds: 1),
            ),
          );
          return;
        }
      } else {
        _selectedArcs.add(arc);
      }
    });
    _applyChargingAnimationIfNeeded();
  }

  void _toggleDirection() {
    if (!_chargingAnimationEnabled) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isClockwise = !_isClockwise;
    });
    _applyChargingAnimationIfNeeded();
  }

  void _toggleCombinedMode(bool combined) {
    if (!_chargingAnimationEnabled) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isCombinedProgress = combined;
    });
    _applyChargingAnimationIfNeeded();
  }

  void _showTimerDurationDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return TimerDurationDialog(
          initialSeconds: _timerDurationSeconds,
          onSave: (newSeconds) {
            setState(() {
              _timerDurationSeconds = newSeconds;
              _isDurationAlways = false;
            });
            _applyChargingAnimationIfNeeded();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildTyphAppBar(),
      body: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: appBackgroundColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(45),
              topRight: Radius.circular(45),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(45),
              topRight: Radius.circular(45),
            ),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: [
                // Category 1 Header: Charging Animation
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CHARGING ANIMATION',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          fontFamily: 'ndot',
                        ),
                      ),
                      Transform.scale(
                        scale: 0.65,
                        child: CupertinoSwitch(
                          value: _chargingAnimationEnabled,
                          activeTrackColor: selectedColor,
                          onChanged: _toggleChargingAnimation,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildChargingAnimationCategory(),

                // Category 2: Glyph Animations
                const SizedBox(height: 20),
                AnimationPlayerSection(
                  onAnimationStarted: () {
                    // Turn off charging timer if animation starts
                    _chargingTimer?.cancel();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTyphAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      centerTitle: false,
      title: const Text(
        'Typh',
        style: TextStyle(
          color: Colors.white,
          fontSize: 25,
          fontFamily: 'Ndot',
        ),
      ),
      actions: [
        ValueListenableBuilder<BatteryStatus>(
          valueListenable: _glyph.batteryNotifier,
          builder: (context, battery, _) {
            final isCharging = battery.isCharging || _simulateCharging;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isCharging
                    ? const Color(0xFF1B2E1D)
                    : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCharging
                        ? Icons.bolt_rounded
                        : Icons.battery_full_rounded,
                    color: isCharging
                        ? const Color.fromARGB(255, 0, 255, 13)
                        : const Color(0xFFAAAAAA),
                    size: 14,
                  ),
                  Text(
                    '${battery.level}%',
                    style: TextStyle(
                      color: isCharging
                          ? const Color.fromARGB(255, 0, 255, 13)
                          : const Color(0xFFCCCCCC),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'ndot',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildChargingAnimationCategory() {
    return AnimatedOpacity(
      opacity: _chargingAnimationEnabled ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_chargingAnimationEnabled,
        child: Column(
          children: [
            MultiSelectArcsCard(
              selectedArcs: _selectedArcs,
              onToggleArc: _toggleArcSelection,
            ),
            const SizedBox(height: 4),
            DirectionCard(
              isClockwise: _isClockwise,
              onToggleDirection: _toggleDirection,
            ),
            const SizedBox(height: 4),
            MultiArcModeCard(
              isCombined: _isCombinedProgress,
              onToggleMode: _toggleCombinedMode,
            ),
            const SizedBox(height: 4),
            DurationCard(
              isDurationAlways: _isDurationAlways,
              timerDurationSeconds: _timerDurationSeconds,
              onSelectAlways: () {
                if (!_isDurationAlways) {
                  setState(() {
                    _isDurationAlways = true;
                  });
                  _applyChargingAnimationIfNeeded();
                }
              },
              onSelectTimer: () {
                setState(() {
                  _isDurationAlways = false;
                });
                _applyChargingAnimationIfNeeded();
                _showTimerDurationDialog();
              },
            ),
            const SizedBox(height: 4),
            BrightnessCard(
              brightness: _chargingBrightness,
              onBrightnessChanged: (val) {
                setState(() {
                  _chargingBrightness = val;
                });
                _applyChargingAnimationIfNeeded();
              },
            ),
            const SizedBox(height: 4),
            ValueListenableBuilder<BatteryStatus>(
              valueListenable: _glyph.batteryNotifier,
              builder: (context, battery, _) {
                return ChargingPreviewCard(
                  battery: battery,
                  simulateCharging: _simulateCharging,
                  simulationPercent: _simulationPercent,
                  onToggleSimulate: (val) {
                    setState(() {
                      _simulateCharging = val;
                    });
                    _applyChargingAnimationIfNeeded();
                  },
                  onPercentChanged: (val) {
                    setState(() {
                      _simulationPercent = val;
                    });
                    _applyChargingAnimationIfNeeded();
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
