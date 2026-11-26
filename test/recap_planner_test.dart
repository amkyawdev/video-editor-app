import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/models/recap.dart';
import 'package:video_editor_app/data/services/ai/recap_planner.dart';

RecapEvidence _evidence({String? transcript, bool withCaption = true}) =>
    RecapEvidence(
      videoName: 'movie.mp4',
      durationUs: 60000000,
      width: 1920,
      height: 1080,
      scenes: <RecapScene>[
        const RecapScene(timeUs: 0, caption: 'A station at dusk'),
        RecapScene(
          timeUs: 12000000,
          caption: withCaption ? 'A train arrives' : '',
          isModelCaption: withCaption,
        ),
      ],
      transcript: transcript,
      meanVolumeDb: -21.4,
      maxVolumeDb: -3.2,
    );

void main() {
  test('sentence splitter handles English and Burmese punctuation', () {
    final parts = RecapScriptBuilder.sentences(
      'First line. Second line! မြန်မာစာကြောင်း။ နောက်တစ်ကြောင်း။',
    );
    expect(parts.length, greaterThanOrEqualTo(3));
    expect(parts.first, 'First line.');
  });

  test('script sentences are distributed inside the video runtime', () {
    final cues = RecapScriptBuilder.distributeAsCues(
      'A man walks in. He opens a door. The screen fades to black.',
      durationUs: 9000000,
    );
    expect(cues, isNotEmpty);
    expect(cues.first.startUs, 0);
    expect(cues.last.endUs, lessThanOrEqualTo(9000000));
    for (var i = 1; i < cues.length; i++) {
      expect(cues[i].startUs, cues[i - 1].endUs);
    }
  });

  test('recap script exports valid SRT only for narratives', () {
    const narrative = RecapScript(
      title: 'Title',
      logline: 'Logline',
      body: 'One sentence. Two sentence.',
      language: 'English',
      isNarrative: true,
      warnings: <String>[],
    );
    final srt = narrative.toSrt(8000000);
    expect(srt, contains('00:00:00,000 -->'));
    expect(srt.trim().split('\n').first, '1');

    const report = RecapScript(
      title: 'Evidence',
      logline: '',
      body: 'Runtime only',
      language: 'English',
      isNarrative: false,
      warnings: <String>[],
    );
    expect(report.toSrt(8000000), isEmpty);
  });

  test('model output is parsed into title, logline and body', () {
    final script = RecapPlanner.parseScript(
      raw:
          'TITLE: The Long Night\nLOGLINE: A careful summary.\nRECAP:\n'
          'A train arrives at dusk. Nobody speaks.',
      evidence: _evidence(transcript: 'hello'),
      language: 'English',
      warnings: const <String>[],
    );
    expect(script.title, 'The Long Night');
    expect(script.logline, 'A careful summary.');
    expect(script.body, contains('A train arrives at dusk.'));
    expect(script.isNarrative, isTrue);
  });

  test('evidence report never invents a plot and stays non-narrative', () {
    final script = RecapPlanner.evidenceReport(
      evidence: _evidence(transcript: 'Someone says hello.'),
      language: 'English',
      warnings: const <String>['No ASR model installed.'],
    );
    expect(script.isNarrative, isFalse);
    expect(script.body, contains('No AI narrative was generated'));
    expect(script.body, contains('Extracted scene evidence'));
    expect(script.body, isNot(contains('villain')));
    expect(script.warnings, contains('No ASR model installed.'));
  });

  test('script prompt forbids invention and includes transcript/captions', () {
    final prompt = RecapPlanner.scriptPrompt(
      evidence: _evidence(transcript: 'They meet at the station.'),
      language: 'Burmese',
      tone: 'factual',
      targetWords: 150,
      maxTranscriptChars: 9000,
    );
    expect(prompt, contains('Never invent plot'));
    expect(prompt, contains('They meet at the station.'));
    expect(prompt, contains('A station at dusk'));
    expect(prompt, contains('Burmese'));
    expect(prompt, contains('TITLE, LOGLINE, RECAP'));
  });
}
