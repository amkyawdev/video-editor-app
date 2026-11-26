import 'dart:convert';
import 'dart:math' as math;

import '../../core/utils/ids.dart';
import 'clip.dart';
import 'export_settings.dart';
import 'media_asset.dart';
import 'subtitle.dart';
import 'track.dart';

class Project {
  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.tracks,
    required this.media,
    required this.subtitles,
    this.canvasWidth = 1920,
    this.canvasHeight = 1080,
    this.fps = 30,
    this.exportSettings = ExportSettings.defaults,
    this.coverPath,
  });

  factory Project.blank({
    String name = 'Untitled project',
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    double fps = 30,
  }) {
    final now = DateTime.now();
    return Project(
      id: newId('prj'),
      name: name,
      createdAt: now,
      updatedAt: now,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      fps: fps,
      tracks: <Track>[
        Track.video(),
        Track.audio(name: 'Audio 1'),
      ],
      media: <MediaAsset>[],
      subtitles: SubtitleDocument(),
    );
  }

  String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;
  int canvasWidth;
  int canvasHeight;
  double fps;
  List<Track> tracks;
  List<MediaAsset> media;
  SubtitleDocument subtitles;
  ExportSettings exportSettings;
  String? coverPath;

  List<Track> get videoTracks =>
      tracks.where((Track t) => t.type == TrackType.video).toList();

  List<Track> get audioTracks =>
      tracks.where((Track t) => t.type == TrackType.audio).toList();

  Track get primaryVideoTrack => videoTracks.first;

  List<Track> get overlayVideoTracks => videoTracks.skip(1).toList();

  double get aspectRatio => canvasWidth / canvasHeight;

  MediaAsset? assetFor(String assetId) {
    for (final asset in media) {
      if (asset.id == assetId) return asset;
    }
    return null;
  }

  List<Clip> get primaryClips => primaryVideoTrack.clips;

  int get videoDurationUs => primaryVideoTrack.durationUs;

  int get durationUs {
    var end = videoDurationUs;
    for (final track in audioTracks) {
      end = math.max(end, track.durationUs);
    }
    for (final track in overlayVideoTracks) {
      end = math.max(end, track.durationUs);
    }
    end = math.max(end, subtitles.durationUs);
    return end;
  }

  Duration get duration => Duration(microseconds: durationUs);

  int get totalClips =>
      tracks.fold<int>(0, (int sum, Track t) => sum + t.clips.length);

  int get totalMediaBytes =>
      media.fold<int>(0, (int sum, MediaAsset m) => sum + m.sizeBytes);

  Track? trackById(String trackId) {
    for (final track in tracks) {
      if (track.id == trackId) return track;
    }
    return null;
  }

  Clip? clipById(String clipId) {
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  Track? trackOfClip(String clipId) {
    for (final track in tracks) {
      if (track.clips.any((Clip c) => c.id == clipId)) return track;
    }
    return null;
  }

  /// The primary clip under the playhead, if any.
  Clip? primaryClipAt(Duration position) =>
      primaryVideoTrack.clipAt(position.inMicroseconds);

  Track addAudioTrack() {
    final track = Track.audio(name: 'Audio ${audioTracks.length + 1}');
    tracks.add(track);
    return track;
  }

  Track addVideoTrack() {
    final track = Track.video(
      name: 'Overlay ${videoTracks.length}',
      sequential: false,
    );
    tracks.insert(videoTracks.length, track);
    return track;
  }

  void touch() => updatedAt = DateTime.now();

  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema': 1,
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'canvasWidth': canvasWidth,
    'canvasHeight': canvasHeight,
    'fps': fps,
    'tracks': tracks.map((Track t) => t.toJson()).toList(),
    'media': media.map((MediaAsset m) => m.toJson()).toList(),
    'subtitles': subtitles.toJson(),
    'exportSettings': exportSettings.toJson(),
    if (coverPath != null) 'coverPath': coverPath,
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    final tracks = (json['tracks'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => Track.fromJson(e as Map<String, dynamic>))
        .toList();
    if (tracks.every((Track t) => t.type != TrackType.video)) {
      tracks.insert(0, Track.video());
    }
    return Project(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled project',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      canvasWidth: (json['canvasWidth'] as num?)?.toInt() ?? 1920,
      canvasHeight: (json['canvasHeight'] as num?)?.toInt() ?? 1080,
      fps: (json['fps'] as num?)?.toDouble() ?? 30,
      tracks: tracks,
      media: (json['media'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => MediaAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtitles: SubtitleDocument.fromJson(
        json['subtitles'] as Map<String, dynamic>?,
      ),
      exportSettings: ExportSettings.fromJson(
        json['exportSettings'] as Map<String, dynamic>?,
      ),
      coverPath: json['coverPath'] as String?,
    );
  }

  factory Project.decode(String raw) =>
      Project.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  Project clone() =>
      Project.fromJson(jsonDecode(toJsonString()) as Map<String, dynamic>);
}

/// Lightweight record used by the project browser without loading every
/// project's full timeline.
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.durationUs,
    required this.clipCount,
    required this.cueCount,
    this.coverPath,
    this.canvasWidth = 1920,
    this.canvasHeight = 1080,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
  final int durationUs;
  final int clipCount;
  final int cueCount;
  final String? coverPath;
  final int canvasWidth;
  final int canvasHeight;

  factory ProjectSummary.fromProject(Project project) => ProjectSummary(
    id: project.id,
    name: project.name,
    updatedAt: project.updatedAt,
    durationUs: project.durationUs,
    clipCount: project.totalClips,
    cueCount: project.subtitles.cueCount,
    coverPath: project.coverPath,
    canvasWidth: project.canvasWidth,
    canvasHeight: project.canvasHeight,
  );
}
