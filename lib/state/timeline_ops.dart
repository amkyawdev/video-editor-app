import 'dart:math' as math;

import '../data/models/clip.dart';
import '../data/models/media_asset.dart';
import '../data/models/project.dart';
import '../data/models/track.dart';

/// Timeline mutations that are shared by the editor, tests and the recap flow.
/// Kept synchronous and side-effect free apart from the project model.
class TimelineOps {
  const TimelineOps._();

  static const int minClipUs = 200000;

  static Clip? addAsset(
    Project project,
    MediaAsset asset, {
    bool overlay = false,
    int? timelineStartUs,
  }) {
    final durationUs = asset.isAudio
        ? asset.durationUs
        : math.min(asset.durationUs, 60 * 1000000);
    if (durationUs <= 0) return null;
    if (asset.isAudio) {
      final track = project.audioTracks.first;
      final start = timelineStartUs ?? 0;
      final clip = Clip(
        id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
        assetId: asset.id,
        durationUs: durationUs,
        timelineStartUs: start,
      );
      track.clips.add(clip);
      track.sortAudioClips();
      project.touch();
      return clip;
    }
    if (overlay) {
      final track = project.addVideoTrack();
      final clip = Clip(
        id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
        assetId: asset.id,
        durationUs: math.min(durationUs, 20 * 1000000),
        timelineStartUs: timelineStartUs ?? 0,
      );
      track.clips.add(clip);
      project.touch();
      return clip;
    }
    final track = project.primaryVideoTrack;
    final clip = Clip(
      id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
      assetId: asset.id,
      durationUs: durationUs,
    );
    track.clips.add(clip);
    project.touch();
    return clip;
  }

  static Clip? clipAtPlayhead(Project project, Duration playhead) {
    final index = _primaryIndexAt(project, playhead.inMicroseconds);
    if (index < 0) return null;
    return project.primaryVideoTrack.clips[index];
  }

  static int _primaryIndexAt(Project project, int timelineUs) {
    final track = project.primaryVideoTrack;
    final starts = track.startsUs;
    for (var i = 0; i < track.clips.length; i++) {
      if (timelineUs >= starts[i] &&
          timelineUs < starts[i] + track.clips[i].durationUs) {
        return i;
      }
    }
    return -1;
  }

  /// Splits the primary clip under the playhead. Cuts inside the first or last
  /// 200 ms are refused so a clip cannot become untrimmable.
  static bool splitAt(Project project, Duration playhead) {
    final track = project.primaryVideoTrack;
    final atUs = playhead.inMicroseconds;
    final index = _primaryIndexAt(project, atUs);
    if (index < 0) return false;
    final clip = track.clips[index];
    final startUs = track.startsUs[index];
    final offset = atUs - startUs;
    if (offset < minClipUs || clip.durationUs - offset < minClipUs) {
      return false;
    }
    final left = clip.copyWith(durationUs: offset);
    final right = clip.copyWith(
      sourceInUs: clip.sourceInUs + (offset * clip.speed).round(),
      durationUs: clip.durationUs - offset,
      transitionIn: TransitionSpec.none,
    );
    track.clips
      ..[index] = left
      ..insert(index + 1, right);
    project.touch();
    return true;
  }

  static bool removeClip(Project project, String clipId) {
    for (final track in project.tracks) {
      final before = track.clips.length;
      track.clips.removeWhere((Clip clip) => clip.id == clipId);
      if (track.clips.length != before) {
        project.touch();
        return true;
      }
    }
    return false;
  }

  static bool trimStart(Project project, String clipId, int deltaUs) {
    final track = project.trackOfClip(clipId);
    final clip = project.clipById(clipId);
    if (track == null || clip == null) return false;
    final delta = deltaUs.clamp(-clip.sourceInUs, clip.durationUs - minClipUs);
    if (delta == 0) return false;
    final updated = clip.copyWith(
      sourceInUs: clip.sourceInUs + (delta * clip.speed).round(),
      durationUs: clip.durationUs - delta,
    );
    _replace(track, updated);
    project.touch();
    return true;
  }

  static bool trimEnd(Project project, String clipId, int deltaUs) {
    final track = project.trackOfClip(clipId);
    final clip = project.clipById(clipId);
    if (track == null || clip == null) return false;
    final asset = project.assetFor(clip.assetId);
    final maxSourceUs = asset?.isVideo == true || asset?.kind == MediaKind.video
        ? (asset?.durationUs ?? clip.sourceOut.inMicroseconds)
        : clip.sourceOut.inMicroseconds;
    final maxDurationUs = math.max(
      minClipUs,
      ((maxSourceUs - clip.sourceInUs) / clip.speed).floor(),
    );
    final updated = clip.copyWith(
      durationUs: (clip.durationUs + deltaUs).clamp(minClipUs, maxDurationUs),
    );
    _replace(track, updated);
    project.touch();
    return true;
  }

  static bool setSpeed(Project project, String clipId, double speed) {
    final track = project.trackOfClip(clipId);
    final clip = project.clipById(clipId);
    if (track == null || clip == null) return false;
    final sourceDurationUs = clip.sourceDurationUs;
    final newDuration = (sourceDurationUs / speed.clamp(0.25, 4.0))
        .round()
        .clamp(minClipUs, 1 << 50);
    _replace(track, clip.copyWith(speed: speed, durationUs: newDuration));
    project.touch();
    return true;
  }

  static bool moveClip(
    Project project,
    String clipId, {
    required int timelineStartUs,
  }) {
    final track = project.trackOfClip(clipId);
    final clip = project.clipById(clipId);
    if (track == null || clip == null) return false;
    if (track.type == TrackType.video && track.sequential) return false;
    _replace(
      track,
      clip.copyWith(timelineStartUs: math.max(0, timelineStartUs)),
    );
    track.sortAudioClips();
    project.touch();
    return true;
  }

  /// Reorders a primary clip. The timeline re-sequences because primary video
  /// clips have no gaps.
  static bool reorderPrimaryClip(Project project, String clipId, int newIndex) {
    final track = project.primaryVideoTrack;
    final index = track.clips.indexWhere((Clip c) => c.id == clipId);
    if (index < 0) return false;
    final target = newIndex.clamp(0, track.clips.length - 1);
    if (target == index) return false;
    final clip = track.clips.removeAt(index);
    track.clips.insert(target, clip);
    project.touch();
    return true;
  }

  /// Merges adjacent primary clips that come from the same asset with
  /// contiguous source ranges and equal speed/volume. This is the honest
  /// definition of "merge" for this data model; otherwise the clips stay
  /// separate and export concatenates them.
  static bool canMergeWithNext(Project project, String clipId) {
    final track = project.primaryVideoTrack;
    final index = track.clips.indexWhere((Clip c) => c.id == clipId);
    if (index < 0 || index >= track.clips.length - 1) return false;
    final a = track.clips[index];
    final b = track.clips[index + 1];
    return a.assetId == b.assetId &&
        a.speed == b.speed &&
        a.volume == b.volume &&
        (a.sourceInUs + a.sourceDurationUs - b.sourceInUs).abs() < 50000 &&
        !b.transitionIn.isActive;
  }

  static bool mergeWithNext(Project project, String clipId) {
    if (!canMergeWithNext(project, clipId)) return false;
    final track = project.primaryVideoTrack;
    final index = track.clips.indexWhere((Clip c) => c.id == clipId);
    final a = track.clips[index];
    final b = track.clips[index + 1];
    track.clips[index] = a.copyWith(durationUs: a.durationUs + b.durationUs);
    track.clips.removeAt(index + 1);
    project.touch();
    return true;
  }

  static bool replaceClip(Project project, Clip updated) {
    final track = project.trackOfClip(updated.id);
    if (track == null) return false;
    _replace(track, updated);
    project.touch();
    return true;
  }

  static void _replace(Track track, Clip updated) {
    final index = track.clips.indexWhere((Clip c) => c.id == updated.id);
    if (index >= 0) track.clips[index] = updated;
  }
}
