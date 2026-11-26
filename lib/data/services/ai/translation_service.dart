import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../../../core/utils/cancellation.dart';
import '../../models/local_model.dart';
import '../../models/subtitle.dart';
import '../models/model_library_service.dart';
import '../subtitle/srt_codec.dart';
import '../subtitle/subtitle_formats.dart';
import 'llama_runner.dart';

enum TranslationStage {
  validating,
  loadingModel,
  translating,
  completed,
  cancelled,
  failed,
}

class TranslationEvent {
  const TranslationEvent({
    required this.stage,
    this.progress = 0,
    this.completedBatches = 0,
    this.totalBatches = 0,
    this.preview,
    this.partialOutput,
    this.output,
    this.error,
    this.targetLanguage = 'Burmese',
  });

  final TranslationStage stage;
  final double progress;
  final int completedBatches;
  final int totalBatches;
  final String? preview;
  final String? partialOutput;
  final String? output;
  final String? error;
  final String targetLanguage;
}

class TranslationException implements Exception {
  TranslationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Prompt building, batching and response parsing. Pure functions so the
/// subtitle translation contract is testable without a model.
class TranslationPlanner {
  const TranslationPlanner._();

  static const String delimiter = '\n@@@\n';

  static List<int> translatableIndexes(List<SubtitleCue> cues) => <int>[
    for (var i = 0; i < cues.length; i++)
      if (cues[i].text.trim().isNotEmpty) i,
  ];

  static List<List<int>> batchCueIndexes(
    List<SubtitleCue> cues, {
    int maxChars = 900,
    int maxCues = 12,
  }) {
    final indexes = translatableIndexes(cues);
    return _batch(indexes, maxCues, (int i) => cues[i].text.length, maxChars);
  }

  static List<List<String>> batchParagraphs(
    List<String> paragraphs, {
    int maxChars = 1200,
    int maxSegments = 8,
  }) {
    final indexes = <int>[
      for (var i = 0; i < paragraphs.length; i++)
        if (paragraphs[i].trim().isNotEmpty) i,
    ];
    final batches = _batch(
      indexes,
      maxSegments,
      (int i) => paragraphs[i].length,
      maxChars,
    );
    return <List<String>>[
      for (final batch in batches)
        <String>[for (final i in batch) paragraphs[i]],
    ];
  }

  static List<List<int>> _batch(
    List<int> indexes,
    int maxItems,
    int Function(int) lengthOf,
    int maxChars,
  ) {
    final batches = <List<int>>[];
    var current = <int>[];
    var chars = 0;
    for (final index in indexes) {
      final length = lengthOf(index);
      final tooBig =
          current.isNotEmpty &&
          (current.length >= maxItems || chars + length > maxChars);
      if (tooBig) {
        batches.add(current);
        current = <int>[];
        chars = 0;
      }
      current.add(index);
      chars += length;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  /// Splits over-long text on sentence boundaries so one prompt never blows the
  /// model context.
  static List<String> splitLongText(String text, {int maxChars = 900}) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return <String>[trimmed];
    final parts = <String>[];
    final buffer = StringBuffer();
    for (final sentence in trimmed.split(RegExp(r'(?<=[။.!?])\s+'))) {
      if (buffer.length + sentence.length > maxChars && buffer.isNotEmpty) {
        parts.add(buffer.toString().trim());
        buffer.clear();
      }
      if (sentence.length > maxChars) {
        for (var start = 0; start < sentence.length; start += maxChars) {
          final end = (start + maxChars).clamp(0, sentence.length);
          parts.add(sentence.substring(start, end));
        }
        continue;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString().trim());
    return parts.where((String p) => p.isNotEmpty).toList();
  }

  static List<String> paragraphsOf(String text) => text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n{2,}'))
      .map((String p) => p.trim())
      .where((String p) => p.isNotEmpty)
      .toList();

  static bool usesHyMtTemplate(LocalModel model) =>
      model.repo.startsWith('tencent/Hy-MT3');

  static String buildPrompt({
    required List<String> segments,
    required String targetLanguage,
    required bool hyMtTemplate,
    String? context,
  }) {
    final body = segments.join(delimiter);
    final contextLine = (context == null || context.trim().isEmpty)
        ? ''
        : '\nContext for names and tone:\n${context.trim()}\n';
    if (hyMtTemplate) {
      return 'Please accurately translate the following text into '
          '$targetLanguage.\n'
          'You must retain the exact same number of delimiter lines '
          'containing @@@ in the translation. Strictly do not omit, escape, '
          'or translate these delimiter lines.$contextLine\n'
          '$body';
    }
    final numbered = <String>[
      for (var i = 0; i < segments.length; i++) '${i + 1}. ${segments[i]}',
    ].join('\n');
    return 'You are a professional subtitle translator. Translate every '
        'numbered segment into $targetLanguage (Myanmar script). Keep names, '
        'numbers and punctuation. Preserve one output line per segment in the '
        'form "1. translation". Do not add explanations or extra segments.'
        '$contextLine\n$numbered';
  }

  static String clean(String raw) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'^```[a-zA-Z]*\n?'), '');
    text = text.replaceAll(RegExp(r'\n?```$'), '');
    text = text.replaceFirst(
      RegExp(r'^(translation|burmese|myanmar)\s*:\s*', caseSensitive: false),
      '',
    );
    return text.trim();
  }

  static List<String> parseDelimited(String raw, int expected) {
    final cleaned = clean(raw);
    final parts = cleaned
        .split(RegExp(r'\n?@@@\n?'))
        .map((String p) => p.trim())
        .where((String p) => p.isNotEmpty)
        .toList();
    return parts.length == expected ? parts : const <String>[];
  }

  static List<String> parseNumbered(String raw, int expected) {
    final cleaned = clean(raw);
    final matches = RegExp(
      r'^\s*(\d{1,3})[.)]\s*(.+)$',
      multiLine: true,
    ).allMatches(cleaned).toList();
    if (matches.length == expected) {
      return <String>[for (final match in matches) match.group(2)!.trim()];
    }
    if (expected == 1) {
      final only = cleaned.replaceFirst(RegExp(r'^\s*1[.)]\s*'), '').trim();
      if (only.isNotEmpty) return <String>[only];
    }
    return const <String>[];
  }
}

/// Translates SRT/TXT only. Video, audio and image inputs are rejected before
/// any model work happens. There is no speech or TTS path in this service.
class SubtitleTranslationService {
  SubtitleTranslationService(this.runner);

  final LlamaRunner runner;

  Stream<TranslationEvent> run({
    required InstalledModel model,
    required String sourcePath,
    required String sourceText,
    String targetLanguage = 'Burmese',
    String? context,
    CancellationToken? token,
    int maxChars = 900,
  }) async* {
    yield TranslationEvent(
      stage: TranslationStage.validating,
      targetLanguage: targetLanguage,
    );
    if (!SubtitleFormats.isTranslationSource(sourcePath)) {
      yield TranslationEvent(
        stage: TranslationStage.failed,
        error:
            'Only .srt and .txt files can be translated. This file is '
            '${SubtitleFormats.extensionOf(sourcePath).isEmpty ? 'unknown' : '.${SubtitleFormats.extensionOf(sourcePath)}'}.',
        targetLanguage: targetLanguage,
      );
      return;
    }
    final isSrt = SubtitleFormats.extensionOf(sourcePath) == 'srt';
    try {
      yield TranslationEvent(
        stage: TranslationStage.loadingModel,
        targetLanguage: targetLanguage,
      );
      final hyMt = TranslationPlanner.usesHyMtTemplate(model.model);
      final params = hyMt
          ? const GenerationParams(
              maxTokens: 1536,
              temp: 0.7,
              topP: 0.6,
              topK: 20,
              penalty: 1.05,
            )
          : const GenerationParams(
              maxTokens: 1536,
              temp: 0.2,
              topP: 0.9,
              topK: 40,
              penalty: 1.05,
            );
      final contextSize = model.model.contextLength.clamp(2048, 8192);

      Future<List<String>> translateBatch(List<String> segments) async {
        final prompt = TranslationPlanner.buildPrompt(
          segments: segments,
          targetLanguage: targetLanguage,
          hyMtTemplate: hyMt,
          context: context,
        );
        var raw = await runner.generate(
          model: model,
          messages: <LlamaChatMessage>[
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
          ],
          params: params,
          contextSize: contextSize,
          token: token,
        );
        var parsed = hyMt
            ? TranslationPlanner.parseDelimited(raw, segments.length)
            : TranslationPlanner.parseNumbered(raw, segments.length);
        if (parsed.isEmpty) {
          // One stricter retry, then per-segment fallback.
          raw = await runner.generate(
            model: model,
            messages: <LlamaChatMessage>[
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
            ],
            params: params.copyWith(temp: 0.1),
            contextSize: contextSize,
            token: token,
          );
          parsed = hyMt
              ? TranslationPlanner.parseDelimited(raw, segments.length)
              : TranslationPlanner.parseNumbered(raw, segments.length);
        }
        if (parsed.isNotEmpty) return parsed;
        final singles = <String>[];
        for (final segment in segments) {
          final singlePrompt = TranslationPlanner.buildPrompt(
            segments: <String>[segment],
            targetLanguage: targetLanguage,
            hyMtTemplate: hyMt,
            context: context,
          );
          final single = await runner.generate(
            model: model,
            messages: <LlamaChatMessage>[
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: singlePrompt,
              ),
            ],
            params: params.copyWith(temp: 0.1),
            contextSize: contextSize,
            token: token,
          );
          final cleaned = TranslationPlanner.clean(single)
              .replaceFirst(RegExp(r'^\s*1[.)]\s*'), '')
              .trim();
          if (cleaned.isEmpty) {
            throw TranslationException(
              'The model returned an empty translation for: '
              '${segment.length > 80 ? '${segment.substring(0, 80)}…' : segment}',
            );
          }
          singles.add(cleaned);
        }
        return singles;
      }

      if (isSrt) {
        final cues = SrtCodec.decode(sourceText);
        if (cues.isEmpty) {
          throw TranslationException('No valid SRT cues were found.');
        }
        final batches = TranslationPlanner.batchCueIndexes(
          cues,
          maxChars: maxChars,
        );
        if (batches.isEmpty) {
          throw TranslationException(
            'Every cue is empty; nothing to translate.',
          );
        }
        final translated = <SubtitleCue>[...cues];
        var done = 0;
        for (final batch in batches) {
          if (token?.isCancelled ?? false) {
            yield TranslationEvent(
              stage: TranslationStage.cancelled,
              progress: done / batches.length,
              completedBatches: done,
              totalBatches: batches.length,
              partialOutput: SrtCodec.encode(translated),
              targetLanguage: targetLanguage,
            );
            return;
          }
          final segments = <String>[for (final i in batch) cues[i].text];
          final results = await translateBatch(segments);
          for (var i = 0; i < batch.length; i++) {
            final cue = cues[batch[i]];
            translated[batch[i]] = cue.copyWith(text: results[i]);
          }
          done++;
          yield TranslationEvent(
            stage: TranslationStage.translating,
            progress: done / batches.length,
            completedBatches: done,
            totalBatches: batches.length,
            preview: results.isEmpty ? null : results.last,
            partialOutput: SrtCodec.encode(translated),
            targetLanguage: targetLanguage,
          );
        }
        yield TranslationEvent(
          stage: TranslationStage.completed,
          progress: 1,
          completedBatches: batches.length,
          totalBatches: batches.length,
          output: SrtCodec.encode(translated),
          partialOutput: SrtCodec.encode(translated),
          targetLanguage: targetLanguage,
        );
        return;
      }

      final paragraphs = TranslationPlanner.paragraphsOf(sourceText);
      if (paragraphs.isEmpty) {
        throw TranslationException('The text file has no paragraphs.');
      }
      final expanded = <String>[
        for (final paragraph in paragraphs)
          ...TranslationPlanner.splitLongText(paragraph, maxChars: maxChars),
      ];
      final batches = TranslationPlanner.batchParagraphs(
        expanded,
        maxChars: maxChars,
      );
      final translated = <String>[...expanded];
      var index = 0;
      for (final batch in batches) {
        if (token?.isCancelled ?? false) {
          yield TranslationEvent(
            stage: TranslationStage.cancelled,
            progress: batches.isEmpty ? 0 : index / batches.length,
            completedBatches: index,
            totalBatches: batches.length,
            partialOutput: translated.join('\n\n'),
            targetLanguage: targetLanguage,
          );
          return;
        }
        final results = await translateBatch(batch);
        for (var i = 0; i < batch.length; i++) {
          translated[index + i] = results[i];
        }
        index += batch.length;
        yield TranslationEvent(
          stage: TranslationStage.translating,
          progress: index / translated.length,
          completedBatches: index,
          totalBatches: batches.length,
          preview: results.last,
          partialOutput: translated.join('\n\n'),
          targetLanguage: targetLanguage,
        );
      }
      yield TranslationEvent(
        stage: TranslationStage.completed,
        progress: 1,
        completedBatches: batches.length,
        totalBatches: batches.length,
        output: translated.join('\n\n'),
        partialOutput: translated.join('\n\n'),
        targetLanguage: targetLanguage,
      );
    } on TranslationException catch (error) {
      yield TranslationEvent(
        stage: TranslationStage.failed,
        error: error.message,
        targetLanguage: targetLanguage,
      );
    } on LlamaRunnerException catch (error) {
      yield TranslationEvent(
        stage: TranslationStage.failed,
        error: error.message,
        targetLanguage: targetLanguage,
      );
    } catch (error) {
      yield TranslationEvent(
        stage: TranslationStage.failed,
        error: 'Translation failed: $error',
        targetLanguage: targetLanguage,
      );
    }
  }
}
