import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../../models/subtitle.dart';

/// WebVTT reader/writer. Cue identifiers, cue settings and NOTE/STYLE blocks
/// are accepted; settings are dropped on write because the app owns styling.
class VttCodec {
  const VttCodec._();

  static final RegExp _timeLine = RegExp(
    r'^\s*(?:[^\n]*?)\s*'
    r'((?:\d{1,3}:)?\d{1,2}:\d{1,2}\.\d{1,3})\s*-->\s*'
    r'((?:\d{1,3}:)?\d{1,2}:\d{1,2}\.\d{1,3})',
  );

  static List<SubtitleCue> decode(String content) {
    final normalized = content
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n{2,}'));
    final cues = <SubtitleCue>[];

    for (final rawBlock in blocks) {
      final block = rawBlock.trim();
      if (block.isEmpty) continue;
      if (block.startsWith('WEBVTT') ||
          block.startsWith('NOTE') ||
          block.startsWith('STYLE') ||
          block.startsWith('REGION')) {
        continue;
      }
      final lines = block.split('\n');
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
    final sorted = List<SubtitleCue>.of(cues)
      ..sort((SubtitleCue a, SubtitleCue b) => a.startUs.compareTo(b.startUs));
    final buffer = StringBuffer('WEBVTT\n\n');
    for (final cue in sorted) {
      buffer
        ..writeln(
          '${TimeUtils.vttTimestamp(cue.start)} --> '
          '${TimeUtils.vttTimestamp(cue.end)}',
        )
        ..writeln(cue.text.trim())
        ..writeln();
    }
    return buffer.toString();
  }
}
