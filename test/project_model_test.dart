import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/models/clip.dart';
import 'package:video_editor_app/data/models/export_settings.dart';
import 'package:video_editor_app/data/models/media_asset.dart';
import 'package:video_editor_app/data/models/project.dart';
import 'package:video_editor_app/data/models/subtitle.dart';

void main() {
  test('project survives a JSON round trip with tracks, cues and styling', () {
    final project = Project.blank(name: 'Round trip', fps: 25);
    project.media.add(
      MediaAsset(
        id: 'a1',
        name: 'clip.mp4',
        path: '/x/clip.mp4',
        kind: MediaKind.video,
        durationUs: 9000000,
        width: 1080,
        height: 1920,
        fps: 25,
        hasAudio: true,
        sizeBytes: 1234,
      ),
    );
    project.primaryVideoTrack.clips.add(
      Clip(
        id: 'c1',
        assetId: 'a1',
        durationUs: 4000000,
        speed: 1.5,
        rotation: 90,
        crop: const CropRect(left: 0.1),
        grade: const ColorGrade(brightness: 0.2, contrast: 1.1),
        effects: const ClipEffects(mirror: true, vignette: 0.3),
        transitionIn: const TransitionSpec(
          type: TransitionType.circleOpen,
          durationUs: 700000,
        ),
      ),
    );
    project.audioTracks.first.clips.add(
      Clip(
        id: 'm1',
        assetId: 'a1',
        durationUs: 3000000,
        timelineStartUs: 1200000,
        volume: 0.6,
      ),
    );
    project.subtitles
      ..cues.add(
        SubtitleCue.create(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 3),
          text: 'မင်္ဂလာပါ',
        ),
      )
      ..style = SubtitleStyle.initial.copyWith(
        fontSize: 72,
        bold: true,
        alignment: SubtitleAlignment.top,
      )
      ..language = 'my';
    project.exportSettings = const ExportSettings(
      container: ExportContainer.mkv,
      videoCodec: VideoCodec.h265,
      subtitleMode: SubtitleExportMode.soft,
      softSubtitleCodec: SoftSubtitleCodec.ass,
    );

    final decoded = Project.decode(project.toJsonString());

    expect(decoded.name, 'Round trip');
    expect(decoded.fps, 25);
    expect(decoded.media.single.width, 1080);
    final clip = decoded.primaryVideoTrack.clips.single;
    expect(clip.speed, 1.5);
    expect(clip.rotation, 90);
    expect(clip.crop.left, closeTo(0.1, 0.0001));
    expect(clip.effects.mirror, isTrue);
    expect(clip.transitionIn.type, TransitionType.circleOpen);
    expect(decoded.audioTracks.first.clips.single.timelineStartUs, 1200000);
    expect(decoded.subtitles.cues.single.text, 'မင်္ဂလာပါ');
    expect(decoded.subtitles.style.fontSize, 72);
    expect(decoded.subtitles.style.alignment, SubtitleAlignment.top);
    expect(decoded.exportSettings.container, ExportContainer.mkv);
    expect(decoded.exportSettings.softSubtitleCodec, SoftSubtitleCodec.ass);
  });

  test('duration accounts for transitions and subtitle tail', () {
    final project = Project.blank(name: 'Duration');
    final track = project.primaryVideoTrack;
    track.clips.addAll(<Clip>[
      Clip(id: 'c1', assetId: 'a', durationUs: 5000000),
      Clip(
        id: 'c2',
        assetId: 'a',
        durationUs: 5000000,
        transitionIn: const TransitionSpec(
          type: TransitionType.fade,
          durationUs: 500000,
        ),
      ),
    ]);
    expect(project.videoDurationUs, 9500000);

    project.subtitles.cues.add(
      SubtitleCue.create(
        start: const Duration(seconds: 12),
        end: const Duration(seconds: 14),
        text: 'tail',
      ),
    );
    expect(project.durationUs, 14000000);
  });

  test('export settings clamp and estimate sizes', () {
    const settings = ExportSettings(
      videoBitrateKbps: 8000,
      audioBitrateKbps: 192,
      audioCodec: ExportAudioCodec.aac,
    );
    expect(settings.estimatedBytes(10000000), greaterThan(9000000));
    expect(settings.copyWith(videoBitrateKbps: 1).videoBitrateKbps, 500);
    expect(
      const ExportSettings(container: ExportContainer.webm)
          .softCodecChoices
          .single,
      SoftSubtitleCodec.webvtt,
    );
  });
}
