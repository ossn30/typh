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
  bool _isTabTapping = false;
  bool _canSwipe = true;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    HapticFeedback.lightImpact();
    setState(() {
      _currentIndex = index;
    });
    _isTabTapping = true;
    _pageController
        .animateToPage(
          index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          _isTabTapping = false;
        });
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
              if (!_isTabTapping) {
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
    const double navHeight = 54.0;
    const double padding = 5.0;
    final double usableWidth = navWidth - (padding * 2);
    final double itemWidth = usableWidth / 3.0;
    const double itemHeight = navHeight - (padding * 2);

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) {
        double page = _currentIndex.toDouble();
        if (_pageController.hasClients &&
            _pageController.position.haveDimensions) {
          page = (_pageController.page ?? _currentIndex.toDouble()).clamp(
            0.0,
            2.0,
          );
        }

        final pillLeft = page * itemWidth;

        return Container(
          width: navWidth,
          height: navHeight,
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: appBackgroundColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
          ),
          child: Stack(
            children: [
              // Real-Time Sliding White Pill Indicator
              Positioned(
                left: pillLeft,
                top: 0,
                width: itemWidth,
                height: itemHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 1),
                      ),
                    ],
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
                      currentPage: page,
                      height: itemHeight,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      index: 1,
                      icon: Icons.notifications_none_rounded,
                      activeIcon: Icons.notifications_rounded,
                      label: 'ALERTS',
                      currentPage: page,
                      height: itemHeight,
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      index: 2,
                      icon: Icons.auto_awesome_rounded,
                      label: 'COMPOSE',
                      currentPage: page,
                      height: itemHeight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    IconData? activeIcon,
    required String label,
    required double currentPage,
    required double height,
  }) {
    // Distance from current page to this tab (0.0 = fully active, 1.0+ = inactive)
    final progress = (1.0 - (currentPage - index).abs()).clamp(0.0, 1.0);
    final color = Color.lerp(
      const Color(0xFF8A8A8E),
      const Color(0xFF0A0A0C),
      progress,
    )!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _onTabTapped(index),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                (progress > 0.5 && activeIcon != null) ? activeIcon : icon,
                color: color,
                size: 17,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  fontFamily: 'ndot',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
