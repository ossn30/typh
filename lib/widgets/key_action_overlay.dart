import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../models/key_action.dart';
import '../services/glyph_service.dart';

class KeyActionOverlay extends StatefulWidget {
  final KeyActionInfo action;
  final String triggerLabel;
  final String? customMessage;
  final VoidCallback onDismiss;

  const KeyActionOverlay({
    super.key,
    required this.action,
    required this.triggerLabel,
    this.customMessage,
    required this.onDismiss,
  });

  @override
  State<KeyActionOverlay> createState() => _KeyActionOverlayState();
}

class _KeyActionOverlayState extends State<KeyActionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Timer? _autoDismissTimer;
  double _brightnessValue = 0.5;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();

    // If brightness slider, load initial system brightness
    if (widget.action.type == KeyActionType.brightnessSlider) {
      GlyphService.instance.getSystemBrightness().then((val) {
        if (mounted) {
          setState(() => _brightnessValue = val);
        }
      });
      // Allow extra time for user to interact with the brightness slider
      _resetTimer(const Duration(milliseconds: 4000));
    } else {
      _resetTimer(const Duration(milliseconds: 2400));
    }
  }

  void _resetTimer(Duration duration) {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  void _onBrightnessChanged(double value) {
    HapticFeedback.selectionClick();
    setState(() => _brightnessValue = value);
    GlyphService.instance.setSystemBrightness(value);
    _resetTimer(const Duration(milliseconds: 3000));
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isBrightness = widget.action.type == KeyActionType.brightnessSlider;

    return Positioned(
      top: topPadding + 14,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: isBrightness ? null : _dismiss,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selectedColor.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: selectedColor.withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          // Glowing icon container
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: selectedColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.action.icon,
                              color: selectedColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: selectedColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      widget.triggerLabel.toUpperCase(),
                                      style: const TextStyle(
                                        color: selectedColor,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'ndot',
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.action.title.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'ndot',
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                if (widget.customMessage != null) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    widget.customMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFFA0A2AA),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF8E8E93),
                              size: 18,
                            ),
                            onPressed: _dismiss,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                        ],
                      ),
                      if (isBrightness) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: appBackgroundColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.brightness_low_rounded,
                                        color: Color(0xFF8E8E93),
                                        size: 16,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'BRIGHTNESS',
                                        style: TextStyle(
                                          color: Color(0xFF8E8E93),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'ndot',
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${(_brightnessValue * 100).round()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'ndot',
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      final val = (_brightnessValue - 0.1)
                                          .clamp(0.01, 1.0);
                                      _onBrightnessChanged(val);
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                  ),
                                  Expanded(
                                    child: CupertinoSlider(
                                      value: _brightnessValue,
                                      min: 0.01,
                                      max: 1.0,
                                      activeColor: selectedColor,
                                      onChanged: _onBrightnessChanged,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_outline_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      final val = (_brightnessValue + 0.1)
                                          .clamp(0.01, 1.0);
                                      _onBrightnessChanged(val);
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

