import 'dart:math' as math;

import '../../../core/utils/time_utils.dart';
import '../../models/clip.dart';
import '../../models/export_settings.dart';
import '../../models/media_asset.dart';
import '../../models/project.dart';
import 'ffmpeg_capabilities.dart';

class ExportException implements Exception {
  ExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ExportSeverity { info, warning, blocking }

class ExportIssue {
  const ExportIssue(this.message, [this.severity = ExportSeverity.warning]);

  final String message;
  final ExportSeverity severity;

  bool get isBlocking => severity == ExportSeverity.blocking;

  @override
  String toString() => '${severity.name}: $message';
}

class ExportPlan {
  const ExportPlan({
    required this.args,
    required this.duration,
    required this.outputPath,
    required this.filterGraph,
    required this.issues,
    required this.hasAudio,
    required this.burnsSubtitles,
    required this.embedsSubtitles,
  });

  final List<String> args;
  final Duration duration;
  final String outputPath;
  final String filterGraph;
  final List<ExportIssue> issues;
  final bool hasAudio;
  final bool burnsSubtitles;
  final bool embedsSubtitles;

  String get commandPreview => 'ffmpeg ${args.join(' ')}';
}

class _ClipRender {
  const _ClipRender({
    required this.clip,
    required this.asset,
    required this.inputIndex,
    required this.durationUs,
  });

  final Clip clip;
  final MediaAsset asset;
  final int inputIndex;
  final int durationUs;
}

class _Segment {
  _Segment(this.clips, this.transitionToNext);

  final List<_ClipRender> clips;
  final TransitionSpec? transitionToNext;
}

/// Translates the project timeline into one FFmpeg argument list. Kept free of
/// platform channels so the command can be unit tested.
class ExportCommandBuilder {
  const ExportCommandBuilder();

  ExportPlan build({
    required Project project,
    required ExportSettings settings,
    required String outputPath,
    String? burnedSubtitlePath,
    String? softSubtitlePath,
    String? fontsDir,
    bool subtitleFilterAvailable = true,
    FfmpegCapabilities? capabilities,
  }) {
    final primary = project.primaryVideoTrack;
    if (primary.clips.isEmpty) {
      throw ExportException('Add at least one clip to the video track first.');
    }

    final issues = ExportValidator.validate(
      project: project,
      settings: settings,
      capabilities: capabilities,
    );
    final blocking = issues.where((ExportIssue i) => i.isBlocking).toList();
    if (blocking.isNotEmpty) {
      throw ExportException(blocking.first.message);
    }

    final width = settings.targetWidth(
      project.canvasWidth,
      project.canvasHeight,
    );
    final height = settings.targetHeight(project.canvasHeight);
    final fps = settings.targetFps(project.fps);
    final totalUs = math.max(project.durationUs, primary.durationUs);
    final total = Duration(microseconds: totalUs);

    final wantBurn =
        settings.subtitleMode == SubtitleExportMode.burnIn &&
        project.subtitles.cues.isNotEmpty;
    final wantSoft =
        settings.subtitleMode == SubtitleExportMode.soft &&
        project.subtitles.cues.isNotEmpty;
    if (wantBurn &&
        (burnedSubtitlePath == null || burnedSubtitlePath.isEmpty)) {
      throw ExportException('Burn-in needs a generated ASS subtitle file.');
    }
    if (wantBurn && !subtitleFilterAvailable) {
      throw ExportException(
        'This FFmpeg build has no libass subtitles filter, so burn-in is '
        'unavailable. Choose a soft subtitle track instead.',
      );
    }
    if (wantSoft && (softSubtitlePath == null || softSubtitlePath.isEmpty)) {
      throw ExportException('Soft subtitles need a subtitle sidecar file.');
    }
    if (settings.subtitleMode == SubtitleExportMode.burnIn &&
        project.subtitles.cues.isEmpty) {
      issues.add(
        const ExportIssue(
          'No subtitle cues: exporting without subtitles.',
          ExportSeverity.info,
        ),
      );
    }

    final args = <String>[];
    final filters = <String>[];
    var inputCount = 0;

    // Inputs: primary clips, overlay clips, audio-track clips, soft subtitles.
    final primaryRenders = <_ClipRender>[];
    for (final clip in primary.clips) {
      final asset = _requireAsset(project, clip);
      args.addAll(_inputArgs(asset, clip, fps));
      primaryRenders.add(
        _ClipRender(
          clip: clip,
          asset: asset,
          inputIndex: inputCount++,
          durationUs: clip.durationUs,
        ),
      );
    }

    final overlayRenders = <_ClipRender>[];
    final overlayStarts = <String, int>{};
    for (final track in project.overlayVideoTracks) {
      if (track.hidden) continue;
      for (final clip in track.clips) {
        final asset = _requireAsset(project, clip);
        args.addAll(_inputArgs(asset, clip, fps));
        overlayStarts[clip.id] = track.startOf(clip);
        overlayRenders.add(
          _ClipRender(
            clip: clip,
            asset: asset,
            inputIndex: inputCount++,
            durationUs: clip.durationUs,
          ),
        );
      }
    }

    final includeAudio = settings.audioCodec != ExportAudioCodec.none;
    final audioRenders = <_ClipRender>[];
    if (includeAudio) {
      for (final track in project.audioTracks) {
        if (track.muted) continue;
        for (final clip in track.clips) {
          final asset = _requireAsset(project, clip);
          args.addAll(_inputArgs(asset, clip, fps));
          audioRenders.add(
            _ClipRender(
              clip: clip,
              asset: asset,
              inputIndex: inputCount++,
              durationUs: clip.durationUs,
            ),
          );
        }
      }
    }

    var softInputIndex = -1;
    if (wantSoft) {
      softInputIndex = inputCount++;
      args.addAll(<String>['-i', softSubtitlePath!]);
    }

    // Per-clip video chains.
    for (final render in primaryRenders) {
      filters.add(
        _videoChain(
          render: render,
          label: 'v${render.inputIndex}',
          width: width,
          height: height,
          fps: fps,
        ),
      );
    }
    for (final render in overlayRenders) {
      filters.add(
        _overlayChain(
          render: render,
          label: 'ov${render.inputIndex}',
          width: width,
          height: height,
          fps: fps,
          startUs: overlayStarts[render.clip.id] ?? 0,
        ),
      );
    }

    // Join the primary clips, honouring transitions.
    final segments = _segments(primaryRenders, primary.clips);
    var videoLabel = _joinVideoSegments(segments, filters, 'vmain');

    // Composite overlays.
    var overlayIndex = 0;
    for (final render in overlayRenders) {
      final startUs = overlayStarts[render.clip.id] ?? 0;
      final start = TimeUtils.ffmpegSeconds(Duration(microseconds: startUs));
      final end = TimeUtils.ffmpegSeconds(
        Duration(microseconds: startUs + render.durationUs),
      );
      final geometry = _overlayGeometry(render.clip, width, height);
      final label = 'vc${overlayIndex++}';
      filters.add(
        '[$videoLabel][ov${render.inputIndex}]overlay='
        'x=${geometry.x}:y=${geometry.y}:'
        "enable='between(t,$start,$end)':eof_action=pass[$label]",
      );
      videoLabel = label;
    }

    // Audio chains, mixing and track volume.
    String? audioLabel;
    if (includeAudio) {
      final mainAudio = _joinPrimaryAudio(
        primaryRenders,
        segments,
        filters,
        project,
        'amain',
      );
      final extras = <String>[];
      for (var i = 0; i < audioRenders.length; i++) {
        final render = audioRenders[i];
        final track = project.trackOfClip(render.clip.id);
        final startUs =
            track?.startOf(render.clip) ?? render.clip.timelineStartUs;
        final label = 'ax$i';
        filters.add(
          '[${render.inputIndex}:a]'
          '${_audioChain(render.clip, volumeScale: track?.volume ?? 1, delayUs: startUs)}'
          '[$label]',
        );
        extras.add(label);
      }
      final sources = <String>[?mainAudio, ...extras];
      if (sources.length == 1) {
        audioLabel = sources.first;
      } else if (sources.length > 1) {
        final inputs = sources.map((String label) => '[$label]').join();
        filters.add(
          '${inputs}amix=inputs=${sources.length}:duration=longest:'
          'normalize=0:dropout_transition=0[amix]',
        );
        audioLabel = 'amix';
      }
      if (audioLabel != null) {
        final totalSec = TimeUtils.ffmpegSeconds(total);
        filters.add(
          '[$audioLabel]atrim=0:$totalSec,apad=whole_dur=$totalSec,'
          'asetpts=PTS-STARTPTS[aout]',
        );
        audioLabel = 'aout';
      }
    }

    // Hold the last frame if audio or subtitles run past the video.
    final primaryDurationUs = primary.durationUs;
    if (totalUs > primaryDurationUs) {
      final padSec = TimeUtils.ffmpegSeconds(
        Duration(microseconds: totalUs - primaryDurationUs),
      );
      filters.add(
        '[$videoLabel]tpad=stop_mode=clone:stop_duration=$padSec[vpad]',
      );
      videoLabel = 'vpad';
    }

    if (wantBurn) {
      final buffer = StringBuffer(
        'subtitles=filename=${_escapeFilterPath(burnedSubtitlePath!)}',
      );
      if (fontsDir != null && fontsDir.isNotEmpty) {
        buffer.write(':fontsdir=${_escapeFilterPath(fontsDir)}');
      }
      filters.add('[$videoLabel]${buffer.toString()}[vout]');
      videoLabel = 'vout';
    }

    args.addAll(<String>['-filter_complex', filters.join(';')]);
    args.addAll(<String>['-map', '[$videoLabel]']);
    if (audioLabel != null) {
      args.addAll(<String>['-map', '[$audioLabel]']);
    } else {
      args.add('-an');
    }
    if (wantSoft) {
      args.addAll(<String>[
        '-map',
        '$softInputIndex:s',
        '-c:s',
        settings.softSubtitleCodec.codecName,
        '-metadata:s:s:0',
        'language=mya',
        '-disposition:s:0',
        'default',
      ]);
    } else {
      args.add('-sn');
    }

    args.addAll(_videoCodecArgs(settings));
    args.addAll(<String>[
      '-b:v',
      '${settings.videoBitrateKbps}k',
      '-maxrate',
      '${(settings.videoBitrateKbps * 1.5).round()}k',
      '-bufsize',
      '${settings.videoBitrateKbps * 2}k',
      '-pix_fmt',
      'yuv420p',
      '-r',
      fps.toStringAsFixed(3),
    ]);
    if (settings.audioCodec != ExportAudioCodec.none) {
      args.addAll(_audioCodecArgs(settings));
    }
    if (settings.container == ExportContainer.mp4) {
      args.addAll(<String>['-movflags', '+faststart']);
    }
    if (settings.videoCodec == VideoCodec.h265) {
      args.addAll(<String>['-tag:v', 'hvc1']);
    }
    args.addAll(<String>[
      '-map_metadata',
      '-1',
      '-metadata',
      'title=${project.name}',
      '-t',
      TimeUtils.ffmpegSeconds(total),
      '-y',
      outputPath,
    ]);

    return ExportPlan(
      args: args,
      duration: total,
      outputPath: outputPath,
      filterGraph: filters.join(';'),
      issues: issues,
      hasAudio: audioLabel != null,
      burnsSubtitles: wantBurn,
      embedsSubtitles: wantSoft,
    );
  }

  List<_Segment> _segments(List<_ClipRender> renders, List<Clip> clips) {
    final segments = <_Segment>[];
    var current = <_ClipRender>[];
    for (var i = 0; i < renders.length; i++) {
      final transition = i > 0 ? clips[i].transitionIn : null;
      if (transition != null && transition.isActive) {
        segments.add(_Segment(current, transition));
        current = <_ClipRender>[];
      }
      current.add(renders[i]);
    }
    segments.add(_Segment(current, null));
    return segments;
  }

  int _segmentDuration(List<_ClipRender> clips) {
    var total = 0;
    for (var i = 0; i < clips.length; i++) {
      if (i > 0 && clips[i].clip.transitionIn.isActive) {
        total -= math.min(clips[i].clip.transitionIn.durationUs, total);
      }
      total += clips[i].durationUs;
    }
    return total;
  }

  String _joinVideoSegments(
    List<_Segment> segments,
    List<String> filters,
    String finalLabel,
  ) {
    final labels = <String>[];
    for (var i = 0; i < segments.length; i++) {
      final clipLabels = segments[i].clips
          .map((_ClipRender r) => 'v${r.inputIndex}')
          .toList();
      if (clipLabels.length == 1) {
        labels.add(clipLabels.first);
        continue;
      }
      final inputs = clipLabels.map((String l) => '[$l]').join();
      filters.add('${inputs}concat=n=${clipLabels.length}:v=1:a=0[vs$i]');
      labels.add('vs$i');
    }

    var current = labels.first;
    var currentDuration = _segmentDuration(segments.first.clips);
    for (var i = 1; i < segments.length; i++) {
      final transition = segments[i - 1].transitionToNext;
      final segmentDuration = _segmentDuration(segments[i].clips);
      final label = 'vj$i';
      final possible = transition != null
          ? math.min(
              transition.durationUs,
              math.min(currentDuration, segmentDuration) ~/ 2,
            )
          : 0;
      if (possible >= 100000) {
        final offset = (currentDuration - possible) / 1000000;
        filters.add(
          '[$current][${labels[i]}]xfade='
          'transition=${transition!.type.ffmpegName}:'
          'duration=${(possible / 1000000).toStringAsFixed(3)}:'
          'offset=${offset.toStringAsFixed(3)}[$label]',
        );
        currentDuration = currentDuration + segmentDuration - possible;
      } else {
        filters.add('[$current][${labels[i]}]concat=n=2:v=1:a=0[$label]');
        currentDuration += segmentDuration;
      }
      current = label;
    }
    if (current != finalLabel) {
      filters.add('[$current]null[$finalLabel]');
    }
    return finalLabel;
  }

  String? _joinPrimaryAudio(
    List<_ClipRender> renders,
    List<_Segment> segments,
    List<String> filters,
    Project project,
    String finalLabel,
  ) {
    final primaryTrack = project.primaryVideoTrack;
    final hasAnyAudio = renders.any(
      (_ClipRender r) => r.asset.hasAudio && r.asset.kind == MediaKind.video,
    );
    if (!hasAnyAudio) return null;

    for (final render in renders) {
      final usable =
          render.asset.hasAudio && render.asset.kind == MediaKind.video;
      if (usable) {
        filters.add(
          '[${render.inputIndex}:a]'
          '${_audioChain(render.clip, volumeScale: primaryTrack.volume, delayUs: 0)}'
          '[pa${render.inputIndex}]',
        );
      } else {
        final seconds = TimeUtils.ffmpegSeconds(
          Duration(microseconds: render.durationUs),
        );
        filters.add(
          'anullsrc=r=48000:cl=stereo,atrim=duration=$seconds'
          '[pa${render.inputIndex}]',
        );
      }
    }

    String? current;
    var index = 0;
    var currentDuration = _segmentDuration(segments.first.clips);
    for (final segment in segments) {
      final clipLabels = segment.clips
          .map((_ClipRender r) => 'pa${r.inputIndex}')
          .toList();
      final label = 'pas$index';
      if (clipLabels.length > 1) {
        final inputs = clipLabels.map((String l) => '[$l]').join();
        filters.add('${inputs}concat=n=${clipLabels.length}:v=0:a=1[$label]');
      } else {
        filters.add('[${clipLabels.first}]anull[$label]');
      }
      if (current == null) {
        current = label;
      } else {
        final transition = segments[index - 1].transitionToNext;
        final segmentDuration = _segmentDuration(segment.clips);
        final possible = transition != null
            ? math.min(
                transition.durationUs,
                math.min(currentDuration, segmentDuration) ~/ 2,
              )
            : 0;
        final nextLabel = 'paj$index';
        if (possible >= 100000) {
          filters.add(
            '[$current][$label]acrossfade='
            'd=${(possible / 1000000).toStringAsFixed(3)}:'
            'c1=tri:c2=tri[$nextLabel]',
          );
          currentDuration = currentDuration + segmentDuration - possible;
        } else {
          filters.add('[$current][$label]concat=n=2:v=0:a=1[$nextLabel]');
          currentDuration += segmentDuration;
        }
        current = nextLabel;
      }
      index++;
    }
    if (current == null) return null;
    if (current != finalLabel) {
      filters.add('[$current]anull[$finalLabel]');
    }
    return finalLabel;
  }

  String _videoChain({
    required _ClipRender render,
    required String label,
    required int width,
    required int height,
    required double fps,
  }) {
    final clip = render.clip;
    final parts = <String>[];
    parts.add(
      clip.speed == 1
          ? 'setpts=PTS-STARTPTS'
          : 'setpts=(PTS-STARTPTS)/${clip.speed.toStringAsFixed(4)}',
    );

    if (!clip.crop.isFull) {
      parts.add(
        'crop=iw*${clip.crop.widthFraction.toStringAsFixed(4)}:'
        'ih*${clip.crop.heightFraction.toStringAsFixed(4)}:'
        'iw*${clip.crop.left.toStringAsFixed(4)}:'
        'ih*${clip.crop.top.toStringAsFixed(4)}',
      );
    }
    switch (clip.rotation) {
      case 90:
        parts.add('transpose=1');
      case 180:
        parts.add('transpose=1,transpose=1');
      case 270:
        parts.add('transpose=2');
    }
    switch (clip.fit) {
      case MediaFit.contain:
        parts.add(
          'scale=$width:$height:'
          'force_original_aspect_ratio=decrease:flags=lanczos',
        );
        parts.add('pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black');
      case MediaFit.cover:
        parts.add(
          'scale=$width:$height:'
          'force_original_aspect_ratio=increase:flags=lanczos',
        );
        parts.add('crop=$width:$height');
      case MediaFit.stretch:
        parts.add('scale=$width:$height:flags=lanczos');
    }
    if (clip.scale != 1 || clip.offsetX != 0 || clip.offsetY != 0) {
      final zoom = math.max(clip.scale, 1.0);
      final scaledWidth = (width * zoom).round();
      final scaledHeight = (height * zoom).round();
      final x =
          ((scaledWidth - width) / 2 + clip.offsetX * (scaledWidth - width) / 2)
              .round();
      final y =
          ((scaledHeight - height) / 2 +
                  clip.offsetY * (scaledHeight - height) / 2)
              .round();
      parts.add('scale=$scaledWidth:$scaledHeight:flags=lanczos');
      parts.add('crop=$width:$height:$x:$y');
    }
    if (!clip.grade.isNeutral) {
      parts.add(
        'eq=brightness=${clip.grade.brightness.toStringAsFixed(3)}:'
        'contrast=${clip.grade.contrast.toStringAsFixed(3)}:'
        'saturation=${clip.grade.saturation.toStringAsFixed(3)}',
      );
    }
    if (clip.effects.grayscale) parts.add('hue=s=0');
    if (clip.effects.mirror) parts.add('hflip');
    if (clip.effects.vignette > 0) {
      parts.add(
        'vignette=angle=${(math.pi / 5 * clip.effects.vignette).toStringAsFixed(4)}',
      );
    }
    parts.add('fps=${fps.toStringAsFixed(3)}');
    parts.add('setsar=1');
    parts.add('format=yuv420p');
    return '[${render.inputIndex}:v]${parts.join(',')}[$label]';
  }

  String _overlayChain({
    required _ClipRender render,
    required String label,
    required int width,
    required int height,
    required double fps,
    required int startUs,
  }) {
    final clip = render.clip;
    final geometry = _overlayGeometry(clip, width, height);
    final shift = TimeUtils.ffmpegSeconds(Duration(microseconds: startUs));
    final parts = <String>[];
    parts.add(
      clip.speed == 1
          ? 'setpts=PTS-STARTPTS+$shift/TB'
          : 'setpts=(PTS-STARTPTS)/${clip.speed.toStringAsFixed(4)}+$shift/TB',
    );
    if (!clip.crop.isFull) {
      parts.add(
        'crop=iw*${clip.crop.widthFraction.toStringAsFixed(4)}:'
        'ih*${clip.crop.heightFraction.toStringAsFixed(4)}:'
        'iw*${clip.crop.left.toStringAsFixed(4)}:'
        'ih*${clip.crop.top.toStringAsFixed(4)}',
      );
    }
    switch (clip.rotation) {
      case 90:
        parts.add('transpose=1');
      case 180:
        parts.add('transpose=1,transpose=1');
      case 270:
        parts.add('transpose=2');
    }
    parts.add(
      'scale=${geometry.width}:${geometry.height}:'
      'force_original_aspect_ratio=decrease:flags=lanczos',
    );
    parts.add(
      'pad=${geometry.width}:${geometry.height}:'
      '(ow-iw)/2:(oh-ih)/2:color=black@0',
    );
    parts.add('fps=${fps.toStringAsFixed(3)}');
    parts.add('format=rgba');
    parts.add('colorchannelmixer=aa=${clip.opacity.toStringAsFixed(3)}');
    return '[${render.inputIndex}:v]${parts.join(',')}[$label]';
  }

  ({int width, int height, int x, int y}) _overlayGeometry(
    Clip clip,
    int canvasWidth,
    int canvasHeight,
  ) {
    final width = (canvasWidth * clip.scale).round();
    final height = (canvasHeight * clip.scale).round();
    final x =
        ((canvasWidth - width) / 2 + clip.offsetX * (canvasWidth - width) / 2)
            .round();
    final y =
        ((canvasHeight - height) / 2 +
                clip.offsetY * (canvasHeight - height) / 2)
            .round();
    return (width: width, height: height, x: x, y: y);
  }

  String _audioChain(
    Clip clip, {
    required double volumeScale,
    required int delayUs,
  }) {
    final parts = <String>['asetpts=PTS-STARTPTS'];
    if (clip.speed != 1) {
      var speed = clip.speed;
      while (speed > 2.0) {
        parts.add('atempo=2.0');
        speed /= 2;
      }
      while (speed < 0.5) {
        parts.add('atempo=0.5');
        speed *= 2;
      }
      if ((speed - 1.0).abs() > 0.001) {
        parts.add('atempo=${speed.toStringAsFixed(4)}');
      }
    }
    final volume = clip.effectiveVolume * volumeScale;
    if ((volume - 1.0).abs() > 0.001) {
      parts.add('volume=${volume.toStringAsFixed(3)}');
    }
    parts.add(
      'aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo',
    );
    if (delayUs > 0) {
      final ms = (delayUs / 1000).round();
      parts.add('adelay=$ms|$ms');
    }
    return parts.join(',');
  }

  List<String> _inputArgs(MediaAsset asset, Clip clip, double fps) {
    final sourceDuration = Duration(microseconds: clip.sourceDurationUs);
    if (asset.kind == MediaKind.image) {
      return <String>[
        '-loop',
        '1',
        '-framerate',
        fps.toStringAsFixed(3),
        '-t',
        TimeUtils.ffmpegSeconds(sourceDuration),
        '-i',
        asset.path,
      ];
    }
    return <String>[
      '-ss',
      TimeUtils.ffmpegSeconds(clip.sourceIn),
      '-t',
      TimeUtils.ffmpegSeconds(sourceDuration),
      '-i',
      asset.path,
    ];
  }

  List<String> _videoCodecArgs(ExportSettings settings) {
    return switch (settings.videoCodec) {
      VideoCodec.h264 => <String>[
        '-c:v',
        'libx264',
        '-preset',
        'medium',
        '-profile:v',
        'high',
      ],
      VideoCodec.h265 => <String>[
        '-c:v',
        'libx265',
        '-preset',
        'medium',
        '-x265-params',
        'log-level=error',
      ],
      VideoCodec.av1 => <String>[
        '-c:v',
        'libaom-av1',
        '-cpu-used',
        '8',
        '-row-mt',
        '1',
      ],
      VideoCodec.vp9 => <String>[
        '-c:v',
        'libvpx-vp9',
        '-deadline',
        'good',
        '-cpu-used',
        '2',
        '-row-mt',
        '1',
      ],
    };
  }

  List<String> _audioCodecArgs(ExportSettings settings) {
    final kbps = '${settings.audioBitrateKbps}k';
    return switch (settings.audioCodec) {
      ExportAudioCodec.aac => <String>[
        '-c:a',
        'aac',
        '-b:a',
        kbps,
        '-ar',
        '48000',
        '-ac',
        '2',
      ],
      ExportAudioCodec.opus => <String>[
        '-c:a',
        'libopus',
        '-b:a',
        kbps,
        '-ar',
        '48000',
        '-ac',
        '2',
      ],
      ExportAudioCodec.mp3 => <String>[
        '-c:a',
        'libmp3lame',
        '-b:a',
        kbps,
        '-ar',
        '48000',
        '-ac',
        '2',
      ],
      ExportAudioCodec.none => const <String>[],
    };
  }

  MediaAsset _requireAsset(Project project, Clip clip) {
    final asset = project.assetFor(clip.assetId);
    if (asset == null) {
      throw ExportException(
        'Clip ${clip.id} points to media that is no longer in the project.',
      );
    }
    return asset;
  }

  static String _escapeFilterPath(String path) {
    final buffer = StringBuffer();
    for (final rune in path.runes) {
      final char = String.fromCharCode(rune);
      switch (char) {
        case '\\':
          buffer.write(r'\\');
        case ':':
          buffer.write(r'\:');
        case ',':
          buffer.write(r'\,');
        case '[':
          buffer.write(r'\[');
        case ']':
          buffer.write(r'\]');
        case ';':
          buffer.write(r'\;');
        default:
          buffer.write(char);
      }
    }
    return buffer.toString();
  }
}

class ExportValidator {
  const ExportValidator._();

  static List<ExportIssue> validate({
    required Project project,
    required ExportSettings settings,
    FfmpegCapabilities? capabilities,
  }) {
    final issues = <ExportIssue>[];
    if (project.primaryClips.isEmpty) {
      issues.add(
        const ExportIssue(
          'Add at least one clip to the video track before exporting.',
          ExportSeverity.blocking,
        ),
      );
    }
    if (!settings.videoCodec.containers.contains(settings.container)) {
      issues.add(
        ExportIssue(
          '${settings.videoCodec.label} cannot be written to '
          '${settings.container.label}. Choose another container or codec.',
          ExportSeverity.blocking,
        ),
      );
    }
    if (!settings.audioCodec.containers.contains(settings.container)) {
      issues.add(
        ExportIssue(
          '${settings.audioCodec.label} audio is not supported by '
          '${settings.container.label}.',
          ExportSeverity.blocking,
        ),
      );
    }
    if (settings.subtitleMode == SubtitleExportMode.soft &&
        !settings.softSubtitleCodec.containers.contains(settings.container)) {
      issues.add(
        ExportIssue(
          '${settings.softSubtitleCodec.label} subtitles cannot be stored in '
          '${settings.container.label}.',
          ExportSeverity.blocking,
        ),
      );
    }
    if (settings.subtitleMode == SubtitleExportMode.soft &&
        settings.container == ExportContainer.mp4 &&
        !project.subtitles.isEmpty) {
      issues.add(
        const ExportIssue(
          'MP4 timed text is plain text: outline, shadow and background styling '
          'only appear with burn-in. Use MKV+ASS or burn-in for styled Myanmar '
          'subtitles.',
        ),
      );
    }
    if (settings.subtitleMode != SubtitleExportMode.none &&
        project.subtitles.isEmpty) {
      issues.add(
        const ExportIssue(
          'No subtitle cues yet; the export continues without subtitles.',
          ExportSeverity.info,
        ),
      );
    }
    if (settings.videoCodec.isSlow) {
      issues.add(
        ExportIssue(
          '${settings.videoCodec.label} encoding is CPU heavy and can take '
          'several times the clip length on a phone.',
          ExportSeverity.info,
        ),
      );
    }
    if (settings.videoBitrateKbps > 24000) {
      issues.add(
        const ExportIssue(
          'Very high bitrate: large file, no visible gain above 1080p.',
          ExportSeverity.info,
        ),
      );
    }
    if (capabilities != null && capabilities.available) {
      if (!capabilities.hasEncoder(settings.videoCodec.encoder)) {
        issues.add(
          ExportIssue(
            'The bundled FFmpeg has no ${settings.videoCodec.encoder} encoder on '
            'this device. Pick another video codec.',
            ExportSeverity.blocking,
          ),
        );
      }
      if (settings.audioCodec != ExportAudioCodec.none &&
          !capabilities.hasEncoder(settings.audioCodec.encoder)) {
        issues.add(
          ExportIssue(
            'The bundled FFmpeg has no ${settings.audioCodec.encoder} encoder on '
            'this device.',
            ExportSeverity.blocking,
          ),
        );
      }
      if (settings.subtitleMode == SubtitleExportMode.burnIn &&
          !project.subtitles.isEmpty &&
          !capabilities.hasFilter('subtitles')) {
        issues.add(
          const ExportIssue(
            'This FFmpeg build cannot burn subtitles (libass filter missing). '
            'Use a soft subtitle track.',
            ExportSeverity.blocking,
          ),
        );
      }
    }
    return issues;
  }
}
