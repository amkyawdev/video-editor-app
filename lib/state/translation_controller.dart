import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/utils/cancellation.dart';
import '../data/models/subtitle.dart';
import '../data/services/ai/translation_service.dart';
import '../data/services/models/model_library_service.dart';
import '../data/services/subtitle/srt_codec.dart';
import '../data/services/subtitle/subtitle_formats.dart';
import 'app_services.dart';
import 'editor_controller.dart';

enum TranslationStatus { idle, running, completed, cancelled, failed }

class TranslationController extends ChangeNotifier {
  TranslationController(this.services);

  final AppServices services;
  TranslationStatus status = TranslationStatus.idle;
  TranslationStage stage = TranslationStage.validating;
  double progress = 0;
  int completedBatches = 0;
  int totalBatches = 0;
  String? preview;
  String? output;
  String? partialOutput;
  String? error;
  String? sourceName;
  String? sourcePath;
  String? sourceContent;
  String targetLanguage = 'Burmese';
  String? context;
  List<SubtitleCue> reviewedCues = <SubtitleCue>[];
  String? savedPath;

  CancellationToken? _token;
  StreamSubscription<TranslationEvent>? _subscription;

  bool get isRunning => status == TranslationStatus.running;

  bool get isSrt =>
      sourcePath != null && SubtitleFormats.extensionOf(sourcePath!) == 'srt';

  String get effectiveOutput {
    if (reviewedCues.isNotEmpty && isSrt) {
      return SrtCodec.encode(reviewedCues);
    }
    return output ?? partialOutput ?? '';
  }

  void setSource({
    required String name,
    required String path,
    required String content,
  }) {
    sourceName = name;
    sourcePath = path;
    sourceContent = content;
    output = null;
    partialOutput = null;
    error = null;
    reviewedCues = <SubtitleCue>[];
    status = TranslationStatus.idle;
    notifyListeners();
  }

  Future<void> start(InstalledModel model) async {
    final content = sourceContent;
    final path = sourcePath;
    if (content == null || path == null) {
      error = 'Choose an SRT or TXT file first.';
      status = TranslationStatus.failed;
      notifyListeners();
      return;
    }
    await _subscription?.cancel();
    _token = CancellationToken();
    status = TranslationStatus.running;
    stage = TranslationStage.validating;
    progress = 0;
    error = null;
    savedPath = null;
    reviewedCues = <SubtitleCue>[];
    notifyListeners();

    final completer = Completer<void>();
    _subscription = services.translation
        .run(
          model: model,
          sourcePath: path,
          sourceText: content,
          targetLanguage: targetLanguage,
          context: context,
          token: _token,
        )
        .listen(
          (TranslationEvent event) {
            stage = event.stage;
            progress = event.progress;
            completedBatches = event.completedBatches;
            totalBatches = event.totalBatches;
            preview = event.preview ?? preview;
            partialOutput = event.partialOutput ?? partialOutput;
            switch (event.stage) {
              case TranslationStage.completed:
                status = TranslationStatus.completed;
                output = event.output;
                final generated = event.output;
                if (generated != null && isSrt) {
                  reviewedCues = SrtCodec.decode(generated);
                }
              case TranslationStage.cancelled:
                status = TranslationStatus.cancelled;
              case TranslationStage.failed:
                status = TranslationStatus.failed;
                error = event.error;
              case TranslationStage.validating:
              case TranslationStage.loadingModel:
              case TranslationStage.translating:
                break;
            }
            notifyListeners();
          },
          onError: (Object e) {
            status = TranslationStatus.failed;
            error = 'Translation failed: $e';
            notifyListeners();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );
    await completer.future;
  }

  void setTargetLanguage(String language) {
    targetLanguage = language;
    notifyListeners();
  }

  void setContext(String value) {
    context = value;
    notifyListeners();
  }

  void cancel() => _token?.cancel();

  void updateReviewedCue(int index, String text) {
    if (index < 0 || index >= reviewedCues.length) return;
    reviewedCues[index] = reviewedCues[index].copyWith(text: text);
    notifyListeners();
  }

  Future<String> saveResult() async {
    final content = effectiveOutput;
    if (content.trim().isEmpty) {
      throw StateError('There is no translated text to save yet.');
    }
    final base = p.basenameWithoutExtension(sourceName ?? 'subtitle');
    final extension = isSrt ? 'srt' : 'txt';
    final file = File(
      p.join(
        services.repository.exportsRoot.path,
        'translations',
        '${base}_my.$extension',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    savedPath = file.path;
    notifyListeners();
    return file.path;
  }

  /// Applies a translated SRT to the open project. The user confirms this in the
  /// UI; timings and cue count must match what was translated.
  String applyToEditor(EditorController editor) {
    if (!isSrt || reviewedCues.isEmpty) {
      return 'Only translated SRT files can be applied to the subtitle track.';
    }
    final document = SubtitleDocument(
      cues: reviewedCues,
      style: editor.project.subtitles.style,
      sourceName: sourceName,
      language: 'my',
    );
    editor.replaceSubtitleDocument(document, sourceName: sourceName);
    return 'Applied ${reviewedCues.length} translated cues to the project.';
  }

  @override
  void dispose() {
    _token?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
