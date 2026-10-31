class GlyphLight {
  final String id;
  final String group;
  final int channelIndex;
  final String description;
  final int position;

  const GlyphLight({
    required this.id,
    required this.group,
    required this.channelIndex,
    required this.description,
    required this.position,
  });
}

class Phone3aGlyphs {
  /// Group C: 20 lights (Indices 0 - 19)
  /// Upper-left circular arc. C1 is bottom-left, C20 is top.
  static final List<GlyphLight> groupC = List.generate(20, (i) {
    final num = i + 1;
    final desc = num == 1
        ? 'Upper-left arc bottom start'
        : num == 20
            ? 'Upper-left arc top end'
            : 'Upper-left arc segment $num';
    return GlyphLight(
      id: 'C$num',
      group: 'C',
      channelIndex: i, // 0..19
      description: desc,
      position: num,
    );
  });

  /// Group A: 11 lights (Indices 20 - 30)
  /// Right arc strip. A1 is top, A11 is bottom.
  static final List<GlyphLight> groupA = List.generate(11, (i) {
    final num = i + 1;
    final desc = num == 1
        ? 'Right arc top start'
        : num == 11
            ? 'Right arc bottom end'
            : 'Right arc segment $num';
    return GlyphLight(
      id: 'A$num',
      group: 'A',
      channelIndex: 20 + i, // 20..30
      description: desc,
      position: num,
    );
  });

  /// Group B: 5 lights (Indices 31 - 35)
  /// Lower-left arc strip. B1 is bottom right, B5 is top left.
  static final List<GlyphLight> groupB = List.generate(5, (i) {
    final num = i + 1;
    final desc = num == 1
        ? 'Bottom-right diagonal start'
        : num == 5
            ? 'Top-left diagonal end'
            : 'Diagonal strip segment $num';
    return GlyphLight(
      id: 'B$num',
      group: 'B',
      channelIndex: 31 + i, // 31..35
      description: desc,
      position: num,
    );
  });

  /// All 36 addressable lights on Nothing Phone (3a)
  static final List<GlyphLight> allLights = [
    ...groupA,
    ...groupB,
    ...groupC,
  ];

  /// Find light by channel index
  static GlyphLight? findByIndex(int channelIndex) {
    try {
      return allLights.firstWhere((light) => light.channelIndex == channelIndex);
    } catch (_) {
      return null;
    }
  }
}

