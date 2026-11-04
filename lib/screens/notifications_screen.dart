import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glyph/colors.dart';
import '../models/installed_app.dart';
import '../services/glyph_service.dart';
import '../services/notification_rule_service.dart';
import '../widgets/app_animation_picker_sheet.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final NotificationRuleService _ruleService = NotificationRuleService.instance;
  final GlyphService _glyph = GlyphService.instance;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _filterConfiguredOnly = false;
  bool _isNotificationAccessGranted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ruleService.init();
    _checkPermission();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    // Lazily load installed apps if not yet loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ruleService.installedAppsNotifier.value.isEmpty &&
          !_ruleService.isLoadingAppsNotifier.value) {
        _ruleService.loadInstalledApps();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final granted = await _glyph.isNotificationAccessGranted();
    if (mounted) {
      setState(() {
        _isNotificationAccessGranted = granted;
      });
    }
  }

  Future<void> _pickDefaultAnimation() async {
    HapticFeedback.lightImpact();
    // Synthetic app for default setting
    const dummyApp = InstalledApp(
      appName: 'Default Notification Alert',
      packageName: 'All other unconfigured apps',
    );
    final selectedId = await showAppAnimationPickerSheet(
      context: context,
      app: dummyApp,
      currentAnimationId: _ruleService.defaultAnimationIdNotifier.value,
      isDefaultMode: true,
    );

    if (selectedId != null && selectedId != '__REMOVE__') {
      await _ruleService.setDefaultAnimation(selectedId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Default Glyph alert updated to ${selectedId.replaceAll('_', ' ').toUpperCase()}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _pickAppAnimation(InstalledApp app) async {
    HapticFeedback.lightImpact();
    final currentId = _ruleService.getAnimationForApp(app.packageName);
    final selectedId = await showAppAnimationPickerSheet(
      context: context,
      app: app,
      currentAnimationId: currentId,
    );

    if (selectedId != null) {
      if (selectedId == '__REMOVE__') {
        await _ruleService.removeAppRule(app.packageName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed custom animation for ${app.appName} (now using Default)',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        await _ruleService.setAppRule(app.packageName, selectedId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Set custom Glyph alert for ${app.appName}! Default alert prevented.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
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
          'ALERTS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFamily: 'ndot',
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _ruleService.loadInstalledApps(forceRefresh: true);
              _checkPermission();
            },
            tooltip: 'Refresh Apps & Permissions',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: appBackgroundColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(35),
              topRight: Radius.circular(35),
            ),
          ),
          child: ValueListenableBuilder<List<InstalledApp>>(
            valueListenable: _ruleService.installedAppsNotifier,
            builder: (context, allApps, _) {
              return ValueListenableBuilder<Map<String, String>>(
                valueListenable: _ruleService.appRulesNotifier,
                builder: (context, appRules, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _ruleService.isLoadingAppsNotifier,
                    builder: (context, isLoading, _) {
                      // Filter apps based on search and configured filter
                      final filteredApps = allApps.where((app) {
                        final matchesQuery =
                            _searchQuery.isEmpty ||
                            app.appName.toLowerCase().contains(_searchQuery) ||
                            app.packageName.toLowerCase().contains(
                              _searchQuery,
                            );
                        final matchesFilter =
                            !_filterConfiguredOnly ||
                            appRules.containsKey(app.packageName);
                        return matchesQuery && matchesFilter;
                      }).toList();

                      // Separate configured apps
                      final configuredApps = allApps
                          .where((app) => appRules.containsKey(app.packageName))
                          .toList();

                      return CustomScrollView(
                        slivers: [
                          // 1. Permission Warning Banner (if not granted)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: _buildPermissionBanner(),
                            ),
                          ),

                          // 2. Master Toggle: Turn Notification Alerts ON / OFF
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: _buildMasterAlertsToggleCard(),
                            ),
                          ),

                          // 3. Setup Guide: Turn on Sounds Only in Notification Centre
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: _buildSoundOnlyDetailsCard(),
                            ),
                          ),

                          // 4. Default Notification Animation Card
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: _buildDefaultAnimationCard(),
                            ),
                          ),

                          // 3. Search and Filter Header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Search Field
                                  Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Search installed apps...',
                                        hintStyle: const TextStyle(
                                          color: Color(0xFF7A7C85),
                                          fontSize: 13,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                          color: Color(0xFF7A7C85),
                                          size: 20,
                                        ),
                                        suffixIcon: _searchQuery.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(
                                                  Icons.clear_rounded,
                                                  color: Colors.white60,
                                                  size: 18,
                                                ),
                                                onPressed: () =>
                                                    _searchController.clear(),
                                              )
                                            : null,
                                        border: InputBorder.none,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Filter Pills
                                  Row(
                                    children: [
                                      _buildFilterPill(
                                        label: 'ALL APPS (${allApps.length})',
                                        isSelected: !_filterConfiguredOnly,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(
                                            () => _filterConfiguredOnly = false,
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      _buildFilterPill(
                                        label:
                                            'CONFIGURED (${configuredApps.length})',
                                        isSelected: _filterConfiguredOnly,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(
                                            () => _filterConfiguredOnly = true,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 4. Configured Apps Section (when on 'ALL APPS' and search is empty)
                          if (!_filterConfiguredOnly &&
                              _searchQuery.isEmpty &&
                              configuredApps.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  6,
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      'CONFIGURED APP ALERTS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'ndot',
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selectedColor.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'PREVENTS DEFAULT',
                                        style: TextStyle(
                                          color: selectedColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'ndot',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => _buildAppTile(
                                  configuredApps[i],
                                  appRules[configuredApps[i].packageName],
                                ),
                                childCount: configuredApps.length,
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Divider(
                                  color: Color(0xFF1E2026),
                                  height: 1,
                                ),
                              ),
                            ),
                          ],

                          // 5. Apps Section Header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                              child: Text(
                                _filterConfiguredOnly
                                    ? 'CONFIGURED APPS (${filteredApps.length})'
                                    : 'ALL INSTALLED APPS (${filteredApps.length})',
                                style: const TextStyle(
                                  color: Color(0xFF8A8A8E),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'ndot',
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),

                          // 6. Apps List
                          if (isLoading && allApps.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(40.0),
                                child: Center(
                                  child: Column(
                                    children: [
                                      CircularProgressIndicator(
                                        color: selectedColor,
                                        strokeWidth: 2.5,
                                      ),
                                      SizedBox(height: 14),
                                      Text(
                                        'LOADING INSTALLED APPS...',
                                        style: TextStyle(
                                          color: Color(0xFF8A8A8E),
                                          fontSize: 11,
                                          fontFamily: 'ndot',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else if (filteredApps.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(40.0),
                                child: Center(
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.search_off_rounded,
                                        color: Color(0xFF55555B),
                                        size: 40,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _filterConfiguredOnly
                                            ? 'NO APPS CONFIGURED YET\nSelect any app below to assign its custom Glyph alert.'
                                            : 'NO APPS MATCHING "$_searchQuery"',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFF8A8A8E),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final app = filteredApps[index];
                                final customAnimId = appRules[app.packageName];
                                return _buildAppTile(app, customAnimId);
                              }, childCount: filteredApps.length),
                            ),

                          // Bottom spacing above navigation bar
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    if (_isNotificationAccessGranted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1E15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF4CAF50),
              size: 18,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'NOTIFICATION LISTENER ACTIVE • GLYPH ALERTS READY',
                style: TextStyle(
                  color: Color(0xFF81C784),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1315),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selectedColor.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: selectedColor,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'NOTIFICATION ACCESS REQUIRED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Grant Notification Access in Android Settings so the Glyph alert service can detect alerts from your chosen apps and trigger their lighting animations.',
            style: TextStyle(
              color: Color(0xFFB0B3BA),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              _glyph.openNotificationAccessSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'ENABLE ACCESS IN SETTINGS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                fontFamily: 'ndot',
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterAlertsToggleCard() {
    return ValueListenableBuilder<bool>(
      valueListenable: _ruleService.alertsEnabledNotifier,
      builder: (context, areAlertsEnabled, _) {
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: areAlertsEnabled
                  ? selectedColor.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: areAlertsEnabled
                          ? selectedColor.withValues(alpha: 0.15)
                          : const Color(0xFF22242A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      color: areAlertsEnabled ? selectedColor : const Color(0xFF7A7C85),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NOTIFICATION GLYPH ALERTS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          areAlertsEnabled
                              ? 'Enabled • Glyphs trigger for incoming alerts'
                              : 'Disabled • In-app animation playback only',
                          style: TextStyle(
                            color: areAlertsEnabled
                                ? const Color(0xFF81C784)
                                : const Color(0xFF8A8A8E),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: CupertinoSwitch(
                      value: areAlertsEnabled,
                      activeTrackColor: selectedColor,
                      onChanged: (val) {
                        HapticFeedback.mediumImpact();
                        _ruleService.setAlertsEnabled(val);
                      },
                    ),
                  ),
                ],
              ),
              if (!areAlertsEnabled) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF191A20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF8A8A8E)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Glyphs will not flash for notifications while disabled. You can still test animations in the app.',
                          style: TextStyle(
                            color: Color(0xFF9E9FA8),
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSoundOnlyDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selectedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.volume_up_rounded,
                  color: selectedColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TURN ON SOUNDS ONLY IN NOTIFICATION CENTRE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        // fontFamily: 'ndot',
                        letterSpacing: 0.7,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Essential for the best Glyph lighting experience',
                      style: TextStyle(
                        color: Color(0xFF8A8A8E),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'To enjoy clean Glyph illumination without distracting on-screen popup banners: open Notification Settings, choose your apps, and turn on Sound while setting banners to Notification Centre only (Deliver Quietly). Your phone\'s rear Glyphs will flash whenever notifications arrive!',
            style: TextStyle(
              color: Color(0xFFC4C7D0),
              fontSize: 11.5,
              height: 1.42,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                _glyph.openNotificationSoundSettings();
              },
              icon: const Icon(
                Icons.tune_rounded,
                size: 16,
                color: Colors.white,
              ),
              label: const Text(
                'OPEN NOTIFICATION SOUND SETTINGS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ndot',
                  letterSpacing: 0.8,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: appBackgroundColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAnimationCard() {
    return ValueListenableBuilder<String?>(
      valueListenable: _ruleService.defaultAnimationIdNotifier,
      builder: (context, defaultId, _) {
        final id = (defaultId != null && defaultId.isNotEmpty)
            ? defaultId
            : 'night_rider';
        final animName = id.replaceAll('_', ' ').toUpperCase();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22242A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEFAULT ALERT ANIMATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.8,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Always active • Plays for unconfigured apps',
                          style: TextStyle(
                            color: Color(0xFF7A7C85),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Always active indicator - No option to turn off
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2E1D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Color(0xFF4CAF50), size: 6),
                        SizedBox(width: 4),
                        Text(
                          'ALWAYS ON',
                          style: TextStyle(
                            color: Color(0xFF81C784),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2026),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ANIMATION: ',
                          style: TextStyle(
                            color: Color(0xFF7A7C85),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'ndot',
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          animName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickDefaultAnimation,
                    icon: const Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: selectedColor,
                    ),
                    label: const Text(
                      'CHANGE DEFAULT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ndot',
                        letterSpacing: 0.6,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: selectedColor,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF16171B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : const Color(0xFF8A8A8E),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFamily: 'ndot',
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildAppTile(InstalledApp app, String? customAnimId) {
    final hasCustom = customAnimId != null && customAnimId.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: hasCustom
            ? selectedColor.withValues(alpha: 0.08)
            : const Color(0xFF141518),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _pickAppAnimation(app),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // App Icon
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: app.iconBytes != null
                      ? Image.memory(
                          app.iconBytes!,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 38,
                          height: 38,
                          color: const Color(0xFF22242A),
                          child: const Icon(
                            Icons.apps_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                ),
                const SizedBox(width: 12),

                // App Name and Package
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7A7C85),
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Status Badge / Action
                if (hasCustom) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selectedColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          customAnimId.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'ndot',
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: appBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'DEFAULT',
                      style: TextStyle(
                        color: Color(0xFF8A8A8E),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'ndot',
                        letterSpacing: 0.6,
                      ),
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
