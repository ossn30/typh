import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/models/glyph_animation.dart';
import 'package:glyph/models/glyph_channel.dart';
import 'package:glyph/services/glyph_service.dart';

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
}
