import '../../core/utils/ids.dart';

enum SubtitleAlignment { bottom, center, top }

enum SubtitleFormat {
  srt('SRT', 'srt'),
  vtt('VTT', 'vtt');

  const SubtitleFormat(this.label, this.extension);

  final String label;
  final String extension;
}

/// Styling shared by the burned-in ASS render and the Flutter preview.
class SubtitleStyle {
  const SubtitleStyle({
    this.fontFamily = 'NotoSansMyanmar',
    this.fontSize = 54,
    this.primaryColor = 0xFFFFFFFF,
    this.outlineColor = 0xFF000000,
    this.outlineWidth = 3,
    this.shadowColor = 0xB3000000,
    this.shadowDepth = 0,
    this.backgroundColor = 0x00000000,
    this.bold = false,
    this.italic = false,
    this.alignment = SubtitleAlignment.bottom,
    this.marginVertical = 8,
    this.marginHorizontal = 8,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
  });

  static const SubtitleStyle initial = SubtitleStyle();

  /// Size is in pixels relative to a 1080 px tall canvas.
  final String fontFamily;
  final double fontSize;
  final int primaryColor;
  final int outlineColor;
  final double outlineWidth;
  final int shadowColor;
  final double shadowDepth;
  final int backgroundColor;
  final bool bold;
  final bool italic;
  final SubtitleAlignment alignment;
  final double marginVertical;
  final double marginHorizontal;
  final double letterSpacing;
  final double lineHeight;

  bool get hasBackground => (backgroundColor >> 24) & 0xFF > 0;

  SubtitleStyle copyWith({
    String? fontFamily,
    double? fontSize,
    int? primaryColor,
    int? outlineColor,
    double? outlineWidth,
    int? shadowColor,
    double? shadowDepth,
    int? backgroundColor,
    bool? bold,
    bool? italic,
    SubtitleAlignment? alignment,
    double? marginVertical,
    double? marginHorizontal,
    double? letterSpacing,
    double? lineHeight,
  }) {
    return SubtitleStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: (fontSize ?? this.fontSize).clamp(16.0, 140.0),
      primaryColor: primaryColor ?? this.primaryColor,
      outlineColor: outlineColor ?? this.outlineColor,
      outlineWidth: (outlineWidth ?? this.outlineWidth).clamp(0.0, 12.0),
      shadowColor: shadowColor ?? this.shadowColor,
      shadowDepth: (shadowDepth ?? this.shadowDepth).clamp(0.0, 12.0),
      backgroundColor: backgroundColor ?? this.backgroundColor,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      alignment: alignment ?? this.alignment,
      marginVertical: (marginVertical ?? this.marginVertical).clamp(0.0, 40.0),
      marginHorizontal: (marginHorizontal ?? this.marginHorizontal).clamp(
        0.0,
        30.0,
      ),
      letterSpacing: (letterSpacing ?? this.letterSpacing).clamp(0.0, 12.0),
      lineHeight: (lineHeight ?? this.lineHeight).clamp(0.9, 2.2),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'primaryColor': primaryColor,
    'outlineColor': outlineColor,
    'outlineWidth': outlineWidth,
    'shadowColor': shadowColor,
    'shadowDepth': shadowDepth,
    'backgroundColor': backgroundColor,
    'bold': bold,
    'italic': italic,
    'alignment': alignment.name,
    'marginVertical': marginVertical,
    'marginHorizontal': marginHorizontal,
    'letterSpacing': letterSpacing,
    'lineHeight': lineHeight,
  };

  factory SubtitleStyle.fromJson(Map<String, dynamic>? json) => json == null
      ? SubtitleStyle.initial
      : SubtitleStyle(
          fontFamily: json['fontFamily'] as String? ?? 'NotoSansMyanmar',
          fontSize: (json['fontSize'] as num?)?.toDouble() ?? 54,
          primaryColor: (json['primaryColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
          outlineColor: (json['outlineColor'] as num?)?.toInt() ?? 0xFF000000,
          outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 3,
          shadowColor: (json['shadowColor'] as num?)?.toInt() ?? 0xB3000000,
          shadowDepth: (json['shadowDepth'] as num?)?.toDouble() ?? 0,
          backgroundColor:
              (json['backgroundColor'] as num?)?.toInt() ?? 0x00000000,
          bold: json['bold'] as bool? ?? false,
          italic: json['italic'] as bool? ?? false,
          alignment: SubtitleAlignment.values.firstWhere(
            (SubtitleAlignment a) => a.name == json['alignment'],
            orElse: () => SubtitleAlignment.bottom,
          ),
          marginVertical: (json['marginVertical'] as num?)?.toDouble() ?? 8,
          marginHorizontal: (json['marginHorizontal'] as num?)?.toDouble() ?? 8,
          letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
          lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
        );
}

class SubtitleCue {
  const SubtitleCue({
    required this.id,
    required this.startUs,
    required this.endUs,
    required this.text,
  });

  factory SubtitleCue.create({
    required Duration start,
    Duration? end,
    String text = '',
  }) {
    final startUs = start.inMicroseconds;
    final endUs = (end ?? start + const Duration(seconds: 2)).inMicroseconds;
    return SubtitleCue(
      id: newId('cue'),
      startUs: startUs,
      endUs: endUs < startUs + 100000 ? startUs + 100000 : endUs,
      text: text,
    );
  }

  final String id;
  final int startUs;
  final int endUs;
  final String text;

  Duration get start => Duration(microseconds: startUs);
  Duration get end => Duration(microseconds: endUs);
  int get durationUs => endUs - startUs;
  Duration get duration => Duration(microseconds: durationUs);

  bool contains(Duration position) =>
      position.inMicroseconds >= startUs && position.inMicroseconds < endUs;

  SubtitleCue copyWith({int? startUs, int? endUs, String? text}) {
    final nextStart = (startUs ?? this.startUs).clamp(0, 1 << 50);
    final nextEnd = (endUs ?? this.endUs).clamp(nextStart + 50000, 1 << 50);
    return SubtitleCue(
      id: id,
      startUs: nextStart,
      endUs: nextEnd,
      text: text ?? this.text,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'startUs': startUs,
    'endUs': endUs,
    'text': text,
  };

  factory SubtitleCue.fromJson(Map<String, dynamic> json) => SubtitleCue(
    id: json['id'] as String? ?? newId('cue'),
    startUs: (json['startUs'] as num?)?.toInt() ?? 0,
    endUs: (json['endUs'] as num?)?.toInt() ?? 2000000,
    text: json['text'] as String? ?? '',
  );
}

class SubtitleDocument {
  SubtitleDocument({
    List<SubtitleCue>? cues,
    this.style = SubtitleStyle.initial,
    this.sourceName,
    this.language = 'my',
  }) : cues = cues ?? <SubtitleCue>[];

  final List<SubtitleCue> cues;
  SubtitleStyle style;
  String? sourceName;
  String language;

  bool get isEmpty => cues.isEmpty;
  int get cueCount => cues.length;

  int get durationUs =>
      cues.isEmpty ? 0 : cues.map((SubtitleCue c) => c.endUs).reduce(_max);

  SubtitleCue? activeAt(Duration position) {
    for (final cue in cues) {
      if (cue.contains(position)) return cue;
    }
    return null;
  }

  void sortCues() => cues.sort((SubtitleCue a, SubtitleCue b) {
    final byStart = a.startUs.compareTo(b.startUs);
    return byStart != 0 ? byStart : a.endUs.compareTo(b.endUs);
  });

  /// Keeps a 20 ms gap so burned-in cues never collide.
  void fixOverlaps({int gapUs = 20000}) {
    sortCues();
    for (var i = 0; i < cues.length - 1; i++) {
      final current = cues[i];
      final next = cues[i + 1];
      if (next.startUs < current.endUs + gapUs) {
        final adjusted = next.copyWith(
          startUs: current.endUs + gapUs,
          endUs: next.endUs > current.endUs + gapUs
              ? next.endUs
              : current.endUs + gapUs + 200000,
        );
        cues[i + 1] = adjusted;
      }
    }
  }

  void shiftAll(Duration offset) {
    final delta = offset.inMicroseconds;
    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      final nextStart = (cue.startUs + delta).clamp(0, 1 << 50);
      final shiftedEnd = cue.endUs + delta;
      final nextEnd = shiftedEnd <= nextStart
          ? nextStart + cue.durationUs
          : shiftedEnd;
      cues[i] = cue.copyWith(startUs: nextStart, endUs: nextEnd);
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cues': cues.map((SubtitleCue c) => c.toJson()).toList(),
    'style': style.toJson(),
    if (sourceName != null) 'sourceName': sourceName,
    'language': language,
  };

  factory SubtitleDocument.fromJson(Map<String, dynamic>? json) {
    if (json == null) return SubtitleDocument();
    return SubtitleDocument(
      cues: (json['cues'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => SubtitleCue.fromJson(e as Map<String, dynamic>))
          .toList(),
      style: SubtitleStyle.fromJson(json['style'] as Map<String, dynamic>?),
      sourceName: json['sourceName'] as String?,
      language: json['language'] as String? ?? 'my',
    );
  }

  static int _max(int a, int b) => a > b ? a : b;
}
