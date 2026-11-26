import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/local_model.dart';
import 'gguf_inspector.dart';
import 'model_catalog.dart';

class ModelLibraryException implements Exception {
  ModelLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ModelDownloadCancelled implements Exception {
  @override
  String toString() => 'Model download cancelled.';
}

class ModelDownloadToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.modelId,
    required this.fileName,
    required this.fileIndex,
    required this.fileCount,
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final String modelId;
  final String fileName;
  final int fileIndex;
  final int fileCount;
  final int receivedBytes;
  final int totalBytes;
  final int bytesPerSecond;

  double get fraction =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);

  String get receivedLabel => LocalModelFile.formatBytes(receivedBytes);
  String get totalLabel => LocalModelFile.formatBytes(totalBytes);
  String get speedLabel => '${LocalModelFile.formatBytes(bytesPerSecond)}/s';
}

class InstalledModel {
  const InstalledModel({
    required this.model,
    required this.weightsPath,
    this.projectorPath,
    this.info,
  });

  final LocalModel model;
  final String weightsPath;
  final String? projectorPath;
  final GgufInfo? info;

  bool get isComplete =>
      model.needsProjector ? projectorPath != null : weightsPath.isNotEmpty;
}

/// Downloads, verifies, stores and deletes GGUF files. Resumable via Range
/// requests; integrity is size + GGUF header because the catalog does not have
/// a published per-file SHA-256 from Hugging Face.
class ModelLibraryService {
  ModelLibraryService(this.root);

  final Directory root;

  Directory modelDir(LocalModel model) =>
      Directory(p.join(root.path, model.id));

  File targetFile(LocalModel model, LocalModelFile file) =>
      File(p.join(modelDir(model).path, p.basename(file.fileName)));

  Future<InstalledModel?> installed(LocalModel model) async {
    final weights = model.weights;
    final projector = model.projector;
    if (weights == null) return null;
    final weightsFile = targetFile(model, weights);
    if (!await weightsFile.exists()) return null;
    File? projectorFile;
    if (projector != null) {
      projectorFile = targetFile(model, projector);
      if (!await projectorFile.exists()) return null;
    }
    GgufInfo? info;
    try {
      info = await GgufInspector.inspect(weightsFile);
    } catch (_) {
      info = null;
    }
    return InstalledModel(
      model: model,
      weightsPath: weightsFile.path,
      projectorPath: projectorFile?.path,
      info: info,
    );
  }

  Future<List<InstalledModel>> installedModels() async {
    final result = <InstalledModel>[];
    for (final model in ModelCatalog.all) {
      final item = await installed(model);
      if (item != null) result.add(item);
    }
    return result;
  }

  Future<Map<String, InstalledModel>> installedById() async {
    final list = await installedModels();
    return <String, InstalledModel>{
      for (final item in list) item.model.id: item,
    };
  }

  /// Best-effort free space probe. Returns null when `df` is unavailable.
  Future<int?> availableBytes(Directory dir) async {
    try {
      await dir.create(recursive: true);
      final result = await Process.run('df', <String>['-k', dir.path]);
      if (result.exitCode != 0) return null;
      final lines = '${result.stdout}'.trim().split('\n');
      if (lines.length < 2) return null;
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return null;
      final kb = int.tryParse(parts[3]);
      return kb == null ? null : kb * 1024;
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureSpace(LocalModel model, Directory dir) async {
    final free = await availableBytes(dir);
    if (free == null) return;
    final needed = (model.totalBytes * 1.15).round() + 50 * 1024 * 1024;
    if (free < needed) {
      throw ModelLibraryException(
        'Not enough storage: ${LocalModelFile.formatBytes(needed)} needed, '
        '${LocalModelFile.formatBytes(free)} free.',
      );
    }
  }

  Stream<ModelDownloadProgress> download(
    LocalModel model, {
    ModelDownloadToken? token,
  }) async* {
    if (!model.downloadable) {
      throw ModelLibraryException(
        '${model.title} is a PC/server model and is not downloadable on a phone.',
      );
    }
    final dir = modelDir(model);
    await dir.create(recursive: true);
    await ensureSpace(model, dir);

    final totalBytes = model.totalBytes;
    var completedBytes = 0;
    for (var index = 0; index < model.files.length; index++) {
      final file = model.files[index];
      final target = targetFile(model, file);
      yield* _downloadFile(
        model: model,
        file: file,
        target: target,
        token: token,
        index: index,
        completedBefore: completedBytes,
        totalBytes: totalBytes,
      );
      completedBytes += file.sizeBytes;
    }
  }

  Stream<ModelDownloadProgress> _downloadFile({
    required LocalModel model,
    required LocalModelFile file,
    required File target,
    required ModelDownloadToken? token,
    required int index,
    required int completedBefore,
    required int totalBytes,
  }) async* {
    final partial = File('${target.path}.part');
    var already = await partial.exists() ? await partial.length() : 0;
    if (already > file.sizeBytes) {
      await partial.writeAsBytes(const <int>[]);
      already = 0;
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse(model.downloadUrl(file));
      final request = await client.getUrl(uri);
      if (already > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$already-');
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw ModelLibraryException(
          'Download failed with HTTP ${response.statusCode}. '
          'Open ${model.modelPageUrl} in a browser to check access.',
        );
      }
      if (response.statusCode == HttpStatus.ok && already > 0) {
        already = 0;
      }
      final sink = partial.openWrite(
        mode: already > 0 ? FileMode.append : FileMode.write,
      );
      var written = already;
      var lastTick = DateTime.now();
      var lastBytes = written;
      try {
        await for (final chunk in response) {
          if (token?.isCancelled ?? false) {
            throw ModelDownloadCancelled();
          }
          sink.add(chunk);
          written += chunk.length;
          final now = DateTime.now();
          final elapsed = now.difference(lastTick).inMilliseconds;
          if (elapsed >= 250) {
            final speed = ((written - lastBytes) * 1000 / elapsed).round();
            yield ModelDownloadProgress(
              modelId: model.id,
              fileName: file.fileName,
              fileIndex: index,
              fileCount: model.files.length,
              receivedBytes: completedBefore + written,
              totalBytes: totalBytes,
              bytesPerSecond: speed,
            );
            lastTick = now;
            lastBytes = written;
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (file.sizeBytes > 0 && written != file.sizeBytes) {
        throw ModelLibraryException(
          'Size mismatch for ${file.fileName}: expected '
          '${file.sizeBytes} bytes, received $written. The partial file was '
          'kept, so the download can resume.',
        );
      }

      final info = await GgufInspector.inspect(partial);
      if (info.tensorCount <= 0) {
        await partial.delete();
        throw ModelLibraryException(
          '${file.fileName} has no tensors and was rejected.',
        );
      }
      await partial.rename(target.path);
      yield ModelDownloadProgress(
        modelId: model.id,
        fileName: file.fileName,
        fileIndex: index,
        fileCount: model.files.length,
        receivedBytes: completedBefore + written,
        totalBytes: totalBytes,
        bytesPerSecond: 0,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> delete(LocalModel model) async {
    final dir = modelDir(model);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<int> installedBytes() async {
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
