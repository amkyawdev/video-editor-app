import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/export_settings.dart';
import '../../../data/models/local_model.dart';
import '../../../data/models/project.dart';
import '../../../data/services/ffmpeg/ffmpeg_capabilities.dart';
import '../../../state/app_services.dart';
import '../../../state/export_controller.dart';
import '../../../widgets/common.dart';
import 'panel_controls.dart';

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.project});

  final Project project;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  late final ExportController controller;

  @override
  void initState() {
    super.initState();
    controller = ExportController(
      services: context.read<AppServices>(),
      project: widget.project,
    )..addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final capabilities = controller.capabilities;
    final issues = controller.issues;
    final rendering =
        controller.status == ExportStatus.rendering ||
        controller.status == ExportStatus.preparing;
    final estimate = settings.estimatedBytes(widget.project.durationUs);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.96,
      minChildSize: 0.55,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadii.xl),
            ),
            border: Border(top: BorderSide(color: AppColors.stroke)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.stroke,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Export',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '${TimeUtils.timecode(widget.project.duration)} · '
                          '${widget.project.primaryClips.length} clips · '
                          'est. ${LocalModelFile.formatBytes(estimate)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: rendering ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ffmpegStatus(capabilities),
              const SizedBox(height: 14),
              PanelSection(
                title: 'Container',
                children: <Widget>[
                  SegmentedRow<ExportContainer>(
                    options: ExportContainer.values,
                    labelOf: (ExportContainer value) => value.label,
                    selected: settings.container,
                    onSelected: controller.setContainer,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    settings.container.blurb,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              PanelSection(
                title: 'Video',
                children: <Widget>[
                  SegmentedRow<VideoCodec>(
                    options: VideoCodec.values
                        .where(
                          (VideoCodec codec) =>
                              codec.containers.contains(settings.container),
                        )
                        .toList(),
                    labelOf: (VideoCodec value) => value.label,
                    selected: settings.videoCodec,
                    onSelected: (VideoCodec value) => controller.updateSettings(
                      settings.copyWith(videoCodec: value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedRow<ResolutionPreset>(
                    options: ResolutionPreset.values,
                    labelOf: (ResolutionPreset value) => value.label,
                    selected: settings.resolution,
                    onSelected: (ResolutionPreset value) => controller
                        .updateSettings(settings.copyWith(resolution: value)),
                  ),
                  const SizedBox(height: 8),
                  SegmentedRow<FrameRatePreset>(
                    options: FrameRatePreset.values,
                    labelOf: (FrameRatePreset value) => value.label,
                    selected: settings.frameRate,
                    onSelected: (FrameRatePreset value) => controller
                        .updateSettings(settings.copyWith(frameRate: value)),
                  ),
                  const SizedBox(height: 4),
                  SliderRow(
                    label: 'Video bitrate',
                    value: settings.videoBitrateKbps.toDouble(),
                    min: 1000,
                    max: 24000,
                    divisions: 46,
                    valueLabel:
                        '${(settings.videoBitrateKbps / 1000).toStringAsFixed(1)} Mbps',
                    onChanged: (double value) => controller.updateSettings(
                      settings.copyWith(videoBitrateKbps: value.round()),
                    ),
                  ),
                  Text(
                    'Output ${settings.targetWidth(widget.project.canvasWidth, widget.project.canvasHeight)}'
                    '×${settings.targetHeight(widget.project.canvasHeight)} · '
                    '${settings.targetFps(widget.project.fps).round()} fps · '
                    '${settings.videoCodec.encoder}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      fontFamily: AppFonts.mono,
                    ),
                  ),
                ],
              ),

              PanelSection(
                title: 'Audio',
                children: <Widget>[
                  SegmentedRow<ExportAudioCodec>(
                    options: ExportAudioCodec.values
                        .where(
                          (ExportAudioCodec codec) =>
                              codec.containers.contains(settings.container),
                        )
                        .toList(),
                    labelOf: (ExportAudioCodec value) => value.label,
                    selected: settings.audioCodec,
                    onSelected: (ExportAudioCodec value) => controller
                        .updateSettings(settings.copyWith(audioCodec: value)),
                  ),
                  if (settings.audioCodec != ExportAudioCodec.none)
                    SliderRow(
                      label: 'Audio bitrate',
                      value: settings.audioBitrateKbps.toDouble(),
                      min: 64,
                      max: 320,
                      divisions: 16,
                      valueLabel: '${settings.audioBitrateKbps} kbps',
                      onChanged: (double value) => controller.updateSettings(
                        settings.copyWith(audioBitrateKbps: value.round()),
                      ),
                    ),
                ],
              ),
              PanelSection(
                title: 'Subtitles',
                children: <Widget>[
                  SegmentedRow<SubtitleExportMode>(
                    options: SubtitleExportMode.values,
                    labelOf: (SubtitleExportMode value) => value.label,
                    selected: settings.subtitleMode,
                    onSelected: (SubtitleExportMode value) => controller
                        .updateSettings(settings.copyWith(subtitleMode: value)),
                  ),
                  if (settings.subtitleMode == SubtitleExportMode.soft) ...[
                    const SizedBox(height: 8),
                    SegmentedRow<SoftSubtitleCodec>(
                      options: settings.softCodecChoices,
                      labelOf: (SoftSubtitleCodec value) => value.label,
                      selected: settings.softSubtitleCodec,
                      onSelected: (SoftSubtitleCodec value) =>
                          controller.updateSettings(
                            settings.copyWith(softSubtitleCodec: value),
                          ),
                    ),
                    const SizedBox(height: 6),
                    InfoNote(
                      message: settings.container == ExportContainer.mp4
                          ? 'MP4 can only carry plain timed text (mov_text). '
                                'Outline, shadow and background styling need '
                                'burn-in or MKV+ASS.'
                          : 'The chosen sidecar codec is written as a real '
                                'soft subtitle track in '
                                '${settings.container.label}.',
                    ),
                  ],
                  if (settings.subtitleMode == SubtitleExportMode.burnIn) ...[
                    const SizedBox(height: 6),
                    const InfoNote(
                      message:
                          'Burned-in subtitles are rendered by libass '
                          'with the bundled Myanmar font, so export shows the '
                          'same styling as the preview.',
                    ),
                  ],
                ],
              ),
              PanelSection(
                title: 'File',
                children: <Widget>[
                  TextField(
                    controller: TextEditingController(text: settings.fileName),
                    onChanged: (String value) => controller.updateSettings(
                      settings.copyWith(fileName: value),
                    ),
                    decoration: InputDecoration(
                      labelText: 'File name',
                      suffixText: '.${settings.container.extension}',
                    ),
                  ),
                ],
              ),
              if (issues.isNotEmpty) ...<Widget>[
                const SectionLabel('Checks'),
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          issue.isBlocking
                              ? Icons.error_outline
                              : Icons.info_outline,
                          size: 14,
                          color: issue.isBlocking
                              ? AppColors.danger
                              : AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            issue.message,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: issue.isBlocking
                                  ? AppColors.danger
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              _progress(),
              const SizedBox(height: 12),
              if (controller.status == ExportStatus.succeeded)
                InfoNote(
                  message:
                      'Saved ${LocalModelFile.formatBytes(controller.outputBytes)} '
                      'to ${controller.outputPath}.',
                  icon: Icons.check_circle_outline,
                  color: AppColors.mint,
                ),
              if (controller.error != null)
                InfoNote(
                  message: controller.error!,
                  icon: Icons.error_outline,
                  color: AppColors.danger,
                ),
              const SizedBox(height: 10),
              if (rendering)
                OutlinedButton.icon(
                  onPressed: controller.cancel,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Cancel render'),
                )
              else
                GradientButton(
                  label: capabilities.available
                      ? 'Render with FFmpeg'
                      : 'FFmpeg unavailable',
                  icon: Icons.play_arrow_rounded,
                  onPressed: controller.canExport && capabilities.available
                      ? controller.start
                      : null,
                ),
              const SizedBox(height: 8),
              Text(
                'Rendering runs locally with FFmpeg 8 (libx264/libx265/libaom/'
                'libvpx + libass). Long exports heat the phone; keep the app '
                'open.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ffmpegStatus(FfmpegCapabilities capabilities) {
    if (!capabilities.available) {
      return InfoNote(
        message:
            capabilities.error ??
            'Probing the bundled FFmpeg build… The export controls unlock '
                'when it responds.',
        icon: Icons.hourglass_empty_rounded,
        color: AppColors.accent,
      );
    }
    return InfoNote(
      message:
          '${capabilities.version} · ${capabilities.encoders.length} encoders · '
          'libass ${capabilities.hasFilter('subtitles') ? 'ready' : 'missing'}',
      icon: Icons.memory_rounded,
      color: AppColors.mint,
    );
  }

  Widget _progress() {
    if (controller.status == ExportStatus.idle) return const SizedBox.shrink();
    if (controller.status == ExportStatus.rendering ||
        controller.status == ExportStatus.preparing) {
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Rendering…',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '${(controller.progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.accent,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: controller.progress == 0 ? null : controller.progress,
              minHeight: 6,
              backgroundColor: AppColors.strokeSoft,
              color: AppColors.accent,
            ),
          ),
          if (controller.planText != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              controller.planText!,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
                fontFamily: AppFonts.mono,
                height: 1.4,
              ),
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
