import '../../../core/utils/time_utils.dart';
import '../../models/recap.dart';

class RecapPlanner {
  const RecapPlanner._();

  static String captionPrompt() =>
      'Describe what is visible in this single video frame in 1-2 factual '
      'sentences. Mention the setting, people or objects, and any visible '
      'action. Do not infer plot, character names, dialogue, or anything '
      'off-screen. If the frame is unclear, say so.';

  static String scriptPrompt({
    required RecapEvidence evidence,
    required String language,
    required String tone,
    required int targetWords,
    required int maxTranscriptChars,
  }) {
    final buffer = StringBuffer()
      ..writeln('You are writing a factual recap of a video from evidence.')
      ..writeln('Hard rules:')
      ..writeln(
        '- Use ONLY the evidence below. Never invent plot, characters, '
        'dialogue, or scenes.',
      )
      ..writeln('- If the evidence is thin or contradictory, say so plainly.')
      ..writeln(
        '- Write in $language. Tone: $tone. '
        'Aim for about $targetWords words.',
      )
      ..writeln('- Output exactly three sections: TITLE, LOGLINE, RECAP.')
      ..writeln()
      ..writeln('Evidence:')
      ..writeln('- File: ${evidence.videoName}')
      ..writeln(
        '- Runtime: ${TimeUtils.timecode(Duration(microseconds: evidence.durationUs))}',
      )
      ..writeln('- Resolution: ${evidence.width}x${evidence.height}');
    if (evidence.meanVolumeDb != null) {
      buffer.writeln(
        '- Mean audio level: ${evidence.meanVolumeDb!.toStringAsFixed(1)} dB '
        '(peak ${evidence.maxVolumeDb?.toStringAsFixed(1) ?? '?'} dB)',
      );
    }
    if (evidence.scenes.isNotEmpty) {
      buffer.writeln('- Sampled frames (FFmpeg scene detection / interval):');
      for (final scene in evidence.scenes.take(24)) {
        final caption = scene.caption.trim().isEmpty
            ? '(frame sampled, no caption)'
            : scene.caption.trim();
        buffer.writeln('  • ${TimeUtils.timecode(scene.time)} — $caption');
      }
    }
    final transcript = evidence.transcript?.trim();
    if (transcript != null && transcript.isNotEmpty) {
      final clipped = transcript.length > maxTranscriptChars
          ? '${transcript.substring(0, maxTranscriptChars)}\n[transcript truncated]'
          : transcript;
      buffer
        ..writeln()
        ..writeln(
          'Transcript evidence'
          '${evidence.transcriptLanguage != null ? ' (language: ${evidence.transcriptLanguage})' : ''}:',
        )
        ..writeln(clipped);
    } else {
      buffer.writeln('- Transcript: none. Do not invent dialogue or audio.');
    }
    return buffer.toString().trimRight();
  }

  static String frameCaptionMessage(RecapEvidence evidence) =>
      'Evidence summary for the recap: ${evidence.scenes.length} sampled '
      'frames over ${TimeUtils.timecode(Duration(microseconds: evidence.durationUs))}.';

  /// Parses TITLE / LOGLINE / RECAP. Unknown output becomes the body with the
  /// file name as title; nothing is invented.
  static RecapScript parseScript({
    required String raw,
    required RecapEvidence evidence,
    required String language,
    required List<String> warnings,
  }) {
    final cleaned = raw.trim();
    final titleMatch = RegExp(
      r'^\s*TITLE\s*:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(cleaned);
    final loglineMatch = RegExp(
      r'^\s*LOGLINE\s*:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(cleaned);
    final recapIndex = cleaned.indexOf(
      RegExp(r'RECAP\s*:', caseSensitive: false),
    );
    var body = cleaned;
    if (recapIndex >= 0) {
      body = cleaned
          .substring(recapIndex)
          .replaceFirst(RegExp(r'RECAP\s*:\s*', caseSensitive: false), '');
    } else {
      body = cleaned
          .replaceAll(
            RegExp(r'^\s*TITLE\s*:.*$', multiLine: true, caseSensitive: false),
            '',
          )
          .replaceAll(
            RegExp(
              r'^\s*LOGLINE\s*:.*$',
              multiLine: true,
              caseSensitive: false,
            ),
            '',
          );
    }
    return RecapScript(
      title: titleMatch?.group(1)?.trim().isNotEmpty == true
          ? titleMatch!.group(1)!.trim()
          : evidence.videoName,
      logline: loglineMatch?.group(1)?.trim() ?? '',
      body: body.trim(),
      language: language,
      isNarrative: true,
      warnings: warnings,
      createdAt: DateTime.now(),
    );
  }

  /// Honest fallback: no narrative model ran, so the app reports the evidence
  /// it actually extracted instead of pretending to understand the movie.
  static RecapScript evidenceReport({
    required RecapEvidence evidence,
    required String language,
    required List<String> warnings,
  }) {
    final buffer = StringBuffer()
      ..writeln('No AI narrative was generated from this video.')
      ..writeln()
      ..writeln(
        'Runtime ${TimeUtils.timecode(Duration(microseconds: evidence.durationUs))} · '
        '${evidence.width}x${evidence.height} · '
        '${evidence.scenes.length} sampled frames.',
      );
    if (evidence.meanVolumeDb != null) {
      buffer.writeln(
        'Audio level: mean ${evidence.meanVolumeDb!.toStringAsFixed(1)} dB, '
        'peak ${evidence.maxVolumeDb?.toStringAsFixed(1) ?? '?'} dB.',
      );
    }
    if (evidence.scenes.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Extracted scene evidence:')
        ..writeln(RecapScriptBuilder.sceneTable(evidence));
    }
    if (evidence.hasTranscript) {
      buffer
        ..writeln()
        ..writeln('Transcript excerpt:')
        ..writeln(
          evidence.transcript!.length > 1200
              ? '${evidence.transcript!.substring(0, 1200)}…'
              : evidence.transcript!,
        );
    }
    return RecapScript(
      title: evidence.videoName,
      logline: 'Evidence report only — no plot summary was generated.',
      body: buffer.toString().trimRight(),
      language: language,
      isNarrative: false,
      warnings: warnings,
      createdAt: DateTime.now(),
    );
  }
}
