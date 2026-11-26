import 'dart:convert';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

class MediaProbeException implements Exception {
  MediaProbeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MediaProbeResult {
  const MediaProbeResult({
    required this.durationUs,
    required this.width,
    required this.height,
    required this.fps,
    required this.hasVideo,
    required this.hasAudio,
    this.videoCodec,
    this.audioCodec,
  });

  final int durationUs;
  final int width;
  final int height;
  final double fps;
  final bool hasVideo;
  final bool hasAudio;
  final String? videoCodec;
  final String? audioCodec;

  Duration get duration => Duration(microseconds: durationUs);
  bool get isVertical => height > width;

  /// Pure parser so FFprobe JSON handling is unit-testable.
  factory MediaProbeResult.fromFfprobeJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw MediaProbeException('FFprobe returned an unexpected payload.');
    }
    final format = decoded['format'] as Map<String, dynamic>?;
    final streams = (decoded['streams'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final video = streams.cast<Map<String, dynamic>?>().firstWhere(
      (Map<String, dynamic>? s) => s?['codec_type'] == 'video',
      orElse: () => null,
    );
    final audio = streams.cast<Map<String, dynamic>?>().firstWhere(
      (Map<String, dynamic>? s) => s?['codec_type'] == 'audio',
      orElse: () => null,
    );
    final durationSeconds =
        double.tryParse('${format?['duration'] ?? ''}') ??
        double.tryParse('${video?['duration'] ?? ''}') ??
        double.tryParse('${audio?['duration'] ?? ''}') ??
        0;
    return MediaProbeResult(
      durationUs: (durationSeconds * 1000000).round(),
      width: (video?['width'] as num?)?.toInt() ?? 0,
      height: (video?['height'] as num?)?.toInt() ?? 0,
      fps:
          _parseRate(video?['avg_frame_rate'] as String?) ??
          _parseRate(video?['r_frame_rate'] as String?) ??
          0,
      hasVideo: video != null,
      hasAudio: audio != null,
      videoCodec: video?['codec_name'] as String?,
      audioCodec: audio?['codec_name'] as String?,
    );
  }

  static double? _parseRate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('/');
    if (parts.length == 2) {
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den != 0) return num / den;
    }
    return double.tryParse(raw);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'durationUs': durationUs,
    'width': width,
    'height': height,
    'fps': fps,
    'hasVideo': hasVideo,
    'hasAudio': hasAudio,
    'videoCodec': videoCodec,
    'audioCodec': audioCodec,
  };
}

class MediaProbeService {
  const MediaProbeService();

  Future<MediaProbeResult> probe(String path) async {
    final session = await FFprobeKit.executeWithArguments(<String>[
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      path,
    ]);
    final output = await session.getOutput() ?? '';
    if (output.trim().isEmpty) {
      throw MediaProbeException(
        'FFprobe could not read this file. It may be unsupported or corrupt.',
      );
    }
    try {
      return MediaProbeResult.fromFfprobeJson(output);
    } on FormatException catch (error) {
      throw MediaProbeException('FFprobe JSON error: ${error.message}');
    }
  }
}
