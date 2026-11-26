import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';

/// What the bundled FFmpeg build can actually do. The export sheet uses this so
/// it never offers a codec the device binary cannot encode.
class FfmpegCapabilities {
  const FfmpegCapabilities({
    required this.available,
    this.version = '',
    this.encoders = const <String>{},
    this.filters = const <String>{},
    this.muxers = const <String>{},
    this.error,
  });

  const FfmpegCapabilities.unknown()
    : available = false,
      version = '',
      encoders = const <String>{},
      filters = const <String>{},
      muxers = const <String>{},
      error = 'FFmpeg has not been probed yet.';

  final bool available;
  final String version;
  final Set<String> encoders;
  final Set<String> filters;
  final Set<String> muxers;
  final String? error;

  bool hasEncoder(String name) => encoders.contains(name);

  bool hasFilter(String name) => filters.contains(name);

  bool hasMuxer(String name) => muxers.contains(name);

  bool get canBurnInSubtitles => available && hasFilter('subtitles');

  static final RegExp _encoderLine = RegExp(r'^\s*[A-Z.]{6}\s+(\S+)');
  static final RegExp _filterLine = RegExp(r'^\s*[TSC.]{1,3}\s+(\S+)');
  static final RegExp _muxerLine = RegExp(r'^\s*[D.]{1,3}\s+(\S+)');

  static Future<FfmpegCapabilities> detect() async {
    try {
      final encoders = await _collect('-hide_banner -encoders', _encoderLine);
      final filters = await _collect('-hide_banner -filters', _filterLine);
      final muxers = await _collect('-hide_banner -muxers', _muxerLine);
      final versionSession = await FFmpegKit.execute('-hide_banner -version');
      final output = await versionSession.getOutput() ?? '';
      final version = output
          .split('\n')
          .firstWhere(
            (String line) => line.startsWith('ffmpeg version'),
            orElse: () => 'ffmpeg',
          );
      return FfmpegCapabilities(
        available: true,
        version: version.trim(),
        encoders: encoders,
        filters: filters,
        muxers: muxers,
      );
    } catch (error) {
      return FfmpegCapabilities(
        available: false,
        error: 'FFmpeg could not start: $error',
      );
    }
  }

  static Future<Set<String>> _collect(String command, RegExp pattern) async {
    final session = await FFmpegKit.execute(command);
    final output = await session.getOutput() ?? '';
    final result = <String>{};
    for (final line in output.split('\n')) {
      final match = pattern.firstMatch(line);
      if (match != null) result.add(match.group(1)!);
    }
    return result;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'available': available,
    'version': version,
    'encoders': encoders.toList()..sort(),
    'filters': filters.toList()..sort(),
    'muxers': muxers.toList()..sort(),
    if (error != null) 'error': error,
  };
}
