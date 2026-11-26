import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/models/subtitle.dart';
import 'package:video_editor_app/data/services/subtitle/ass_writer.dart';
import 'package:video_editor_app/data/services/subtitle/srt_codec.dart';
import 'package:video_editor_app/data/services/subtitle/subtitle_formats.dart';
import 'package:video_editor_app/data/services/subtitle/vtt_codec.dart';

void main() {
  group('SRT', () {
    test('parses BOM, CRLF, multiline text and Myanmar script', () {
      const raw =
          '\uFEFF1\r\n'
          '00:00:01,250 --> 00:00:04,000\r\n'
          'မင်္ဂလာပါ\r\n'
          'second line\r\n'
          '\r\n'
          '2\r\n'
          '00:00:05,5 --> 00:00:07,000\r\n'
          'ကျေးဇူးတင်ပါတယ်\r\n';

      final cues = SrtCodec.decode(raw);

      expect(cues, hasLength(2));
      expect(cues.first.start, const Duration(milliseconds: 1250));
      expect(cues.first.end, const Duration(seconds: 4));
      expect(cues.first.text, 'မင်္ဂလာပါ\nsecond line');
      expect(cues[1].start, const Duration(milliseconds: 5500));
      expect(cues[1].text, 'ကျေးဇူးတင်ပါတယ်');
    });

    test('skips malformed blocks and repairs zero-length cues', () {
      const raw =
          'not a cue\n\n'
          '1\n00:00:02,000 --> 00:00:02,000\nclamped\n';
      final cues = SrtCodec.decode(raw);
      expect(cues, hasLength(1));
      expect(cues.single.duration, const Duration(seconds: 1));
    });

    test('round trips through encode', () {
      final cues = <SubtitleCue>[
        SubtitleCue.create(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 2),
          text: 'မြန်မာ စာတန်းထိုး',
        ),
        SubtitleCue.create(
          start: const Duration(seconds: 3),
          end: const Duration(seconds: 4),
          text: 'line one\nline two',
        ),
      ];
      final encoded = SrtCodec.encode(cues.reversed.toList());
      final decoded = SrtCodec.decode(encoded);
      expect(
        decoded.map((SubtitleCue c) => c.text).toList(),
        cues.map((SubtitleCue c) => c.text).toList(),
      );
      expect(encoded.indexOf('00:00:01,000 --> 00:00:02,000'), greaterThan(0));
    });
  });

  group('WebVTT', () {
    test('parses header, NOTE blocks, identifiers and settings', () {
      const raw =
          'WEBVTT\n\n'
          'NOTE this is a comment\n\n'
          'intro\n'
          '00:00:01.000 --> 00:00:03.500 align:start position:10%\n'
          'Hello\n\n'
          '00:04.000 --> 00:06.000\n'
          'မြန်မာ\n';
      final cues = VttCodec.decode(raw);
      expect(cues, hasLength(2));
      expect(cues.first.start, const Duration(seconds: 1));
      expect(cues.first.end, const Duration(milliseconds: 3500));
      expect(cues[1].text, 'မြန်မာ');
      expect(cues[1].start, const Duration(seconds: 4));
    });

    test('writes a WEBVTT header and dotted timestamps', () {
      final encoded = VttCodec.encode(<SubtitleCue>[
        SubtitleCue.create(
          start: const Duration(milliseconds: 1500),
          end: const Duration(milliseconds: 2500),
          text: 'ဟုတ်ကဲ့',
        ),
      ]);
      expect(encoded.startsWith('WEBVTT\n\n'), isTrue);
      expect(encoded, contains('00:00:01.500 --> 00:00:02.500'));
    });
  });

  group('file guards', () {
    test('accepts only srt and vtt for subtitle import', () {
      expect(SubtitleFormats.isSubtitleFile('/x/a.srt'), isTrue);
      expect(SubtitleFormats.isSubtitleFile('/x/a.SRT'), isTrue);
      expect(SubtitleFormats.isSubtitleFile('/x/a.vtt'), isTrue);
      expect(SubtitleFormats.isSubtitleFile('/x/a.mp4'), isFalse);
      expect(
        () => SubtitleFormats.parseOrThrow('a.ass', 'x'),
        throwsA(isA<SubtitleFileException>()),
      );
    });

    test('GGUF translation sources are limited to srt and txt', () {
      expect(SubtitleFormats.isTranslationSource('a.srt'), isTrue);
      expect(SubtitleFormats.isTranslationSource('a.txt'), isTrue);
      expect(SubtitleFormats.isTranslationSource('a.vtt'), isFalse);
      expect(SubtitleFormats.isTranslationSource('a.mp4'), isFalse);
      expect(SubtitleFormats.isTranslationSource('a.wav'), isFalse);
    });
  });

  group('subtitle operations', () {
    test('fixOverlaps leaves a gap', () {
      final doc = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue.create(
            start: Duration.zero,
            end: const Duration(seconds: 3),
            text: 'a',
          ),
          SubtitleCue.create(
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 4),
            text: 'b',
          ),
        ],
      );
      doc.fixOverlaps();
      expect(
        doc.cues[1].startUs,
        greaterThanOrEqualTo(doc.cues[0].endUs + 20000),
      );
    });

    test('shiftAll clamps at zero and keeps durations', () {
      final doc = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue.create(
            start: const Duration(seconds: 1),
            end: const Duration(seconds: 3),
            text: 'a',
          ),
        ],
      );
      doc.shiftAll(const Duration(seconds: -5));
      expect(doc.cues.single.startUs, 0);
      expect(doc.cues.single.endUs, 2000000);
    });

    test('activeAt finds the cue under the playhead', () {
      final doc = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue.create(
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 4),
            text: 'a',
          ),
        ],
      );
      expect(doc.activeAt(const Duration(seconds: 3))?.text, 'a');
      expect(doc.activeAt(const Duration(seconds: 5)), isNull);
    });
  });

  group('ASS writer', () {
    test('writes style, font, timing and escaped Myanmar text', () {
      final doc = SubtitleDocument(
        cues: <SubtitleCue>[
          SubtitleCue.create(
            start: const Duration(seconds: 1, milliseconds: 250),
            end: const Duration(seconds: 4),
            text: 'မင်္ဂလာပါ\n{not a tag}',
          ),
        ],
        style: SubtitleStyle.initial.copyWith(
          fontFamily: 'NotoSansMyanmar',
          fontSize: 60,
          bold: true,
          alignment: SubtitleAlignment.top,
          backgroundColor: 0xCC000000,
          outlineWidth: 2,
          marginVertical: 10,
        ),
      );
      final ass = AssWriter.build(doc, canvasWidth: 1920, canvasHeight: 1080);
      expect(ass, contains('PlayResX: 1920'));
      expect(ass, contains('PlayResY: 1080'));
      expect(ass, contains('Noto Sans Myanmar'));
      expect(ass, contains('Style: Amkyaw,Noto Sans Myanmar,60.0'));
      expect(ass, contains(',8,154,154,108,1'));
      expect(ass, contains('Dialogue: 0,0:00:01.25,0:00:04.00'));
      expect(ass, contains(r'မင်္ဂလာပါ\N\{not a tag\}'));
      expect(ass, contains('&H33')); // 0xCC background -> ASS alpha 0x33
    });

    test('maps alignment to ASS numpad values', () {
      for (final (SubtitleAlignment alignment, int expected)
          in <(SubtitleAlignment, int)>[
            (SubtitleAlignment.bottom, 2),
            (SubtitleAlignment.center, 5),
            (SubtitleAlignment.top, 8),
          ]) {
        final doc = SubtitleDocument(
          cues: <SubtitleCue>[
            SubtitleCue.create(
              start: Duration.zero,
              end: const Duration(seconds: 1),
              text: 'x',
            ),
          ],
          style: SubtitleStyle.initial.copyWith(alignment: alignment),
        );
        final ass = AssWriter.build(doc, canvasWidth: 1080, canvasHeight: 1920);
        expect(ass, contains(',$expected,'));
      }
    });
  });
}
