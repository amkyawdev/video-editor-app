import '../../models/subtitle.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';

class SubtitleParseException implements Exception {
  SubtitleParseException(this.message);

  final String message;

  @override
  String toString() => 'SubtitleParseException: $message';
}

/// SubRip (SRT) reader/writer. Handles CRLF, a UTF-8 BOM, missing sequence
/// numbers, single-digit milliseconds and multi-line cue text.
class SrtCodec {
  const SrtCodec._();

  static final RegExp _timeLine = RegExp(
    r'^\s*(\d{1,3}:\d{1,2}:\d{1,2}[,.]\d{1,3}|\d{1,2}:\d{1,2}[,.]\d{1,3})\s*-->\s*'
    r'(\d{1,3}:\d{1,2}:\d{1,2}[,.]\d{1,3}|\d{1,2}:\d{1,2}[,.]\d{1,3})',
  );

  static List<SubtitleCue> decode(String content) {
    final normalized = content
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n{2,}'));
    final cues = <SubtitleCue>[];

    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((String line) => line.trimRight())
          .toList();
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
      if (lines.isEmpty) continue;

      var timeIndex = 0;
      while (timeIndex < lines.length &&
          _timeLine.firstMatch(lines[timeIndex]) == null) {
        timeIndex++;
      }
      if (timeIndex >= lines.length) continue;

      final match = _timeLine.firstMatch(lines[timeIndex]);
      if (match == null) continue;
      final start = TimeUtils.parseTimestamp(match.group(1) ?? '');
      final end = TimeUtils.parseTimestamp(match.group(2) ?? '');
      if (start == null || end == null) continue;

      final text = lines.sublist(timeIndex + 1).join('\n').trim();
      final safeEnd = end <= start ? start + const Duration(seconds: 1) : end;
      cues.add(
        SubtitleCue(
          id: newId('cue'),
          startUs: start.inMicroseconds,
          endUs: safeEnd.inMicroseconds,
          text: text,
        ),
      );
    }

    return cues;
  }

  static String encode(List<SubtitleCue> cues) {
    final buffer = StringBuffer();
    final sorted = List<SubtitleCue>.of(cues)
      ..sort((SubtitleCue a, SubtitleCue b) => a.startUs.compareTo(b.startUs));
    for (var i = 0; i < sorted.length; i++) {
      final cue = sorted[i];
      buffer
        ..writeln(i + 1)
        ..writeln(
          '${TimeUtils.srtTimestamp(cue.start)} --> '
          '${TimeUtils.srtTimestamp(cue.end)}',
        )
        ..writeln(cue.text.trim())
        ..writeln();
    }
    return '${buffer.toString().trimRight()}\n';
  }
}
