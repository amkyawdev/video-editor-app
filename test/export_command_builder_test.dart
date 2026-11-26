import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/models/clip.dart';
import 'package:video_editor_app/data/models/export_settings.dart';
import 'package:video_editor_app/data/models/media_asset.dart';
import 'package:video_editor_app/data/models/project.dart';
import 'package:video_editor_app/data/models/subtitle.dart';
import 'package:video_editor_app/data/services/ffmpeg/export_command_builder.dart';

const Duration _fiveSeconds = Duration(seconds: 5);

MediaAsset _asset({
  String id = 'asset1',
  bool hasAudio = true,
  MediaKind kind = MediaKind.video,
  int durationUs = 60000000,
}) => MediaAsset(
  id: id,
  name: 'media-$id.mp4',
  path: '/media/$id.mp4',
  kind: kind,
  durationUs: durationUs,
  width: 1920,
  height: 1080,
  fps: 30,
  hasAudio: hasAudio,
  sizeBytes: 1000,
);

Clip _clip({
  String id = 'clip1',
  String assetId = 'asset1',
  Duration duration = _fiveSeconds,
  Duration sourceIn = Duration.zero,
  double speed = 1,
  TransitionSpec transition = TransitionSpec.none,
  int rotation = 0,
  CropRect crop = CropRect.full,
  ColorGrade grade = ColorGrade.neutral,
  ClipEffects effects = ClipEffects.none,
  int timelineStartUs = 0,
}) => Clip(
  id: id,
  assetId: assetId,
  durationUs: duration.inMicroseconds,
  sourceInUs: sourceIn.inMicroseconds,
  speed: speed,
  transitionIn: transition,
  rotation: rotation,
  crop: crop,
  grade: grade,
  effects: effects,
  timelineStartUs: timelineStartUs,
);

Project _project({
  required List<Clip> clips,
  bool hasAudio = true,
  List<MediaAsset>? assets,
}) {
  final project = Project.blank(name: 'Test project');
  project.media.addAll(assets ?? <MediaAsset>[_asset(hasAudio: hasAudio)]);
  project.primaryVideoTrack.clips.addAll(clips);
  return project;
}

void main() {
  const builder = ExportCommandBuilder();

  test('burns styled ASS subtitles into an H.264 MP4', () {
    final project = _project(clips: <Clip>[_clip()]);
    project.subtitles.cues.add(
      SubtitleCue.create(
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 2),
        text: 'မင်္ဂလာပါ',
      ),
    );

    final plan = builder.build(
      project: project,
      settings: const ExportSettings(),
      outputPath: '/out/movie.mp4',
      burnedSubtitlePath: '/cache/sub.ass',
      fontsDir: '/cache/fonts',
    );
    final command = plan.args.join(' ');

    expect(plan.burnsSubtitles, isTrue);
    expect(plan.embedsSubtitles, isFalse);
    expect(command, contains('-c:v libx264'));
    expect(command, contains('-pix_fmt yuv420p'));
    expect(command, contains('-movflags +faststart'));
    expect(command, contains('-c:a aac'));
    expect(command, contains('subtitles=filename=/cache/sub.ass'));
    expect(command, contains('fontsdir=/cache/fonts'));
    expect(command, contains('-map [vout]'));
    expect(plan.duration, _fiveSeconds);
  });

  test('soft subtitle track is mapped with the container codec', () {
    final project = _project(clips: <Clip>[_clip()]);
    project.subtitles.cues.add(
      SubtitleCue.create(
        start: Duration.zero,
        end: const Duration(seconds: 2),
        text: 'မြန်မာ',
      ),
    );

    final plan = builder.build(
      project: project,
      settings: const ExportSettings(
        container: ExportContainer.mkv,
        subtitleMode: SubtitleExportMode.soft,
        softSubtitleCodec: SoftSubtitleCodec.ass,
      ),
      outputPath: '/out/movie.mkv',
      softSubtitlePath: '/cache/sub.ass',
    );
    final command = plan.args.join(' ');

    expect(plan.embedsSubtitles, isTrue);
    expect(command, contains('-map 1:s'));
    expect(command, contains('-c:s ass'));
    expect(command, contains('language=mya'));
    expect(command, isNot(contains('subtitles=filename=')));
  });

  test('hard cuts use concat and transitions use xfade with a real offset', () {
    final hardCut = _project(
      clips: <Clip>[
        _clip(id: 'c1'),
        _clip(id: 'c2'),
      ],
    );
    final hardPlan = builder.build(
      project: hardCut,
      settings: const ExportSettings(),
      outputPath: '/out/cut.mp4',
    );
    expect(hardPlan.filterGraph, contains('concat=n=2:v=1:a=0'));

    final withFade = _project(
      clips: <Clip>[
        _clip(id: 'c1'),
        _clip(
          id: 'c2',
          transition: const TransitionSpec(
            type: TransitionType.fade,
            durationUs: 500000,
          ),
        ),
      ],
    );
    final fadePlan = builder.build(
      project: withFade,
      settings: const ExportSettings(),
      outputPath: '/out/fade.mp4',
    );
    expect(fadePlan.filterGraph, contains('xfade=transition=fade'));
    expect(fadePlan.filterGraph, contains('duration=0.500:offset=4.500'));
    expect(fadePlan.duration, const Duration(milliseconds: 9500));
  });

  test('speed change trims the source range and retimes video and audio', () {
    final project = _project(
      clips: <Clip>[_clip(duration: const Duration(seconds: 5), speed: 2)],
    );
    final plan = builder.build(
      project: project,
      settings: const ExportSettings(),
      outputPath: '/out/speed.mp4',
    );
    final command = plan.args.join(' ');
    expect(command, contains('-t 10.000'));
    expect(plan.filterGraph, contains('setpts=(PTS-STARTPTS)/2.0000'));
    expect(plan.filterGraph, contains('atempo=2.0000'));
    expect(plan.duration, _fiveSeconds);
  });

  test('extra audio tracks are mixed with the clip audio', () {
    final project = _project(
      clips: <Clip>[_clip()],
      assets: <MediaAsset>[
        _asset(),
        _asset(id: 'music', kind: MediaKind.audio),
      ],
    );
    final musicTrack = project.audioTracks.first;
    musicTrack.clips.add(
      _clip(
        id: 'musicClip',
        assetId: 'music',
        duration: const Duration(seconds: 3),
        timelineStartUs: 1000000,
      ),
    );

    final plan = builder.build(
      project: project,
      settings: const ExportSettings(),
      outputPath: '/out/mix.mp4',
    );
    final command = plan.args.join(' ');
    expect(plan.hasAudio, isTrue);
    expect(plan.filterGraph, contains('amix=inputs=2'));
    expect(plan.filterGraph, contains('adelay=1000|1000'));
    expect(command, contains('-map [aout]'));
  });

  test('silent video exports with -an and no audio filter graph', () {
    final project = _project(clips: <Clip>[_clip()], hasAudio: false);
    final plan = builder.build(
      project: project,
      settings: const ExportSettings(),
      outputPath: '/out/silent.mp4',
    );
    expect(plan.hasAudio, isFalse);
    expect(plan.args, contains('-an'));
    expect(plan.filterGraph, isNot(contains('amix')));
  });

  test('crop, rotate, grade, effects and zoom reach the filter graph', () {
    final project = _project(
      clips: <Clip>[
        _clip(
          rotation: 90,
          crop: const CropRect(left: 0.1, right: 0.1),
          grade: const ColorGrade(brightness: 0.2, saturation: 1.4),
          effects: const ClipEffects(grayscale: true, mirror: true),
        ),
      ],
    );
    final plan = builder.build(
      project: project,
      settings: const ExportSettings(resolution: ResolutionPreset.p720),
      outputPath: '/out/look.mp4',
    );
    expect(plan.filterGraph, contains('crop=iw*0.8000:ih*1.0000'));
    expect(plan.filterGraph, contains('transpose=1'));
    expect(plan.filterGraph, contains('scale=1280:720'));
    expect(plan.filterGraph, contains('eq=brightness=0.200'));
    expect(plan.filterGraph, contains('hue=s=0'));
    expect(plan.filterGraph, contains('hflip'));
  });

  test('WebM uses VP9 and Opus with a WebVTT sidecar', () {
    final project = _project(clips: <Clip>[_clip()]);
    project.subtitles.cues.add(
      SubtitleCue.create(
        start: Duration.zero,
        end: const Duration(seconds: 1),
        text: 'x',
      ),
    );
    final plan = builder.build(
      project: project,
      settings: const ExportSettings(
        container: ExportContainer.webm,
        videoCodec: VideoCodec.vp9,
        audioCodec: ExportAudioCodec.opus,
        subtitleMode: SubtitleExportMode.soft,
        softSubtitleCodec: SoftSubtitleCodec.webvtt,
      ),
      outputPath: '/out/movie.webm',
      softSubtitlePath: '/cache/sub.vtt',
    );
    final command = plan.args.join(' ');
    expect(command, contains('-c:v libvpx-vp9'));
    expect(command, contains('-c:a libopus'));
    expect(command, contains('-c:s webvtt'));
    expect(command, isNot(contains('-movflags')));
  });

  test('validation blocks impossible container/codec pairs', () {
    final project = _project(clips: <Clip>[_clip()]);
    expect(
      () => builder.build(
        project: project,
        settings: const ExportSettings(
          container: ExportContainer.mp4,
          videoCodec: VideoCodec.vp9,
        ),
        outputPath: '/out/x.mp4',
      ),
      throwsA(isA<ExportException>()),
    );
    expect(
      () => builder.build(
        project: project,
        settings: const ExportSettings(
          container: ExportContainer.mp4,
          audioCodec: ExportAudioCodec.opus,
        ),
        outputPath: '/out/x.mp4',
      ),
      throwsA(isA<ExportException>()),
    );
  });

  test('burn-in refuses to run without the libass filter', () {
    final project = _project(clips: <Clip>[_clip()]);
    project.subtitles.cues.add(
      SubtitleCue.create(
        start: Duration.zero,
        end: const Duration(seconds: 1),
        text: 'x',
      ),
    );
    expect(
      () => builder.build(
        project: project,
        settings: const ExportSettings(),
        outputPath: '/out/x.mp4',
        burnedSubtitlePath: '/cache/sub.ass',
        subtitleFilterAvailable: false,
      ),
      throwsA(isA<ExportException>()),
    );
  });

  test('overlay video track is composited with a timestamp shift', () {
    final project = _project(
      clips: <Clip>[_clip()],
      assets: <MediaAsset>[
        _asset(),
        _asset(id: 'overlay'),
      ],
    );
    final overlayTrack = project.addVideoTrack();
    overlayTrack.clips.add(
      _clip(
        id: 'ov1',
        assetId: 'overlay',
        duration: const Duration(seconds: 2),
        timelineStartUs: 1000000,
      ),
    );

    final plan = builder.build(
      project: project,
      settings: const ExportSettings(),
      outputPath: '/out/overlay.mp4',
    );
    expect(plan.filterGraph, contains('overlay='));
    expect(plan.filterGraph, contains("enable='between(t,1.000,3.000)'"));
    expect(plan.filterGraph, contains(r'setpts=PTS-STARTPTS+1.000/TB'));
  });

  test(
    'subtitle-only timeline extends the video by cloning the last frame',
    () {
      final project = _project(clips: <Clip>[_clip()]);
      project.subtitles.cues.add(
        SubtitleCue.create(
          start: const Duration(seconds: 6),
          end: const Duration(seconds: 8),
          text: 'late',
        ),
      );
      final plan = builder.build(
        project: project,
        settings: const ExportSettings(),
        outputPath: '/out/late.mp4',
        burnedSubtitlePath: '/cache/sub.ass',
      );
      expect(plan.duration, const Duration(seconds: 8));
      expect(
        plan.filterGraph,
        contains('tpad=stop_mode=clone:stop_duration=3.000'),
      );
    },
  );
}
