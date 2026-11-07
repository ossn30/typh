import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/animation_service.dart';
import '../services/glyph_service.dart';
import '../services/settings_service.dart';
import '../widgets/animation_player_cards.dart';
import '../widgets/charging_cards.dart';
import '../widgets/shake_torch_cards.dart';
import '../widgets/timer_duration_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final GlyphService _glyph = GlyphService.instance;
  final AnimationService _animService = AnimationService.instance;
  final SettingsService _settings = SettingsService.instance;

  // Charging Animation Settings
  bool _chargingAnimationEnabled = true;
  late final AnimationController _chargingAnimController;
  late final Animation<double> _expandAnimation;
  late final Animation<double> _fadeAnimation;

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

  // Shake for Glyph Torch Settings
  bool _shakeTorchEnabled = false;
  double _shakeThreshold = 2.0; // 2.0G default (Medium)
  int _torchBrightness = 4000; // 400..4000
  bool _isRecentShake = false;
  StreamSubscription<double>? _shakeSubscription;
  Timer? _shakeHighlightTimer;
  late final AnimationController _shakeAnimController;
  late final Animation<double> _shakeExpandAnimation;
  late final Animation<double> _shakeFadeAnimation;

  @override
  void initState() {
    super.initState();

    // Restore persisted settings from device storage
    _chargingAnimationEnabled = _settings.chargingAnimationEnabled;
    _selectedArcs.clear();
    _selectedArcs.addAll(_settings.selectedArcs);
    _isClockwise = _settings.isClockwise;
    _isCombinedProgress = _settings.isCombinedProgress;
    _isDurationAlways = _settings.isDurationAlways;
    _timerDurationSeconds = _settings.timerDurationSeconds;
    _chargingBrightness = _settings.chargingBrightness;

    _shakeTorchEnabled = _settings.shakeTorchEnabled;
    _shakeThreshold = _settings.shakeThreshold;
    _torchBrightness = _settings.torchBrightness;

    _chargingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: _chargingAnimationEnabled ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _chargingAnimController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _chargingAnimController,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 0.7, curve: Curves.easeIn),
    );

    // Shake Torch Animation Controller
    _shakeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: _shakeTorchEnabled ? 1.0 : 0.0,
    );
    _shakeExpandAnimation = CurvedAnimation(
      parent: _shakeAnimController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _shakeFadeAnimation = CurvedAnimation(
      parent: _shakeAnimController,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 0.7, curve: Curves.easeIn),
    );

    _glyph.init();
    _glyph.batteryNotifier.addListener(_onBatteryStateChanged);

    if (_shakeTorchEnabled) {
      _glyph.setShakeDetection(enabled: true, threshold: _shakeThreshold);
    }

    // Listen to native accelerometer shake events
    _shakeSubscription = _glyph.onShakeDetected.listen((gForce) {
      _handleShakeDetected();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyChargingAnimationIfNeeded();
    });
  }

  @override
  void dispose() {
    _shakeSubscription?.cancel();
    _shakeHighlightTimer?.cancel();
    _shakeAnimController.dispose();
    _glyph.setShakeDetection(enabled: false);

    _chargingAnimController.dispose();
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
    _settings.setChargingAnimationEnabled(enabled);

    if (enabled) {
      _chargingAnimController.forward();
      _applyChargingAnimationIfNeeded();
    } else {
      _chargingAnimController.reverse();
      _chargingTimer?.cancel();
      _glyph.turnOffAll();
    }
  }

  void _toggleShakeTorch(bool enabled) {
    HapticFeedback.mediumImpact();
    setState(() {
      _shakeTorchEnabled = enabled;
    });
    _settings.setShakeTorchEnabled(enabled);

    if (enabled) {
      _shakeAnimController.forward();
      _glyph.setShakeDetection(enabled: true, threshold: _shakeThreshold);
    } else {
      _shakeAnimController.reverse();
      _glyph.setShakeDetection(enabled: false, threshold: _shakeThreshold);
      if (_glyph.isTorchOnNotifier.value) {
        _glyph.setTorch(false);
      }
    }
  }

  void _handleShakeDetected() {
    if (!_shakeTorchEnabled || !mounted) return;
    HapticFeedback.heavyImpact();

    setState(() {
      _isRecentShake = true;
    });
    _shakeHighlightTimer?.cancel();
    _shakeHighlightTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isRecentShake = false;
        });
      }
    });

    if (_animService.isPlayingNotifier.value) {
      _animService.stopAnimation();
    }
    _chargingTimer?.cancel();
    _glyph.toggleTorch(brightness: _torchBrightness);
  }

  void _updateShakeThreshold(double newThreshold) {
    setState(() {
      _shakeThreshold = newThreshold;
    });
    _settings.setShakeThreshold(newThreshold);
    if (_shakeTorchEnabled) {
      _glyph.setShakeDetection(enabled: true, threshold: newThreshold);
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
    _settings.setSelectedArcs(_selectedArcs);
    _applyChargingAnimationIfNeeded();
  }

  void _toggleDirection() {
    if (!_chargingAnimationEnabled) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isClockwise = !_isClockwise;
    });
    _settings.setIsClockwise(_isClockwise);
    _applyChargingAnimationIfNeeded();
  }

  void _toggleCombinedMode(bool combined) {
    if (!_chargingAnimationEnabled) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isCombinedProgress = combined;
    });
    _settings.setIsCombinedProgress(_isCombinedProgress);
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
            _settings.setTimerDurationSeconds(newSeconds);
            _settings.setIsDurationAlways(false);
            _applyChargingAnimationIfNeeded();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                // Category 1 Header: Charging Animation
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 0,
                  ),
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
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  alignment: Alignment.topCenter,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildChargingAnimationCategory(),
                  ),
                ),

                // Category 2 Header: Shake for Glyph Torch
                // const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SHAKE FOR GLYPH TORCH',
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
                          value: _shakeTorchEnabled,
                          activeTrackColor: selectedColor,
                          onChanged: _toggleShakeTorch,
                        ),
                      ),
                    ],
                  ),
                ),
                SizeTransition(
                  sizeFactor: _shakeExpandAnimation,
                  alignment: Alignment.topCenter,
                  child: FadeTransition(
                    opacity: _shakeFadeAnimation,
                    child: _buildShakeTorchCategory(),
                  ),
                ),

                // Category 3: Glyph Animations
                const SizedBox(height: 0),
                AnimationPlayerSection(
                  onAnimationStarted: () {
                    // Turn off charging timer or torch if animation starts
                    _chargingTimer?.cancel();
                    if (_glyph.isTorchOnNotifier.value) {
                      _glyph.setTorch(false);
                    }
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
          fontSize: 22,
          fontWeight: FontWeight.w700,
          fontFamily: 'Ndot',
        ),
      ),
      actions: [
        InkWell(
          onTap: () {
            launchUrl(Uri.parse('https://github.com/Ossn30'));
          },
          child: Row(
            children: [
              const Text(
                'by Ossn30',
                style: TextStyle(
                  color: selectedColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Ndot',
                ),
              ),
              SizedBox(width: 16),
            ],
          ),
        ),
      ],
      // actions: [
      //   ValueListenableBuilder<BatteryStatus>(
      //     valueListenable: _glyph.batteryNotifier,
      //     builder: (context, battery, _) {
      //       final isCharging = battery.isCharging || _simulateCharging;
      //       return Container(
      //         margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
      //         padding: const EdgeInsets.symmetric(horizontal: 10),
      //         decoration: BoxDecoration(
      //           color: isCharging
      //               ? const Color(0xFF1B2E1D)
      //               : const Color(0xFF1E1E1E),
      //           borderRadius: BorderRadius.circular(12),
      //         ),
      //         child: Row(
      //           mainAxisSize: MainAxisSize.min,
      //           children: [
      //             Icon(
      //               isCharging
      //                   ? Icons.bolt_rounded
      //                   : Icons.battery_full_rounded,
      //               color: isCharging
      //                   ? const Color.fromARGB(255, 0, 255, 13)
      //                   : const Color(0xFFAAAAAA),
      //               size: 14,
      //             ),
      //             Text(
      //               '${battery.level}%',
      //               style: TextStyle(
      //                 color: isCharging
      //                     ? const Color.fromARGB(255, 0, 255, 13)
      //                     : const Color(0xFFCCCCCC),
      //                 fontSize: 11,
      //                 fontWeight: FontWeight.w700,
      //                 fontFamily: 'ndot',
      //               ),
      //             ),
      //           ],
      //         ),
      //       );
      //     },
      //   ),
      //   const SizedBox(width: 16),
      // ],
    );
  }

  Widget _buildChargingAnimationCategory() {
    return IgnorePointer(
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
                _settings.setIsDurationAlways(true);
                _applyChargingAnimationIfNeeded();
              }
            },
            onSelectTimer: () {
              setState(() {
                _isDurationAlways = false;
              });
              _settings.setIsDurationAlways(false);
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
              _settings.setChargingBrightness(val);
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildShakeTorchCategory() {
    return IgnorePointer(
      ignoring: !_shakeTorchEnabled,
      child: Column(
        children: [
          ShakeIntensityCard(
            currentThreshold: _shakeThreshold,
            onThresholdChanged: _updateShakeThreshold,
          ),
          const SizedBox(height: 4),
          TorchBrightnessCard(
            brightness: _torchBrightness,
            onBrightnessChanged: (val) {
              setState(() {
                _torchBrightness = val;
              });
              _settings.setTorchBrightness(val);
              if (_glyph.isTorchOnNotifier.value) {
                _glyph.setTorch(true, brightness: val);
              }
            },
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<bool>(
            valueListenable: _glyph.isTorchOnNotifier,
            builder: (context, isTorchOn, _) {
              return TorchStatusCard(
                isTorchOn: isTorchOn,
                isRecentShake: _isRecentShake,
                onToggleTorch: () {
                  if (_animService.isPlayingNotifier.value) {
                    _animService.stopAnimation();
                  }
                  _chargingTimer?.cancel();
                  _glyph.toggleTorch(brightness: _torchBrightness);
                },
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }


}
