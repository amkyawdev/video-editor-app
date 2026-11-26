import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/clip.dart';
import '../../../data/models/media_asset.dart';
import '../../../data/models/subtitle.dart';
import '../../../data/models/track.dart';
import '../../../state/editor_controller.dart';

/// Preview is best-effort: the primary video clip plus the audio clip under the
/// playhead are played in sync. Overlay lanes and multi-track mixing are
/// rendered authoritatively by FFmpeg on export.
class PreviewStage extends StatefulWidget {
  const PreviewStage({super.key});

  @override
  State<PreviewStage> createState() => _PreviewStageState();
}

class _PreviewStageState extends State<PreviewStage> {
  VideoPlayerController? _video;
  VideoPlayerController? _audio;
  String? _videoClipId;
  String? _audioClipId;
  Timer? _ticker;
  bool _initializing = false;
  String? _error;
  EditorController? _editor;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editor = context.read<EditorController>();
      _editor = editor;
      editor.addListener(_onEditorChanged);
      _sync(force: true);
    });
  }

  @override
  void dispose() {
    _editor?.removeListener(_onEditorChanged);
    _ticker?.cancel();
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    final editor = _editor;
    if (editor == null || !mounted) return;
    if (editor.isPlaying != _wasPlaying) {
      _wasPlaying = editor.isPlaying;
      if (editor.isPlaying) {
        _startTicker();
        _video?.play();
        _audio?.play();
      } else {
        _ticker?.cancel();
        _video?.pause();
        _audio?.pause();
      }
    }
    _sync();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 120), (_) => _tick());
  }

  Future<void> _tick() async {
    final editor = _editor;
    final controller = _video;
    if (editor == null || controller == null || !mounted) return;
    if (!controller.value.isInitialized) return;
    final clip = editor.project.clipById(_videoClipId ?? '');
    if (clip == null) return;
    final track = editor.project.primaryVideoTrack;
    final startUs = track.startOf(clip);
    final sourcePosition = controller.value.position;
    final elapsedUs =
        (sourcePosition.inMicroseconds - clip.sourceInUs) / clip.speed;
    final timelineUs = startUs + elapsedUs;
    if (timelineUs >= startUs + clip.durationUs - 40000) {
      final next = _nextClip(clip);
      editor.setPlayhead(Duration(microseconds: startUs + clip.durationUs));
      if (next == null) {
        editor.setPlaying(false);
        return;
      }
      await _sync(force: true);
      return;
    }
    if (timelineUs >= 0) {
      editor.setPlayhead(Duration(microseconds: timelineUs.round()));
    }
  }

  Clip? _nextClip(Clip clip) {
    final clips = _editor?.project.primaryVideoTrack.clips ?? <Clip>[];
    final index = clips.indexWhere((Clip c) => c.id == clip.id);
    if (index < 0 || index >= clips.length - 1) return null;
    return clips[index + 1];
  }

  Future<void> _sync({bool force = false}) async {
    final editor = _editor;
    if (editor == null || !mounted) return;
    final playheadUs = editor.playhead.inMicroseconds;
    final project = editor.project;
    final primary = project.primaryVideoTrack;
    final clip = primary.clipAt(playheadUs);
    if (clip == null) {
      await _disposeVideo();
      await _disposeAudio();
      return;
    }
    final asset = project.assetFor(clip.assetId);
    if (asset == null || !asset.isVisual) {
      await _disposeVideo();
    } else if (_videoClipId != clip.id) {
      await _loadVideo(clip, asset);
    }
    final video = _video;
    if (video != null && video.value.isInitialized) {
      final startUs = primary.startOf(clip);
      final targetUs =
          clip.sourceInUs + ((playheadUs - startUs) * clip.speed).round();
      final drift = (video.value.position.inMicroseconds - targetUs).abs();
      if (force || drift > 400000) {
        await video.seekTo(Duration(microseconds: targetUs.clamp(0, 1 << 50)));
      }
      await video.setVolume(clip.muted ? 0 : clip.volume.clamp(0, 1));
    }
    await _syncAudio(playheadUs);
  }

  Future<void> _loadVideo(Clip clip, MediaAsset asset) async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    await _disposeVideo();
    final controller = VideoPlayerController.file(File(asset.path));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setPlaybackSpeed(clip.speed);
      final primary = _editor!.project.primaryVideoTrack;
      final startUs = primary.startOf(clip);
      final targetUs =
          clip.sourceInUs +
          ((_editor!.playhead.inMicroseconds - startUs) * clip.speed).round();
      await controller.seekTo(
        Duration(microseconds: targetUs.clamp(0, 1 << 50)),
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _videoClipId = clip.id;
        _initializing = false;
      });
      if (_editor?.isPlaying ?? false) await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _video = null;
        _videoClipId = clip.id;
        _initializing = false;
        _error =
            'This video cannot be previewed on this device. '
            'FFmpeg export may still work.';
      });
    }
  }

  Future<void> _disposeVideo() async {
    final old = _video;
    _video = null;
    _videoClipId = null;
    if (old != null) await old.dispose();
  }

  Future<void> _syncAudio(int playheadUs) async {
    final editor = _editor!;
    Clip? active;
    Track? activeTrack;
    for (final track in editor.project.audioTracks) {
      if (track.muted) continue;
      for (final clip in track.clips) {
        if (playheadUs >= clip.timelineStartUs && playheadUs < clip.endUs) {
          active = clip;
          activeTrack = track;
          break;
        }
      }
      if (active != null) break;
    }
    if (active == null) {
      await _disposeAudio();
      return;
    }
    if (_audioClipId == active.id) return;
    final asset = editor.project.assetFor(active.assetId);
    if (asset == null) return;
    await _disposeAudio();
    final controller = VideoPlayerController.file(File(asset.path));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(
        (active.effectiveVolume * activeTrack!.volume).clamp(0, 1),
      );
      await controller.seekTo(
        Duration(
          microseconds:
              active.sourceInUs +
              ((playheadUs - active.timelineStartUs) * active.speed).round(),
        ),
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _audio = controller;
        _audioClipId = active!.id;
      });
      if (editor.isPlaying) await controller.play();
    } catch (_) {
      await controller.dispose();
    }
  }

  Future<void> _disposeAudio() async {
    final old = _audio;
    _audio = null;
    _audioClipId = null;
    if (old != null) await old.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final project = editor.project;
    final subtitle = project.subtitles.activeAt(editor.playhead);
    final hasOverlay = project.overlayVideoTracks.any(
      (Track t) => t.clips.isNotEmpty,
    );

    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: project.aspectRatio,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.stageGradient,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.stroke),
                ),
                clipBehavior: ui.Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Center(child: _stageContent(editor)),
                    if (subtitle != null)
                      _SubtitleOverlay(
                        cue: subtitle,
                        style: project.subtitles.style,
                        canvasHeight: project.canvasHeight,
                      ),
                    if (_initializing)
                      const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    if (hasOverlay)
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: _Badge(
                          text: 'Overlay tracks show on export',
                          color: AppColors.violet,
                        ),
                      ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _Badge(
                        text:
                            '${project.canvasWidth}x${project.canvasHeight} · '
                            '${project.fps.round()} fps',
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _transport(editor),
      ],
    );
  }

  Widget _stageContent(EditorController editor) {
    final video = _video;
    if (video != null && video.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: video.value.size.width,
          height: video.value.size.height,
          child: VideoPlayer(video),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.videocam_off_outlined,
              color: AppColors.textMuted,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }
    if (editor.project.primaryClips.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.movie_creation_outlined,
              color: AppColors.textMuted,
              size: 28,
            ),
            SizedBox(height: 8),
            Text(
              'Import media, then add it to the timeline',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _transport(EditorController editor) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () =>
              editor.setPlayhead(editor.playhead - const Duration(seconds: 5)),
          icon: const Icon(Icons.replay_5_rounded),
          color: AppColors.textSecondary,
        ),
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            gradient: AppColors.accentGradient,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: editor.project.primaryClips.isEmpty
                ? null
                : editor.togglePlay,
            icon: Icon(
              editor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: const Color(0xFF1A1204),
            ),
          ),
        ),
        IconButton(
          onPressed: () =>
              editor.setPlayhead(editor.playhead + const Duration(seconds: 5)),
          icon: const Icon(Icons.forward_5_rounded),
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${TimeUtils.timecode(editor.playhead)}  /  '
            '${TimeUtils.timecode(editor.duration)}',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        IconButton(
          onPressed: editor.canSplit ? editor.splitAtPlayhead : null,
          icon: const Icon(Icons.content_cut_rounded),
          tooltip: 'Split at playhead',
          color: editor.canSplit ? AppColors.accent : AppColors.textMuted,
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.alpha(Colors.black, 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.alpha(Colors.white, 0.08)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({
    required this.cue,
    required this.style,
    required this.canvasHeight,
  });

  final SubtitleCue cue;
  final SubtitleStyle style;
  final int canvasHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final height = constraints.maxHeight;
        final factor = height / (canvasHeight <= 0 ? 1080 : canvasHeight);
        final family = style.fontFamily == 'NotoSansMyanmar'
            ? AppFonts.myanmar
            : style.fontFamily == 'JetBrainsMono'
            ? AppFonts.mono
            : AppFonts.ui;
        final fontSize = style.fontSize * factor;
        final fill = TextStyle(
          fontFamily: family,
          fontSize: fontSize,
          height: style.lineHeight,
          fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: style.letterSpacing,
          color: Color(style.primaryColor),
        );
        final stroke = TextStyle(
          fontFamily: family,
          fontSize: fontSize,
          height: style.lineHeight,
          fontWeight: fill.fontWeight,
          fontStyle: fill.fontStyle,
          letterSpacing: style.letterSpacing,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.outlineWidth * factor * 2
            ..color = Color(style.outlineColor),
        );
        final alignment = switch (style.alignment) {
          SubtitleAlignment.bottom => Alignment.bottomCenter,
          SubtitleAlignment.center => Alignment.center,
          SubtitleAlignment.top => Alignment.topCenter,
        };
        final marginV = style.marginVertical / 100 * height;
        return Align(
          alignment: alignment,
          child: Padding(
            padding: EdgeInsets.only(
              left: constraints.maxWidth * style.marginHorizontal / 100,
              right: constraints.maxWidth * style.marginHorizontal / 100,
              top: style.alignment == SubtitleAlignment.top ? marginV : 0,
              bottom: style.alignment == SubtitleAlignment.bottom ? marginV : 0,
            ),
            child: Container(
              padding: style.hasBackground
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                  : EdgeInsets.zero,
              decoration: style.hasBackground
                  ? BoxDecoration(
                      color: Color(style.backgroundColor),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Stack(
                children: <Widget>[
                  if (style.outlineWidth > 0)
                    Text(cue.text, textAlign: TextAlign.center, style: stroke),
                  Text(cue.text, textAlign: TextAlign.center, style: fill),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
