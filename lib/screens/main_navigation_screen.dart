import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../services/glyph_service.dart';
import '../services/settings_service.dart';
import 'compose_screen.dart';
import 'home_screen.dart';
import 'island_screen.dart';
import 'key_remapper_screen.dart';
import 'notifications_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Guarantee settings and hardware background connections are synced on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SettingsService.instance.syncToNative();
      GlyphService.instance.init();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SettingsService.instance.syncToNative();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          const KeyRemapperScreen(),
          const IslandScreen(),
          const NotificationsScreen(),
          ComposeScreen(onAnimationSaved: () => _onTabTapped(0)),
        ],
      ),
      bottomNavigationBar: _buildNothingNavBar(context),
    );
  }

  Widget _buildNothingNavBar(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: appBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 8,
        bottom: math.max(10.0, bottomInset),
      ),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(26),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildNavItem(
              index: 0,
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'HOME',
            ),
            _buildNavItem(
              index: 1,
              icon: Icons.smart_button_outlined,
              activeIcon: Icons.smart_button_rounded,
              label: 'KEYMAP',
            ),
            _buildNavItem(
              index: 2,
              icon: Icons.bubble_chart_outlined,
              activeIcon: Icons.bubble_chart_rounded,
              label: 'ISLAND',
            ),
            _buildNavItem(
              index: 3,
              icon: Icons.notifications_none_rounded,
              activeIcon: Icons.notifications_rounded,
              label: 'ALERTS',
            ),
            _buildNavItem(
              index: 4,
              icon: Icons.auto_awesome_outlined,
              activeIcon: Icons.auto_awesome_rounded,
              label: 'COMPOSE',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return Expanded(
      flex: isSelected ? 3 : 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTabTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isSelected ? appBackgroundColor : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected ? selectedColor : const Color(0xFF757780),
                  size: 18,
                ),
                if (isSelected) ...[
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 3.5,
                    height: 3.5,
                    decoration: const BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
