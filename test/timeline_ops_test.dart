import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/models/clip.dart';
import 'package:video_editor_app/data/models/media_asset.dart';
import 'package:video_editor_app/data/models/project.dart';
import 'package:video_editor_app/state/timeline_ops.dart';

Project _project({int clips = 2}) {
  final project = Project.blank(name: 'Edit test');
  project.media.add(
    MediaAsset(
      id: 'a1',
      name: 'a.mp4',
      path: '/a.mp4',
      kind: MediaKind.video,
      durationUs: 60000000,
      hasAudio: true,
    ),
  );
  for (var i = 0; i < clips; i++) {
    project.primaryVideoTrack.clips.add(
      Clip(
        id: 'c$i',
        assetId: 'a1',
        durationUs: 5000000,
        sourceInUs: i * 5000000,
      ),
    );
  }
  return project;
}

void main() {
  test('splits the playhead clip into two contiguous clips', () {
    final project = _project(clips: 1);
    expect(TimelineOps.splitAt(project, const Duration(seconds: 2)), isTrue);
    final clips = project.primaryVideoTrack.clips;
    expect(clips, hasLength(2));
    expect(clips[0].durationUs, 2000000);
    expect(clips[1].durationUs, 3000000);
    expect(clips[1].sourceInUs, 2000000);
    expect(project.primaryVideoTrack.startsUs, <int>[0, 2000000]);
  });

  test('refuses to split within 200 ms of an edge', () {
    final project = _project(clips: 1);
    expect(
      TimelineOps.splitAt(project, const Duration(milliseconds: 100)),
      isFalse,
    );
  });

  test('trims start and end while respecting source bounds', () {
    final project = _project(clips: 1);
    expect(TimelineOps.trimStart(project, 'c0', 500000), isTrue);
    var clip = project.primaryVideoTrack.clips.single;
    expect(clip.sourceInUs, 500000);
    expect(clip.durationUs, 4500000);

    expect(TimelineOps.trimEnd(project, 'c0', -1000000), isTrue);
    clip = project.primaryVideoTrack.clips.single;
    expect(clip.durationUs, 3500000);

    expect(TimelineOps.trimEnd(project, 'c0', 99000000), isTrue);
    expect(
      project.primaryVideoTrack.clips.single.durationUs,
      lessThanOrEqualTo(59500000),
    );
  });

  test('speed changes timeline duration from the source range', () {
    final project = _project(clips: 1);
    expect(TimelineOps.setSpeed(project, 'c0', 2), isTrue);
    final clip = project.primaryVideoTrack.clips.single;
    expect(clip.speed, 2);
    expect(clip.durationUs, 2500000);
    expect(clip.sourceDurationUs, 5000000);
  });

  test('merges only contiguous clips from the same asset', () {
    final project = _project(clips: 1);
    TimelineOps.splitAt(project, const Duration(seconds: 2));
    expect(TimelineOps.canMergeWithNext(project, 'c0'), isTrue);
    expect(TimelineOps.mergeWithNext(project, 'c0'), isTrue);
    expect(project.primaryVideoTrack.clips, hasLength(1));
    expect(project.primaryVideoTrack.clips.single.durationUs, 5000000);

    final other = _project(clips: 2);
    expect(TimelineOps.canMergeWithNext(other, 'c0'), isTrue);
    other.primaryVideoTrack.clips[1] = other.primaryVideoTrack.clips[1]
        .copyWith(assetId: 'other');
    expect(TimelineOps.canMergeWithNext(other, 'c0'), isFalse);
  });

  test('reorders clips on the primary track', () {
    final project = _project(clips: 2);
    expect(TimelineOps.reorderPrimaryClip(project, 'c1', 0), isTrue);
    expect(
      project.primaryVideoTrack.clips.map((Clip c) => c.id).toList(),
      <String>['c1', 'c0'],
    );
  });

  test('audio assets land on the audio track at the requested offset', () {
    final project = _project(clips: 1);
    project.media.add(
      MediaAsset(
        id: 'm1',
        name: 'music.mp3',
        path: '/music.mp3',
        kind: MediaKind.audio,
        durationUs: 12000000,
      ),
    );
    final clip = TimelineOps.addAsset(
      project,
      project.media.last,
      timelineStartUs: 3000000,
    );
    expect(clip, isNotNull);
    expect(project.audioTracks.first.clips.single.timelineStartUs, 3000000);
  });

  test('removes clips by id', () {
    final project = _project(clips: 2);
    expect(TimelineOps.removeClip(project, 'c0'), isTrue);
    expect(project.primaryVideoTrack.clips.single.id, 'c1');
    expect(TimelineOps.removeClip(project, 'nope'), isFalse);
  });
}
