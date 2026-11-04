import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/installed_app.dart';
import '../models/glyph_animation.dart';
import 'animation_service.dart';
import 'glyph_service.dart';

class NotificationRuleService {
  NotificationRuleService._();
  static final NotificationRuleService instance = NotificationRuleService._();

  final GlyphService _glyph = GlyphService.instance;
  final AnimationService _anim = AnimationService.instance;

  SharedPreferences? _prefs;

  static const String _kAlertsEnabled = 'alert_master_enabled';
  static const String _kDefaultAnimationId = 'alert_default_animation_id';
  static const String _kDefaultEnabled = 'alert_default_enabled';
  static const String _kAppRulesMap = 'alert_app_rules_map';

  final ValueNotifier<bool> alertsEnabledNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<Map<String, String>> appRulesNotifier =
      ValueNotifier<Map<String, String>>({});
  final ValueNotifier<String?> defaultAnimationIdNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> defaultEnabledNotifier =
      ValueNotifier<bool>(true);

  final ValueNotifier<List<InstalledApp>> installedAppsNotifier =
      ValueNotifier<List<InstalledApp>>([]);
  final ValueNotifier<bool> isLoadingAppsNotifier =
      ValueNotifier<bool>(false);

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs ??= await SharedPreferences.getInstance();

    final alertsEnabled = _prefs?.getBool(_kAlertsEnabled) ?? false;
    String defaultId = _prefs?.getString(_kDefaultAnimationId) ?? 'night_rider';
    // If legacy default was 'pulse', migrate to 'night_rider'
    if (defaultId == 'pulse') {
      defaultId = 'night_rider';
      _prefs?.setString(_kDefaultAnimationId, 'night_rider');
    }
    const defaultEnabled = true; // Always on, no toggle to turn off
    final rulesJson = _prefs?.getString(_kAppRulesMap);

    Map<String, String> rules = {};
    if (rulesJson != null && rulesJson.isNotEmpty) {
      try {
        final decoded = json.decode(rulesJson) as Map<String, dynamic>;
        rules = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (e) {
        debugPrint('Error decoding app alert rules: $e');
      }
    }

    alertsEnabledNotifier.value = alertsEnabled;
    defaultAnimationIdNotifier.value = defaultId;
    defaultEnabledNotifier.value = defaultEnabled;
    appRulesNotifier.value = Map.unmodifiable(rules);
    _isInitialized = true;

    // Sync rules to native notification listener in the background
    syncRulesToNative();
  }

  bool get alertsEnabled => alertsEnabledNotifier.value;

  Future<void> setAlertsEnabled(bool enabled) async {
    alertsEnabledNotifier.value = enabled;
    await _prefs?.setBool(_kAlertsEnabled, enabled);
    await syncRulesToNative();
  }

  Future<void> loadInstalledApps({bool forceRefresh = false}) async {
    if (!forceRefresh && installedAppsNotifier.value.isNotEmpty) return;

    isLoadingAppsNotifier.value = true;
    try {
      final rawApps = await _glyph.getInstalledApps();
      final apps = rawApps.map((m) => InstalledApp.fromMap(m)).toList();
      installedAppsNotifier.value = List.unmodifiable(apps);
    } catch (e) {
      debugPrint('Error loading installed apps: $e');
    } finally {
      isLoadingAppsNotifier.value = false;
    }
  }

  String? getAnimationForApp(String packageName) {
    return appRulesNotifier.value[packageName];
  }

  bool isAppConfigured(String packageName) {
    return appRulesNotifier.value.containsKey(packageName);
  }

  Future<void> setAppRule(String packageName, String animationId) async {
    final next = Map<String, String>.from(appRulesNotifier.value);
    next[packageName] = animationId;
    appRulesNotifier.value = Map.unmodifiable(next);

    await _prefs?.setString(_kAppRulesMap, json.encode(next));
    await syncRulesToNative();
  }

  Future<void> removeAppRule(String packageName) async {
    final next = Map<String, String>.from(appRulesNotifier.value);
    next.remove(packageName);
    appRulesNotifier.value = Map.unmodifiable(next);

    await _prefs?.setString(_kAppRulesMap, json.encode(next));
    await syncRulesToNative();
  }

  Future<void> setDefaultAnimation(String? animationId) async {
    final effectiveId = animationId ?? 'night_rider';
    defaultAnimationIdNotifier.value = effectiveId;
    await _prefs?.setString(_kDefaultAnimationId, effectiveId);
    await syncRulesToNative();
  }

  Future<void> setDefaultEnabled(bool enabled) async {
    // Default alert animation is always on
    defaultEnabledNotifier.value = true;
    await _prefs?.setBool(_kDefaultEnabled, true);
    await syncRulesToNative();
  }

  /// Sync complete animation frame payloads to native NotificationListenerService
  Future<void> syncRulesToNative() async {
    try {
      // 1. Prepare default animation payload
      String? defaultAnimJson;
      final defId = defaultAnimationIdNotifier.value ?? 'night_rider';
      if (defId.isNotEmpty) {
        final anim = await _resolveFullAnimation(defId);
        if (anim != null && anim.frames.isNotEmpty) {
          defaultAnimJson = json.encode({
            'id': anim.id,
            'name': anim.name,
            'frames': anim.frames
                .map((f) => {
                      'durationMs': f.durationMs,
                      'channels': f.channels.toList(),
                      'brightness': f.brightness,
                    })
                .toList(),
          });
        }
      }

      // 2. Prepare each app rule payload
      final Map<String, String> rulesMap = {};
      for (final entry in appRulesNotifier.value.entries) {
        final pkg = entry.key;
        final animId = entry.value;
        final anim = await _resolveFullAnimation(animId);
        if (anim != null && anim.frames.isNotEmpty) {
          rulesMap[pkg] = json.encode({
            'id': anim.id,
            'name': anim.name,
            'frames': anim.frames
                .map((f) => {
                      'durationMs': f.durationMs,
                      'channels': f.channels.toList(),
                      'brightness': f.brightness,
                    })
                .toList(),
          });
        }
      }

      final payload = {
        'alerts_enabled': alertsEnabledNotifier.value,
        'default_enabled': true, // Always on
        'default_animation': defaultAnimJson,
        'rules': rulesMap,
      };

      await _glyph.syncNotificationRules(payload);
    } catch (e) {
      debugPrint('Error syncing notification rules to native: $e');
    }
  }

  Future<GlyphAnimation?> _resolveFullAnimation(String id) async {
    // Check custom animations first
    final customList = await _anim.loadCustomAnimations();
    final customMatch = customList.where((a) => a.id == id);
    if (customMatch.isNotEmpty) {
      return customMatch.first;
    }

    // Check presets
    final indexList = await _anim.loadAnimationsIndex();
    final presetMatch = indexList.where((a) => a.id == id);
    if (presetMatch.isNotEmpty) {
      return await _anim.loadFullAnimation(presetMatch.first);
    }

    return null;
  }
}

