import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

class SceneFrame {
  const SceneFrame({required this.path, required this.timeUs, this.score});

  final String path;
  final int timeUs;
  final double? score;

  Duration get time => Duration(microseconds: timeUs);
}

class AudioAnalysis {
  const AudioAnalysis({
    required this.meanVolumeDb,
    required this.maxVolumeDb,
    required this.wavPath,
  });

  final double meanVolumeDb;
  final double maxVolumeDb;
  final String wavPath;
}

/// FFmpeg jobs used for thumbnails, waveforms, scene sampling and the recap
/// evidence stage. Every method talks to the real FFmpeg binary.
class MediaExtractionService {
  const MediaExtractionService();

  Future<String?> thumbnail({
    required String videoPath,
    required Directory outputDir,
    String name = 'thumb.jpg',
    Duration at = const Duration(milliseconds: 500),
    int width = 480,
  }) async {
    final output = File(p.join(outputDir.path, name));
    await outputDir.create(recursive: true);
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-hide_banner',
      '-ss',
      (at.inMilliseconds / 1000).toStringAsFixed(3),
      '-i',
      videoPath,
      '-frames:v',
      '1',
      '-vf',
      'scale=$width:-2',
      '-q:v',
      '4',
      '-y',
      output.path,
    ]);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) return null;
    return await output.exists() ? output.path : null;
  }

  Future<String?> waveform({
    required String audioPath,
    required Directory outputDir,
    String name = 'waveform.png',
  }) async {
    final output = File(p.join(outputDir.path, name));
    await outputDir.create(recursive: true);
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-hide_banner',
      '-i',
      audioPath,
      '-filter_complex',
      'showwavespic=s=1200x140:colors=0xF2B24A',
      '-frames:v',
      '1',
      '-y',
      output.path,
    ]);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) return null;
    return await output.exists() ? output.path : null;
  }

  /// Samples real frames with FFmpeg scene detection, with a timed fallback when
  /// the video has too few hard cuts.
  Future<List<SceneFrame>> extractScenes({
    required String videoPath,
    required Directory outputDir,
    int maxFrames = 24,
    double sceneThreshold = 0.30,
    int intervalSeconds = 8,
  }) async {
    await outputDir.create(recursive: true);
    final metaFile = File(p.join(outputDir.path, 'scene_metadata.txt'));
    for (final child in outputDir.listSync()) {
      if (child is File && p.basename(child.path).startsWith('scene_')) {
        child.deleteSync();
      }
    }
    final pattern = p.join(outputDir.path, 'scene_%03d.jpg');
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-hide_banner',
      '-i',
      videoPath,
      '-vf',
      "select='gt(scene,$sceneThreshold)',"
          'metadata=print:file=${metaFile.path},scale=640:-2',
      '-fps_mode',
      'vfr',
      '-frames:v',
      '$maxFrames',
      '-q:v',
      '4',
      '-y',
      pattern,
    ]);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) {
      return <SceneFrame>[];
    }
    final images =
        outputDir
            .listSync()
            .whereType<File>()
            .where(
              (File f) =>
                  p.basename(f.path).startsWith('scene_') &&
                  f.path.toLowerCase().endsWith('.jpg'),
            )
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    if (images.isEmpty) {
      return _intervalFrames(
        videoPath: videoPath,
        outputDir: outputDir,
        maxFrames: maxFrames,
        intervalSeconds: intervalSeconds,
      );
    }
    final times = <int>[];
    if (await metaFile.exists()) {
      final raw = await metaFile.readAsString();
      for (final match in RegExp(
        r'pts_time:([0-9]+(?:\.[0-9]+)?)',
      ).allMatches(raw)) {
        final seconds = double.tryParse(match.group(1) ?? '');
        if (seconds != null) times.add((seconds * 1000000).round());
      }
    }
    return <SceneFrame>[
      for (var i = 0; i < images.length; i++)
        SceneFrame(
          path: images[i].path,
          timeUs: i < times.length ? times[i] : i * intervalSeconds * 1000000,
        ),
    ];
  }

  Future<List<SceneFrame>> _intervalFrames({
    required String videoPath,
    required Directory outputDir,
    required int maxFrames,
    required int intervalSeconds,
  }) async {
    final pattern = p.join(outputDir.path, 'interval_%03d.jpg');
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-hide_banner',
      '-i',
      videoPath,
      '-vf',
      'fps=1/$intervalSeconds,scale=640:-2',
      '-frames:v',
      '$maxFrames',
      '-q:v',
      '4',
      '-y',
      pattern,
    ]);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) return <SceneFrame>[];
    final images =
        outputDir
            .listSync()
            .whereType<File>()
            .where(
              (File f) =>
                  p.basename(f.path).startsWith('interval_') &&
                  f.path.toLowerCase().endsWith('.jpg'),
            )
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    return <SceneFrame>[
      for (var i = 0; i < images.length; i++)
        SceneFrame(path: images[i].path, timeUs: i * intervalSeconds * 1000000),
    ];
  }

  /// Mono 16 kHz WAV, the input shape required by on-device ASR.
  Future<String?> extractAudioWav({
    required String videoPath,
    required Directory outputDir,
    String name = 'audio.wav',
  }) async {
    final output = File(p.join(outputDir.path, name));
    await outputDir.create(recursive: true);
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-hide_banner',
      '-i',
      videoPath,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'pcm_s16le',
      '-y',
      output.path,
    ]);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) return null;
    return await output.exists() ? output.path : null;
  }

  Future<AudioAnalysis?> analyzeLoudness(String audioPath) async {
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-hide_banner',
      '-i',
      audioPath,
      '-af',
      'volumedetect',
      '-f',
      'null',
      '-',
    ]);
    final logs = await session.getOutput() ?? '';
    final mean = RegExp(r'mean_volume:\s*(-?[0-9.]+)\s*dB').firstMatch(logs);
    final max = RegExp(r'max_volume:\s*(-?[0-9.]+)\s*dB').firstMatch(logs);
    if (mean == null || max == null) return null;
    return AudioAnalysis(
      meanVolumeDb: double.parse(mean.group(1)!),
      maxVolumeDb: double.parse(max.group(1)!),
      wavPath: audioPath,
    );
  }
}
