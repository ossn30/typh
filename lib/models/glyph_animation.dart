class GlyphAnimationFrame {
  final int durationMs;
  final Set<int> channels;
  final int brightness;

  const GlyphAnimationFrame({
    required this.durationMs,
    required this.channels,
    this.brightness = 4000,
  });

  factory GlyphAnimationFrame.fromJson(Map<String, dynamic> json) {
    final chList = (json['channels'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toSet() ??
        <int>{};
    return GlyphAnimationFrame(
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 50,
      channels: chList,
      brightness: (json['brightness'] as num?)?.toInt() ?? 4000,
    );
  }

  Map<String, dynamic> toJson() => {
    'durationMs': durationMs,
    'channels': channels.toList(),
    'brightness': brightness,
  };
}

class GlyphAnimation {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String path;
  final bool loop;
  final bool isCustom;
  final List<GlyphAnimationFrame> frames;

  const GlyphAnimation({
    required this.id,
    required this.name,
    required this.description,
    this.icon = 'play_arrow',
    required this.path,
    this.loop = true,
    this.isCustom = false,
    this.frames = const [],
  });

  factory GlyphAnimation.fromIndexJson(Map<String, dynamic> json) {
    return GlyphAnimation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? 'play_arrow',
      path: json['path'] as String? ?? '',
      isCustom: json['isCustom'] as bool? ?? false,
    );
  }

  factory GlyphAnimation.fromFullJson(
    Map<String, dynamic> json, {
    required String path,
    String? fallbackId,
    String? fallbackName,
    String? fallbackDescription,
    String? fallbackIcon,
    bool isCustom = false,
  }) {
    final framesData = (json['frames'] as List<dynamic>?) ?? [];
    final parsedFrames = framesData
        .map((f) => GlyphAnimationFrame.fromJson(f as Map<String, dynamic>))
        .toList();

    return GlyphAnimation(
      id: json['id'] as String? ?? fallbackId ?? '',
      name: json['name'] as String? ?? fallbackName ?? 'Animation',
      description:
          json['description'] as String? ?? fallbackDescription ?? '',
      icon: json['icon'] as String? ?? fallbackIcon ?? 'play_arrow',
      path: path,
      loop: json['loop'] as bool? ?? true,
      isCustom: json['isCustom'] as bool? ?? isCustom,
      frames: parsedFrames,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'path': path,
    'loop': loop,
    'isCustom': isCustom,
    'frames': frames.map((f) => f.toJson()).toList(),
  };

  GlyphAnimation copyWith({List<GlyphAnimationFrame>? frames, bool? isCustom}) {
    return GlyphAnimation(
      id: id,
      name: name,
      description: description,
      icon: icon,
      path: path,
      loop: loop,
      isCustom: isCustom ?? this.isCustom,
      frames: frames ?? this.frames,
    );
  }
}

