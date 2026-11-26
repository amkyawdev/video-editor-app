import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/services/ffmpeg/media_probe_service.dart';

void main() {
  test('parses FFprobe JSON into duration, size and stream flags', () {
    const json = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264", "width": 1080,
     "height": 1920, "avg_frame_rate": "30000/1001", "duration": "12.5"},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"duration": "12.520000"}
}
''';
    final info = MediaProbeResult.fromFfprobeJson(json);
    expect(info.hasVideo, isTrue);
    expect(info.hasAudio, isTrue);
    expect(info.width, 1080);
    expect(info.height, 1920);
    expect(info.isVertical, isTrue);
    expect(info.durationUs, 12520000);
    expect(info.fps, closeTo(29.97, 0.01));
    expect(info.videoCodec, 'h264');
  });

  test('audio-only files report no video stream', () {
    const json = '''
{"streams": [{"codec_type": "audio", "codec_name": "mp3"}],
 "format": {"duration": "5.0"}}
''';
    final info = MediaProbeResult.fromFfprobeJson(json);
    expect(info.hasVideo, isFalse);
    expect(info.hasAudio, isTrue);
    expect(info.duration, const Duration(seconds: 5));
  });

  test('malformed payload fails loudly', () {
    expect(
      () => MediaProbeResult.fromFfprobeJson('[]'),
      throwsA(isA<MediaProbeException>()),
    );
  });
}
