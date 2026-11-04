import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import 'compose_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

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
        left: 16,
        right: 16,
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
            Expanded(
              child: _buildNavItem(
                index: 0,
                icon: Icons.home_rounded,
                activeIcon: Icons.home_rounded,
                label: 'HOME',
              ),
            ),
            Expanded(
              child: _buildNavItem(
                index: 1,
                icon: Icons.notifications_none_rounded,
                activeIcon: Icons.notifications_rounded,
                label: 'ALERTS',
              ),
            ),
            Expanded(
              child: _buildNavItem(
                index: 2,
                icon: Icons.auto_awesome_outlined,
                activeIcon: Icons.auto_awesome_rounded,
                label: 'COMPOSE',
              ),
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTabTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
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
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF757780),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 5),
                Container(
                  width: 4,
                  height: 4,
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
    );
  }
}
