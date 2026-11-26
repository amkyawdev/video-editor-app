import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/subtitle.dart';
import '../../data/services/ai/recap_service.dart';
import '../../data/services/subtitle/srt_codec.dart';
import '../../state/app_services.dart';
import '../../state/models_controller.dart';
import '../../state/recap_controller.dart';
import '../../widgets/common.dart';
import '../editor/panels/panel_controls.dart';
import '../models/model_library_screen.dart';

class RecapScreen extends StatefulWidget {
  const RecapScreen({super.key});

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  late final RecapController controller;

  @override
  void initState() {
    super.initState();
    controller = RecapController(context.read<AppServices>())
      ..addListener(_refresh);
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

  Future<String?> _materialize(PlatformFile file, String suffix) async {
    final existing = file.path;
    if (existing != null) return existing;
    final services = context.read<AppServices>();
    final dir = Directory('${services.cacheDir.path}/recap_inputs');
    await dir.create(recursive: true);
    final target = File(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$suffix',
    );
    final sink = target.openWrite();
    try {
      await for (final chunk in file.readAsByteStream()) {
        sink.add(chunk);
      }
      await sink.close();
      return target.path;
    } catch (_) {
      await sink.close();
      return null;
    }
  }

  Future<void> _pickVideo() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>[
        'mp4',
        'mov',
        'mkv',
        'webm',
        'm4v',
        'avi',
        '3gp',
      ],
    );
    if (file == null || !mounted) return;
    final path = await _materialize(file, file.name);
    if (path == null) {
      if (mounted) {
        showAppSnack(context, 'Could not read that video file.', error: true);
      }
      return;
    }
    controller.setVideo(path: path, name: file.name);
  }

  Future<void> _pickTranscript() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['srt', 'txt'],
    );
    if (file == null || !mounted) return;
    try {
      final raw = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final text = file.extension == 'srt'
          ? SrtCodec.decode(raw).map((SubtitleCue c) => c.text).join(' ')
          : raw;
      controller.setTranscript(name: file.name, text: text);
    } catch (error) {
      if (mounted) showAppSnack(context, '$error', error: true);
    }
  }

  Future<void> _start(ModelsController models) async {
    final analysis = models.installedRecap;
    final asr = models.installedAsr;
    await controller.start(analysisModel: analysis, asrModel: asr);
    if (!mounted) return;
    if (controller.status == RecapStatus.failed && controller.error != null) {
      showAppSnack(context, controller.error!, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelsController>();
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      color: AppColors.textSecondary,
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Movie recap',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Evidence-first: frames, audio, transcript',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PillButton(
                      label: 'Local AI',
                      icon: Icons.offline_bolt_rounded,
                      selected: true,
                      compact: true,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: <Widget>[
                    _videoCard(),
                    const SizedBox(height: 12),
                    _transcriptCard(),
                    const SizedBox(height: 12),
                    _optionsCard(),
                    const SizedBox(height: 12),
                    _modelsCard(models),
                    const SizedBox(height: 14),
                    _runControls(models),
                    _progressCard(),
                    if (controller.error != null) ...<Widget>[
                      const SizedBox(height: 10),
                      InfoNote(
                        message: controller.error!,
                        icon: Icons.error_outline,
                        color: AppColors.danger,
                      ),
                    ],
                    if (controller.warnings.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _warningsCard(),
                    ],
                    if (controller.evidence != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _evidenceCard(),
                    ],
                    if (controller.script != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _scriptCard(),
                    ],
                    const SizedBox(height: 14),
                    const InfoNote(
                      message:
                          'No TTS or voice generation exists in this app. '
                          'The recap is text only, exported as TXT or SRT.',
                      icon: Icons.text_fields_rounded,
                      color: AppColors.textMuted,
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

  Widget _videoCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Video'),
          Text(
            controller.videoName ?? 'No video selected',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            controller.videoPath == null
                ? 'FFmpeg extracts a 16 kHz audio track and scene frames. The '
                      'video is not uploaded.'
                : 'A local working copy is used for frame/audio extraction.',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'Choose video',
            icon: Icons.video_file_outlined,
            onTap: controller.isRunning ? null : _pickVideo,
          ),
        ],
      ),
    );
  }

  Widget _transcriptCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel('Transcript (optional)')),
              if (controller.transcriptText != null)
                PillButton(
                  label: 'Clear',
                  compact: true,
                  onTap: () => controller.setTranscript(),
                ),
            ],
          ),
          Text(
            controller.transcriptName ??
                (controller.transcriptText == null
                    ? 'No transcript attached'
                    : 'Transcript attached'),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'Attach an SRT/TXT transcript for precise audio evidence. Without '
            'a transcript, audio is not understood unless a local ASR model is '
            'installed and the speech language is supported.',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'Attach SRT/TXT',
            icon: Icons.subtitles_outlined,
            compact: true,
            onTap: controller.isRunning ? null : _pickTranscript,
          ),
        ],
      ),
    );
  }

  Widget _optionsCard() {
    final settings = controller.settings;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Recap settings'),
          const Text(
            'Language',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          SegmentedRow<String>(
            options: const <String>['English', 'Burmese'],
            labelOf: (String value) => value,
            selected: settings.language,
            onSelected: (String value) =>
                controller.updateSettings(settings.copyWith(language: value)),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tone',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          SegmentedRow<String>(
            options: const <String>['factual', 'dramatic', 'short'],
            labelOf: (String value) => value,
            selected: settings.tone,
            onSelected: (String value) =>
                controller.updateSettings(settings.copyWith(tone: value)),
          ),
          const SizedBox(height: 6),
          SliderRow(
            label: 'Target length',
            value: settings.targetWords.toDouble(),
            min: 60,
            max: 600,
            divisions: 18,
            valueLabel: '${settings.targetWords} words',
            onChanged: (double value) => controller.updateSettings(
              settings.copyWith(targetWords: value.round()),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Transcribe audio locally',
              style: TextStyle(fontSize: 12),
            ),
            subtitle: const Text(
              'Uses Qwen3-ASR when installed. Burmese is not in its language '
              'list.',
              style: TextStyle(fontSize: 9, color: AppColors.textMuted),
            ),
            value: settings.useAsr,
            onChanged: (bool value) =>
                controller.updateSettings(settings.copyWith(useAsr: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Caption sampled frames',
              style: TextStyle(fontSize: 12),
            ),
            subtitle: const Text(
              'Requires a vision GGUF + mmproj (Qwen2.5-VL).',
              style: TextStyle(fontSize: 9, color: AppColors.textMuted),
            ),
            value: settings.useVisionCaptions,
            onChanged: (bool value) => controller.updateSettings(
              settings.copyWith(useVisionCaptions: value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelsCard(ModelsController models) {
    final analysisModels = models.installedRecapModels;
    final asrModels = models.installedAsrModels;
    final analysis = models.installedRecap;
    final asr = models.installedAsr;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel('Local models')),
              PillButton(
                label: 'Library',
                icon: Icons.download_rounded,
                compact: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ModelLibraryScreen(),
                  ),
                ),
              ),
            ],
          ),
          if (analysisModels.isEmpty)
            const InfoNote(
              message:
                  'No analysis model installed. The pipeline still '
                  'extracts frames and transcript, but it will return an '
                  'evidence report instead of inventing a plot.',
              color: AppColors.accent,
            )
          else
            DropdownButtonFormField<String>(
              initialValue: analysis?.model.id,
              dropdownColor: AppColors.surfaceHigh,
              decoration: const InputDecoration(
                labelText: 'Script / vision model',
              ),
              items: <DropdownMenuItem<String>>[
                for (final item in analysisModels)
                  DropdownMenuItem<String>(
                    value: item.model.id,
                    child: Text(
                      item.model.title,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              onChanged: controller.isRunning
                  ? null
                  : (String? value) => models.selectRecap(value),
            ),
          if (asrModels.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: asr?.model.id,
              dropdownColor: AppColors.surfaceHigh,
              decoration: const InputDecoration(labelText: 'ASR model'),
              items: <DropdownMenuItem<String>>[
                for (final item in asrModels)
                  DropdownMenuItem<String>(
                    value: item.model.id,
                    child: Text(
                      item.model.title,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              onChanged: controller.isRunning
                  ? null
                  : (String? value) => models.selectAsr(value),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No ASR model installed. Attach a transcript, or install '
                'Qwen3-ASR 0.6B from the library.',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _runControls(ModelsController models) {
    if (controller.isRunning) {
      return OutlinedButton.icon(
        onPressed: controller.cancel,
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: const Text('Cancel recap'),
      );
    }
    return GradientButton(
      label: controller.videoPath == null
          ? 'Choose a video first'
          : 'Analyse locally',
      icon: Icons.auto_awesome_rounded,
      onPressed: controller.videoPath == null ? null : () => _start(models),
    );
  }

  Widget _progressCard() {
    if (controller.status == RecapStatus.idle) return const SizedBox.shrink();
    const stages = <(RecapStage, String)>[
      (RecapStage.probing, 'Probe video'),
      (RecapStage.extractingAudio, 'Extract audio'),
      (RecapStage.samplingFrames, 'Sample frames'),
      (RecapStage.transcribing, 'Transcribe'),
      (RecapStage.captioning, 'Caption frames'),
      (RecapStage.scripting, 'Write recap'),
    ];
    final activeIndex = stages.indexWhere(
      ((RecapStage, String) item) => item.$1 == controller.stage,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GlassCard(
        highlight: controller.isRunning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                ProgressRing(
                  value: controller.progress,
                  size: 54,
                  strokeWidth: 5,
                  color: controller.status == RecapStatus.failed
                      ? AppColors.danger
                      : AppColors.accent,
                  center: Text(
                    '${(controller.progress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: AppFonts.mono,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        controller.status == RecapStatus.ready
                            ? (controller.script?.isNarrative == true
                                  ? 'Recap ready'
                                  : 'Evidence report ready')
                            : controller.status == RecapStatus.cancelled
                            ? 'Cancelled'
                            : controller.status == RecapStatus.failed
                            ? 'Failed'
                            : controller.message,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Stages produce real FFmpeg evidence. Nothing is '
                        'uploaded.',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < stages.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: <Widget>[
                    Icon(
                      i < activeIndex
                          ? Icons.check_circle_rounded
                          : i == activeIndex
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 13,
                      color: i <= activeIndex && activeIndex >= 0
                          ? AppColors.accent
                          : AppColors.stroke,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      stages[i].$2,
                      style: TextStyle(
                        fontSize: 10,
                        color: i <= activeIndex && activeIndex >= 0
                            ? AppColors.textSecondary
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _warningsCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Analysis limits'),
          for (final warning in controller.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 13,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      warning,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _evidenceCard() {
    final evidence = controller.evidence!;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel('Extracted evidence')),
              Text(
                '${evidence.scenes.length} frames',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          Text(
            '${TimeUtils.timecode(Duration(microseconds: evidence.durationUs))}'
            ' · ${evidence.width}x${evidence.height}'
            '${evidence.meanVolumeDb != null ? ' · mean ${evidence.meanVolumeDb!.toStringAsFixed(1)} dB' : ''}',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              fontFamily: AppFonts.mono,
            ),
          ),
          if (evidence.scenes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: evidence.scenes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (BuildContext context, int index) {
                  final scene = evidence.scenes[index];
                  return SizedBox(
                    width: 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ThumbnailImage(
                          path: scene.path,
                          width: 104,
                          height: 58,
                          radius: 5,
                        ),
                        Text(
                          TimeUtils.timecode(scene.time),
                          style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textMuted,
                            fontFamily: AppFonts.mono,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          if (evidence.hasTranscript) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Transcript${evidence.transcriptLanguage != null ? ' · ${evidence.transcriptLanguage}' : ''}',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: SelectableText(
                  evidence.transcript!,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scriptCard() {
    final script = controller.script!;
    return GlassCard(
      key: ValueKey<DateTime?>(script.createdAt),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel('Recap script')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.alpha(
                    script.isNarrative ? AppColors.mint : AppColors.accent,
                    0.12,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  script.isNarrative ? 'Model narrative' : 'Evidence report',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: script.isNarrative
                        ? AppColors.mint
                        : AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          _ScriptField(
            label: 'Title',
            value: script.title,
            onChanged: (String value) => controller.updateScript(title: value),
          ),
          const SizedBox(height: 8),
          _ScriptField(
            label: 'Logline',
            value: script.logline,
            maxLines: 2,
            onChanged: (String value) =>
                controller.updateScript(logline: value),
          ),
          const SizedBox(height: 8),
          _ScriptField(
            label: 'Recap body',
            value: script.body,
            maxLines: 12,
            onChanged: (String value) => controller.updateScript(body: value),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: PillButton(
                  label: 'Export TXT',
                  icon: Icons.description_outlined,
                  onTap: () async {
                    try {
                      final path = await controller.exportTxt();
                      if (mounted) showAppSnack(context, 'Saved to $path');
                    } catch (error) {
                      if (mounted) {
                        showAppSnack(context, '$error', error: true);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: PillButton(
                  label: 'Export SRT',
                  icon: Icons.subtitles_outlined,
                  onTap: controller.canExportSrt
                      ? () async {
                          try {
                            final path = await controller.exportSrt();
                            if (mounted) {
                              showAppSnack(context, 'Saved to $path');
                            }
                          } catch (error) {
                            if (mounted) {
                              showAppSnack(context, '$error', error: true);
                            }
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
          if (!controller.canExportSrt)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'SRT export is unavailable for an evidence report because it '
                'has no narrative sentences to time.',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScriptField extends StatelessWidget {
  const _ScriptField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 12, height: 1.5),
      decoration: InputDecoration(labelText: label),
    );
  }
}
