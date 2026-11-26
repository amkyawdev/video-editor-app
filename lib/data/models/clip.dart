import '../../core/utils/ids.dart';

/// How a source frame fills the project canvas.
enum MediaFit { contain, cover, stretch }

/// Crop expressed as the fraction removed from each edge of the source.
class CropRect {
  const CropRect({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const CropRect full = CropRect();

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isFull => left == 0 && top == 0 && right == 0 && bottom == 0;
  double get widthFraction => (1 - left - right).clamp(0.05, 1.0);
  double get heightFraction => (1 - top - bottom).clamp(0.05, 1.0);

  CropRect copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) => CropRect(
    left: (left ?? this.left).clamp(0.0, 0.45),
    top: (top ?? this.top).clamp(0.0, 0.45),
    right: (right ?? this.right).clamp(0.0, 0.45),
    bottom: (bottom ?? this.bottom).clamp(0.0, 0.45),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'l': double.parse(left.toStringAsFixed(4)),
    't': double.parse(top.toStringAsFixed(4)),
    'r': double.parse(right.toStringAsFixed(4)),
    'b': double.parse(bottom.toStringAsFixed(4)),
  };

  factory CropRect.fromJson(Map<String, dynamic>? json) => json == null
      ? CropRect.full
      : CropRect(
          left: (json['l'] as num?)?.toDouble() ?? 0,
          top: (json['t'] as num?)?.toDouble() ?? 0,
          right: (json['r'] as num?)?.toDouble() ?? 0,
          bottom: (json['b'] as num?)?.toDouble() ?? 0,
        );
}

/// FFmpeg `eq` colour correction values.
class ColorGrade {
  const ColorGrade({
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
  });

  static const ColorGrade neutral = ColorGrade();

  final double brightness;
  final double contrast;
  final double saturation;

  bool get isNeutral => brightness == 0 && contrast == 1 && saturation == 1;

  ColorGrade copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
  }) => ColorGrade(
    brightness: (brightness ?? this.brightness).clamp(-1.0, 1.0),
    contrast: (contrast ?? this.contrast).clamp(0.0, 2.0),
    saturation: (saturation ?? this.saturation).clamp(0.0, 3.0),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'br': brightness,
    'co': contrast,
    'sa': saturation,
  };

  factory ColorGrade.fromJson(Map<String, dynamic>? json) => json == null
      ? ColorGrade.neutral
      : ColorGrade(
          brightness: (json['br'] as num?)?.toDouble() ?? 0,
          contrast: (json['co'] as num?)?.toDouble() ?? 1,
          saturation: (json['sa'] as num?)?.toDouble() ?? 1,
        );
}

class ClipEffects {
  const ClipEffects({
    this.grayscale = false,
    this.mirror = false,
    this.vignette = 0,
  });

  static const ClipEffects none = ClipEffects();

  final bool grayscale;
  final bool mirror;
  final double vignette;

  bool get isNone => !grayscale && !mirror && vignette == 0;

  ClipEffects copyWith({bool? grayscale, bool? mirror, double? vignette}) =>
      ClipEffects(
        grayscale: grayscale ?? this.grayscale,
        mirror: mirror ?? this.mirror,
        vignette: (vignette ?? this.vignette).clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'gray': grayscale,
    'mirror': mirror,
    'vig': vignette,
  };

  factory ClipEffects.fromJson(Map<String, dynamic>? json) => json == null
      ? ClipEffects.none
      : ClipEffects(
          grayscale: json['gray'] as bool? ?? false,
          mirror: json['mirror'] as bool? ?? false,
          vignette: (json['vig'] as num?)?.toDouble() ?? 0,
        );
}

enum TransitionType {
  none('none', 'None'),
  fade('fade', 'Fade'),
  dissolve('dissolve', 'Dissolve'),
  slideLeft('slideleft', 'Slide left'),
  slideRight('slideright', 'Slide right'),
  wipeLeft('wipeleft', 'Wipe left'),
  wipeUp('wipeup', 'Wipe up'),
  circleOpen('circleopen', 'Circle open'),
  smoothLeft('smoothleft', 'Smooth left');

  const TransitionType(this.ffmpegName, this.label);

  final String ffmpegName;
  final String label;

  bool get isNone => this == TransitionType.none;
}

class TransitionSpec {
  const TransitionSpec({
    this.type = TransitionType.fade,
    this.durationUs = 500000,
  });

  static const TransitionSpec none = TransitionSpec(type: TransitionType.none);

  final TransitionType type;
  final int durationUs;

  bool get isActive => !type.isNone && durationUs > 0;

  TransitionSpec copyWith({TransitionType? type, int? durationUs}) =>
      TransitionSpec(
        type: type ?? this.type,
        durationUs: (durationUs ?? this.durationUs).clamp(100000, 3000000),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'durationUs': durationUs,
  };

  factory TransitionSpec.fromJson(Map<String, dynamic>? json) => json == null
      ? TransitionSpec.none
      : TransitionSpec(
          type: TransitionType.values.firstWhere(
            (TransitionType t) => t.name == json['type'],
            orElse: () => TransitionType.none,
          ),
          durationUs: (json['durationUs'] as num?)?.toInt() ?? 500000,
        );
}

/// A single cut on a track. `durationUs` is timeline time; the source range is
/// `sourceInUs .. sourceInUs + durationUs * speed`.
class Clip {
  Clip({
    required this.id,
    required this.assetId,
    required this.durationUs,
    this.sourceInUs = 0,
    this.timelineStartUs = 0,
    this.speed = 1,
    this.volume = 1,
    this.muted = false,
    this.rotation = 0,
    this.fit = MediaFit.contain,
    this.scale = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.opacity = 1,
    this.crop = CropRect.full,
    this.grade = ColorGrade.neutral,
    this.effects = ClipEffects.none,
    this.transitionIn = TransitionSpec.none,
    this.label,
  });

  factory Clip.fromAsset({
    required String assetId,
    required int durationUs,
    String? label,
  }) => Clip(
    id: newId('clip'),
    assetId: assetId,
    durationUs: durationUs,
    label: label,
  );

  final String id;
  final String assetId;
  final int sourceInUs;
  final int durationUs;
  final int timelineStartUs;
  final double speed;
  final double volume;
  final bool muted;
  final int rotation;
  final MediaFit fit;
  final double scale;
  final double offsetX;
  final double offsetY;
  final double opacity;
  final CropRect crop;
  final ColorGrade grade;
  final ClipEffects effects;
  final TransitionSpec transitionIn;
  final String? label;

  Duration get duration => Duration(microseconds: durationUs);
  Duration get sourceIn => Duration(microseconds: sourceInUs);
  int get sourceDurationUs => (durationUs * speed).round();
  Duration get sourceOut =>
      Duration(microseconds: sourceInUs + sourceDurationUs);
  int get endUs => timelineStartUs + durationUs;
  Duration get end => Duration(microseconds: endUs);
  double get effectiveVolume => muted ? 0 : volume;

  Clip copyWith({
    String? assetId,
    int? sourceInUs,
    int? durationUs,
    int? timelineStartUs,
    double? speed,
    double? volume,
    bool? muted,
    int? rotation,
    MediaFit? fit,
    double? scale,
    double? offsetX,
    double? offsetY,
    double? opacity,
    CropRect? crop,
    ColorGrade? grade,
    ClipEffects? effects,
    TransitionSpec? transitionIn,
    bool clearTransition = false,
    String? label,
  }) {
    return Clip(
      id: id,
      assetId: assetId ?? this.assetId,
      sourceInUs: (sourceInUs ?? this.sourceInUs).clamp(0, 1 << 50),
      durationUs: (durationUs ?? this.durationUs).clamp(
        50000,
        24 * 3600 * 1000000,
      ),
      timelineStartUs: (timelineStartUs ?? this.timelineStartUs).clamp(
        0,
        1 << 50,
      ),
      speed: (speed ?? this.speed).clamp(0.25, 4.0),
      volume: (volume ?? this.volume).clamp(0.0, 2.0),
      muted: muted ?? this.muted,
      rotation: ((rotation ?? this.rotation) % 360 + 360) % 360,
      fit: fit ?? this.fit,
      scale: (scale ?? this.scale).clamp(0.2, 4.0),
      offsetX: (offsetX ?? this.offsetX).clamp(-1.0, 1.0),
      offsetY: (offsetY ?? this.offsetY).clamp(-1.0, 1.0),
      opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
      crop: crop ?? this.crop,
      grade: grade ?? this.grade,
      effects: effects ?? this.effects,
      transitionIn: clearTransition
          ? TransitionSpec.none
          : (transitionIn ?? this.transitionIn),
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'assetId': assetId,
    'sourceInUs': sourceInUs,
    'durationUs': durationUs,
    'timelineStartUs': timelineStartUs,
    'speed': speed,
    'volume': volume,
    'muted': muted,
    'rotation': rotation,
    'fit': fit.name,
    'scale': scale,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'opacity': opacity,
    'crop': crop.toJson(),
    'grade': grade.toJson(),
    'effects': effects.toJson(),
    'transitionIn': transitionIn.toJson(),
    if (label != null) 'label': label,
  };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
    id: json['id'] as String,
    assetId: json['assetId'] as String,
    sourceInUs: (json['sourceInUs'] as num?)?.toInt() ?? 0,
    durationUs: (json['durationUs'] as num?)?.toInt() ?? 0,
    timelineStartUs: (json['timelineStartUs'] as num?)?.toInt() ?? 0,
    speed: (json['speed'] as num?)?.toDouble() ?? 1,
    volume: (json['volume'] as num?)?.toDouble() ?? 1,
    muted: json['muted'] as bool? ?? false,
    rotation: (json['rotation'] as num?)?.toInt() ?? 0,
    fit: MediaFit.values.firstWhere(
      (MediaFit fit) => fit.name == json['fit'],
      orElse: () => MediaFit.contain,
    ),
    scale: (json['scale'] as num?)?.toDouble() ?? 1,
    offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
    offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    crop: CropRect.fromJson(json['crop'] as Map<String, dynamic>?),
    grade: ColorGrade.fromJson(json['grade'] as Map<String, dynamic>?),
    effects: ClipEffects.fromJson(json['effects'] as Map<String, dynamic>?),
    transitionIn: TransitionSpec.fromJson(
      json['transitionIn'] as Map<String, dynamic>?,
    ),
    label: json['label'] as String?,
  );
}
