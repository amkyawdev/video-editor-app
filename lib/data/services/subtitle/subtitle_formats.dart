import 'dart:io';

import '../../models/subtitle.dart';
import 'srt_codec.dart';
import 'vtt_codec.dart';

class SubtitleFileException implements Exception {
  SubtitleFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Single entry point for subtitle serialization and for the file type guards.
class SubtitleFormats {
  const SubtitleFormats._();

  static const Set<String> subtitleExtensions = <String>{'srt', 'vtt'};

  /// GGUF translation is deliberately limited to subtitle text sources.
  static const Set<String> translatableExtensions = <String>{'srt', 'txt'};

  static String extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static bool isSubtitleFile(String path) =>
      subtitleExtensions.contains(extensionOf(path));

  static bool isTranslationSource(String path) =>
      translatableExtensions.contains(extensionOf(path));

  static SubtitleFormat formatOf(String path) =>
      extensionOf(path) == 'vtt' ? SubtitleFormat.vtt : SubtitleFormat.srt;

  static List<SubtitleCue> decode(String content, SubtitleFormat format) =>
      switch (format) {
        SubtitleFormat.srt => SrtCodec.decode(content),
        SubtitleFormat.vtt => VttCodec.decode(content),
      };

  static String encode(List<SubtitleCue> cues, SubtitleFormat format) =>
      switch (format) {
        SubtitleFormat.srt => SrtCodec.encode(cues),
        SubtitleFormat.vtt => VttCodec.encode(cues),
      };

  static List<SubtitleCue> decodeFile(String path, String content) =>
      decode(content, formatOf(path));

  /// Rejects unsupported or empty files with a user-facing message.
  static List<SubtitleCue> parseOrThrow(String fileName, String content) {
    if (!isSubtitleFile(fileName)) {
      throw SubtitleFileException(
        'Only .srt and .vtt subtitle files are supported.',
      );
    }
    final cues = decodeFile(fileName, content);
    if (cues.isEmpty) {
      throw SubtitleFileException(
        'No cues were found in $fileName. Check the timestamp format.',
      );
    }
    return cues;
  }
}
