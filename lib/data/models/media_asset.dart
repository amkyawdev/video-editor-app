/// A file imported into a project. Media is copied into the project folder so
/// a project keeps working after the source file is moved or the cache clears.
enum MediaKind { video, audio, image }

class MediaAsset {
  MediaAsset({
    required this.id,
    required this.name,
    required this.path,
    required this.kind,
    required this.durationUs,
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.sizeBytes = 0,
    this.hasAudio = false,
    this.thumbnailPath,
    this.waveformPath,
  });

  final String id;
  final String name;
  final String path;
  final MediaKind kind;
  final int durationUs;
  final int width;
  final int height;
  final double fps;
  final int sizeBytes;
  final bool hasAudio;
  final String? thumbnailPath;
  final String? waveformPath;

  Duration get duration => Duration(microseconds: durationUs);
  bool get isVisual => kind == MediaKind.video || kind == MediaKind.image;
  bool get isVideo => kind == MediaKind.video;
  bool get isAudio => kind == MediaKind.audio;
  double get aspectRatio => width > 0 && height > 0 ? width / height : 16 / 9;

  MediaAsset copyWith({
    String? name,
    String? path,
    int? durationUs,
    int? width,
    int? height,
    double? fps,
    int? sizeBytes,
    bool? hasAudio,
    String? thumbnailPath,
    String? waveformPath,
  }) {
    return MediaAsset(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      kind: kind,
      durationUs: durationUs ?? this.durationUs,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      hasAudio: hasAudio ?? this.hasAudio,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      waveformPath: waveformPath ?? this.waveformPath,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'path': path,
    'kind': kind.name,
    'durationUs': durationUs,
    'width': width,
    'height': height,
    'fps': fps,
    'sizeBytes': sizeBytes,
    'hasAudio': hasAudio,
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
    if (waveformPath != null) 'waveformPath': waveformPath,
  };

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'media',
    path: json['path'] as String,
    kind: MediaKind.values.firstWhere(
      (MediaKind kind) => kind.name == json['kind'],
      orElse: () => MediaKind.video,
    ),
    durationUs: (json['durationUs'] as num?)?.toInt() ?? 0,
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
    fps: (json['fps'] as num?)?.toDouble() ?? 0,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    hasAudio: json['hasAudio'] as bool? ?? false,
    thumbnailPath: json['thumbnailPath'] as String?,
    waveformPath: json['waveformPath'] as String?,
  );
}
