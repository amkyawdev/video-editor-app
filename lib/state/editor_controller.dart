import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/models/clip.dart';
import '../data/models/export_settings.dart';
import '../data/models/media_asset.dart';
import '../data/models/project.dart';
import '../data/models/subtitle.dart';
import '../data/services/ffmpeg/media_probe_service.dart';
import '../data/services/subtitle/subtitle_formats.dart';
import 'app_services.dart';
import 'timeline_ops.dart';

class EditorController extends ChangeNotifier {
  EditorController({required this.project, required this.services})
    : _playhead = Duration.zero;

  final AppServices services;
  Project project;

  Duration _playhead;
  bool _playing = false;
  bool _dirty = false;
  bool _saving = false;
  bool _disposed = false;
  String? _selectedClipId;
  String? _selectedCueId;
  String? _selectedTrackId;
  Timer? _autosave;

  final List<String> _undoStack = <String>[];
  final List<String> _redoStack = <String>[];
  static const int _maxHistory = 40;

  Duration get playhead => _playhead;
  bool get isPlaying => _playing;
  bool get isDirty => _dirty;
  bool get isSaving => _saving;
  String? get selectedClipId => _selectedClipId;
  String? get selectedCueId => _selectedCueId;
  String? get selectedTrackId => _selectedTrackId;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  Duration get duration => project.duration;
  Clip? get selectedClip =>
      _selectedClipId == null ? null : project.clipById(_selectedClipId!);
  SubtitleCue? get selectedCue => _selectedCueId == null
      ? null
      : project.subtitles.cues.cast<SubtitleCue?>().firstWhere(
          (SubtitleCue? c) => c?.id == _selectedCueId,
          orElse: () => null,
        );
  MediaAsset? get selectedClipAsset {
    final clip = selectedClip;
    return clip == null ? null : project.assetFor(clip.assetId);
  }

  bool get canSplit {
    final clip = TimelineOps.clipAtPlayhead(project, _playhead);
    if (clip == null) return false;
    final track = project.primaryVideoTrack;
    final index = track.clips.indexWhere((Clip c) => c.id == clip.id);
    final startUs = track.startsUs[index];
    final offset = _playhead.inMicroseconds - startUs;
    return offset >= TimelineOps.minClipUs &&
        clip.durationUs - offset >= TimelineOps.minClipUs;
  }

  bool get canMergeSelected =>
      _selectedClipId != null &&
      TimelineOps.canMergeWithNext(project, _selectedClipId!);

  void selectClip(String? clipId) {
    _selectedClipId = clipId;
    if (clipId != null) {
      _selectedCueId = null;
      _selectedTrackId = project.trackOfClip(clipId)?.id;
    }
    _notify();
  }

  void selectCue(String? cueId) {
    _selectedCueId = cueId;
    if (cueId != null) _selectedClipId = null;
    _notify();
  }

  void setPlayhead(Duration position) {
    final total = duration;
    final clamped = TimeUtilsClamp.apply(position, total);
    if (clamped == _playhead) return;
    _playhead = clamped;
    _notify();
  }

  void setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    _notify();
  }

  void togglePlay() => setPlaying(!_playing);

  void _recordUndo() {
    _undoStack.add(project.toJsonString());
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _mutate(void Function() action) {
    _recordUndo();
    action();
    _dirty = true;
    _scheduleSave();
    _notify();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(project.toJsonString());
    project = Project.decode(_undoStack.removeLast());
    _dirty = true;
    _scheduleSave();
    _notify();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(project.toJsonString());
    project = Project.decode(_redoStack.removeLast());
    _dirty = true;
    _scheduleSave();
    _notify();
  }

  Future<MediaAsset> importMedia(File file) async {
    final asset = await services.importer.importIntoProject(
      source: file,
      project: project,
      repository: services.repository,
    );
    _dirty = true;
    _scheduleSave();
    _notify();
    return asset;
  }

  void addAssetToTimeline(MediaAsset asset, {bool overlay = false}) {
    _mutate(() {
      final clip = TimelineOps.addAsset(
        project,
        asset,
        overlay: overlay,
        timelineStartUs: _playhead.inMicroseconds,
      );
      if (clip != null) {
        _selectedClipId = clip.id;
        _selectedTrackId = project.trackOfClip(clip.id)?.id;
      }
    });
  }

  void splitAtPlayhead() {
    if (!canSplit) return;
    _mutate(() {
      if (TimelineOps.splitAt(project, _playhead)) {
        _selectedClipId = null;
      }
    });
  }

  void deleteSelectedClip() {
    final id = _selectedClipId;
    if (id == null) return;
    _mutate(() {
      TimelineOps.removeClip(project, id);
      _selectedClipId = null;
      _selectedTrackId = null;
    });
  }

  void mergeSelectedWithNext() {
    final id = _selectedClipId;
    if (id == null) return;
    _mutate(() => TimelineOps.mergeWithNext(project, id));
  }

  void trimSelectedStart(int deltaUs) {
    final id = _selectedClipId;
    if (id == null) return;
    _mutate(() => TimelineOps.trimStart(project, id, deltaUs));
  }

  void trimSelectedEnd(int deltaUs) {
    final id = _selectedClipId;
    if (id == null) return;
    _mutate(() => TimelineOps.trimEnd(project, id, deltaUs));
  }

  void setClipSpeed(double speed) {
    final id = _selectedClipId;
    if (id == null) return;
    _mutate(() => TimelineOps.setSpeed(project, id, speed));
  }

  void updateClip(Clip updated) {
    _mutate(() => TimelineOps.replaceClip(project, updated));
  }

  void moveClipTo(String clipId, int timelineStartUs) {
    _mutate(() {
      TimelineOps.moveClip(project, clipId, timelineStartUs: timelineStartUs);
    });
  }

  void reorderClip(String clipId, int newIndex) {
    _mutate(() => TimelineOps.reorderPrimaryClip(project, clipId, newIndex));
  }

  void addAudioTrack() {
    _mutate(() => project.addAudioTrack());
  }

  void addOverlayTrack() {
    _mutate(() => project.addVideoTrack());
  }

  void setTrackMuted(String trackId, bool muted) {
    _mutate(() {
      final track = project.trackById(trackId);
      track?.muted = muted;
    });
  }

  void setTrackVolume(String trackId, double volume) {
    _mutate(() {
      final track = project.trackById(trackId);
      track?.volume = volume.clamp(0.0, 2.0);
    });
  }

  void renameProject(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _mutate(() => project.name = trimmed);
  }

  void setCanvas({required int width, required int height, double? fps}) {
    _mutate(() {
      project.canvasWidth = width;
      project.canvasHeight = height;
      if (fps != null) project.fps = fps;
    });
  }

  void setExportSettings(ExportSettings settings) {
    _mutate(() => project.exportSettings = settings);
  }

  // Subtitle editing -------------------------------------------------------

  SubtitleCue addCueAtPlayhead({String text = 'New subtitle'}) {
    final cue = SubtitleCue.create(
      start: _playhead,
      end: _playhead + const Duration(seconds: 2),
      text: text,
    );
    _mutate(() {
      project.subtitles.cues.add(cue);
      project.subtitles.fixOverlaps();
    });
    _selectedCueId = cue.id;
    _notify();
    return cue;
  }

  void updateCue(SubtitleCue updated) {
    _mutate(() {
      final index = project.subtitles.cues.indexWhere(
        (SubtitleCue c) => c.id == updated.id,
      );
      if (index >= 0) project.subtitles.cues[index] = updated;
    });
  }

  void deleteCue(String id) {
    _mutate(() {
      project.subtitles.cues.removeWhere((SubtitleCue c) => c.id == id);
      if (_selectedCueId == id) _selectedCueId = null;
    });
  }

  void shiftCues(Duration offset) {
    _mutate(() => project.subtitles.shiftAll(offset));
  }

  void applySubtitleStyle(SubtitleStyle style) {
    _mutate(() => project.subtitles.style = style);
  }

  void replaceSubtitleDocument(
    SubtitleDocument document, {
    String? sourceName,
  }) {
    _mutate(() {
      document.style = project.subtitles.style;
      project.subtitles = document;
      project.subtitles.sourceName = sourceName;
      project.subtitles.fixOverlaps();
      _selectedCueId = document.cues.isEmpty ? null : document.cues.first.id;
    });
  }

  /// Imports .srt/.vtt by file name and parsed cue count. Any other extension is
  /// rejected by SubtitleFormats before this method touches the project.
  void importSubtitleText(String fileName, String content) {
    final cues = SubtitleFormats.parseOrThrow(fileName, content);
    final document = SubtitleDocument(
      cues: cues,
      style: project.subtitles.style,
      sourceName: fileName,
      language: SubtitleFormats.extensionOf(fileName) == 'vtt'
          ? project.subtitles.language
          : project.subtitles.language,
    );
    replaceSubtitleDocument(document, sourceName: fileName);
  }

  Future<String> exportSubtitles(SubtitleFormat format) async {
    final content = SubtitleFormats.encode(project.subtitles.cues, format);
    final safeName = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return services.repository.writeExport(
      project.id,
      '$safeName.${format.extension}',
      content,
    );
  }

  Future<String> exportSubtitleSidecar(SubtitleFormat format) =>
      exportSubtitles(format);

  Future<void> save() async {
    if (_saving) return;
    _saving = true;
    _notify();
    try {
      await services.repository.save(project);
      _dirty = false;
    } finally {
      _saving = false;
      _notify();
    }
  }

  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), () {
      if (!_disposed) unawaited(save());
    });
  }

  Future<void> flush() async {
    _autosave?.cancel();
    if (_dirty) await save();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autosave?.cancel();
    super.dispose();
  }

  static Future<MediaProbeResult> probeFor(File file, AppServices services) =>
      services.probe.probe(file.path);
}

abstract final class TimeUtilsClamp {
  static Duration apply(Duration value, Duration total) {
    if (value < Duration.zero) return Duration.zero;
    if (total > Duration.zero && value > total) return total;
    return value;
  }
}
