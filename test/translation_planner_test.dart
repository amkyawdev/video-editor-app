import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/models/local_model.dart';
import 'package:video_editor_app/data/models/subtitle.dart';
import 'package:video_editor_app/data/services/ai/translation_service.dart';
import 'package:video_editor_app/data/services/models/model_catalog.dart';
import 'package:video_editor_app/data/services/subtitle/subtitle_formats.dart';

SubtitleCue _cue(int i, String text) => SubtitleCue(
  id: 'c$i',
  startUs: i * 2000000,
  endUs: i * 2000000 + 1500000,
  text: text,
);

void main() {
  test('batching skips empty cues and respects the character budget', () {
    final cues = <SubtitleCue>[
      _cue(0, 'a' * 400),
      _cue(1, 'b' * 400),
      _cue(2, ''),
      _cue(3, 'c' * 400),
    ];
    final batches = TranslationPlanner.batchCueIndexes(
      cues,
      maxChars: 500,
      maxCues: 10,
    );
    expect(batches.expand((List<int> b) => b).toList(), <int>[0, 1, 3]);
    expect(batches.every((List<int> b) => b.length == 1), isTrue);
    expect(TranslationPlanner.translatableIndexes(cues), <int>[0, 1, 3]);
  });

  test(
    'Hy-MT3 prompt uses documented delimiter template and language name',
    () {
      final prompt = TranslationPlanner.buildPrompt(
        segments: const <String>['one', 'two'],
        targetLanguage: 'Burmese',
        hyMtTemplate: true,
      );
      expect(prompt, contains('translate the following text into Burmese'));
      expect(prompt, contains('@@@'));
      expect(prompt, contains('retain the exact same number of delimiter'));
    },
  );

  test('generic prompt numbers every segment and demands no extra text', () {
    final prompt = TranslationPlanner.buildPrompt(
      segments: const <String>['Hello', 'World'],
      targetLanguage: 'Burmese',
      hyMtTemplate: false,
      context: 'Name: Aung',
    );
    expect(prompt, contains('1. Hello'));
    expect(prompt, contains('2. World'));
    expect(prompt, contains('Name: Aung'));
    expect(prompt, contains('Do not add explanations'));
  });

  test('parsers accept only a complete segment set', () {
    expect(
      TranslationPlanner.parseDelimited('မင်္ဂလာပါ\n@@@\nကျေးဇူး', 2),
      <String>['မင်္ဂလာပါ', 'ကျေးဇူး'],
    );
    expect(TranslationPlanner.parseDelimited('only one', 2), isEmpty);
    expect(TranslationPlanner.parseNumbered('1. တစ်\n2. နှစ်', 2), <String>[
      'တစ်',
      'နှစ်',
    ]);
    expect(TranslationPlanner.parseNumbered('no numbers here', 2), isEmpty);
  });

  test('markdown fences and language prefixes are cleaned', () {
    expect(
      TranslationPlanner.clean('```\nBurmese: မင်္ဂလာပါ\n```'),
      'မင်္ဂလာပါ',
    );
  });

  test('long SRT text is split under the character budget', () {
    final long = List<String>.filled(40, 'ဒါဟာ စမ်းသပ်စာသားပါ။').join(' ');
    final parts = TranslationPlanner.splitLongText(long, maxChars: 180);
    expect(parts.length, greaterThan(1));
    expect(parts.every((String p) => p.length <= 180), isTrue);
    expect(parts.join(' ').replaceAll(' ', ''), long.replaceAll(' ', ''));
  });

  test('Hy-MT3 catalog entry is the recognised template family', () {
    final model = ModelCatalog.defaultTranslation;
    expect(TranslationPlanner.usesHyMtTemplate(model), isTrue);
    expect(model.burmeseEvidence, isTrue);
  });

  test('translation sources stay limited to SRT and TXT', () {
    expect(SubtitleFormats.isTranslationSource('a.srt'), isTrue);
    expect(SubtitleFormats.isTranslationSource('a.txt'), isTrue);
    expect(SubtitleFormats.isTranslationSource('a.vtt'), isFalse);
    expect(SubtitleFormats.isTranslationSource('a.wav'), isFalse);
    expect(ModelTier.values, contains(ModelTier.serverOnly));
  });
}
