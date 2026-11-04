import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../models/glyph_animation.dart';
import '../services/animation_service.dart';
import '../services/glyph_service.dart';
import '../widgets/glyph_strip_editor_dialog.dart';
import '../widgets/interactive_glyph_visualizer.dart';

class ComposeScreen extends StatefulWidget {
  final VoidCallback? onAnimationSaved;
  final ValueChanged<bool>? onSwipeLockChanged;

  const ComposeScreen({
    super.key,
    this.onAnimationSaved,
    this.onSwipeLockChanged,
  });

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final GlyphService _glyph = GlyphService.instance;
  final AnimationService _animService = AnimationService.instance;

  final TextEditingController _nameController = TextEditingController(
    text: 'My Custom Animation',
  );

  bool _loop = true;
  int _activeFrameIndex = 0;

  // Playback & testing states
  bool _isPlayingLoop = false;
  bool _isPlayingOnce = false;
  bool _isTestingFrame = false;
  Timer? _playbackOnceTimer;

  // List of frames being composed
  final List<GlyphAnimationFrame> _frames = [
    const GlyphAnimationFrame(
      durationMs: 50,
      channels: {0, 1, 2, 20, 31},
      brightness: 4000,
    ),
    const GlyphAnimationFrame(
      durationMs: 50,
      channels: {3, 4, 5, 21, 32},
      brightness: 4000,
    ),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _playbackOnceTimer?.cancel();
    _stopPlayback();
    _glyph.turnOffAll();
    super.dispose();
  }

  GlyphAnimationFrame get _currentFrame {
    if (_activeFrameIndex >= _frames.length) {
      _activeFrameIndex = _frames.length - 1;
    }
    return _frames[_activeFrameIndex];
  }

  int get _totalDurationMs {
    return _frames.fold(0, (sum, f) => sum + f.durationMs);
  }

  void _updateFrameAtIndex(
    int index, {
    int? durationMs,
    Set<int>? channels,
    int? brightness,
  }) {
    if (index < 0 || index >= _frames.length) return;
    setState(() {
      final f = _frames[index];
      _frames[index] = GlyphAnimationFrame(
        durationMs: durationMs ?? f.durationMs,
        channels: channels ?? f.channels,
        brightness: brightness ?? f.brightness,
      );
    });
  }

  void _updateCurrentFrame({
    int? durationMs,
    Set<int>? channels,
    int? brightness,
  }) {
    _updateFrameAtIndex(
      _activeFrameIndex,
      durationMs: durationMs,
      channels: channels,
      brightness: brightness,
    );
  }

  void _openStripEditor(String strip) {
    showGlyphStripEditorDialog(
      context: context,
      initialStrip: strip,
      activeChannels: _currentFrame.channels,
      brightness: _currentFrame.brightness,
      onChannelsChanged: (newChannels) {
        _updateCurrentFrame(channels: newChannels);
        if (_isTestingFrame) {
          _glyph.setChannels(newChannels, brightness: _currentFrame.brightness);
        }
      },
    );
  }

  void _clearAllChannels() {
    HapticFeedback.lightImpact();
    _updateCurrentFrame(channels: <int>{});
    if (_isTestingFrame) {
      _glyph.turnOffAll();
    }
  }

  void _selectAll36Channels() {
    HapticFeedback.lightImpact();
    final all36 = List.generate(36, (i) => i).toSet();
    _updateCurrentFrame(channels: all36);
    if (_isTestingFrame) {
      _glyph.setChannels(all36, brightness: _currentFrame.brightness);
    }
  }

  void _invertChannels() {
    HapticFeedback.lightImpact();
    final current = _currentFrame.channels;
    final inverted = List.generate(
      36,
      (i) => i,
    ).where((i) => !current.contains(i)).toSet();
    _updateCurrentFrame(channels: inverted);
    if (_isTestingFrame) {
      _glyph.setChannels(inverted, brightness: _currentFrame.brightness);
    }
  }

  void _addNewFrame() {
    HapticFeedback.mediumImpact();
    setState(() {
      _frames.add(
        GlyphAnimationFrame(
          durationMs: _currentFrame.durationMs,
          channels: Set<int>.from(_currentFrame.channels),
          brightness: _currentFrame.brightness,
        ),
      );
      _activeFrameIndex = _frames.length - 1;
    });
    if (_isTestingFrame) {
      _glyph.setChannels(
        _currentFrame.channels,
        brightness: _currentFrame.brightness,
      );
    }
  }

  void _duplicateFrame() {
    HapticFeedback.lightImpact();
    setState(() {
      _frames.insert(
        _activeFrameIndex + 1,
        GlyphAnimationFrame(
          durationMs: _currentFrame.durationMs,
          channels: Set<int>.from(_currentFrame.channels),
          brightness: _currentFrame.brightness,
        ),
      );
      _activeFrameIndex++;
    });
    if (_isTestingFrame) {
      _glyph.setChannels(
        _currentFrame.channels,
        brightness: _currentFrame.brightness,
      );
    }
  }

  void _deleteCurrentFrame() {
    if (_frames.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least 1 frame is required in an animation.'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _frames.removeAt(_activeFrameIndex);
      if (_activeFrameIndex >= _frames.length) {
        _activeFrameIndex = _frames.length - 1;
      }
    });
    if (_isTestingFrame) {
      _glyph.setChannels(
        _currentFrame.channels,
        brightness: _currentFrame.brightness,
      );
    }
  }

  // --- Playback & Test Frame Logic ---

  void _stopPlayback() {
    _playbackOnceTimer?.cancel();
    if (_isPlayingLoop || _isPlayingOnce) {
      setState(() {
        _isPlayingLoop = false;
        _isPlayingOnce = false;
      });
      _animService.stopAnimation();
    }
  }

  void _togglePlayLoop() {
    HapticFeedback.mediumImpact();
    if (_isPlayingLoop) {
      _stopPlayback();
      return;
    }

    // Stop any existing playback or test frame
    _stopPlayback();
    if (_isTestingFrame) {
      _isTestingFrame = false;
      _glyph.turnOffAll();
    }

    setState(() {
      _isPlayingLoop = true;
    });

    final anim = GlyphAnimation(
      id: 'preview_loop_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim().isEmpty
          ? 'Loop Preview'
          : _nameController.text.trim(),
      description: 'Looping preview sequence',
      path: '',
      loop: true,
      frames: _frames,
    );
    _animService.playAnimation(anim);
  }

  void _togglePlayOnce() {
    HapticFeedback.mediumImpact();
    if (_isPlayingOnce) {
      _stopPlayback();
      return;
    }

    // Stop any existing playback or test frame
    _stopPlayback();
    if (_isTestingFrame) {
      _isTestingFrame = false;
      _glyph.turnOffAll();
    }

    setState(() {
      _isPlayingOnce = true;
    });

    final anim = GlyphAnimation(
      id: 'preview_once_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim().isEmpty
          ? 'Once Preview'
          : _nameController.text.trim(),
      description: 'Single-run preview sequence',
      path: '',
      loop: false,
      frames: _frames,
    );
    _animService.playAnimation(anim);

    _playbackOnceTimer?.cancel();
    _playbackOnceTimer = Timer(
      Duration(milliseconds: _totalDurationMs + 50),
      () {
        if (mounted && _isPlayingOnce) {
          setState(() {
            _isPlayingOnce = false;
          });
        }
      },
    );
  }

  void _toggleTestFrame() {
    HapticFeedback.lightImpact();
    _stopPlayback();

    setState(() {
      _isTestingFrame = !_isTestingFrame;
    });

    if (_isTestingFrame) {
      _glyph.setChannels(
        _currentFrame.channels,
        brightness: _currentFrame.brightness,
      );
    } else {
      _glyph.turnOffAll();
    }
  }

  // --- Save Dialog & Persistence ---

  void _showSaveDialog() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.2,
                ),
              ),
              title: const Row(
                children: [
                  Icon(Icons.save_rounded, color: selectedColor, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'SAVE ANIMATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'ndot',
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ANIMATION NAME',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        fontFamily: 'ndot',
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: appBackgroundColor,
                        hintText: 'Enter animation name...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF555555),
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'DEFAULT LOOP',
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            fontFamily: 'ndot',
                          ),
                        ),
                        Transform.scale(
                          scale: 0.8,
                          child: CupertinoSwitch(
                            value: _loop,
                            activeTrackColor: selectedColor,
                            onChanged: (val) {
                              HapticFeedback.lightImpact();
                              setDialogState(() => _loop = val);
                              setState(() => _loop = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: appBackgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_frames.length} FRAMES',
                            style: const TextStyle(
                              color: Color(0xFFCCCCCC),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'ndot',
                            ),
                          ),
                          Text(
                            'TOTAL: ${_totalDurationMs}MS',
                            style: const TextStyle(
                              color: selectedColor,
                              fontSize: 10,
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontWeight: FontWeight.w700,
                      fontFamily: 'ndot',
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) {
                      return;
                    }
                    Navigator.of(ctx).pop();
                    await _saveAnimation();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'SAVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ndot',
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveAnimation() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name for your animation.'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    final animId =
        'custom_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    final customAnim = GlyphAnimation(
      id: animId,
      name: name,
      description:
          'Custom user animation • ${_frames.length} frames • ${_totalDurationMs}ms',
      icon: 'auto_awesome',
      path: '',
      loop: _loop,
      isCustom: true,
      frames: _frames,
    );

    final success = await _animService.saveCustomAnimation(customAnim);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "$name" to Custom Animations!'),
          backgroundColor: const Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onAnimationSaved?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save animation. Please try again.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // --- Frame Settings Popover Sheet ---

  void _showFrameSettingsSheet(BuildContext context, int frameIndex) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final frame = _frames[frameIndex];
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              decoration: const BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 30,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.tune_rounded,
                            color: selectedColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'FRAME ${frameIndex + 1} SETTINGS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'ndot',
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: appBackgroundColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${frame.channels.length} LEDS LIT',
                          style: const TextStyle(
                            color: selectedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'ndot',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 1. Duration Slider & Presets
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'FRAME DURATION',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          fontFamily: 'ndot',
                        ),
                      ),
                      Text(
                        '${frame.durationMs}MS',
                        style: const TextStyle(
                          color: selectedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'ndot',
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: selectedColor,
                      inactiveTrackColor: const Color(0xFF262626),
                      thumbColor: Colors.white,
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: frame.durationMs.toDouble().clamp(20, 800),
                      min: 20,
                      max: 800,
                      divisions: 39,
                      onChanged: (val) {
                        final rounded = ((val / 20).round() * 20).clamp(
                          20,
                          800,
                        );
                        if (rounded != frame.durationMs) {
                          HapticFeedback.selectionClick();
                          setSheetState(() {});
                          _updateFrameAtIndex(frameIndex, durationMs: rounded);
                        }
                      },
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [30, 50, 80, 120, 200, 500].map((ms) {
                      final isCurrent = frame.durationMs == ms;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setSheetState(() {});
                          _updateFrameAtIndex(frameIndex, durationMs: ms);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? selectedColor
                                : appBackgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCurrent
                                  ? selectedColor
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            '${ms}ms',
                            style: TextStyle(
                              color: isCurrent
                                  ? Colors.white
                                  : const Color(0xFFCCCCCC),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'ndot',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 2. Brightness Slider & Presets
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'FRAME BRIGHTNESS',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          fontFamily: 'ndot',
                        ),
                      ),
                      Text(
                        '${((frame.brightness / 4000) * 100).round()}%',
                        style: const TextStyle(
                          color: selectedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'ndot',
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: selectedColor,
                      inactiveTrackColor: const Color(0xFF262626),
                      thumbColor: Colors.white,
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: frame.brightness.toDouble().clamp(400, 4000),
                      min: 400,
                      max: 4000,
                      divisions: 36,
                      onChanged: (val) {
                        final rounded = val.round();
                        if (rounded != frame.brightness) {
                          HapticFeedback.selectionClick();
                          setSheetState(() {});
                          _updateFrameAtIndex(frameIndex, brightness: rounded);
                          if (_isTestingFrame &&
                              frameIndex == _activeFrameIndex) {
                            _glyph.setChannels(
                              frame.channels,
                              brightness: rounded,
                            );
                          }
                        }
                      },
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children:
                        [
                          {'pct': 25, 'val': 1000},
                          {'pct': 50, 'val': 2000},
                          {'pct': 75, 'val': 3000},
                          {'pct': 100, 'val': 4000},
                        ].map((preset) {
                          final val = preset['val'] as int;
                          final pct = preset['pct'] as int;
                          final isCurrent =
                              (frame.brightness - val).abs() < 100;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setSheetState(() {});
                              _updateFrameAtIndex(frameIndex, brightness: val);
                              if (_isTestingFrame &&
                                  frameIndex == _activeFrameIndex) {
                                _glyph.setChannels(
                                  frame.channels,
                                  brightness: val,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? selectedColor
                                    : appBackgroundColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isCurrent
                                      ? selectedColor
                                      : Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Text(
                                '$pct%',
                                style: TextStyle(
                                  color: isCurrent
                                      ? Colors.white
                                      : const Color(0xFFCCCCCC),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'ndot',
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 22),

                  // Done Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'DONE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'ndot',
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'COMPOSE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFamily: 'ndot',
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _showSaveDialog,
            icon: const Icon(
              Icons.check_rounded,
              color: selectedColor,
              size: 18,
            ),
            label: const Text(
              'SAVE',
              style: TextStyle(
                color: selectedColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                fontFamily: 'ndot',
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Container(
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
              padding: const EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: 24,
              ),
              children: [
                // 1. Interactive Glyph Visualizer (First at top)
                _buildVisualizerCard(),
                const SizedBox(height: 14),

                // 2. Timeline Filmstrip (Second)
                _buildTimelineFilmstrip(),
                const SizedBox(height: 14),

                // 3. Playback Controls & Test Frame (Below Timeline)
                _buildPlaybackControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisualizerCard() {
    final frame = _currentFrame;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'GLYPH VISUALIZER',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      fontFamily: 'ndot',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selectedColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'F${_activeFrameIndex + 1}',
                      style: const TextStyle(
                        color: selectedColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '${frame.channels.length} / 36 LEDS LIT',
                style: const TextStyle(
                  color: selectedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick actions toolbar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildToolbarButton('ALL 36', _selectAll36Channels),
                const SizedBox(width: 6),
                _buildToolbarButton('ARC A (11)', () => _openStripEditor('A')),
                const SizedBox(width: 6),
                _buildToolbarButton('ARC C (20)', () => _openStripEditor('C')),
                const SizedBox(width: 6),
                _buildToolbarButton('ARC B (5)', () => _openStripEditor('B')),
                const SizedBox(width: 6),
                _buildToolbarButton('CLEAR', _clearAllChannels),
                const SizedBox(width: 6),
                _buildToolbarButton('INVERT', _invertChannels),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Interactive Glyph Visualizer Canvas
          InteractiveGlyphVisualizer(
            activeChannels: frame.channels,
            brightness: frame.brightness,
            height: 330,
            onSwipeLockChanged: widget.onSwipeLockChanged,
            onChannelsChanged: (newChannels) {
              _updateCurrentFrame(channels: newChannels);
              if (_isTestingFrame) {
                _glyph.setChannels(newChannels, brightness: frame.brightness);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: appBackgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'ndot',
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineFilmstrip() {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TIMELINE • FRAME ${_activeFrameIndex + 1} OF ${_frames.length}',
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontFamily: 'ndot',
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, size: 17),
                    color: selectedColor,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Customize Frame',
                    onPressed: () =>
                        _showFrameSettingsSheet(context, _activeFrameIndex),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    color: const Color(0xFFCCCCCC),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Duplicate Frame',
                    onPressed: _duplicateFrame,
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: const Color(0xFFFF5252),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Delete Frame',
                    onPressed: _deleteCurrentFrame,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _frames.length + 1,
              separatorBuilder: (context, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == _frames.length) {
                  // Add Frame Button
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _addNewFrame,
                      child: Container(
                        width: 64,
                        decoration: BoxDecoration(
                          color: appBackgroundColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: selectedColor,
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }

                final frame = _frames[index];
                final isSelected = index == _activeFrameIndex;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (isSelected) {
                        // Tapping again opens customization sheet
                        _showFrameSettingsSheet(context, index);
                      } else {
                        setState(() => _activeFrameIndex = index);
                        if (_isTestingFrame) {
                          _glyph.setChannels(
                            frame.channels,
                            brightness: frame.brightness,
                          );
                        }
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 64,
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? selectedColor : appBackgroundColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!isSelected)
                                Text(
                                  'F${index + 1}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFFCCCCCC),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'ndot',
                                  ),
                                ),
                              if (isSelected) ...[
                                GestureDetector(
                                  onTap: () =>
                                      _showFrameSettingsSheet(context, index),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(
                                      Icons.tune_rounded,
                                      size: 22,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${frame.durationMs}ms',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : const Color(0xFF777777),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'ndot',
                            ),
                          ),
                          // Text(
                          //   '${frame.channels.length} on',
                          //   style: TextStyle(
                          //     color: isSelected
                          //         ? Colors.white.withValues(alpha: 0.85)
                          //         : const Color(0xFF999999),
                          //     fontSize: 8,
                          //     fontWeight: FontWeight.w700,
                          //   ),
                          // ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls() {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Row 1: The two play buttons (PLAY LOOP and PLAY ONCE)
          Row(
            children: [
              Expanded(
                child: _buildPlayButton(
                  label: _isPlayingLoop ? 'STOP LOOP' : 'PLAY LOOP',
                  icon: _isPlayingLoop
                      ? Icons.stop_rounded
                      : Icons.repeat_rounded,
                  isActive: _isPlayingLoop,
                  onTap: _togglePlayLoop,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPlayButton(
                  label: _isPlayingOnce ? 'STOP' : 'PLAY ONCE',
                  icon: _isPlayingOnce
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  isActive: _isPlayingOnce,
                  onTap: _togglePlayOnce,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Test Frame (Toggleable!)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _toggleTestFrame,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: _isTestingFrame
                      ? const Color(0xFFFFD600).withValues(alpha: 0.15)
                      : appBackgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isTestingFrame
                        ? const Color(0xFFFFD600)
                        : Colors.white.withValues(alpha: 0.1),
                    width: _isTestingFrame ? 1.4 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isTestingFrame
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: _isTestingFrame
                          ? const Color(0xFFFFD600)
                          : const Color(0xFF888888),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isTestingFrame
                          ? 'TEST FRAME: ON (ACTIVE)'
                          : 'TEST FRAME (TOGGLE)',
                      style: TextStyle(
                        color: _isTestingFrame
                            ? const Color(0xFFFFD600)
                            : const Color(0xFFCCCCCC),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: isActive ? selectedColor : appBackgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? selectedColor
                  : Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
