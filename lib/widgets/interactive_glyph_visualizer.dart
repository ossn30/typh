import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';

/// Single source of truth for Nothing Phone (2a) / (3a) glyph visualizer geometry.
/// Guarantees that track drawing, LED dot placement, and touch hit-testing align with 100% pixel precision.
class GlyphGeometry {
  static Offset getCenter(Size size) {
    return Offset(size.width * 0.50, size.height * 0.48);
  }

  static double getShortest(Size size) {
    return math.min(size.width, size.height);
  }

  static double getCircleRadius(Size size) {
    return getShortest(size) * 0.355;
  }

  static double getTrackRadius(Size size) {
    return getShortest(size) * 0.410;
  }

  static double getTrackWidth(Size size) {
    return getShortest(size) * 0.058;
  }

  // --- Track Arcs (Flutter canvas angles: 0 rad = 3 o'clock, clockwise) ---
  // Track C (Right arc): spans from -54° to +54° (sweep = 108°)
  static const double trackCStartAngle = -54.0 * math.pi / 180.0;
  static const double trackCSweepAngle = 108.0 * math.pi / 180.0;

  // Track A (Upper-left arc): spans from -166° to -112° (sweep = 54°)
  static const double trackAStartAngle = -166.0 * math.pi / 180.0;
  static const double trackASweepAngle = 54.0 * math.pi / 180.0;

  // Track B (Lower-left arc): spans from 122° to 158° (sweep = 36°)
  static const double trackBStartAngle = 122.0 * math.pi / 180.0;
  static const double trackBSweepAngle = 36.0 * math.pi / 180.0;

  /// Returns the precise angular position (in radians) for any of the 36 addressable LEDs
  static double getChannelAngle(int channel) {
    if (channel >= 0 && channel < 20) {
      // Group C: 20 LEDs (C1..C20)
      // C1 starts at bottom (+49°), C20 ends at top (-49°)
      const double cStart = 49.0 * math.pi / 180.0;
      const double cEnd = -49.0 * math.pi / 180.0;
      final t = channel / 19.0;
      return cStart + (cEnd - cStart) * t;
    } else if (channel >= 20 && channel <= 30) {
      // Group A: 11 LEDs (A1..A11)
      // A1 starts at top (-116°), A11 ends at bottom (-162°)
      const double aStart = -116.0 * math.pi / 180.0;
      const double aEnd = -162.0 * math.pi / 180.0;
      final t = (channel - 20) / 10.0;
      return aStart + (aEnd - aStart) * t;
    } else if (channel >= 31 && channel <= 35) {
      // Group B: 5 LEDs (B1..B5)
      // B1 starts at bottom-right (126°), B5 ends at top-left (154°)
      const double bStart = 126.0 * math.pi / 180.0;
      const double bEnd = 154.0 * math.pi / 180.0;
      final t = (channel - 31) / 4.0;
      return bStart + (bEnd - bStart) * t;
    }
    return 0.0;
  }

  /// Calculates the exact pixel center for channel [channel] given the visualizer canvas [size]
  static Offset getDotCenter(int channel, Size size) {
    final center = getCenter(size);
    final radius = getTrackRadius(size);
    final angle = getChannelAngle(channel);
    return center + Offset(radius * math.cos(angle), radius * math.sin(angle));
  }
}

class InteractiveGlyphVisualizer extends StatefulWidget {
  final Set<int> activeChannels;
  final ValueChanged<Set<int>> onChannelsChanged;
  final int brightness;
  final double height;
  final ValueChanged<bool>? onSwipeLockChanged;

  const InteractiveGlyphVisualizer({
    super.key,
    required this.activeChannels,
    required this.onChannelsChanged,
    this.brightness = 4000,
    this.height = 350,
    this.onSwipeLockChanged,
  });

  @override
  State<InteractiveGlyphVisualizer> createState() =>
      _InteractiveGlyphVisualizerState();
}

class _InteractiveGlyphVisualizerState
    extends State<InteractiveGlyphVisualizer> {
  // Gesture dragging state
  bool? _dragActionAdd; // true = painting ON, false = erasing OFF
  final Set<int> _dragVisitedChannels = {};

  void _handleTouch(Offset localPos, Size size, {bool isInitial = false}) {
    // Comfortable touch radius for fingers
    const double hitRadius = 26.0;
    int? closestChannel;
    double closestDist = double.infinity;

    for (int ch = 0; ch < 36; ch++) {
      final dotCenter = GlyphGeometry.getDotCenter(ch, size);
      final dist = (localPos - dotCenter).distance;
      if (dist <= hitRadius && dist < closestDist) {
        closestDist = dist;
        closestChannel = ch;
      }
    }

    if (closestChannel == null) return;

    final ch = closestChannel;
    if (_dragVisitedChannels.contains(ch)) return;
    _dragVisitedChannels.add(ch);

    final currentChannels = Set<int>.from(widget.activeChannels);

    if (isInitial) {
      _dragActionAdd = !currentChannels.contains(ch);
    }

    if (_dragActionAdd == true) {
      currentChannels.add(ch);
    } else {
      currentChannels.remove(ch);
    }

    HapticFeedback.selectionClick();
    widget.onChannelsChanged(currentChannels);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = widget.height;
        final size = Size(width, height);

        return Listener(
          onPointerDown: (_) {
            widget.onSwipeLockChanged?.call(true);
          },
          onPointerUp: (_) {
            widget.onSwipeLockChanged?.call(false);
          },
          onPointerCancel: (_) {
            widget.onSwipeLockChanged?.call(false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              widget.onSwipeLockChanged?.call(true);
              _dragVisitedChannels.clear();
              _handleTouch(details.localPosition, size, isInitial: true);
            },
            onPanUpdate: (details) {
              _handleTouch(details.localPosition, size);
            },
            onPanEnd: (_) {
              _dragVisitedChannels.clear();
              _dragActionAdd = null;
              widget.onSwipeLockChanged?.call(false);
            },
            onPanCancel: () {
              _dragVisitedChannels.clear();
              _dragActionAdd = null;
              widget.onSwipeLockChanged?.call(false);
            },
            onTapDown: (details) {
              widget.onSwipeLockChanged?.call(true);
              _dragVisitedChannels.clear();
              _handleTouch(details.localPosition, size, isInitial: true);
              _dragVisitedChannels.clear();
              _dragActionAdd = null;
            },
            onTapUp: (_) {
              widget.onSwipeLockChanged?.call(false);
            },
            onTapCancel: () {
              widget.onSwipeLockChanged?.call(false);
            },
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.9),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Phone Camera Island, Sensor, and Glyph Arc Tracks (from Code)
                  CustomPaint(
                    size: size,
                    painter: _PhoneOutlinePainter(
                      activeChannels: widget.activeChannels,
                      brightness: widget.brightness,
                    ),
                  ),

                  // 2. Interactive LED Dots (36 Addressable LEDs placed squarely on the tracks)
                  for (int ch = 0; ch < 36; ch++) ...[
                    _buildPositionedDot(ch, size),
                  ],

                  // 3. Quick Hint Banner at bottom
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141416).withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                color: Color(0xFF888888),
                                size: 13,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'TAP OR SLIDE OVER LEDS TO SELECT',
                                style: TextStyle(
                                  color: Color(0xFF888888),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'ndot',
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPositionedDot(int channel, Size size) {
    final dotCenter = GlyphGeometry.getDotCenter(channel, size);
    final isLit = widget.activeChannels.contains(channel);
    const double dotRadius = 7.0; // 14px dot sits nicely inside 20px track

    return Positioned(
      left: dotCenter.dx - dotRadius,
      top: dotCenter.dy - dotRadius,
      child: IgnorePointer(
        // Touches handled smoothly by parent GestureDetector
        child: _LedDotWidget(
          channel: channel,
          isLit: isLit,
          brightness: widget.brightness,
        ),
      ),
    );
  }
}

/// Custom painter for Nothing Phone (2a) / (3a) back design
/// Renders:
/// 1. Outer circle
/// 2. Horizontal camera pill with left capsule and right circular lens ("the eyes")
/// 3. Upper sensor/flash dot at 11 o'clock
/// 4. Three curved glyph strip tracks with rounded end caps (Arc A, Arc B, Arc C)
class _PhoneOutlinePainter extends CustomPainter {
  final Set<int> activeChannels;
  final int brightness;

  _PhoneOutlinePainter({
    required this.activeChannels,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = GlyphGeometry.getCenter(size);
    final shortest = GlyphGeometry.getShortest(size);
    final circleRadius = GlyphGeometry.getCircleRadius(size);
    final trackRadius = GlyphGeometry.getTrackRadius(size);
    final trackWidth = GlyphGeometry.getTrackWidth(size);

    // Thin stroke for phone outlines
    final outlinePaint = Paint()
      ..color = const Color(0xFF2C2D30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // 1. Central Large Circle
    canvas.drawCircle(center, circleRadius, outlinePaint);

    // 2. Camera Pill ("The Eyes" outer container)
    final pillWidth = circleRadius * 1.34;
    final pillHeight = circleRadius * 0.58;
    final pillRect = Rect.fromCenter(
      center: center,
      width: pillWidth,
      height: pillHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, Radius.circular(pillHeight / 2)),
      outlinePaint,
    );

    // 3. Left Inner Lens Capsule
    final leftCapsuleRect = Rect.fromLTWH(
      pillRect.left + 7.0,
      pillRect.top + 6.0,
      pillWidth * 0.54,
      pillHeight - 12.0,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        leftCapsuleRect,
        Radius.circular((pillHeight - 12.0) / 2),
      ),
      outlinePaint,
    );

    // 4. Right Inner Circular Lens
    final rightLensCenter = Offset(pillRect.left + pillWidth * 0.77, center.dy);
    final rightLensRadius = (pillHeight - 12.0) / 2;
    canvas.drawCircle(rightLensCenter, rightLensRadius, outlinePaint);

    // 5. Sensor / Mic Dot (at 11 o'clock above camera pill)
    final sensorCenter = Offset(
      center.dx - circleRadius * 0.26,
      center.dy - circleRadius * 0.58,
    );
    canvas.drawCircle(sensorCenter, shortest * 0.022, outlinePaint);

    // 6. The Three Glyph Strip Tracks (dark charcoal beds with rounded end caps)
    final trackPaint = Paint()
      ..color = const Color(0xFF4A4A4E)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = trackWidth;

    final trackRect = Rect.fromCircle(center: center, radius: trackRadius);

    // Track C (Right Arc)
    canvas.drawArc(
      trackRect,
      GlyphGeometry.trackCStartAngle,
      GlyphGeometry.trackCSweepAngle,
      false,
      trackPaint,
    );

    // Track A (Upper-Left Arc)
    canvas.drawArc(
      trackRect,
      GlyphGeometry.trackAStartAngle,
      GlyphGeometry.trackASweepAngle,
      false,
      trackPaint,
    );

    // Track B (Lower-Left Arc)
    canvas.drawArc(
      trackRect,
      GlyphGeometry.trackBStartAngle,
      GlyphGeometry.trackBSweepAngle,
      false,
      trackPaint,
    );

    // 7. Glowing Neon Aura on active tracks
    final hasActiveC = activeChannels.any((c) => c >= 0 && c < 20);
    final hasActiveA = activeChannels.any((c) => c >= 20 && c <= 30);
    final hasActiveB = activeChannels.any((c) => c >= 31 && c <= 35);

    if (hasActiveC || hasActiveA || hasActiveB) {
      final glowPaint = Paint()
        ..color = selectedColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = trackWidth + 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

      if (hasActiveC) {
        canvas.drawArc(
          trackRect,
          GlyphGeometry.trackCStartAngle,
          GlyphGeometry.trackCSweepAngle,
          false,
          glowPaint,
        );
      }
      if (hasActiveA) {
        canvas.drawArc(
          trackRect,
          GlyphGeometry.trackAStartAngle,
          GlyphGeometry.trackASweepAngle,
          false,
          glowPaint,
        );
      }
      if (hasActiveB) {
        canvas.drawArc(
          trackRect,
          GlyphGeometry.trackBStartAngle,
          GlyphGeometry.trackBSweepAngle,
          false,
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PhoneOutlinePainter oldDelegate) {
    return oldDelegate.activeChannels != activeChannels ||
        oldDelegate.brightness != brightness;
  }
}

/// An individual interactive Glyph LED dot with authentic bloom/glow
class _LedDotWidget extends StatelessWidget {
  final int channel;
  final bool isLit;
  final int brightness;

  const _LedDotWidget({
    required this.channel,
    required this.isLit,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final glowOpacity = (brightness / 4000.0).clamp(0.4, 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLit ? selectedColor : const Color(0xFF222226),
        border: Border.all(
          color: isLit ? Colors.white : const Color(0xFF38383D),
          width: isLit ? 1.4 : 0.8,
        ),
        boxShadow: isLit
            ? [
                BoxShadow(
                  color: selectedColor.withValues(alpha: 0.85 * glowOpacity),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.6 * glowOpacity),
                  blurRadius: 3,
                  spreadRadius: 0.8,
                ),
              ]
            : null,
      ),
      child: Center(
        child: isLit
            ? Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              )
            : Container(
                width: 2.5,
                height: 2.5,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF3E3E44),
                ),
              ),
      ),
    );
  }
}
