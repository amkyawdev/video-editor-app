import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/cancellation.dart';
import '../../models/local_model.dart';
import '../../models/recap.dart';
import '../ffmpeg/media_extraction_service.dart';
import '../ffmpeg/media_probe_service.dart';
import '../models/model_library_service.dart';
import 'asr_service.dart';
import 'llama_runner.dart';
import 'recap_planner.dart';

enum RecapStage {
  preparing,
  probing,
  extractingAudio,
  samplingFrames,
  transcribing,
  captioning,
  scripting,
  completed,
  cancelled,
}

class RecapProgress {
  const RecapProgress({
    required this.stage,
    required this.fraction,
    required this.message,
  });

  final RecapStage stage;
  final double fraction;
  final String message;
}

class RecapCancelled implements Exception {
  @override
  String toString() => 'Recap cancelled.';
}

class RecapSettings {
  const RecapSettings({
    this.language = 'English',
    this.tone = 'neutral and factual',
    this.targetWords = 180,
    this.useVisionCaptions = true,
    this.useAsr = true,
    this.maxFrames = 18,
  });

  final String language;
  final String tone;
  final int targetWords;
  final bool useVisionCaptions;
  final bool useAsr;
  final int maxFrames;

  RecapSettings copyWith({
    String? language,
    String? tone,
    int? targetWords,
    bool? useVisionCaptions,
    bool? useAsr,
    int? maxFrames,
  }) => RecapSettings(
    language: language ?? this.language,
    tone: tone ?? this.tone,
    targetWords: targetWords ?? this.targetWords,
    useVisionCaptions: useVisionCaptions ?? this.useVisionCaptions,
    useAsr: useAsr ?? this.useAsr,
    maxFrames: maxFrames ?? this.maxFrames,
  );
}

class RecapRunResult {
  const RecapRunResult({
    required this.evidence,
    required this.script,
    this.analysisModelTitle,
    this.asrModelTitle,
  });

  final RecapEvidence evidence;
  final RecapScript script;
  final String? analysisModelTitle;
  final String? asrModelTitle;
}

/// Staged, evidence-first recap pipeline:
/// FFmpeg probe → audio extraction → scene frames → optional local ASR →
/// optional local vision captions → optional local script model.
///
/// A text-only model never receives pixels. When no analysis model is
/// installed the pipeline returns an evidence report, never a fake plot.
class MovieRecapService {
  MovieRecapService({
    required this.runner,
    required this.extraction,
    required this.probe,
    required this.asr,
  });

  final LlamaRunner runner;
  final MediaExtractionService extraction;
  final MediaProbeService probe;
  final AsrService asr;

  Future<RecapRunResult> run({
    required File video,
    required Directory workDir,
    required RecapSettings settings,
    InstalledModel? analysisModel,
    InstalledModel? asrModel,
    String? importedTranscript,
    String? importedTranscriptName,
    CancellationToken? token,
    void Function(RecapProgress progress)? onProgress,
  }) async {
    void report(RecapStage stage, double fraction, String message) {
      onProgress?.call(
        RecapProgress(stage: stage, fraction: fraction, message: message),
      );
    }

    void checkCancelled() {
      if (token?.isCancelled ?? false) throw RecapCancelled();
    }

    final warnings = <String>[];
    await workDir.create(recursive: true);
    report(RecapStage.preparing, 0.02, 'Preparing workspace');
    checkCancelled();

    report(RecapStage.probing, 0.05, 'Reading video metadata');
    final info = await probe.probe(video.path);
    if (!info.hasVideo) {
      throw RecapException('This file has no video track to recap.');
    }
    checkCancelled();

    report(RecapStage.extractingAudio, 0.12, 'Extracting 16 kHz audio');
    final wavPath = await extraction.extractAudioWav(
      videoPath: video.path,
      outputDir: workDir,
    );
    AudioAnalysis? audio;
    if (wavPath != null) {
      audio = await extraction.analyzeLoudness(wavPath);
    } else {
      warnings.add('No audio track could be extracted; the recap is silent.');
    }
    checkCancelled();

    report(RecapStage.samplingFrames, 0.25, 'Sampling scene frames');
    final frames = await extraction.extractScenes(
      videoPath: video.path,
      outputDir: Directory(p.join(workDir.path, 'frames')),
      maxFrames: settings.maxFrames,
    );
    if (frames.isEmpty) {
      warnings.add('No frames could be sampled from this video.');
    }
    checkCancelled();

    String? transcript = importedTranscript?.trim();
    String? transcriptLanguage;
    String? asrTitle;
    if (settings.useAsr && asrModel != null && wavPath != null) {
      report(RecapStage.transcribing, 0.42, 'Transcribing audio locally');
      try {
        final result = await asr.transcribe(
          model: asrModel,
          wavPath: wavPath,
          token: token,
        );
        transcript = result.text;
        transcriptLanguage = result.language;
        asrTitle = asrModel.model.title;
      } on AsrException catch (error) {
        warnings.add('Local ASR failed: ${error.message}');
      }
    } else if (settings.useAsr && asrModel == null) {
      warnings.add(
        'No local ASR model is installed, so audio was not transcribed. '
        'Install Qwen3-ASR in the model library, or attach an SRT/TXT '
        'transcript.',
      );
    }
    if (transcript != null &&
        transcript.trim().isNotEmpty &&
        importedTranscriptName != null) {
      transcriptLanguage ??= 'imported ($importedTranscriptName)';
    }
    checkCancelled();

    final canSee =
        analysisModel != null &&
        analysisModel.model.capabilities.contains(ModelCapability.vision) &&
        analysisModel.projectorPath != null &&
        settings.useVisionCaptions;
    var scenes = <RecapScene>[
      for (final frame in frames)
        RecapScene(timeUs: frame.timeUs, caption: '', path: frame.path),
    ];

    if (analysisModel != null &&
        analysisModel.model.capabilities.contains(ModelCapability.vision) &&
        analysisModel.projectorPath == null) {
      warnings.add(
        'The selected vision model is missing its projector file, so frames '
        'were not captioned.',
      );
    }

    if (canSee && scenes.isNotEmpty) {
      final captionBudget = frames.take(10).toList();
      for (var i = 0; i < captionBudget.length; i++) {
        checkCancelled();
        report(
          RecapStage.captioning,
          0.45 + 0.3 * (i + 1) / captionBudget.length,
          'Captioning frame ${i + 1} of ${captionBudget.length}',
        );
        try {
          final caption = await runner.generate(
            model: analysisModel,
            messages: <LlamaChatMessage>[
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: <LlamaContentPart>[
                  LlamaImageContent(path: captionBudget[i].path),
                  LlamaTextContent(RecapPlanner.captionPrompt()),
                ],
              ),
            ],
            params: const GenerationParams(
              maxTokens: 160,
              temp: 0.2,
              topP: 0.9,
            ),
            allowVision: true,
            contextSize: 4096,
            token: token,
          );
          final targetIndex = scenes.indexWhere(
            (RecapScene s) => s.timeUs == captionBudget[i].timeUs,
          );
          if (targetIndex >= 0) {
            scenes[targetIndex] = RecapScene(
              timeUs: scenes[targetIndex].timeUs,
              caption: caption,
              path: scenes[targetIndex].path,
              isModelCaption: true,
            );
          }
        } catch (error) {
          warnings.add(
            'Frame at ${captionBudget[i].timeUs ~/ 1000000}s was not '
            'captioned: $error',
          );
        }
      }
    } else if (analysisModel != null && !canSee) {
      warnings.add(
        'The selected model is text-only: it never sees the video frames. '
        'Captions require the Qwen2.5-VL entry with its mmproj file.',
      );
    }

    final evidence = RecapEvidence(
      videoName: p.basename(video.path),
      durationUs: info.durationUs,
      width: info.width,
      height: info.height,
      scenes: scenes,
      transcript: transcript,
      transcriptLanguage: transcriptLanguage,
      meanVolumeDb: audio?.meanVolumeDb,
      maxVolumeDb: audio?.maxVolumeDb,
      asrModelTitle: asrTitle,
      usedVisionModel: canSee,
    );

    checkCancelled();
    report(RecapStage.scripting, 0.8, 'Writing recap from evidence');

    final hasEvidence = evidence.hasTranscript || evidence.hasCaptions;
    if (analysisModel == null) {
      warnings.add(
        'No analysis model is installed. This is an evidence report, not a '
        'plot summary.',
      );
      return RecapRunResult(
        evidence: evidence,
        script: RecapPlanner.evidenceReport(
          evidence: evidence,
          language: settings.language,
          warnings: warnings,
        ),
      );
    }
    if (!hasEvidence) {
      warnings.add(
        'There is no transcript and no vision caption, so a plot recap would '
        'have to be invented. The app returned the extracted evidence instead.',
      );
      return RecapRunResult(
        evidence: evidence,
        script: RecapPlanner.evidenceReport(
          evidence: evidence,
          language: settings.language,
          warnings: warnings,
        ),
        analysisModelTitle: analysisModel.model.title,
      );
    }

    final raw = await runner.generate(
      model: analysisModel,
      messages: <LlamaChatMessage>[
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text:
              'You are a careful recap writer. You must not invent facts '
              'that are absent from the evidence.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: RecapPlanner.scriptPrompt(
            evidence: evidence,
            language: settings.language,
            tone: settings.tone,
            targetWords: settings.targetWords,
            maxTranscriptChars: 9000,
          ),
        ),
      ],
      params: GenerationParams(
        maxTokens: (settings.targetWords * 3).clamp(512, 4096),
        temp: 0.4,
        topP: 0.9,
      ),
      allowVision: canSee,
      contextSize: 8192,
      token: token,
    );
    if (token?.isCancelled ?? false) throw RecapCancelled();

    report(RecapStage.completed, 1, 'Recap ready');
    return RecapRunResult(
      evidence: evidence,
      script: RecapPlanner.parseScript(
        raw: raw,
        evidence: evidence,
        language: settings.language,
        warnings: warnings,
      ),
      analysisModelTitle: analysisModel.model.title,
      asrModelTitle: asrTitle,
    );
  }
}

class RecapException implements Exception {
  RecapException(this.message);

  final String message;

  @override
  String toString() => message;
}
