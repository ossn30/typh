import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import 'selectable_segment.dart';

enum ShakeIntensityPreset {
  low(1.2, 'LOW', 'Gentle flick / light shake'),
  medium(2.7, 'MEDIUM', 'Balanced natural shake'),
  high(4.2, 'HIGH', 'Firm deliberate shake');

  final double threshold;
  final String label;
  final String description;

  const ShakeIntensityPreset(this.threshold, this.label, this.description);
}

/// 1st Card: Shake Intensity & Sensitivity Tuning
class ShakeIntensityCard extends StatelessWidget {
  final double currentThreshold;
  final ValueChanged<double> onThresholdChanged;

  const ShakeIntensityCard({
    super.key,
    required this.currentThreshold,
    required this.onThresholdChanged,
  });

  ShakeIntensityPreset get _currentPreset {
    if (currentThreshold <= 1.6) return ShakeIntensityPreset.low;
    if (currentThreshold >= 3.0) return ShakeIntensityPreset.high;
    return ShakeIntensityPreset.medium;
  }

  String get _thresholdDescription {
    if (currentThreshold <= 1.3) {
      return 'Ultra sensitive • Gentle wrist flick triggers torch';
    } else if (currentThreshold <= 1.8) {
      return 'Low intensity • Light shake triggers torch';
    } else if (currentThreshold <= 2.8) {
      return 'Medium intensity • Natural standard shake';
    } else if (currentThreshold <= 4.2) {
      return 'High intensity • Firm shake required to avoid false triggers';
    } else {
      return 'Maximum resistance • Vigorous hard shake required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = _currentPreset;

    return Container(
      decoration: const BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SHAKE INTENSITY',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontFamily: 'ndot',
                ),
              ),
              Text(
                '${currentThreshold.toStringAsFixed(1)}G',
                style: const TextStyle(
                  color: selectedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SelectableSegment(
                  title: 'LOW',
                  subtitle: '1.2G',
                  icon: Icons.bolt_rounded,
                  isSelected: preset == ShakeIntensityPreset.low,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onThresholdChanged(ShakeIntensityPreset.low.threshold);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableSegment(
                  title: 'MEDIUM',
                  subtitle: '2.2G',
                  icon: Icons.vibration_rounded,
                  isSelected: preset == ShakeIntensityPreset.medium,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onThresholdChanged(ShakeIntensityPreset.medium.threshold);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableSegment(
                  title: 'HIGH',
                  subtitle: '3.8G',
                  icon: Icons.shield_rounded,
                  isSelected: preset == ShakeIntensityPreset.high,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onThresholdChanged(ShakeIntensityPreset.high.threshold);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.vibration_rounded,
                color: Color(0xFF777777),
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: selectedColor,
                    inactiveTrackColor: const Color(0xFF262626),
                    thumbColor: Colors.white,
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: currentThreshold.clamp(1.1, 6.0),
                    min: 1.1,
                    max: 6.0,
                    divisions: 49,
                    onChanged: (val) {
                      final rounded = (val * 10).round() / 10;
                      if ((rounded - currentThreshold).abs() >= 0.05) {
                        HapticFeedback.selectionClick();
                        onThresholdChanged(rounded);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.electric_bolt_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Text(
              _thresholdDescription,
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2nd Card: Torch Brightness Controller
class TorchBrightnessCard extends StatelessWidget {
  final int brightness; // 400..4000
  final ValueChanged<int> onBrightnessChanged;

  const TorchBrightnessCard({
    super.key,
    required this.brightness,
    required this.onBrightnessChanged,
  });

  @override
  Widget build(BuildContext context) {
    final percent = ((brightness / 4000) * 100).round().clamp(10, 100);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TORCH BRIGHTNESS',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontFamily: 'ndot',
                ),
              ),
              Text(
                '$percent%',
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
              const Icon(
                Icons.flash_off_rounded,
                color: Color(0xFF777777),
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: selectedColor,
                    inactiveTrackColor: const Color(0xFF262626),
                    thumbColor: Colors.white,
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: brightness.toDouble(),
                    min: 400,
                    max: 4000,
                    divisions: 36,
                    onChanged: (val) {
                      final roundVal = val.round();
                      if (roundVal != brightness) {
                        HapticFeedback.selectionClick();
                        onBrightnessChanged(roundVal);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.flash_on_rounded, color: Colors.white, size: 16),
            ],
          ),
        ],
      ),
    );
  }
}

/// 3rd Card: Torch Live Status & Interactive Test Button
class TorchStatusCard extends StatelessWidget {
  final bool isTorchOn;
  final bool isRecentShake;
  final VoidCallback onToggleTorch;

  const TorchStatusCard({
    super.key,
    required this.isTorchOn,
    required this.isRecentShake,
    required this.onToggleTorch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
          bottomLeft: Radius.circular(35),
          bottomRight: Radius.circular(35),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isTorchOn
                      ? const Color(0x40FFD600)
                      : const Color(0xFF1F1F1F),
                ),
                child: Icon(
                  isTorchOn
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  color: isTorchOn
                      ? const Color(0xFFFFD600)
                      : const Color(0xFF666666),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isTorchOn ? 'TORCH ACTIVE' : 'TORCH STANDBY',
                    style: TextStyle(
                      color: isTorchOn ? Colors.white : const Color(0xFFAAAAAA),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ndot',
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRecentShake
                              ? selectedColor
                              : (isTorchOn
                                    ? const Color(0xFFFFD600)
                                    : const Color(0xFF555555)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isRecentShake
                            ? 'SHAKE DETECTED!'
                            : (isTorchOn
                                  ? '36 LEDs Illuminated'
                                  : 'Shake phone to toggle'),
                        style: TextStyle(
                          color: isRecentShake
                              ? selectedColor
                              : const Color(0xFF777777),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.mediumImpact();
                onToggleTorch();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isTorchOn ? selectedColor : appBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isTorchOn ? 'TURN OFF' : 'TEST TOGGLE',
                  style: TextStyle(
                    color: isTorchOn ? Colors.white : const Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
