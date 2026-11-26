import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/repositories/project_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/ai/asr_service.dart';
import '../data/services/ai/llama_runner.dart';
import '../data/services/ai/recap_service.dart';
import '../data/services/ai/translation_service.dart';
import '../data/services/ffmpeg/ffmpeg_capabilities.dart';
import '../data/services/ffmpeg/media_extraction_service.dart';
import '../data/services/ffmpeg/media_probe_service.dart';
import '../data/services/ffmpeg/render_service.dart';
import '../data/services/media_importer.dart';
import '../data/services/models/model_library_service.dart';

/// Composition root. Owns the long-lived services and the FFmpeg capability
/// probe so every screen sees the same truth about the device binary.
class AppServices {
  AppServices({
    required this.repository,
    required this.settings,
    required this.cacheDir,
    required this.probe,
    required this.extraction,
    required this.importer,
    required this.render,
    required this.models,
    required this.runner,
    required this.translation,
    required this.recap,
    required this.asr,
  });

  final ProjectRepository repository;
  final SettingsRepository settings;
  final Directory cacheDir;
  final MediaProbeService probe;
  final MediaExtractionService extraction;
  final MediaImporterService importer;
  final RenderService render;
  final ModelLibraryService models;
  final LlamaRunner runner;
  final SubtitleTranslationService translation;
  final MovieRecapService recap;
  final AsrService asr;

  final ValueNotifier<FfmpegCapabilities> capabilities =
      ValueNotifier<FfmpegCapabilities>(const FfmpegCapabilities.unknown());
  Future<FfmpegCapabilities>? _capabilityProbe;

  Directory get exportsRoot => repository.exportsRoot;

  static Future<AppServices> bootstrap() async {
    final repository = await ProjectRepository.open();
    await repository.init();
    final settings = await SettingsRepository.open();
    final cacheDir = await getApplicationCacheDirectory();
    final runner = LlamaRunner();
    final extraction = const MediaExtractionService();
    final probe = const MediaProbeService();
    final asr = const AsrService();
    final services = AppServices(
      repository: repository,
      settings: settings,
      cacheDir: cacheDir,
      probe: probe,
      extraction: extraction,
      importer: const MediaImporterService(),
      render: RenderService(),
      models: ModelLibraryService(repository.modelsRoot),
      runner: runner,
      translation: SubtitleTranslationService(runner),
      recap: MovieRecapService(
        runner: runner,
        extraction: extraction,
        probe: probe,
        asr: asr,
      ),
      asr: asr,
    );
    // Probe in the background; the export sheet shows a waiting state until the
    // real encoder list arrives.
    services.ensureCapabilities();
    return services;
  }

  Future<FfmpegCapabilities> ensureCapabilities({bool force = false}) {
    if (force) _capabilityProbe = null;
    final existing = _capabilityProbe;
    if (existing != null) return existing;
    final probe = FfmpegCapabilities.detect().then((FfmpegCapabilities caps) {
      capabilities.value = caps;
      return caps;
    });
    _capabilityProbe = probe;
    return probe;
  }

  Future<void> dispose() async {
    await runner.dispose();
  }
}
