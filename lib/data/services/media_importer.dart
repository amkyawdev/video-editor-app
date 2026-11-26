import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/media_asset.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import 'ffmpeg/media_extraction_service.dart';
import 'ffmpeg/media_probe_service.dart';

class MediaImportException implements Exception {
  MediaImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MediaImporterService {
  const MediaImporterService({
    this.probe = const MediaProbeService(),
    this.extraction = const MediaExtractionService(),
  });

  final MediaProbeService probe;
  final MediaExtractionService extraction;

  static const Set<String> imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  Future<MediaAsset> importIntoProject({
    required File source,
    required Project project,
    required ProjectRepository repository,
  }) async {
    if (!await source.exists()) {
      throw MediaImportException('The selected file no longer exists.');
    }
    final size = await source.length();
    if (size == 0) {
      throw MediaImportException('The selected file is empty.');
    }
    final extension = p
        .extension(source.path)
        .replaceFirst('.', '')
        .toLowerCase();
    final isImage = imageExtensions.contains(extension);

    final targetPath = await repository.uniqueMediaPath(
      project.id,
      p.basename(source.path),
    );
    final copied = await source.copy(targetPath);

    MediaProbeResult? info;
    try {
      info = await probe.probe(copied.path);
    } catch (_) {
      if (!isImage) {
        await copied.delete();
        throw MediaImportException(
          'This file could not be decoded. Supported inputs are MP4, MOV, '
          'MKV, WebM, MP3, M4A, WAV, AAC, JPG, PNG and WebP.',
        );
      }
    }

    final kind = isImage
        ? MediaKind.image
        : (info?.hasVideo ?? false)
        ? MediaKind.video
        : MediaKind.audio;
    if (kind == MediaKind.audio && !(info?.hasAudio ?? false)) {
      await copied.delete();
      throw MediaImportException('No audio or video stream was found.');
    }

    final durationUs = kind == MediaKind.image
        ? const Duration(seconds: 5).inMicroseconds
        : (info?.durationUs ?? 0);
    if (durationUs <= 0) {
      await copied.delete();
      throw MediaImportException('The media duration could not be read.');
    }

    final assetId = 'asset_${DateTime.now().microsecondsSinceEpoch}';
    final thumbs = repository.thumbDir(project.id);
    await thumbs.create(recursive: true);

    String? thumbnailPath;
    String? waveformPath;
    if (kind != MediaKind.audio) {
      thumbnailPath = await extraction.thumbnail(
        videoPath: copied.path,
        outputDir: thumbs,
        name: '$assetId.jpg',
        at: durationUs > 2000000
            ? const Duration(seconds: 1)
            : const Duration(milliseconds: 100),
      );
    } else {
      waveformPath = await extraction.waveform(
        audioPath: copied.path,
        outputDir: thumbs,
        name: '$assetId.png',
      );
    }

    final asset = MediaAsset(
      id: assetId,
      name: p.basename(source.path),
      path: copied.path,
      kind: kind,
      durationUs: durationUs,
      width: info?.width ?? 0,
      height: info?.height ?? 0,
      fps: info?.fps ?? 0,
      sizeBytes: size,
      hasAudio: info?.hasAudio ?? false,
      thumbnailPath: thumbnailPath,
      waveformPath: waveformPath,
    );
    project.media.add(asset);
    if (project.coverPath == null && thumbnailPath != null) {
      project.coverPath = thumbnailPath;
    }
    project.touch();
    return asset;
  }
}
