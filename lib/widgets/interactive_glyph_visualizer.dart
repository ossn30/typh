import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import 'glyph_strip_editor_dialog.dart';

/// Single source of truth for Nothing Phone (2a) / (3a) visualizer geometry,
/// measured with sub-pixel precision from the physical hardware schematic.
class GlyphGeometry {
  static Offset getCenter(Size size) {
    return Offset(size.width * 0.50, size.height * 0.50);
  }

  static double getShortest(Size size) {
    return math.min(size.width, size.height);
  }

  static double getCircleRadius(Size size) {
    return getShortest(size) * 0.395;
  }

  // --- Radius per Track ---
  static double getTrackRadius(int channel, Size size) {
    final shortest = getShortest(size);
    if (channel >= 0 && channel < 20) {
      // Arc C (upper-left) sits slightly further out
      return shortest * 0.448;
    }
    // Arc A (right) and Arc B (lower-left)
    return shortest * 0.434;
  }

  static double getTrackWidth(Size size) {
    return getShortest(size) * 0.040;
  }

  // --- Exact Track Arcs from Hardware Image ---
  // Track A (Right arc): from -17.0° to +33.0° (sweep = 50.0°)
  static const double trackAStartAngle = -8.0 * math.pi / 180.0;
  static const double trackASweepAngle = 40.0 * math.pi / 180.0;

  // Track C (Upper-left arc): from -163.0° to -120.0° (sweep = 43.0°)
  static const double trackCStartAngle = -173.0 * math.pi / 180.0;
  static const double trackCSweepAngle = 50.0 * math.pi / 180.0;

  // Track B (Lower-left arc): from 133.5° to 155.5° (sweep = 22.0°)
  static const double trackBStartAngle = 133.5 * math.pi / 180.0;
  static const double trackBSweepAngle = 22.0 * math.pi / 180.0;

  /// Returns the precise angular position (in radians) for each LED channel.
  /// All dots are positioned with safety margins from the track end caps.
  static double getChannelAngle(int channel) {
    if (channel >= 0 && channel < 20) {
      // Group C: 20 LEDs (C1..C20) on Upper-Left Arc
      // C1 starts at bottom (-160.5°), C20 ends at top (-122.5°)
      // Track spans -163.0° to -120.0°, so all dots are safely inside!
      const double cStart = -170.5 * math.pi / 180.0;
      const double cEnd = -124.5 * math.pi / 180.0;
      final t = channel / 19.0;
      return cStart + (cEnd - cStart) * t;
    } else if (channel >= 20 && channel <= 30) {
      // Group A: 11 LEDs (A1..A11) on Right Arc
      // A1 starts at top (-13.5°), A11 ends at bottom (+29.5°)
      // Track spans -17.0° to +33.0°, so all dots are safely inside!
      const double aStart = -6.5 * math.pi / 180.0;
      const double aEnd = 29.5 * math.pi / 180.0;
      final t = (channel - 20) / 10.0;
      return aStart + (aEnd - aStart) * t;
    } else if (channel >= 31 && channel <= 35) {
      // Group B: 5 LEDs (B1..B5) on Lower-Left Arc
      // B1 starts at bottom-right (136.0°), B5 ends at top-left (153.0°)
      // Track spans 133.5° to 155.5°, so all dots are safely inside!
      const double bStart = 136.0 * math.pi / 180.0;
      const double bEnd = 153.0 * math.pi / 180.0;
      final t = (channel - 31) / 4.0;
      return bStart + (bEnd - bStart) * t;
    }
    return 0.0;
  }

  /// Exact dot radius tailored to prevent any overlapping along each arc
  static double getDotRadius(int channel) {
    if (channel >= 0 && channel < 20) {
      // Group C (20 LEDs across 38°): 4.0px diameter leaves ~1.1px gap
      return 2.0;
    } else if (channel >= 20 && channel <= 30) {
      // Group A (11 LEDs across 43°): 5.0px diameter leaves ~5.5px gap
      return 2.5;
    } else {
      // Group B (5 LEDs across 17°): 5.6px diameter leaves ~5.7px gap
      return 2.8;
    }
  }

  /// Calculates the exact pixel center for channel [channel] given canvas [size]
  static Offset getDotCenter(int channel, Size size) {
    final center = getCenter(size);
    final radius = getTrackRadius(channel, size);
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
    this.height = 360,
    this.onSwipeLockChanged,
  });

  @override
  State<InteractiveGlyphVisualizer> createState() =>
      _InteractiveGlyphVisualizerState();
}

class _InteractiveGlyphVisualizerState
    extends State<InteractiveGlyphVisualizer> {
  bool? _dragActionAdd; // true = painting ON, false = erasing OFF
  final Set<int> _dragVisitedChannels = {};

  String? _detectTappedStrip(Offset localPos, Size size) {
    final center = GlyphGeometry.getCenter(size);
    final shortest = GlyphGeometry.getShortest(size);
    final dist = (localPos - center).distance;

    final trackRadius = shortest * 0.436;
    if ((dist - trackRadius).abs() > 48.0) {
      return null;
    }

    final angle =
        math.atan2(localPos.dy - center.dy, localPos.dx - center.dx) *
        180 /
        math.pi;

    // Right Strip: Arc A (-25° to +40°)
    if (angle >= -25.0 && angle <= 40.0) {
      return 'A';
    }
    // Upper-Left Strip: Arc C (-170° to -110°)
    if (angle <= -110.0 && angle >= -170.0) {
      return 'C';
    }
    // Lower-Left Strip: Arc B (125° to 165°)
    if (angle >= 125.0 && angle <= 165.0) {
      return 'B';
    }
    return null;
  }

  void _handleTouch(Offset localPos, Size size, {bool isInitial = false}) {
    // Generous touch hit-testing radius for comfortable finger interaction
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
            onTapUp: (details) {
              widget.onSwipeLockChanged?.call(false);
              final strip = _detectTappedStrip(details.localPosition, size);
              if (strip != null) {
                showGlyphStripEditorDialog(
                  context: context,
                  initialStrip: strip,
                  activeChannels: widget.activeChannels,
                  onChannelsChanged: widget.onChannelsChanged,
                  brightness: widget.brightness,
                );
              }
            },
            onTapCancel: () {
              widget.onSwipeLockChanged?.call(false);
            },
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(32),
                // border: Border.all(color: const Color.fromARGB(255, 0, 0, 0)),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Phone Camera Island, Sensor, and Glyph Arc Tracks
                  CustomPaint(
                    size: size,
                    painter: _PhoneOutlinePainter(
                      activeChannels: widget.activeChannels,
                      brightness: widget.brightness,
                    ),
                  ),

                  // 2. Interactive LED Dots (precisely aligned without overlap)
                  for (int ch = 0; ch < 36; ch++) ...[
                    _buildPositionedDot(ch, size),
                  ],

                  // 3. Quick Hint Banner at bottom (tap to open Straight Segment Editor)
                  // Positioned(
                  //   left: 16,
                  //   right: 16,
                  //   bottom: 10,
                  //   child: Center(
                  //     child: FittedBox(
                  //       fit: BoxFit.scaleDown,
                  //       child: Material(
                  //         color: Colors.transparent,
                  //         child: InkWell(
                  //           borderRadius: BorderRadius.circular(12),
                  //           onTap: () {
                  //             showGlyphStripEditorDialog(
                  //               context: context,
                  //               initialStrip: 'C',
                  //               activeChannels: widget.activeChannels,
                  //               onChannelsChanged: widget.onChannelsChanged,
                  //               brightness: widget.brightness,
                  //             );
                  //           },
                  //           child: Container(
                  //             padding: const EdgeInsets.symmetric(
                  //               horizontal: 12,
                  //               vertical: 5,
                  //             ),
                  //             decoration: BoxDecoration(
                  //               color: const Color(
                  //                 0xFF16171B,
                  //               ).withValues(alpha: 0.9),
                  //               borderRadius: BorderRadius.circular(12),
                  //               border: Border.all(
                  //                 color: Colors.white.withValues(alpha: 0.12),
                  //                 width: 1,
                  //               ),
                  //             ),
                  //             child: const Row(
                  //               mainAxisSize: MainAxisSize.min,
                  //               children: [
                  //                 Icon(
                  //                   Icons.open_in_full_rounded,
                  //                   color: selectedColor,
                  //                   size: 13,
                  //                 ),
                  //                 SizedBox(width: 6),
                  //                 Text(
                  //                   'TAP ANY STRIP FOR STRAIGHT SEGMENT EDITOR',
                  //                   style: TextStyle(
                  //                     color: Colors.white,
                  //                     fontSize: 9.5,
                  //                     fontWeight: FontWeight.w700,
                  //                     fontFamily: 'ndot',
                  //                     letterSpacing: 0.6,
                  //                   ),
                  //                 ),
                  //               ],
                  //             ),
                  //           ),
                  //         ),
                  //       ),
                  //     ),
                  //   ),
                  // ),
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
    final dotRadius = GlyphGeometry.getDotRadius(channel);
    final isLit = widget.activeChannels.contains(channel);

    return Positioned(
      left: dotCenter.dx - dotRadius - 2,
      top: dotCenter.dy - dotRadius - 1,
      child: IgnorePointer(
        child: _LedDotWidget(
          channel: channel,
          dotRadius: dotRadius,
          isLit: isLit,
          brightness: widget.brightness,
        ),
      ),
    );
  }
}

/// Custom painter for Nothing Phone (2a) / (3a) back design
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
    final trackRadiusC = GlyphGeometry.getTrackRadius(0, size);
    final trackRadiusA = GlyphGeometry.getTrackRadius(20, size);
    final trackWidth = GlyphGeometry.getTrackWidth(size);

    // Subtle dark stroke for camera island contours
    final outlinePaint = Paint()
      ..color = const Color(0xFF28282B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // 1. Central Large Circle
    canvas.drawCircle(center, circleRadius, outlinePaint);

    // 2. Camera Pill ("The Eyes" outer pill)
    final pillWidth = shortest * 0.645;
    final pillHeight = shortest * 0.282;
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
    final leftCapsuleWidth = shortest * 0.360;
    final leftCapsuleHeight = shortest * 0.179;
    final leftCapsuleRect = Rect.fromCenter(
      center: Offset(center.dx - shortest * 0.091, center.dy),
      width: leftCapsuleWidth,
      height: leftCapsuleHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        leftCapsuleRect,
        Radius.circular(leftCapsuleHeight / 2),
      ),
      outlinePaint,
    );

    // 4. Right Inner Circular Lens
    final rightLensCenter = Offset(center.dx + shortest * 0.176, center.dy);
    final rightLensRadius = shortest * 0.089;
    canvas.drawCircle(rightLensCenter, rightLensRadius, outlinePaint);

    // 5. Sensor / Mic Dot (vertically aligned with left capsule)
    final sensorCenter = Offset(
      center.dx - shortest * 0.091,
      center.dy - shortest * 0.270,
    );
    canvas.drawCircle(sensorCenter, shortest * 0.0216, outlinePaint);

    // 6. The Three Glyph Strip Tracks (dark charcoal beds with rounded end caps)
    final trackPaint = Paint()
      ..color = const Color(0xFF48484C)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = trackWidth;

    final trackRectC = Rect.fromCircle(center: center, radius: trackRadiusC);
    final trackRectA = Rect.fromCircle(center: center, radius: trackRadiusA);

    // Track A (Right Arc: from -17° to +33°)
    canvas.drawArc(
      trackRectA,
      GlyphGeometry.trackAStartAngle,
      GlyphGeometry.trackASweepAngle,
      false,
      trackPaint,
    );

    // Track C (Upper-Left Arc: from -163° to -120°)
    canvas.drawArc(
      trackRectC,
      GlyphGeometry.trackCStartAngle,
      GlyphGeometry.trackCSweepAngle,
      false,
      trackPaint,
    );

    // Track B (Lower-Left Arc: from 133.5° to 155.5°)
    canvas.drawArc(
      trackRectA,
      GlyphGeometry.trackBStartAngle,
      GlyphGeometry.trackBSweepAngle,
      false,
      trackPaint,
    );

    // 7. Glowing Neon Aura on active tracks
    // final hasActiveC = activeChannels.any((c) => c >= 0 && c < 20);
    // final hasActiveA = activeChannels.any((c) => c >= 20 && c <= 30);
    // final hasActiveB = activeChannels.any((c) => c >= 31 && c <= 35);

    // if (hasActiveC || hasActiveA || hasActiveB) {
    //   final glowPaint = Paint()
    //     ..color = selectedColor.withValues(alpha: 0.22)
    //     ..style = PaintingStyle.stroke
    //     ..strokeCap = StrokeCap.round
    //     ..strokeWidth = trackWidth + 5.0
    //     ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0);

    //   if (hasActiveC) {
    //     canvas.drawArc(
    //       trackRectC,
    //       GlyphGeometry.trackCStartAngle,
    //       GlyphGeometry.trackCSweepAngle,
    //       false,
    //       glowPaint,
    //     );
    //   }
    //   if (hasActiveA) {
    //     canvas.drawArc(
    //       trackRectA,
    //       GlyphGeometry.trackAStartAngle,
    //       GlyphGeometry.trackASweepAngle,
    //       false,
    //       glowPaint,
    //     );
    //   }
    //   if (hasActiveB) {
    //     canvas.drawArc(
    //       trackRectC,
    //       GlyphGeometry.trackBStartAngle,
    //       GlyphGeometry.tra ckBSweepAngle,
    //       false,
    //       glowPaint,
    //     );
    //   }
    // }
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
  final double dotRadius;
  final bool isLit;
  final int brightness;

  const _LedDotWidget({
    required this.channel,
    required this.dotRadius,
    required this.isLit,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final size = dotRadius * 3.5;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLit ? whiteColor : Colors.black,
      ),
      // ),
    );
  }
}
