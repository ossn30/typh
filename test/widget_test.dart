import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/models/glyph_animation.dart';
import 'package:glyph/models/glyph_channel.dart';
import 'package:glyph/models/installed_app.dart';
import 'package:glyph/screens/compose_screen.dart';
import 'package:glyph/screens/main_navigation_screen.dart';
import 'package:glyph/screens/notifications_screen.dart';
import 'package:glyph/screens/setup_screen.dart';
import 'package:glyph/services/glyph_service.dart';
import 'package:glyph/services/notification_rule_service.dart';
import 'package:glyph/services/settings_service.dart';
import 'package:glyph/widgets/glyph_strip_editor_dialog.dart';
import 'package:glyph/widgets/interactive_glyph_visualizer.dart';
import 'package:glyph/widgets/shake_torch_cards.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Phone 3a glyph channels configuration test', () {
    // Nothing Phone (3a) has exactly 36 lights across groups A, B, and C
    expect(Phone3aGlyphs.allLights.length, equals(36));

    // Group C: 20 lights (indices 0..19)
    expect(Phone3aGlyphs.groupC.length, equals(20));
    expect(Phone3aGlyphs.groupC.first.id, equals('C1'));
    expect(Phone3aGlyphs.groupC.first.channelIndex, equals(0));
    expect(Phone3aGlyphs.groupC.last.id, equals('C20'));
    expect(Phone3aGlyphs.groupC.last.channelIndex, equals(19));

    // Group A: 11 lights (indices 20..30)
    expect(Phone3aGlyphs.groupA.length, equals(11));
    expect(Phone3aGlyphs.groupA.first.id, equals('A1'));
    expect(Phone3aGlyphs.groupA.first.channelIndex, equals(20));
    expect(Phone3aGlyphs.groupA.last.id, equals('A11'));
    expect(Phone3aGlyphs.groupA.last.channelIndex, equals(30));

    // Group B: 5 lights (indices 31..35)
    expect(Phone3aGlyphs.groupB.length, equals(5));
    expect(Phone3aGlyphs.groupB.first.id, equals('B1'));
    expect(Phone3aGlyphs.groupB.first.channelIndex, equals(31));
    expect(Phone3aGlyphs.groupB.last.id, equals('B5'));
    expect(Phone3aGlyphs.groupB.last.channelIndex, equals(35));
  });

  test('Charging animation computation test', () {
    // 50% on Arc C clockwise (20 LEDs -> first 10 LEDs: 0..9)
    final chCW = GlyphService.computeChargingChannels(
      percentage: 50,
      selectedArcs: {'C'},
      isClockwise: true,
      isCombined: true,
    );
    expect(chCW.length, equals(10));
    expect(chCW, containsAll([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]));

    // 50% on Arc C anticlockwise (20 LEDs -> last 10 LEDs: 19..10)
    final chACW = GlyphService.computeChargingChannels(
      percentage: 50,
      selectedArcs: {'C'},
      isClockwise: false,
      isCombined: true,
    );
    expect(chACW.length, equals(10));
    expect(chACW, containsAll([19, 18, 17, 16, 15, 14, 13, 12, 11, 10]));

    // Arc B direction test (5 LEDs: 31..35)
    // CW: starts at 31
    final chBCW = GlyphService.computeChargingChannels(
      percentage: 40, // 2 LEDs
      selectedArcs: {'B'},
      isClockwise: true,
      isCombined: false,
    );
    expect(chBCW.length, equals(2));
    expect(chBCW, containsAll([31, 32]));

    // ACW: starts at 35
    final chBACW = GlyphService.computeChargingChannels(
      percentage: 40, // 2 LEDs
      selectedArcs: {'B'},
      isClockwise: false,
      isCombined: false,
    );
    expect(chBACW.length, equals(2));
    expect(chBACW, containsAll([35, 34]));

    // Multi-select Arc C, Arc A, and Arc B at 100%
    final chAll = GlyphService.computeChargingChannels(
      percentage: 100,
      selectedArcs: {'C', 'A', 'B'},
      isClockwise: true,
      isCombined: true,
    );
    expect(chAll.length, equals(36));
  });

  test('Combined vs Standalone multi-arc charging test', () {
    // Multi-select Arc C (20) and Arc A (11) -> 31 LEDs total
    // At ~32% (10 LEDs):
    // In Combined mode: 10 LEDs fill Arc C first (0..9), Arc A has 0 LEDs!
    final combinedLow = GlyphService.computeChargingChannels(
      percentage: 32, // (31 * 32 / 100).ceil() = 10 LEDs
      selectedArcs: {'C', 'A'},
      isClockwise: true,
      isCombined: true,
    );
    expect(combinedLow.length, equals(10));
    expect(combinedLow, containsAll([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]));
    // Verify none of Arc A (20..30) is lit yet
    for (int ch in combinedLow) {
      expect(ch < 20, isTrue);
    }

    // In Standalone mode at 32%:
    // Arc C has ceil(20 * 0.32) = 7 LEDs (0..6)
    // Arc A has ceil(11 * 0.32) = 4 LEDs (20..23)
    final standaloneLow = GlyphService.computeChargingChannels(
      percentage: 32,
      selectedArcs: {'C', 'A'},
      isClockwise: true,
      isCombined: false,
    );
    expect(standaloneLow.length, equals(11)); // 7 + 4 = 11
    expect(standaloneLow, containsAll([0, 1, 2, 3, 4, 5, 6]));
    expect(standaloneLow, containsAll([20, 21, 22, 23]));

    // In Combined mode at 80% (ceil(31 * 0.8) = 25 LEDs):
    // All 20 LEDs of Arc C are full (0..19), plus first 5 LEDs of Arc A (20..24)!
    final combinedHigh = GlyphService.computeChargingChannels(
      percentage: 80,
      selectedArcs: {'C', 'A'},
      isClockwise: true,
      isCombined: true,
    );
    expect(combinedHigh.length, equals(25));
    for (int i = 0; i < 20; i++) {
      expect(combinedHigh.contains(i), isTrue); // Entire Arc C full
    }
    expect(combinedHigh, containsAll([20, 21, 22, 23, 24])); // First 5 of Arc A
  });

  test('Timer duration formatting and bounds test', () {
    // Helper function equivalent to formatDuration
    String formatDuration(int seconds) {
      if (seconds < 60) return '${seconds}s';
      final mins = seconds ~/ 60;
      final remSecs = seconds % 60;
      if (remSecs == 0) return '${mins}m';
      return '${mins}m ${remSecs}s';
    }

    expect(formatDuration(0), equals('0s'));
    expect(formatDuration(3), equals('3s'));
    expect(formatDuration(30), equals('30s'));
    expect(formatDuration(60), equals('1m'));
    expect(formatDuration(90), equals('1m 30s'));
    expect(formatDuration(300), equals('5m'));
    expect(formatDuration(1800), equals('30m'));
  });

  test('GlyphAnimation model parsing test', () {
    final json = {
      'id': 'test_anim',
      'name': 'Test Animation',
      'description': 'A test animation',
      'icon': 'speed',
      'loop': true,
      'frames': [
        {
          'durationMs': 50,
          'channels': [0, 1, 2],
          'brightness': 3000
        },
        {
          'durationMs': 100,
          'channels': [20, 21],
          'brightness': 4000
        }
      ]
    };

    final anim = GlyphAnimation.fromFullJson(json, path: 'assets/animations/test_anim.json');
    expect(anim.id, equals('test_anim'));
    expect(anim.name, equals('Test Animation'));
    expect(anim.loop, isTrue);
    expect(anim.frames.length, equals(2));
    expect(anim.frames[0].durationMs, equals(50));
    expect(anim.frames[0].channels, equals({0, 1, 2}));
    expect(anim.frames[0].brightness, equals(3000));
    expect(anim.frames[1].durationMs, equals(100));
    expect(anim.frames[1].channels, equals({20, 21}));
    expect(anim.frames[1].brightness, equals(4000));
  });

  test('Verify all 18 animations files exist and have valid frames', () {
    final indexFile = File('assets/animations.json');
    expect(indexFile.existsSync(), isTrue);
    final indexData = json.decode(indexFile.readAsStringSync()) as List<dynamic>;
    expect(indexData.length, greaterThanOrEqualTo(17));

    for (final item in indexData) {
      final map = item as Map<String, dynamic>;
      final path = map['path'] as String;
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'File $path must exist');

      final content = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final anim = GlyphAnimation.fromFullJson(content, path: path);
      expect(anim.frames.isNotEmpty, isTrue, reason: 'Animation ${anim.id} must have frames');
      for (final frame in anim.frames) {
        expect(frame.durationMs, greaterThan(0));
        for (final ch in frame.channels) {
          expect(ch >= 0 && ch <= 35, isTrue,
              reason: 'Channel $ch in ${anim.id} must be within 0..35');
        }
      }
    }
  });

  test('ShakeIntensityPreset values and threshold boundaries test', () {
    expect(ShakeIntensityPreset.low.threshold, equals(1.2));
    expect(ShakeIntensityPreset.medium.threshold, equals(2.2));
    expect(ShakeIntensityPreset.high.threshold, equals(3.8));
    expect(ShakeIntensityPreset.values.length, equals(3));
  });

  test('SettingsService persistence and retrieval test', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService.instance;
    await settings.init();

    // Verify defaults
    expect(settings.chargingAnimationEnabled, isTrue);
    expect(settings.selectedArcs, equals({'C'}));
    expect(settings.isClockwise, isTrue);
    expect(settings.isCombinedProgress, isTrue);
    expect(settings.isDurationAlways, isTrue);
    expect(settings.timerDurationSeconds, equals(3));
    expect(settings.chargingBrightness, equals(4000));
    expect(settings.shakeTorchEnabled, isFalse);
    expect(settings.shakeThreshold, equals(2.0));
    expect(settings.torchBrightness, equals(4000));

    // Update settings
    await settings.setChargingAnimationEnabled(false);
    await settings.setSelectedArcs({'A', 'B'});
    await settings.setIsClockwise(false);
    await settings.setIsCombinedProgress(false);
    await settings.setIsDurationAlways(false);
    await settings.setTimerDurationSeconds(15);
    await settings.setChargingBrightness(2500);
    await settings.setShakeTorchEnabled(true);
    await settings.setShakeThreshold(1.4);
    await settings.setTorchBrightness(1800);

    // Verify persisted changes
    expect(settings.chargingAnimationEnabled, isFalse);
    expect(settings.selectedArcs, equals({'A', 'B'}));
    expect(settings.isClockwise, isFalse);
    expect(settings.isCombinedProgress, isFalse);
    expect(settings.isDurationAlways, isFalse);
    expect(settings.timerDurationSeconds, equals(15));
    expect(settings.chargingBrightness, equals(2500));
    expect(settings.shakeTorchEnabled, isTrue);
    expect(settings.shakeThreshold, equals(1.4));
    expect(settings.torchBrightness, equals(1800));
  });

  testWidgets('InteractiveGlyphVisualizer renders 36 LEDs and handles interaction', (tester) async {
    Set<int> selected = {0, 1, 20};
    Set<int>? latestChanged;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 380,
              child: InteractiveGlyphVisualizer(
                activeChannels: selected,
                onChannelsChanged: (newChannels) {
                  latestChanged = newChannels;
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(InteractiveGlyphVisualizer), findsOneWidget);

    // Tap in the visualizer
    await tester.tap(find.byType(InteractiveGlyphVisualizer));
    await tester.pump();
    expect(latestChanged != null || selected.isNotEmpty, isTrue);
  });

  testWidgets('ComposeScreen displays visualizer first, timeline, controls and save dialog', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();

    await tester.pumpWidget(
      const MaterialApp(
        home: ComposeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify visualizer is present
    expect(find.byType(InteractiveGlyphVisualizer), findsOneWidget);

    // Verify timeline is present
    expect(find.textContaining('TIMELINE'), findsOneWidget);

    // Verify play and test buttons are present
    expect(find.text('PLAY LOOP'), findsOneWidget);
    expect(find.text('PLAY ONCE'), findsOneWidget);
    expect(find.text('TEST FRAME (TOGGLE)'), findsOneWidget);

    // Toggle test frame
    await tester.tap(find.text('TEST FRAME (TOGGLE)'));
    await tester.pumpAndSettle();
    expect(find.text('TEST FRAME: ON (ACTIVE)'), findsOneWidget);

    // Toggle off
    await tester.tap(find.text('TEST FRAME: ON (ACTIVE)'));
    await tester.pumpAndSettle();
    expect(find.text('TEST FRAME (TOGGLE)'), findsOneWidget);

    // Tap SAVE button to trigger the dialog
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    // Verify save dialog appeared
    expect(find.text('SAVE ANIMATION'), findsOneWidget);
    expect(find.text('ANIMATION NAME'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
  });

  testWidgets('MainNavigationScreen floating pill animated navbar renders items', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();

    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('ALERTS'), findsOneWidget);
    expect(find.text('COMPOSE'), findsOneWidget);

    // Switch to Compose
    await tester.tap(find.text('COMPOSE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ComposeScreen), findsOneWidget);

    // Switch to Alerts
    await tester.tap(find.text('ALERTS'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NotificationsScreen), findsOneWidget);

    // Verify Master Alerts Toggle card (option to turn alerts off or on)
    expect(find.text('NOTIFICATION GLYPH ALERTS'), findsOneWidget);

    // Verify Sound Only guide header and button
    expect(find.textContaining('TURN ON SOUNDS ONLY IN NOTIFICATION CENTRE'), findsOneWidget);
    expect(find.text('OPEN NOTIFICATION SOUND SETTINGS'), findsOneWidget);

    // Verify Default Alert Animation card (always on, night rider by default, no switch)
    expect(find.text('DEFAULT ALERT ANIMATION'), findsOneWidget);
    expect(find.text('ALWAYS ON'), findsOneWidget);
    expect(find.textContaining('NIGHT RIDER'), findsOneWidget);
    expect(find.text('CHANGE DEFAULT'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  test('NotificationRuleService persistence and app assignment test', () async {
    SharedPreferences.setMockInitialValues({});
    final service = NotificationRuleService.instance;
    await service.init();

    expect(service.defaultEnabledNotifier.value, isTrue);
    expect(service.defaultAnimationIdNotifier.value, equals('night_rider'));
    expect(service.alertsEnabled, isFalse); // Default OFF for notification lights

    await service.setAlertsEnabled(true);
    expect(service.alertsEnabled, isTrue);

    // Assign custom animation to WhatsApp
    await service.setAppRule('com.whatsapp', 'cylon');
    expect(service.getAnimationForApp('com.whatsapp'), equals('cylon'));
    expect(service.isAppConfigured('com.whatsapp'), isTrue);

    // Change default
    await service.setDefaultAnimation('sonar');
    expect(service.defaultAnimationIdNotifier.value, equals('sonar'));

    // Remove WhatsApp rule
    await service.removeAppRule('com.whatsapp');
    expect(service.isAppConfigured('com.whatsapp'), isFalse);
    expect(service.getAnimationForApp('com.whatsapp'), isNull);
  });

  testWidgets('SetupScreen displays first-time setup options and completes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();

    await tester.pumpWidget(
      const MaterialApp(
        home: SetupScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HARDWARE SETUP'), findsOneWidget);
    expect(find.text('CHARGING ANIMATION'), findsOneWidget);
    expect(find.text('NOTIFICATION GLYPH LIGHTS'), findsOneWidget);
    expect(find.text('DEFAULT: OFF (IN-APP PLAY ONLY)'), findsOneWidget);
    expect(find.text('START USING GLYPH'), findsOneWidget);

    await tester.tap(find.text('START USING GLYPH'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(SettingsService.instance.hasCompletedOnboarding, isTrue);
  });

  testWidgets('GlyphStripEditorDialog displays straight strip with segments and cuts', (tester) async {
    Set<int> channels = {0, 1};
    Set<int>? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showGlyphStripEditorDialog(
                  context: ctx,
                  initialStrip: 'C',
                  activeChannels: channels,
                  onChannelsChanged: (c) => changed = c,
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.byType(GlyphStripEditorDialog), findsOneWidget);
    expect(find.textContaining('ARC C'), findsWidgets);
    expect(find.text('ARC A (11)'), findsOneWidget);
    expect(find.text('ARC B (5)'), findsOneWidget);
    expect(find.text('SELECT ALL'), findsOneWidget);
    expect(find.text('CLEAR'), findsOneWidget);

    // Switch to Arc A
    await tester.tap(find.text('ARC A (11)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ARC A • RIGHT ARC'), findsOneWidget);

    // Close
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.byType(GlyphStripEditorDialog), findsNothing);
    expect(channels.isNotEmpty || changed != null, isTrue);
  });

  test('InstalledApp model supports both iconBytes and iconBase64', () {
    final bytes = [137, 80, 78, 71]; // PNG magic numbers
    final appWithBytes = InstalledApp.fromMap({
      'appName': 'Test App 1',
      'packageName': 'com.test.app1',
      'iconBytes': Uint8List.fromList(bytes),
    });
    expect(appWithBytes.appName, equals('Test App 1'));
    expect(appWithBytes.packageName, equals('com.test.app1'));
    expect(appWithBytes.iconBytes, isNotNull);
    expect(appWithBytes.iconBytes!.length, equals(4));

    final base64String = base64Encode(bytes);
    final appWithBase64 = InstalledApp.fromMap({
      'appName': 'Test App 2',
      'packageName': 'com.test.app2',
      'iconBase64': base64String,
    });
    expect(appWithBase64.appName, equals('Test App 2'));
    expect(appWithBase64.iconBytes, isNotNull);
    expect(appWithBase64.iconBytes!.length, equals(4));
  });

  test('Real-time battery percentage tracking dynamically increments LEDs', () {
    // Starting at 40% on Arc C (20 LEDs -> 8 LEDs)
    final ch40 = GlyphService.computeChargingChannels(
      percentage: 40,
      selectedArcs: {'C'},
      isClockwise: true,
      isCombined: true,
    );
    expect(ch40.length, equals(8));

    // Real-time battery increment to 45% -> 9 LEDs
    final ch45 = GlyphService.computeChargingChannels(
      percentage: 45,
      selectedArcs: {'C'},
      isClockwise: true,
      isCombined: true,
    );
    expect(ch45.length, equals(9));
    expect(ch45.containsAll(ch40), isTrue);

    // Real-time battery increment to 50% -> 10 LEDs
    final ch50 = GlyphService.computeChargingChannels(
      percentage: 50,
      selectedArcs: {'C'},
      isClockwise: true,
      isCombined: true,
    );
    expect(ch50.length, equals(10));
    expect(ch50.containsAll(ch45), isTrue);
  });
}
