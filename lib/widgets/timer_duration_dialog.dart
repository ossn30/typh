import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';

String formatDuration(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  final mins = seconds ~/ 60;
  final remSecs = seconds % 60;
  if (remSecs == 0) {
    return '${mins}m';
  }
  return '${mins}m ${remSecs}s';
}

class TimerDurationDialog extends StatefulWidget {
  final int initialSeconds;
  final ValueChanged<int> onSave;

  const TimerDurationDialog({
    super.key,
    required this.initialSeconds,
    required this.onSave,
  });

  @override
  State<TimerDurationDialog> createState() => _TimerDurationDialogState();
}

class _TimerDurationDialogState extends State<TimerDurationDialog> {
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
  }

  static int progressToSeconds(double p) {
    if (p <= 0.0) return 0;
    if (p >= 1.0) return 1800;

    // Piecewise knob curve:
    // 0.0 .. 0.35 -> 0s .. 30s (by 1s steps)
    // 0.35 .. 0.65 -> 30s .. 300s (5m, by 5s steps)
    // 0.65 .. 1.0  -> 300s .. 1800s (30m, by 30s steps)
    if (p <= 0.35) {
      final frac = p / 0.35;
      return (frac * 30).round();
    } else if (p <= 0.65) {
      final frac = (p - 0.35) / 0.30;
      final sec = 30 + frac * 270;
      return ((sec / 5).round() * 5).clamp(30, 300);
    } else {
      final frac = (p - 0.65) / 0.35;
      final sec = 300 + frac * 1500;
      return ((sec / 30).round() * 30).clamp(300, 1800);
    }
  }

  static double secondsToProgress(int s) {
    if (s <= 0) return 0.0;
    if (s >= 1800) return 1.0;

    if (s <= 30) {
      return (s / 30.0) * 0.35;
    } else if (s <= 300) {
      return 0.35 + ((s - 30.0) / 270.0) * 0.30;
    } else {
      return 0.65 + ((s - 300.0) / 1500.0) * 0.35;
    }
  }

  void _handleGesture(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final angle = atan2(dy, dx);

    const startAngle = 135 * pi / 180;
    const sweepAngle = 270 * pi / 180;

    double diff = angle - startAngle;
    while (diff < 0) {
      diff += 2 * pi;
    }
    while (diff >= 2 * pi) {
      diff -= 2 * pi;
    }

    double p;
    if (diff <= sweepAngle) {
      p = diff / sweepAngle;
    } else {
      final gap = 2 * pi - sweepAngle;
      final gapProgress = (diff - sweepAngle) / gap;
      p = gapProgress < 0.5 ? 1.0 : 0.0;
    }

    final newSec = progressToSeconds(p);
    if (newSec != _seconds) {
      HapticFeedback.selectionClick();
      setState(() {
        _seconds = newSec;
      });
    }
  }

  Widget _buildStepButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: appBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _buildPresetChip(int sec, String label) {
    final isSelected = _seconds == sec;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _seconds = sec;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : appBackgroundColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFFCCCCCC),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'ndot',
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TIMER DURATION',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ndot',
                    letterSpacing: 1.0,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: appBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '0s - 30m',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 10,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Knob Control
            GestureDetector(
              onPanStart: (details) =>
                  _handleGesture(details.localPosition, const Size(190, 190)),
              onPanUpdate: (details) =>
                  _handleGesture(details.localPosition, const Size(190, 190)),
              onTapDown: (details) =>
                  _handleGesture(details.localPosition, const Size(190, 190)),
              child: SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(190, 190),
                      painter: _KnobPainter(
                        progress: secondsToProgress(_seconds),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatDuration(_seconds),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'ROTATE KNOB',
                          style: TextStyle(
                            color: Color(0xFF777777),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'ndot',
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Fine tuning +/- row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepButton(
                  icon: Icons.remove_rounded,
                  onTap: () {
                    setState(() {
                      if (_seconds <= 10) {
                        _seconds = (_seconds - 1).clamp(0, 1800);
                      } else if (_seconds <= 60) {
                        _seconds = (_seconds - 5).clamp(0, 1800);
                      } else {
                        _seconds = (_seconds - 30).clamp(0, 1800);
                      }
                    });
                  },
                ),
                const SizedBox(width: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: appBackgroundColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    formatDuration(_seconds),
                    style: const TextStyle(
                      color: Color(0xFFFF5252),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ndot',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _buildStepButton(
                  icon: Icons.add_rounded,
                  onTap: () {
                    setState(() {
                      if (_seconds < 10) {
                        _seconds = (_seconds + 1).clamp(0, 1800);
                      } else if (_seconds < 60) {
                        _seconds = (_seconds + 5).clamp(0, 1800);
                      } else {
                        _seconds = (_seconds + 30).clamp(0, 1800);
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick Preset Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _buildPresetChip(3, '3s'),
                _buildPresetChip(5, '5s'),
                _buildPresetChip(10, '10s'),
                _buildPresetChip(30, '30s'),
                _buildPresetChip(60, '1m'),
                _buildPresetChip(300, '5m'),
                _buildPresetChip(1800, '30m'),
              ],
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: appBackgroundColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'CANCEL',
                          style: TextStyle(
                            color: Color(0xFFCCCCCC),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        widget.onSave(_seconds);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'SET TIMER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double progress;

  _KnobPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 12;
    const startAngle = 135 * pi / 180;
    const sweepAngle = 270 * pi / 180;

    // 1. Background Arc Track
    final trackPaint = Paint()
      ..color = const Color(0xFF232427)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // 2. Active Progress Arc
    if (progress > 0.001) {
      final activePaint = Paint()
        ..color = const Color(0xFFE10600)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        startAngle,
        sweepAngle * progress.clamp(0.0, 1.0),
        false,
        activePaint,
      );
    }

    // 3. Dial tick dots around the track
    final tickPaint = Paint()
      ..color = const Color(0xFF44474E)
      ..style = PaintingStyle.fill;
    const tickCount = 12;
    for (int i = 0; i <= tickCount; i++) {
      final tAngle = startAngle + (sweepAngle * (i / tickCount));
      final tx = center.dx + (outerRadius + 8) * cos(tAngle);
      final ty = center.dy + (outerRadius + 8) * sin(tAngle);
      canvas.drawCircle(Offset(tx, ty), 1.5, tickPaint);
    }

    // 4. Central Knob Body
    final knobRadius = outerRadius - 16;
    final knobPaint = Paint()
      ..color = const Color(0xFF161719)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, knobRadius, knobPaint);

    final knobBorderPaint = Paint()
      ..color = const Color(0xFF2C2D31)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, knobRadius, knobBorderPaint);

    // 5. Indicator Notch on Knob Rim
    final currentAngle = startAngle + sweepAngle * progress.clamp(0.0, 1.0);
    final indicatorX = center.dx + (knobRadius - 8) * cos(currentAngle);
    final indicatorY = center.dy + (knobRadius - 8) * sin(currentAngle);

    final indicatorPaint = Paint()
      ..color = const Color(0xFFE10600)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(indicatorX, indicatorY), 4, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

