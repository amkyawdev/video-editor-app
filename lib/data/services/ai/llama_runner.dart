import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../../../core/utils/cancellation.dart';
import '../models/model_library_service.dart';

class LlamaRunnerException implements Exception {
  LlamaRunnerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Owns one llama.cpp engine at a time. Loading is expensive (hundreds of MB
/// to GBs), so the app keeps the engine resident until another model is asked
/// for. Jobs are serialised: translation and recap never share a KV cache.
class LlamaRunner {
  LlamaEngine? _engine;
  String? _engineKey;
  Future<void> _tail = Future<void>.value();
  bool _busy = false;

  bool get isBusy => _busy;

  String? get loadedKey => _engineKey;

  Future<LlamaEngine> ensureLoaded(
    InstalledModel model, {
    int? contextSize,
    bool allowVision = false,
  }) async {
    final key =
        '${model.model.id}|${model.weightsPath}|'
        '${model.projectorPath ?? ''}|${contextSize ?? 0}|$allowVision';
    final existing = _engine;
    if (existing != null && _engineKey == key) return existing;

    await dispose();
    final projectorPath = allowVision ? model.projectorPath : null;
    final engine = await LlamaEngine.load(
      LlamaModel(
        ModelSource.path(model.weightsPath),
        projector: projectorPath == null
            ? null
            : ModelSource.path(projectorPath),
      ),
      params: ModelParams(
        contextSize: contextSize ?? 4096,
        gpuLayers: ModelParams.maxGpuLayers,
      ),
    );
    _engine = engine;
    _engineKey = key;
    return engine;
  }

  /// Serialises model jobs so two pipelines never share one KV cache.
  Future<T> exclusive<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    await previous;
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
      completer.complete();
    }
  }

  Future<String> generate({
    required InstalledModel model,
    required List<LlamaChatMessage> messages,
    GenerationParams params = const GenerationParams(),
    bool allowVision = false,
    int? contextSize,
    CancellationToken? token,
    void Function(String soFar)? onToken,
  }) async {
    final engine = await ensureLoaded(
      model,
      contextSize: contextSize,
      allowVision: allowVision,
    );
    final buffer = StringBuffer();
    await for (final chunk in engine.create(messages, params: params)) {
      if (token?.isCancelled ?? false) break;
      final piece = chunk.text;
      if (piece.isEmpty) continue;
      buffer.write(piece);
      onToken?.call(buffer.toString());
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw LlamaRunnerException(
        'The model produced no text. Try a larger token budget or a different '
        'model.',
      );
    }
    return text;
  }

  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _engineKey = null;
    if (engine != null) {
      await engine.dispose();
    }
  }
}
