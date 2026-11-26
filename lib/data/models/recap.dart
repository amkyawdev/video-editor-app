import 'dart:math' as math;

import '../../core/utils/time_utils.dart';
import 'subtitle.dart';

class RecapScene {
  const RecapScene({
    required this.timeUs,
    required this.caption,
    this.path,
    this.isModelCaption = false,
  });

  final int timeUs;
  final String caption;
  final String? path;
  final bool isModelCaption;

  Duration get time => Duration(microseconds: timeUs);
}

class RecapEvidence {
  const RecapEvidence({
    required this.videoName,
    required this.durationUs,
    required this.width,
    required this.height,
    required this.scenes,
    this.transcript,
    this.transcriptLanguage,
    this.meanVolumeDb,
    this.maxVolumeDb,
    this.asrModelTitle,
    this.usedVisionModel = false,
  });

  final String videoName;
  final int durationUs;
  final int width;
  final int height;
  final List<RecapScene> scenes;
  final String? transcript;
  final String? transcriptLanguage;
  final double? meanVolumeDb;
  final double? maxVolumeDb;
  final String? asrModelTitle;
  final bool usedVisionModel;

  bool get hasTranscript => transcript != null && transcript!.trim().isNotEmpty;

  bool get hasCaptions =>
      scenes.any((RecapScene scene) => scene.caption.trim().isNotEmpty);
}

class RecapScript {
  const RecapScript({
    required this.title,
    required this.logline,
    required this.body,
    required this.language,
    required this.isNarrative,
    required this.warnings,
    this.createdAt,
  });

  final String title;
  final String logline;
  final String body;
  final String language;
  final bool isNarrative;
  final List<String> warnings;
  final DateTime? createdAt;

  String get plainText {
    final buffer = StringBuffer();
    if (title.trim().isNotEmpty) buffer.writeln('# $title');
    if (logline.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(logline.trim());
    }
    if (body.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(body.trim());
    }
    return buffer.toString().trimRight();
  }

  /// Distributes script sentences over the video runtime. Technical evidence
  /// reports are not exported as subtitles.
  String toSrt(int durationUs) {
    if (!isNarrative || body.trim().isEmpty) return '';
    final cues = RecapScriptBuilder.distributeAsCues(
      body,
      durationUs: durationUs,
    );
    return SubtitleDocumentCodec.encodeSrt(cues);
  }

  RecapScript copyWith({
    String? title,
    String? logline,
    String? body,
    String? language,
    bool? isNarrative,
    List<String>? warnings,
  }) => RecapScript(
    title: title ?? this.title,
    logline: logline ?? this.logline,
    body: body ?? this.body,
    language: language ?? this.language,
    isNarrative: isNarrative ?? this.isNarrative,
    warnings: warnings ?? this.warnings,
    createdAt: createdAt ?? DateTime.now(),
  );
}

/// Sentence splitting and SRT distribution are pure so they can be tested
/// without a device.
class RecapScriptBuilder {
  const RecapScriptBuilder._();

  static const List<String> _burmeseBreaks = <String>['။', '၊'];

  static List<String> sentences(String body) {
    final normalized = body.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const <String>[];
    final result = <String>[];
    for (final line in normalized.split('\n')) {
      final paragraph = line.trim();
      if (paragraph.isEmpty) continue;
      var start = 0;
      for (var i = 0; i < paragraph.length; i++) {
        final char = paragraph[i];
        final isBreak =
            char == '.' ||
            char == '!' ||
            char == '?' ||
            _burmeseBreaks.contains(char);
        if (!isBreak) continue;
        final next = i + 1;
        final atEnd = next >= paragraph.length;
        final spaceAfter = !atEnd && paragraph[next] == ' ';
        if (atEnd || spaceAfter) {
          final piece = paragraph.substring(start, next).trim();
          if (piece.isNotEmpty) result.add(piece);
          start = next;
        }
      }
      if (start < paragraph.length) {
        final tail = paragraph.substring(start).trim();
        if (tail.isNotEmpty) result.add(tail);
      }
    }
    return result;
  }

  static List<SubtitleCue> distributeAsCues(
    String body, {
    required int durationUs,
    int minCueUs = 1800000,
    int maxCues = 60,
  }) {
    final parts = sentences(body);
    if (parts.isEmpty || durationUs <= 0) return const <SubtitleCue>[];
    final chunks = <String>[];
    var buffer = StringBuffer();
    for (final part in parts) {
      if (buffer.isNotEmpty && buffer.length + part.length > 120) {
        chunks.add(buffer.toString().trim());
        buffer = StringBuffer();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(part);
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    final limited = chunks.take(maxCues).toList();
    final perCue = math.max(
      minCueUs,
      (durationUs / math.max(limited.length, 1)).floor(),
    );
    final cues = <SubtitleCue>[];
    var cursor = 0;
    for (final chunk in limited) {
      if (cursor >= durationUs) break;
      final end = math.min(cursor + perCue, durationUs);
      if (end - cursor < 300000) break;
      cues.add(
        SubtitleCue(
          id: 'recap_${cues.length}',
          startUs: cursor,
          endUs: end,
          text: chunk,
        ),
      );
      cursor = end;
    }
    return cues;
  }

  static String sceneTable(RecapEvidence evidence) {
    final buffer = StringBuffer();
    for (final scene in evidence.scenes) {
      buffer.writeln(
        '${TimeUtils.timecode(scene.time)} — '
        '${scene.caption.trim().isEmpty ? '(frame sample)' : scene.caption.trim()}',
      );
    }
    return buffer.toString().trimRight();
  }
}

class SubtitleDocumentCodec {
  const SubtitleDocumentCodec._();

  static String encodeSrt(List<SubtitleCue> cues) {
    final buffer = StringBuffer();
    for (var i = 0; i < cues.length; i++) {
      buffer
        ..writeln(i + 1)
        ..writeln(
          '${TimeUtils.srtTimestamp(cues[i].start)} --> '
          '${TimeUtils.srtTimestamp(cues[i].end)}',
        )
        ..writeln(cues[i].text.trim())
        ..writeln();
    }
    return buffer.toString().trimRight();
  }
}
