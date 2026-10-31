import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../services/glyph_service.dart';
import 'selectable_segment.dart';
import 'timer_duration_dialog.dart';

/// 1st Card: Multi-select arcs (Arc A, Arc B, Arc C)
class MultiSelectArcsCard extends StatelessWidget {
  final Set<String> selectedArcs;
  final ValueChanged<String> onToggleArc;

  const MultiSelectArcsCard({
    super.key,
    required this.selectedArcs,
    required this.onToggleArc,
  });

  Widget _buildArcOptionButton({
    required String arcId,
    required String label,
    required String ledCount,
    required String description,
  }) {
    final bool isSelected = selectedArcs.contains(arcId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(25),
        onTap: () {
          HapticFeedback.lightImpact();
          onToggleArc(arcId);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : appBackgroundColor,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 14,
                    color: isSelected ? Colors.white : const Color(0xFF777777),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFFCCCCCC),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      fontFamily: 'ndot',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: _buildArcOptionButton(
              arcId: 'A',
              label: 'Arc A',
              ledCount: '11 LEDs',
              description: 'Right Arc',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildArcOptionButton(
              arcId: 'B',
              label: 'Arc B',
              ledCount: '5 LEDs',
              description: 'Lower Left',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildArcOptionButton(
              arcId: 'C',
              label: 'Arc C',
              ledCount: '20 LEDs',
              description: 'Upper Left',
            ),
          ),
        ],
      ),
    );
  }
}

/// 2nd Card: Direction (Clockwise / Anticlockwise)
class DirectionCard extends StatelessWidget {
  final bool isClockwise;
  final VoidCallback onToggleDirection;

  const DirectionCard({
    super.key,
    required this.isClockwise,
    required this.onToggleDirection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: SelectableSegment(
              title: 'CLOCKWISE',
              subtitle: 'Left to Right ↻',
              icon: Icons.rotate_right_rounded,
              isSelected: isClockwise,
              onTap: () {
                if (!isClockwise) onToggleDirection();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableSegment(
              title: 'ANTICLOCKWISE',
              subtitle: 'Right to Left ↺',
              icon: Icons.rotate_left_rounded,
              isSelected: !isClockwise,
              onTap: () {
                if (isClockwise) onToggleDirection();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 3rd Card: Multi-Arc Mode (Combined / Standalone)
class MultiArcModeCard extends StatelessWidget {
  final bool isCombined;
  final ValueChanged<bool> onToggleMode;

  const MultiArcModeCard({
    super.key,
    required this.isCombined,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: SelectableSegment(
              title: 'COMBINED',
              subtitle: 'Single Track',
              icon: Icons.link_rounded,
              isSelected: isCombined,
              onTap: () => onToggleMode(true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableSegment(
              title: 'STANDALONE',
              subtitle: 'Mirrored Arcs',
              icon: Icons.splitscreen_rounded,
              isSelected: !isCombined,
              onTap: () => onToggleMode(false),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4th Card: Duration (Always / Timer)
class DurationCard extends StatelessWidget {
  final bool isDurationAlways;
  final int timerDurationSeconds;
  final VoidCallback onSelectAlways;
  final VoidCallback onSelectTimer;

  const DurationCard({
    super.key,
    required this.isDurationAlways,
    required this.timerDurationSeconds,
    required this.onSelectAlways,
    required this.onSelectTimer,
  });

  @override
  Widget build(BuildContext context) {
    final timerLabel = formatDuration(timerDurationSeconds);
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: SelectableSegment(
              title: 'ALWAYS',
              subtitle: '',
              icon: Icons.all_inclusive_rounded,
              isSelected: isDurationAlways,
              onTap: onSelectAlways,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableSegment(
              title: 'TIMER $timerLabel',
              subtitle: '',
              icon: Icons.timer_outlined,
              isSelected: !isDurationAlways,
              onTap: onSelectTimer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 5th Card: Preview & Live Charging Status
class ChargingPreviewCard extends StatelessWidget {
  final BatteryStatus battery;
  final bool simulateCharging;
  final int simulationPercent;
  final ValueChanged<bool> onToggleSimulate;
  final ValueChanged<int> onPercentChanged;

  const ChargingPreviewCard({
    super.key,
    required this.battery,
    required this.simulateCharging,
    required this.simulationPercent,
    required this.onToggleSimulate,
    required this.onPercentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isPhysicallyCharging = battery.isCharging;
    final currentLevel = simulateCharging ? simulationPercent : battery.level;

    return Container(
      decoration: const BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(35),
          bottomLeft: Radius.circular(35),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CHARGING PREVIEW',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontFamily: 'ndot',
                ),
              ),
              Row(
                children: [
                  const Text(
                    'Test Preview',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'ndot',
                    ),
                  ),
                  const SizedBox(width: 3),
                  Transform.scale(
                    scale: 0.65,
                    child: CupertinoSwitch(
                      value: simulateCharging,
                      activeTrackColor: selectedColor,
                      onChanged: (val) {
                        HapticFeedback.mediumImpact();
                        onToggleSimulate(val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: appBackgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: (isPhysicallyCharging || simulateCharging)
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFFA000),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPhysicallyCharging
                        ? 'DEVICE CHARGING ($currentLevel%)'
                        : simulateCharging
                        ? 'TEST SIMULATION ($currentLevel%)'
                        : 'BATTERY LEVEL: $currentLevel%',
                    style: TextStyle(
                      color: (isPhysicallyCharging || simulateCharging)
                          ? const Color(0xFF81C784)
                          : const Color(0xFFCCCCCC),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
                Text(
                  '$currentLevel%',
                  style: const TextStyle(
                    color: Color(0xFFFF5252),
                    fontFamily: 'ndot',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (simulateCharging) ...[
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: selectedColor,
                      inactiveTrackColor: const Color(0xFF262626),
                      thumbColor: Colors.white,
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: simulationPercent.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (val) {
                        final roundVal = val.round();
                        if (roundVal != simulationPercent) {
                          HapticFeedback.selectionClick();
                          onPercentChanged(roundVal);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Card: Brightness Controller for Charging Animation
class BrightnessCard extends StatelessWidget {
  final int brightness; // 400..4000
  final ValueChanged<int> onBrightnessChanged;

  const BrightnessCard({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'BRIGHTNESS',
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
                Icons.brightness_low_rounded,
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
              const Icon(
                Icons.brightness_high_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ],
      ),
    );
  }
}


