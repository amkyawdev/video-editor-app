import 'package:llamadart/llamadart.dart';

import '../../../core/utils/cancellation.dart';
import '../models/model_library_service.dart';

class AsrException implements Exception {
  AsrException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AsrTranscription {
  const AsrTranscription({required this.text, this.language});

  final String text;
  final String? language;
}

/// Runs Qwen3-ASR locally through llamadart's speech-to-text engine. The model
/// and its audio projector are GGUF files installed from the model library.
class AsrService {
  const AsrService();

  Future<AsrTranscription> transcribe({
    required InstalledModel model,
    required String wavPath,
    CancellationToken? token,
  }) async {
    if (token?.isCancelled ?? false) {
      throw AsrException('Transcription cancelled.');
    }
    if (model.projectorPath == null) {
      throw AsrException(
        'The ASR model is missing its audio projector (mmproj) file. '
        'Reinstall ${model.model.title}.',
      );
    }
    final engine = await SpeechToTextEngine.load(
      SpeechToTextModel(
        ModelSource.path(model.weightsPath),
        projector: ModelSource.path(model.projectorPath!),
        adapter: const Qwen3AsrAdapter(),
      ),
      params: const ModelParams(contextSize: 4096),
    );
    try {
      final result = await engine.transcribeOnce(
        SpeechToTextRequest(
          audio: SpeechAudioFileInput(wavPath),
          maxOutputTokens: 4096,
        ),
      );
      if (token?.isCancelled ?? false) {
        throw AsrException('Transcription cancelled.');
      }
      final text = result.text.trim();
      if (text.isEmpty) {
        throw AsrException(
          'The ASR model returned no words. The audio may be music-only, or '
          'the spoken language may not be one of the 30 supported languages.',
        );
      }
      return AsrTranscription(text: text, language: result.language);
    } finally {
      await engine.dispose();
    }
  }
}
