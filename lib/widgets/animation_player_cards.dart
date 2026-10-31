import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../models/glyph_animation.dart';
import '../services/animation_service.dart';

class AnimationPlayerSection extends StatefulWidget {
  final VoidCallback? onAnimationStarted;

  const AnimationPlayerSection({
    super.key,
    this.onAnimationStarted,
  });

  @override
  State<AnimationPlayerSection> createState() => _AnimationPlayerSectionState();
}

class _AnimationPlayerSectionState extends State<AnimationPlayerSection> {
  final AnimationService _animService = AnimationService.instance;
  List<GlyphAnimation> _animations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnimations();
  }

  Future<void> _loadAnimations() async {
    final list = await _animService.loadAnimationsIndex();
    if (mounted) {
      setState(() {
        _animations = list;
        _isLoading = false;
      });
    }
  }

  IconData _getIconForId(String id) {
    switch (id) {
      case 'cyber_chase':
        return Icons.speed_rounded;
      case 'breathing_pulse':
        return Icons.air_rounded;
      case 'heartbeat':
        return Icons.favorite_rounded;
      case 'radar_scanner':
        return Icons.radar_rounded;
      case 'equalizer_wave':
        return Icons.graphic_eq_rounded;
      case 'strobe_alert':
        return Icons.flash_on_rounded;
      case 'orbit_spin':
        return Icons.sync_rounded;
      default:
        return Icons.play_arrow_rounded;
    }
  }

  BorderRadius _getBorderRadius(int index, int total) {
    if (total == 1) {
      return BorderRadius.circular(25);
    }
    if (index == 0) {
      return const BorderRadius.only(
        topLeft: Radius.circular(25),
        topRight: Radius.circular(25),
        bottomLeft: Radius.circular(6),
        bottomRight: Radius.circular(6),
      );
    }
    if (index == total - 1) {
      return const BorderRadius.only(
        topLeft: Radius.circular(6),
        topRight: Radius.circular(6),
        bottomLeft: Radius.circular(35),
        bottomRight: Radius.circular(35),
      );
    }
    return BorderRadius.circular(6);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GLYPH ANIMATIONS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  fontFamily: 'ndot',
                ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _animService.currentPlayingIdNotifier,
                builder: (context, playingId, _) {
                  if (playingId == null) return const SizedBox.shrink();
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _animService.stopAnimation();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: selectedColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: selectedColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: selectedColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'STOP ALL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'ndot',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: selectedColor,
              ),
            ),
          )
        else
          ValueListenableBuilder<String?>(
            valueListenable: _animService.currentPlayingIdNotifier,
            builder: (context, currentPlayingId, _) {
              return Column(
                children: List.generate(_animations.length, (index) {
                  final anim = _animations[index];
                  final isPlaying = currentPlayingId == anim.id;
                  final borderRadius =
                      _getBorderRadius(index, _animations.length);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: borderRadius,
                        onTap: () {
                          if (isPlaying) {
                            HapticFeedback.mediumImpact();
                            _animService.stopAnimation();
                          } else {
                            HapticFeedback.mediumImpact();
                            widget.onAnimationStarted?.call();
                            _animService.playAnimation(anim);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: borderRadius,
                            border: isPlaying
                                ? Border.all(color: selectedColor, width: 1.2)
                                : null,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              // Icon badge
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? selectedColor
                                      : appBackgroundColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getIconForId(anim.id),
                                  color: isPlaying
                                      ? Colors.white
                                      : const Color(0xFFCCCCCC),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      anim.name,
                                      style: TextStyle(
                                        color: isPlaying
                                            ? Colors.white
                                            : const Color(0xFFE0E0E0),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'ndot',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      anim.description,
                                      style: const TextStyle(
                                        color: Color(0xFF888888),
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Action Pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? selectedColor
                                      : appBackgroundColor,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPlaying
                                          ? Icons.stop_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isPlaying ? 'STOP' : 'PLAY',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'ndot',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
      ],
    );
  }
}

