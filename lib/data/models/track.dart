import 'dart:math' as math;

import '../../core/utils/ids.dart';
import 'clip.dart';

enum TrackType { video, audio, subtitle }

/// A lane on the timeline. Video tracks are laid out sequentially; audio tracks
/// place clips at an explicit timeline offset.
class Track {
  Track({
    required this.id,
    required this.type,
    required this.name,
    this.muted = false,
    this.locked = false,
    this.hidden = false,
    this.volume = 1,
    this.sequential = true,
    List<Clip>? clips,
  }) : clips = clips ?? <Clip>[];

  factory Track.video({String name = 'Video 1', bool sequential = true}) =>
      Track(
        id: newId('trk'),
        type: TrackType.video,
        name: name,
        sequential: sequential,
      );

  factory Track.audio({String name = 'Audio 1'}) =>
      Track(id: newId('trk'), type: TrackType.audio, name: name);

  final String id;
  final TrackType type;
  String name;
  bool muted;
  bool locked;
  bool hidden;
  double volume;

  /// Primary video lanes are laid out end to end. Overlay video lanes keep the
  /// explicit offset of each clip.
  bool sequential;
  final List<Clip> clips;

  bool get isVideo => type == TrackType.video;
  bool get isAudio => type == TrackType.audio;

  /// Primary video lanes are sequenced. Additional video lanes are overlays
  /// that keep their explicit start offsets.
  bool get isSequential => type == TrackType.video && clips.isNotEmpty;

  List<int> get startsUs {
    final starts = <int>[];
    var cursor = 0;
    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      if (type == TrackType.video && sequential) {
        if (i > 0 && clip.transitionIn.isActive) {
          cursor = math.max(0, cursor - clip.transitionIn.durationUs);
        }
        starts.add(cursor);
        cursor += clip.durationUs;
      } else {
        starts.add(clip.timelineStartUs);
      }
    }
    return starts;
  }

  int get durationUs {
    if (clips.isEmpty) return 0;
    final starts = startsUs;
    var end = 0;
    for (var i = 0; i < clips.length; i++) {
      end = math.max(end, starts[i] + clips[i].durationUs);
    }
    return end;
  }

  int startOf(Clip clip) {
    final index = clips.indexWhere((Clip c) => c.id == clip.id);
    if (index < 0) return clip.timelineStartUs;
    return startsUs[index];
  }

  Clip? clipAt(int timelineUs) {
    final starts = startsUs;
    for (var i = 0; i < clips.length; i++) {
      if (timelineUs >= starts[i] &&
          timelineUs < starts[i] + clips[i].durationUs) {
        return clips[i];
      }
    }
    return null;
  }

  /// Re-sequences an overlay/audio lane when clips are moved.
  void sortAudioClips() {
    if (type != TrackType.audio) return;
    clips.sort(
      (Clip a, Clip b) => a.timelineStartUs.compareTo(b.timelineStartUs),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'name': name,
    'muted': muted,
    'locked': locked,
    'hidden': hidden,
    'volume': volume,
    'sequential': sequential,
    'clips': clips.map((Clip c) => c.toJson()).toList(),
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    type: TrackType.values.firstWhere(
      (TrackType t) => t.name == json['type'],
      orElse: () => TrackType.video,
    ),
    name: json['name'] as String? ?? 'Track',
    muted: json['muted'] as bool? ?? false,
    locked: json['locked'] as bool? ?? false,
    hidden: json['hidden'] as bool? ?? false,
    volume: (json['volume'] as num?)?.toDouble() ?? 1,
    sequential: json['sequential'] as bool? ?? true,
    clips: (json['clips'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => Clip.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
