import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/models/export_settings.dart';
import '../data/models/project.dart';
import '../data/services/ffmpeg/export_command_builder.dart';
import '../data/services/ffmpeg/ffmpeg_capabilities.dart';
import '../data/services/ffmpeg/render_service.dart';
import 'app_services.dart';

enum ExportStatus { idle, preparing, rendering, succeeded, failed, cancelled }

class ExportController extends ChangeNotifier {
  ExportController({
    required this.services,
    required this.project,
    ExportSettings? initial,
  }) : settings = initial ?? project.exportSettings;

  final AppServices services;
  final Project project;
  ExportSettings settings;

  ExportStatus status = ExportStatus.idle;
  double progress = 0;
  String? error;
  String? outputPath;
  int outputBytes = 0;
  ExportPlan? plan;
  String? planText;
  bool _disposed = false;

  FfmpegCapabilities get capabilities => services.capabilities.value;

  List<ExportIssue> get issues => ExportValidator.validate(
    project: project,
    settings: settings,
    capabilities: capabilities.available ? capabilities : null,
  );

  bool get canExport =>
      status != ExportStatus.rendering &&
      status != ExportStatus.preparing &&
      !issues.any((ExportIssue i) => i.isBlocking);

  void updateSettings(ExportSettings next) {
    settings = next;
    notifyListeners();
  }

  void setContainer(ExportContainer container) {
    var next = settings.copyWith(container: container);
    if (!next.videoCodec.containers.contains(container)) {
      next = next.copyWith(
        videoCodec: VideoCodec.values.firstWhere(
          (VideoCodec codec) => codec.containers.contains(container),
        ),
      );
    }
    if (!next.audioCodec.containers.contains(container)) {
      next = next.copyWith(
        audioCodec: ExportAudioCodec.values.firstWhere(
          (ExportAudioCodec codec) => codec.containers.contains(container),
        ),
      );
    }
    final soft = SoftSubtitleCodec.forContainer(container);
    if (!soft.contains(next.softSubtitleCodec) && soft.isNotEmpty) {
      next = next.copyWith(softSubtitleCodec: soft.first);
    }
    settings = next;
    notifyListeners();
  }

  Future<void> start() async {
    if (!canExport) return;
    status = ExportStatus.preparing;
    progress = 0;
    error = null;
    outputPath = null;
    outputBytes = 0;
    notifyListeners();
    final caps = await services.ensureCapabilities();
    if (!caps.available) {
      status = ExportStatus.failed;
      error =
          caps.error ??
          'FFmpeg did not start on this device, so export is unavailable.';
      notifyListeners();
      return;
    }
    await WakelockPlus.enable();
    try {
      status = ExportStatus.rendering;
      notifyListeners();
      final result = await services.render.render(
        project: project,
        settings: settings,
        outputDir: services.repository.projectExportsDir(project.id),
        cacheDir: services.cacheDir,
        capabilities: caps,
        onPlan: (ExportPlan value) {
          plan = value;
          planText = RenderService.describePlan(value);
          notifyListeners();
        },
        onProgress: (RenderProgress value) {
          progress = value.fraction;
          notifyListeners();
        },
      );
      outputPath = result.path;
      outputBytes = result.sizeBytes;
      status = ExportStatus.succeeded;
      project.exportSettings = settings;
      await services.settings.setDefaultExport(settings);
      await services.repository.save(project);
    } on RenderCancelled {
      status = ExportStatus.cancelled;
    } on RenderException catch (e) {
      status = ExportStatus.failed;
      error = e.message;
    } catch (e) {
      status = ExportStatus.failed;
      error = 'Export failed: $e';
    } finally {
      await WakelockPlus.disable();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> cancel() async {
    await services.render.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
