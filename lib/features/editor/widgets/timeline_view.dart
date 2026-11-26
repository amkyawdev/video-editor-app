import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/clip.dart';
import '../../../data/models/subtitle.dart';
import '../../../data/models/track.dart';
import '../../../state/editor_controller.dart';
import '../../../widgets/common.dart';

class TimelineView extends StatefulWidget {
  const TimelineView({super.key, this.onCueTap});

  final void Function(SubtitleCue cue)? onCueTap;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  static const double _rulerHeight = 26;
  static const double _videoLaneHeight = 62;
  static const double _overlayLaneHeight = 48;
  static const double _audioLaneHeight = 44;
  static const double _subtitleLaneHeight = 34;
  static const double _laneGap = 6;
  static const double _leading = 58;

  final ScrollController _scroll = ScrollController();
  double _pps = 54;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _laneHeight(Track track) => switch (track.type) {
    TrackType.video => track.sequential ? _videoLaneHeight : _overlayLaneHeight,
    TrackType.audio => _audioLaneHeight,
    TrackType.subtitle => _subtitleLaneHeight,
  };

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final project = editor.project;
    final tracks = <Track>[...project.videoTracks, ...project.audioTracks];
    final durationSeconds = math.max(
      editor.duration.inMilliseconds / 1000,
      6.0,
    );
    final contentWidth = durationSeconds * _pps + 80;
    final laneTotal =
        tracks.fold<double>(
          0,
          (double sum, Track t) => sum + _laneHeight(t) + _laneGap,
        ) +
        _subtitleLaneHeight +
        _laneGap;
    final contentHeight = _rulerHeight + laneTotal;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limits) {
        final available = limits.maxHeight.isFinite
            ? (limits.maxHeight - 34).clamp(60.0, 300.0)
            : 300.0;
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(top: BorderSide(color: AppColors.stroke)),
          ),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 4),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.view_timeline_outlined,
                      size: 15,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'TIMELINE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${TimeUtils.timecode(editor.duration)} · '
                      '${project.totalClips} clips',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    _ZoomButton(
                      icon: Icons.remove_rounded,
                      onTap: () =>
                          setState(() => _pps = (_pps / 1.4).clamp(10, 220)),
                    ),
                    Text(
                      '${_pps.round()} px/s',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        fontFamily: AppFonts.mono,
                      ),
                    ),
                    _ZoomButton(
                      icon: Icons.add_rounded,
                      onTap: () =>
                          setState(() => _pps = (_pps * 1.4).clamp(10, 220)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: math.min(contentHeight + 4, available),
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    width: contentWidth,
                    height: contentHeight,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (TapDownDetails details) {
                              final seconds =
                                  (details.localPosition.dx - _leading) / _pps;
                              editor.setPlayhead(
                                Duration(
                                  milliseconds: (seconds * 1000).round().clamp(
                                    0,
                                    editor.duration.inMilliseconds,
                                  ),
                                ),
                              );
                            },
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _TimelinePainter(
                              durationSeconds: durationSeconds,
                              pps: _pps,
                              leading: _leading,
                              trackHeights: <double>[
                                for (final track in tracks) _laneHeight(track),
                                _subtitleLaneHeight,
                              ],
                              rulerHeight: _rulerHeight,
                              laneGap: _laneGap,
                            ),
                          ),
                        ),
                        ..._laneWidgets(editor, tracks, contentWidth),
                        _playhead(editor),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _laneWidgets(
    EditorController editor,
    List<Track> tracks,
    double contentWidth,
  ) {
    final widgets = <Widget>[];
    var top = _rulerHeight;
    for (final track in tracks) {
      final height = _laneHeight(track);
      widgets.add(
        Positioned(
          left: 0,
          top: top,
          width: contentWidth,
          height: height,
          child: _lane(editor, track, height),
        ),
      );
      top += height + _laneGap;
    }
    widgets.add(
      Positioned(
        left: 0,
        top: top,
        width: contentWidth,
        height: _subtitleLaneHeight,
        child: _subtitleLane(editor),
      ),
    );
    return widgets;
  }

  Widget _lane(EditorController editor, Track track, double height) {
    final starts = track.startsUs;
    return Stack(
      children: <Widget>[
        Positioned(
          left: _leading,
          right: 12,
          top: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: track.type == TrackType.audio
                  ? AppColors.alpha(AppColors.mint, 0.05)
                  : AppColors.alpha(Colors.white, 0.025),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.strokeSoft),
            ),
          ),
        ),
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          width: _leading - 12,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                track.type == TrackType.audio
                    ? 'AUD'
                    : track.sequential
                    ? 'VID'
                    : 'OVR',
                style: const TextStyle(
                  fontSize: 8,
                  color: AppColors.textMuted,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < track.clips.length; i++)
          _clipTile(editor, track, track.clips[i], starts[i], height),
      ],
    );
  }

  Widget _clipTile(
    EditorController editor,
    Track track,
    Clip clip,
    int startUs,
    double laneHeight,
  ) {
    final asset = editor.project.assetFor(clip.assetId);
    final left = _leading + startUs / 1000000 * _pps;
    final width = math.max(clip.durationUs / 1000000 * _pps, 14.0);
    final selected = editor.selectedClipId == clip.id;
    return Positioned(
      left: left,
      top: 4,
      width: width,
      height: laneHeight - 8,
      child: GestureDetector(
        onTap: () => editor.selectClip(clip.id),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.stroke,
              width: selected ? 1.6 : 1,
            ),
          ),
          clipBehavior: ui.Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (asset != null && asset.isVisual)
                ThumbnailImage(path: asset.thumbnailPath),
              if (asset != null && asset.isAudio && asset.waveformPath != null)
                Opacity(
                  opacity: 0.6,
                  child: Image.file(
                    File(asset.waveformPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      AppColors.alpha(Colors.black, 0.05),
                      AppColors.alpha(Colors.black, 0.65),
                    ],
                  ),
                ),
              ),
              if (clip.transitionIn.isActive)
                Positioned(
                  left: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.alpha(AppColors.violet, 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'fx',
                      style: TextStyle(
                        fontSize: 7,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (width > 46)
                Positioned(
                  left: 5,
                  right: 3,
                  bottom: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        clip.label ?? asset?.name ?? 'Clip',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 3),
                          ],
                        ),
                      ),
                      if (laneHeight > 50)
                        Text(
                          '${TimeUtils.compact(clip.duration)}'
                          '${clip.speed != 1 ? ' · ${clip.speed}x' : ''}',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textSecondary,
                            fontFamily: AppFonts.mono,
                            shadows: <Shadow>[
                              Shadow(color: Colors.black, blurRadius: 3),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subtitleLane(EditorController editor) {
    return Stack(
      children: <Widget>[
        Positioned(
          left: _leading,
          right: 12,
          top: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.alpha(AppColors.violet, 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.strokeSoft),
            ),
          ),
        ),
        const Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          width: _leading - 12,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'SUB',
              style: TextStyle(
                fontSize: 8,
                letterSpacing: 1,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
        for (final cue in editor.project.subtitles.cues)
          Positioned(
            left: _leading + cue.startUs / 1000000 * _pps,
            top: 4,
            width: math.max(cue.durationUs / 1000000 * _pps, 10.0),
            height: _subtitleLaneHeight - 8,
            child: GestureDetector(
              onTap: () {
                editor.selectCue(cue.id);
                editor.setPlayhead(cue.start);
                widget.onCueTap?.call(cue);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: editor.selectedCueId == cue.id
                      ? AppColors.alpha(AppColors.violet, 0.45)
                      : AppColors.alpha(AppColors.violet, 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: editor.selectedCueId == cue.id
                        ? AppColors.violet
                        : AppColors.alpha(AppColors.violet, 0.3),
                  ),
                ),
                child: Text(
                  cue.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.textPrimary,
                    fontFamily: AppFonts.myanmar,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _playhead(EditorController editor) {
    final left = _leading + editor.playhead.inMilliseconds / 1000 * _pps;
    return Positioned(
      left: left - 6,
      top: _rulerHeight - 8,
      bottom: 0,
      width: 12,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          final seconds = (details.localPosition.dx + 6) / _pps;
          editor.setPlayhead(
            Duration(
              milliseconds: (seconds * 1000).round().clamp(
                0,
                editor.duration.inMilliseconds,
              ),
            ),
          );
        },
        child: Column(
          children: <Widget>[
            Container(
              width: 12,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: Container(width: 2, color: AppColors.accent)),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 15, color: AppColors.textSecondary),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.durationSeconds,
    required this.pps,
    required this.leading,
    required this.trackHeights,
    required this.rulerHeight,
    required this.laneGap,
  });

  final double durationSeconds;
  final double pps;
  final double leading;
  final List<double> trackHeights;
  final double rulerHeight;
  final double laneGap;

  @override
  void paint(Canvas canvas, Size size) {
    final lanePaint = Paint()..color = AppColors.strokeSoft;
    var top = rulerHeight;
    for (final height in trackHeights) {
      canvas.drawLine(
        Offset(leading, top - laneGap / 2),
        Offset(size.width - 12, top - laneGap / 2),
        lanePaint,
      );
      top += height + laneGap;
    }

    final step = _tickStep();
    final tickPaint = Paint()
      ..color = AppColors.stroke
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(
      color: AppColors.textMuted,
      fontSize: 9,
      fontFamily: AppFonts.mono,
    );
    for (var second = 0.0; second <= durationSeconds; second += step) {
      final x = leading + second * pps;
      final major = (second / step).round() % 5 == 0;
      canvas.drawLine(
        Offset(x, rulerHeight - (major ? 10 : 5)),
        Offset(x, rulerHeight),
        tickPaint,
      );
      if (major) {
        final label = TimeUtils.timecode(
          Duration(milliseconds: (second * 1000).round()),
          withMillis: false,
          padHours: false,
        );
        final painter = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x + 3, 2));
      }
    }
  }

  double _tickStep() {
    if (pps >= 140) return 1;
    if (pps >= 70) return 2;
    if (pps >= 35) return 5;
    if (pps >= 16) return 10;
    return 30;
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.pps != pps ||
      oldDelegate.durationSeconds != durationSeconds ||
      oldDelegate.trackHeights.length != trackHeights.length;
}
