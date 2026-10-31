import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../services/glyph_service.dart';

/// Opens the custom straight strip editor dialog for fine-grained LED segment editing.
Future<void> showGlyphStripEditorDialog({
  required BuildContext context,
  required String initialStrip,
  required Set<int> activeChannels,
  required ValueChanged<Set<int>> onChannelsChanged,
  int brightness = 4000,
}) {
  HapticFeedback.mediumImpact();
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => GlyphStripEditorDialog(
      initialStrip: initialStrip,
      activeChannels: activeChannels,
      onChannelsChanged: onChannelsChanged,
      brightness: brightness,
    ),
  );
}

class GlyphStripEditorDialog extends StatefulWidget {
  final String initialStrip; // 'C', 'A', or 'B'
  final Set<int> activeChannels;
  final ValueChanged<Set<int>> onChannelsChanged;
  final int brightness;

  const GlyphStripEditorDialog({
    super.key,
    required this.initialStrip,
    required this.activeChannels,
    required this.onChannelsChanged,
    this.brightness = 4000,
  });

  @override
  State<GlyphStripEditorDialog> createState() => _GlyphStripEditorDialogState();
}

class _GlyphStripEditorDialogState extends State<GlyphStripEditorDialog> {
  late String _selectedStrip;
  late Set<int> _currentChannels;
  final Set<int> _dragVisited = {};
  bool? _dragAdd;

  @override
  void initState() {
    super.initState();
    _selectedStrip = widget.initialStrip.toUpperCase();
    _currentChannels = Set<int>.from(widget.activeChannels);
  }

  /// Ordered channels from physical TOP to physical BOTTOM
  List<int> get _stripChannels {
    switch (_selectedStrip) {
      case 'A':
        // Top A1 (20) to Bottom A11 (30)
        return List.generate(11, (i) => 20 + i);
      case 'B':
        // Top B5 (35) to Bottom B1 (31)
        return List.generate(5, (i) => 35 - i);
      case 'C':
      default:
        // Top C20 (19) to Bottom C1 (0)
        return List.generate(20, (i) => 19 - i);
    }
  }

  String _getChannelLabel(int channel) {
    if (channel >= 0 && channel < 20) {
      return 'C${channel + 1}';
    } else if (channel >= 20 && channel <= 30) {
      return 'A${channel - 19}';
    } else {
      return 'B${channel - 30}';
    }
  }

  String get _stripTitle {
    switch (_selectedStrip) {
      case 'A':
        return 'ARC A • RIGHT ARC';
      case 'B':
        return 'ARC B • LOWER LEFT';
      case 'C':
      default:
        return 'ARC C • UPPER LEFT';
    }
  }

  void _updateChannels(Set<int> newChannels) {
    setState(() {
      _currentChannels = newChannels;
    });
    widget.onChannelsChanged(newChannels);
    // Live preview on physical hardware
    GlyphService.instance.setChannels(
      newChannels,
      brightness: widget.brightness,
    );
  }

  void _toggleChannel(int channel) {
    HapticFeedback.selectionClick();
    final updated = Set<int>.from(_currentChannels);
    if (updated.contains(channel)) {
      updated.remove(channel);
    } else {
      updated.add(channel);
    }
    _updateChannels(updated);
  }

  void _selectAllInStrip() {
    HapticFeedback.lightImpact();
    final updated = Set<int>.from(_currentChannels)..addAll(_stripChannels);
    _updateChannels(updated);
  }

  void _clearAllInStrip() {
    HapticFeedback.lightImpact();
    final updated = Set<int>.from(_currentChannels)..removeAll(_stripChannels);
    _updateChannels(updated);
  }

  void _invertInStrip() {
    HapticFeedback.lightImpact();
    final updated = Set<int>.from(_currentChannels);
    for (final ch in _stripChannels) {
      if (updated.contains(ch)) {
        updated.remove(ch);
      } else {
        updated.add(ch);
      }
    }
    _updateChannels(updated);
  }

  void _handleDragTouch(double localY, double totalHeight) {
    final channels = _stripChannels;
    final count = channels.length;
    final segHeight = totalHeight / count;
    final index = (localY / segHeight).floor().clamp(0, count - 1);
    final ch = channels[index];

    if (_dragVisited.contains(ch)) return;
    _dragVisited.add(ch);

    _dragAdd ??= !_currentChannels.contains(ch);

    final updated = Set<int>.from(_currentChannels);
    if (_dragAdd == true) {
      updated.add(ch);
    } else {
      updated.remove(ch);
    }

    HapticFeedback.selectionClick();
    _updateChannels(updated);
  }

  @override
  Widget build(BuildContext context) {
    final channels = _stripChannels;
    final activeInStrip = channels
        .where((c) => _currentChannels.contains(c))
        .length;

    // Height of the straight strip adapted to segment count
    final double stripHeight = _selectedStrip == 'B'
        ? 260.0
        : _selectedStrip == 'A'
        ? 340.0
        : 390.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.linear_scale_rounded,
                      color: selectedColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _stripTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'ndot',
                        letterSpacing: 0.8,
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
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    '$activeInStrip / ${channels.length} ON',
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
            const SizedBox(height: 12),

            // 2. Strip Switcher Tabs (ARC C, ARC A, ARC B)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: appBackgroundColor,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  _buildStripTab('A', 'ARC A (11)'),
                  _buildStripTab('C', 'ARC C (20)'),
                  _buildStripTab('B', 'ARC B (5)'),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 3. Quick Action Buttons for current strip
            Row(
              children: [
                _buildQuickAction('SELECT ALL', _selectAllInStrip),
                const SizedBox(width: 6),
                _buildQuickAction('CLEAR', _clearAllInStrip),
                const SizedBox(width: 6),
                _buildQuickAction('INVERT', _invertInStrip),
              ],
            ),
            const SizedBox(height: 14),

            // 4. Center: Straight Vertical Strip with Cuts and Labels
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // The Vertical Segmented Strip
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) {
                          _dragVisited.clear();
                          _dragAdd = null;
                          _handleDragTouch(d.localPosition.dy, stripHeight);
                        },
                        onPanUpdate: (d) {
                          _handleDragTouch(d.localPosition.dy, stripHeight);
                        },
                        onPanEnd: (_) {
                          _dragVisited.clear();
                          _dragAdd = null;
                        },
                        onTapDown: (d) {
                          _dragVisited.clear();
                          _dragAdd = null;
                          _handleDragTouch(d.localPosition.dy, stripHeight);
                          _dragVisited.clear();
                          _dragAdd = null;
                        },
                        child: Container(
                          width: 66,
                          height: stripHeight,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Column(
                              children: List.generate(channels.length, (idx) {
                                final ch = channels[idx];
                                final isLit = _currentChannels.contains(ch);
                                final isFirst = idx == 0;
                                final isLast = idx == channels.length - 1;

                                return Expanded(
                                  child: Container(
                                    margin: EdgeInsets.only(
                                      bottom: isLast
                                          ? 0
                                          : 1.5, // Thin cut between segments
                                    ),
                                    decoration: BoxDecoration(
                                      color: isLit
                                          ? selectedColor
                                          : appBackgroundColor,
                                      borderRadius: BorderRadius.vertical(
                                        top: isFirst
                                            ? const Radius.circular(15)
                                            : Radius.zero,
                                        bottom: isLast
                                            ? const Radius.circular(15)
                                            : Radius.zero,
                                      ),
                                    ),
                                    child: Center(
                                      child: isLit
                                          ? Container(
                                              width: 22,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            )
                                          : Container(
                                              width: 16,
                                              height: 2.5,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF33343A),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Segment Labels (e.g. C20 down to C1)
                      SizedBox(
                        height: stripHeight,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(channels.length, (idx) {
                            final ch = channels[idx];
                            final isLit = _currentChannels.contains(ch);
                            final label = _getChannelLabel(ch);

                            return Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => _toggleChannel(ch),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Center(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: isLit
                                            ? Colors.white
                                            : const Color(0xFF77777D),
                                        fontSize: channels.length > 15
                                            ? 9.5
                                            : 11,
                                        fontWeight: isLit
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        fontFamily: 'ndot',
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 5. Done Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
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
      ),
    );
  }

  Widget _buildStripTab(String key, String title) {
    final isSelected = _selectedStrip == key;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: () {
            if (_selectedStrip != key) {
              HapticFeedback.lightImpact();
              setState(() {
                _selectedStrip = key;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.black : const Color(0xFF888888),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(String label, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: appBackgroundColor,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'ndot',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
