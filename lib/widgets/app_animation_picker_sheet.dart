import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../models/glyph_animation.dart';
import '../models/installed_app.dart';
import '../services/animation_service.dart';

Future<String?> showAppAnimationPickerSheet({
  required BuildContext context,
  required InstalledApp app,
  String? currentAnimationId,
  bool isDefaultMode = false,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => AppAnimationPickerSheet(
      app: app,
      currentAnimationId: currentAnimationId,
      isDefaultMode: isDefaultMode,
    ),
  );
}

class AppAnimationPickerSheet extends StatefulWidget {
  final InstalledApp app;
  final String? currentAnimationId;
  final bool isDefaultMode;

  const AppAnimationPickerSheet({
    super.key,
    required this.app,
    this.currentAnimationId,
    this.isDefaultMode = false,
  });

  @override
  State<AppAnimationPickerSheet> createState() =>
      _AppAnimationPickerSheetState();
}

class _AppAnimationPickerSheetState extends State<AppAnimationPickerSheet> {
  final AnimationService _animService = AnimationService.instance;

  List<GlyphAnimation> _presets = [];
  List<GlyphAnimation> _customs = [];
  bool _isLoading = true;

  String? _selectedId;
  String? _previewingId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentAnimationId;
    _loadAnimations();
  }

  @override
  void dispose() {
    // If preview was playing, stop it
    if (_previewingId != null) {
      _animService.stopAnimation();
    }
    super.dispose();
  }

  Future<void> _loadAnimations() async {
    final presets = await _animService.loadAnimationsIndex();
    final customs = await _animService.loadCustomAnimations();
    if (mounted) {
      setState(() {
        _presets = presets;
        _customs = customs;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePreview(GlyphAnimation anim) async {
    HapticFeedback.selectionClick();
    if (_previewingId == anim.id) {
      await _animService.stopAnimation();
      if (mounted) {
        setState(() {
          _previewingId = null;
        });
      }
    } else {
      setState(() {
        _previewingId = anim.id;
      });
      await _animService.playAnimation(anim);
      if (mounted && _previewingId == anim.id) {
        // Stop after 3 seconds of preview
        Future.delayed(const Duration(milliseconds: 3200), () {
          if (mounted && _previewingId == anim.id) {
            _animService.stopAnimation();
            setState(() {
              _previewingId = null;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Color(0xFF111215),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
          top: BorderSide(color: Color(0xFF2A2B30), width: 1.2),
          left: BorderSide(color: Color(0xFF2A2B30), width: 1.2),
          right: BorderSide(color: Color(0xFF2A2B30), width: 1.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header with app info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.app.iconBytes != null
                      ? Image.memory(
                          widget.app.iconBytes!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          color: const Color(0xFF22242A),
                          child: const Icon(
                            Icons.apps_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.app.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7A7C85),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF1E2026), height: 1),

          // List of animations
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: selectedColor,
                      strokeWidth: 2.5,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      // 1. Custom Animations Section (if any)
                      if (_customs.isNotEmpty) ...[
                        _buildSectionHeader('CUSTOM ANIMATIONS (${_customs.length})'),
                        ..._customs.map((a) => _buildAnimationTile(a)),
                        const SizedBox(height: 16),
                      ],

                      // 2. Preset Animations Section
                      _buildSectionHeader('PRESET ANIMATIONS (${_presets.length})'),
                      ..._presets.map((a) => _buildAnimationTile(a)),
                    ],
                  ),
          ),

          // Bottom Action Bar
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              mediaQuery.padding.bottom + 12,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0C0D0F),
              border: Border(
                top: BorderSide(color: Color(0xFF1E2026), width: 1),
              ),
            ),
            child: Row(
              children: [
                if (!widget.isDefaultMode && widget.currentAnimationId != null) ...[
                  OutlinedButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop('__REMOVE__');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE53935),
                      side: const BorderSide(color: Color(0xFFE53935), width: 1.2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'REMOVE (USE DEFAULT)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'ndot',
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedId != null
                        ? () {
                            HapticFeedback.mediumImpact();
                            Navigator.of(context).pop(_selectedId);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedColor,
                      disabledBackgroundColor: const Color(0xFF2A2B30),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      widget.isDefaultMode
                          ? 'APPLY DEFAULT ANIMATION'
                          : 'APPLY ALERT ANIMATION',
                      style: const TextStyle(
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
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF8A8A8E),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          fontFamily: 'ndot',
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildAnimationTile(GlyphAnimation anim) {
    final isSelected = _selectedId == anim.id;
    final isPreviewing = _previewingId == anim.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? selectedColor.withValues(alpha: 0.12)
            : const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? selectedColor
              : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedId = anim.id;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Radio indicator
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? selectedColor
                          : const Color(0xFF55555B),
                      width: 2,
                    ),
                    color: isSelected ? selectedColor : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Name and Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              anim.name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFFEDEDED),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (anim.isCustom) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: selectedColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'CUSTOM',
                                style: TextStyle(
                                  color: selectedColor,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'ndot',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        anim.description.isNotEmpty
                            ? anim.description
                            : '${anim.frames.length} frames',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7A7C85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Live Preview / Test Button
                IconButton(
                  onPressed: () => _togglePreview(anim),
                  tooltip: isPreviewing ? 'Stop' : 'Test on Phone',
                  icon: Icon(
                    isPreviewing
                        ? Icons.stop_circle_rounded
                        : Icons.play_circle_outline_rounded,
                    color: isPreviewing ? selectedColor : Colors.white70,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
