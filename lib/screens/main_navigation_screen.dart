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
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _canSwipe = true;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    HapticFeedback.lightImpact();
    final oldIndex = _currentIndex;
    setState(() {
      _currentIndex = index;
    });

    final dist = (index - oldIndex).abs();
    if (dist > 1) {
      // Instant switch for non-adjacent screens (e.g. Home <-> Compose)
      // Eliminates intermediate screen loading and scroll jank!
      _pageController.jumpToPage(index);
    } else {
      // Smooth animation for adjacent screens
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final bottomInset = mediaQuery.padding.bottom;
    final navWidth = (screenWidth - 48).clamp(290.0, 350.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Swipeable Full-Screen Pages
          PageView(
            controller: _pageController,
            physics: _canSwipe
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            onPageChanged: (index) {
              if (_currentIndex != index) {
                HapticFeedback.selectionClick();
                setState(() {
                  _currentIndex = index;
                });
              }
            },
            children: [
              const HomeScreen(),
              const NotificationsScreen(),
              ComposeScreen(
                onAnimationSaved: () {
                  _onTabTapped(0);
                },
                onSwipeLockChanged: (locked) {
                  if (_canSwipe == locked) {
                    setState(() {
                      _canSwipe = !locked;
                    });
                  }
                },
              ),
            ],
          ),

          // 2. Production Floating Pill Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: math.max(14.0, bottomInset + 8.0),
            child: Center(child: _buildFloatingPillNavBar(navWidth)),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingPillNavBar(double navWidth) {
    const double navHeight = 50.0;
    const double padding = 5.0;
    final double usableWidth = navWidth - (padding * 3);
    final double itemWidth = usableWidth / 3.0;
    const double itemHeight = navHeight - (padding * 2.4);

    return Container(
      width: navWidth,
      height: navHeight,
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: appBackgroundColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Stack(
        children: [
          // Hardware-accelerated sliding white pill indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            left: _currentIndex * itemWidth,
            top: 0,
            width: itemWidth,
            height: itemHeight,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),

          // Tab Items Row
          Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  index: 0,
                  icon: Icons.home_rounded,
                  label: 'HOME',
                  isSelected: _currentIndex == 0,
                  height: itemHeight,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 1,
                  icon: Icons.notifications_none_rounded,
                  activeIcon: Icons.notifications_rounded,
                  label: 'ALERTS',
                  isSelected: _currentIndex == 1,
                  height: itemHeight,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 2,
                  icon: Icons.auto_awesome_rounded,
                  label: 'COMPOSE',
                  isSelected: _currentIndex == 2,
                  height: itemHeight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    IconData? activeIcon,
    required String label,
    required bool isSelected,
    required double height,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _onTabTapped(index),
        child: SizedBox(
          height: height,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: isSelected
                  ? const Color(0xFF0A0A0C)
                  : const Color(0xFF8A8A8E),
            ),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (context, color, child) {
              final activeColor =
                  color ??
                  (isSelected
                      ? const Color(0xFF0A0A0C)
                      : const Color(0xFF8A8A8E));
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected && activeIcon != null ? activeIcon : icon,
                    color: activeColor,
                    size: 17,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: activeColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      fontFamily: 'ndot',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
