import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/file_names.dart';
import '../../../core/utils/font_assets.dart';
import '../../../core/utils/time_utils.dart';
import '../../models/export_settings.dart';
import '../../models/project.dart';
import '../../models/subtitle.dart';
import '../subtitle/ass_writer.dart';
import '../subtitle/subtitle_formats.dart';
import 'ffmpeg_capabilities.dart';
import 'export_command_builder.dart';

class RenderException implements Exception {
  RenderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RenderCancelled implements Exception {
  @override
  String toString() => 'Render cancelled.';
}

class RenderProgress {
  const RenderProgress({
    required this.fraction,
    required this.processedUs,
    required this.speed,
    required this.sizeBytes,
  });

  final double fraction;
  final int processedUs;
  final double speed;
  final int sizeBytes;
}

class RenderResult {
  const RenderResult({
    required this.path,
    required this.sizeBytes,
    required this.duration,
    required this.plan,
  });

  final String path;
  final int sizeBytes;
  final Duration duration;
  final ExportPlan plan;
}

class RenderService {
  RenderService([this.builder = const ExportCommandBuilder()]);

  final ExportCommandBuilder builder;
  int? _sessionId;
  bool _cancelRequested = false;

  bool get isRunning => _sessionId != null;

  Future<void> cancel() async {
    _cancelRequested = true;
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }

  Future<RenderResult> render({
    required Project project,
    required ExportSettings settings,
    required Directory outputDir,
    required Directory cacheDir,
    required FfmpegCapabilities capabilities,
    void Function(RenderProgress progress)? onProgress,
    void Function(ExportPlan plan)? onPlan,
  }) async {
    if (_sessionId != null) {
      throw RenderException('Another render is already running.');
    }
    _cancelRequested = false;
    await outputDir.create(recursive: true);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final workDir = Directory(p.join(cacheDir.path, 'render_$stamp'));
    await workDir.create(recursive: true);

    final baseName = sanitizeFileName(
      settings.fileName.isEmpty ? project.name : settings.fileName,
      fallback: 'amkyaw-export',
    );
    final output = File(
      p.join(
        outputDir.path,
        withExtension('${baseName}_$stamp', settings.container.extension),
      ),
    );

    String? assPath;
    String? softPath;
    String? fontsDir;

    final wantBurn =
        settings.subtitleMode == SubtitleExportMode.burnIn &&
        project.subtitles.cues.isNotEmpty;
    final wantSoft =
        settings.subtitleMode == SubtitleExportMode.soft &&
        project.subtitles.cues.isNotEmpty;

    try {
      if (wantBurn) {
        final fonts = await FontAssets.materialize(cacheDir);
        fontsDir = fonts.path;
        final file = File(p.join(workDir.path, 'sub.ass'));
        await file.writeAsString(
          AssWriter.build(
            project.subtitles,
            canvasWidth: project.canvasWidth,
            canvasHeight: project.canvasHeight,
          ),
          flush: true,
        );
        assPath = file.path;
      }
      if (wantSoft) {
        final codec = settings.softSubtitleCodec;
        final extension = switch (codec) {
          SoftSubtitleCodec.ass => 'ass',
          SoftSubtitleCodec.webvtt => 'vtt',
          _ => 'srt',
        };
        final file = File(p.join(workDir.path, 'soft.$extension'));
        final text = codec == SoftSubtitleCodec.ass
            ? AssWriter.build(
                project.subtitles,
                canvasWidth: project.canvasWidth,
                canvasHeight: project.canvasHeight,
              )
            : SubtitleFormats.encode(
                project.subtitles.cues,
                codec == SoftSubtitleCodec.webvtt
                    ? SubtitleFormat.vtt
                    : SubtitleFormat.srt,
              );
        await file.writeAsString(text, flush: true);
        softPath = file.path;
      }

      final plan = builder.build(
        project: project,
        settings: settings,
        outputPath: output.path,
        burnedSubtitlePath: assPath,
        softSubtitlePath: softPath,
        fontsDir: fontsDir,
        subtitleFilterAvailable: capabilities.canBurnInSubtitles,
        capabilities: capabilities,
      );
      onPlan?.call(plan);

      final completer = Completer<RenderResult>();
      final totalMs = plan.duration.inMilliseconds;

      final session = await FFmpegKit.executeWithArgumentsAsync(
        plan.args,
        (session) async {
          if (completer.isCompleted) return;
          final code = await session.getReturnCode();
          if (ReturnCode.isCancel(code) || _cancelRequested) {
            completer.completeError(RenderCancelled());
            return;
          }
          if (!ReturnCode.isSuccess(code)) {
            final logs = await session.getOutput() ?? '';
            final tail = logs.length > 4000
                ? logs.substring(logs.length - 4000)
                : logs;
            completer.completeError(
              RenderException('FFmpeg failed. Last log lines:\n$tail'),
            );
            return;
          }
          if (!await output.exists() || await output.length() == 0) {
            completer.completeError(
              RenderException('FFmpeg reported success but wrote no file.'),
            );
            return;
          }
          completer.complete(
            RenderResult(
              path: output.path,
              sizeBytes: await output.length(),
              duration: plan.duration,
              plan: plan,
            ),
          );
        },
        null,
        (Statistics stats) {
          if (completer.isCompleted) return;
          final fraction = totalMs <= 0
              ? 0.0
              : (stats.getTime() / totalMs).clamp(0.0, 0.999).toDouble();
          onProgress?.call(
            RenderProgress(
              fraction: fraction,
              processedUs: stats.getTime() * 1000,
              speed: stats.getSpeed(),
              sizeBytes: stats.getSize(),
            ),
          );
        },
      );
      _sessionId = session.getSessionId();
      if (_cancelRequested) {
        await cancel();
      }
      return await completer.future;
    } finally {
      _sessionId = null;
      _cancelRequested = false;
      try {
        if (await workDir.exists()) {
          await workDir.delete(recursive: true);
        }
      } catch (_) {
        // A leftover cache folder is harmless.
      }
    }
  }

  static String describePlan(ExportPlan plan) {
    final buffer = StringBuffer()
      ..writeln('Duration: ${TimeUtils.timecode(plan.duration)}')
      ..writeln('Audio track: ${plan.hasAudio ? 'yes' : 'no'}')
      ..writeln('Burned subtitles: ${plan.burnsSubtitles ? 'yes' : 'no'}')
      ..writeln('Soft subtitles: ${plan.embedsSubtitles ? 'yes' : 'no'}');
    for (final issue in plan.issues) {
      buffer.writeln('${issue.severity.name}: ${issue.message}');
    }
    return buffer.toString();
  }
}
