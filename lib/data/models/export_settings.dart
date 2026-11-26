/// Export options. Everything here maps to a real FFmpeg option in the
/// bundled FFmpeg 8 build (libx264, libx265, libaom, libvpx, libopus, libass).
enum ExportContainer {
  mp4('MP4', 'mp4', 'Best compatibility'),
  mkv('MKV', 'mkv', 'Flexible tracks'),
  webm('WebM', 'webm', 'Open web format');

  const ExportContainer(this.label, this.extension, this.blurb);

  final String label;
  final String extension;
  final String blurb;
}

enum VideoCodec {
  h264('H.264', 'libx264', 'Universal compatibility'),
  h265('H.265', 'libx265', 'Smaller files, wider device support'),
  av1('AV1', 'libaom-av1', 'Smallest files, slow to encode'),
  vp9('VP9', 'libvpx-vp9', 'WebM native, slow to encode');

  const VideoCodec(this.label, this.encoder, this.blurb);

  final String label;
  final String encoder;
  final String blurb;

  bool get isSlow => this == VideoCodec.av1 || this == VideoCodec.vp9;

  Set<ExportContainer> get containers => switch (this) {
    VideoCodec.h264 => {ExportContainer.mp4, ExportContainer.mkv},
    VideoCodec.h265 => {ExportContainer.mp4, ExportContainer.mkv},
    VideoCodec.av1 => {
      ExportContainer.mp4,
      ExportContainer.mkv,
      ExportContainer.webm,
    },
    VideoCodec.vp9 => {ExportContainer.mkv, ExportContainer.webm},
  };
}

enum ExportAudioCodec {
  aac('AAC', 'aac', 'Standard for MP4'),
  opus('Opus', 'libopus', 'Efficient, WebM native'),
  mp3('MP3', 'libmp3lame', 'Legacy playback'),
  none('No audio', '', 'Silent export');

  const ExportAudioCodec(this.label, this.encoder, this.blurb);

  final String label;
  final String encoder;
  final String blurb;

  Set<ExportContainer> get containers => switch (this) {
    ExportAudioCodec.aac => {ExportContainer.mp4, ExportContainer.mkv},
    ExportAudioCodec.opus => {ExportContainer.mkv, ExportContainer.webm},
    ExportAudioCodec.mp3 => {ExportContainer.mp4, ExportContainer.mkv},
    ExportAudioCodec.none => ExportContainer.values.toSet(),
  };
}

enum ResolutionPreset {
  source('Source'),
  p1080('1080p'),
  p720('720p'),
  p480('480p');

  const ResolutionPreset(this.label);

  final String label;

  int resolveHeight(int canvasHeight) => switch (this) {
    ResolutionPreset.source => canvasHeight,
    ResolutionPreset.p1080 => 1080,
    ResolutionPreset.p720 => 720,
    ResolutionPreset.p480 => 480,
  };
}

enum FrameRatePreset {
  source('Source'),
  fps24('24'),
  fps25('25'),
  fps30('30'),
  fps60('60');

  const FrameRatePreset(this.label);

  final String label;

  double resolve(double projectFps) => switch (this) {
    FrameRatePreset.source => projectFps,
    FrameRatePreset.fps24 => 24,
    FrameRatePreset.fps25 => 25,
    FrameRatePreset.fps30 => 30,
    FrameRatePreset.fps60 => 60,
  };
}

enum SubtitleExportMode {
  none('No subtitles'),
  burnIn('Burn into video'),
  soft('Soft subtitle track');

  const SubtitleExportMode(this.label);

  final String label;
}

enum SoftSubtitleCodec {
  movText('MP4 timed text', 'mov_text', {ExportContainer.mp4}),
  subrip('SubRip (SRT)', 'srt', {ExportContainer.mkv}),
  ass('ASS / SSA', 'ass', {ExportContainer.mkv}),
  webvtt('WebVTT', 'webvtt', {ExportContainer.webm});

  const SoftSubtitleCodec(this.label, this.codecName, this.containers);

  final String label;
  final String codecName;
  final Set<ExportContainer> containers;

  static List<SoftSubtitleCodec> forContainer(ExportContainer container) =>
      values
          .where((SoftSubtitleCodec c) => c.containers.contains(container))
          .toList();
}

class ExportSettings {
  const ExportSettings({
    this.container = ExportContainer.mp4,
    this.videoCodec = VideoCodec.h264,
    this.audioCodec = ExportAudioCodec.aac,
    this.resolution = ResolutionPreset.p1080,
    this.frameRate = FrameRatePreset.fps30,
    this.videoBitrateKbps = 8000,
    this.audioBitrateKbps = 192,
    this.subtitleMode = SubtitleExportMode.burnIn,
    this.softSubtitleCodec = SoftSubtitleCodec.movText,
    this.fileName = 'amkyaw-export',
  });

  static const ExportSettings defaults = ExportSettings();

  final ExportContainer container;
  final VideoCodec videoCodec;
  final ExportAudioCodec audioCodec;
  final ResolutionPreset resolution;
  final FrameRatePreset frameRate;
  final int videoBitrateKbps;
  final int audioBitrateKbps;
  final SubtitleExportMode subtitleMode;
  final SoftSubtitleCodec softSubtitleCodec;
  final String fileName;

  ExportSettings copyWith({
    ExportContainer? container,
    VideoCodec? videoCodec,
    ExportAudioCodec? audioCodec,
    ResolutionPreset? resolution,
    FrameRatePreset? frameRate,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    SubtitleExportMode? subtitleMode,
    SoftSubtitleCodec? softSubtitleCodec,
    String? fileName,
  }) {
    final nextContainer = container ?? this.container;
    return ExportSettings(
      container: nextContainer,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      videoBitrateKbps: (videoBitrateKbps ?? this.videoBitrateKbps).clamp(
        500,
        80000,
      ),
      audioBitrateKbps: (audioBitrateKbps ?? this.audioBitrateKbps).clamp(
        48,
        512,
      ),
      subtitleMode: subtitleMode ?? this.subtitleMode,
      softSubtitleCodec: softSubtitleCodec ?? this.softSubtitleCodec,
      fileName: fileName ?? this.fileName,
    );
  }

  int targetHeight(int canvasHeight) => resolution.resolveHeight(canvasHeight);

  int targetWidth(int canvasWidth, int canvasHeight) {
    final height = targetHeight(canvasHeight);
    final width = (canvasWidth * height / canvasHeight).round();
    // H.264 needs an even resolution.
    return (width / 2).round() * 2;
  }

  double targetFps(double projectFps) => frameRate.resolve(projectFps);

  List<SoftSubtitleCodec> get softCodecChoices =>
      SoftSubtitleCodec.forContainer(container);

  int estimatedBytes(int durationUs) {
    final seconds = durationUs / 1000000;
    final audioKbps = audioCodec == ExportAudioCodec.none
        ? 0
        : audioBitrateKbps;
    return ((videoBitrateKbps + audioKbps) * 1000 / 8 * seconds).round();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'container': container.name,
    'videoCodec': videoCodec.name,
    'audioCodec': audioCodec.name,
    'resolution': resolution.name,
    'frameRate': frameRate.name,
    'videoBitrateKbps': videoBitrateKbps,
    'audioBitrateKbps': audioBitrateKbps,
    'subtitleMode': subtitleMode.name,
    'softSubtitleCodec': softSubtitleCodec.name,
    'fileName': fileName,
  };

  factory ExportSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ExportSettings.defaults;
    T pick<T extends Enum>(List<T> values, Object? raw, T fallback) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
      return fallback;
    }

    return ExportSettings(
      container: pick(
        ExportContainer.values,
        json['container'],
        ExportContainer.mp4,
      ),
      videoCodec: pick(VideoCodec.values, json['videoCodec'], VideoCodec.h264),
      audioCodec: pick(
        ExportAudioCodec.values,
        json['audioCodec'],
        ExportAudioCodec.aac,
      ),
      resolution: pick(
        ResolutionPreset.values,
        json['resolution'],
        ResolutionPreset.p1080,
      ),
      frameRate: pick(
        FrameRatePreset.values,
        json['frameRate'],
        FrameRatePreset.fps30,
      ),
      videoBitrateKbps: (json['videoBitrateKbps'] as num?)?.toInt() ?? 8000,
      audioBitrateKbps: (json['audioBitrateKbps'] as num?)?.toInt() ?? 192,
      subtitleMode: pick(
        SubtitleExportMode.values,
        json['subtitleMode'],
        SubtitleExportMode.burnIn,
      ),
      softSubtitleCodec: pick(
        SoftSubtitleCodec.values,
        json['softSubtitleCodec'],
        SoftSubtitleCodec.movText,
      ),
      fileName: json['fileName'] as String? ?? 'amkyaw-export',
    );
  }
}
