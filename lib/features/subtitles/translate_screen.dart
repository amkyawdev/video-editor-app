import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/services/ai/translation_service.dart';
import '../../data/services/subtitle/srt_codec.dart';
import '../../data/services/subtitle/subtitle_formats.dart';
import '../../state/app_services.dart';
import '../../state/editor_controller.dart';
import '../../state/models_controller.dart';
import '../../state/translation_controller.dart';
import '../../widgets/common.dart';
import '../editor/panels/panel_controls.dart';
import '../models/model_library_screen.dart';

class TranslateScreen extends StatefulWidget {
  const TranslateScreen({
    super.key,
    this.initialName,
    this.initialPath,
    this.initialContent,
    this.editor,
    this.startInTranslation = true,
  });

  final String? initialName;
  final String? initialPath;
  final String? initialContent;
  final EditorController? editor;
  final bool startInTranslation;

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class TranslateFromEditorScreen extends StatelessWidget {
  const TranslateFromEditorScreen({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final name = '${editor.project.name}.srt';
    final content = SrtCodec.encode(editor.project.subtitles.cues);
    return TranslateScreen(
      initialName: name,
      initialPath: name,
      initialContent: content,
      editor: editor,
    );
  }
}

class _TranslateScreenState extends State<TranslateScreen> {
  late final TranslationController controller;

  @override
  void initState() {
    super.initState();
    controller = TranslationController(context.read<AppServices>())
      ..addListener(_refresh);
    if (widget.initialContent != null) {
      controller.setSource(
        name: widget.initialName ?? 'subtitles.srt',
        path: widget.initialPath ?? widget.initialName ?? 'subtitles.srt',
        content: widget.initialContent!,
      );
    }
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

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['srt', 'txt'],
    );
    if (file == null || !mounted) return;
    final extension = SubtitleFormats.extensionOf(file.name);
    if (!SubtitleFormats.isTranslationSource(file.name)) {
      showAppSnack(
        context,
        'Translation accepts .srt and .txt only.',
        error: true,
      );
      return;
    }
    try {
      final content = utf8.decode(
        await file.readAsBytes(),
        allowMalformed: true,
      );
      controller.setSource(
        name: file.name,
        path: file.path ?? '${file.name}.$extension',
        content: content,
      );
    } catch (error) {
      if (mounted) showAppSnack(context, '$error', error: true);
    }
  }

  void _useProjectSubtitles() {
    final editor = widget.editor;
    if (editor == null || editor.project.subtitles.cues.isEmpty) {
      showAppSnack(
        context,
        'The project has no subtitle cues yet.',
        error: true,
      );
      return;
    }
    final name = '${editor.project.name}.srt';
    controller.setSource(
      name: name,
      path: name,
      content: SrtCodec.encode(editor.project.subtitles.cues),
    );
  }

  Future<void> _start(ModelsController models) async {
    final installed = models.installedTranslation;
    if (installed == null) {
      showAppSnack(
        context,
        'Install a translation model in the model library first.',
        error: true,
      );
      return;
    }
    await controller.start(installed);
    if (!mounted) return;
    if (controller.status == TranslationStatus.failed &&
        controller.error != null) {
      showAppSnack(context, controller.error!, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelsController>();
    final installed = models.installedTranslationModels;
    final selected = models.installedTranslation;
    final isSrt = controller.isSrt;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 14, 0),
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
                            'Offline translation',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'SRT / TXT → Myanmar with a local GGUF model',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PillButton(
                      label: 'Burmese',
                      icon: Icons.translate_rounded,
                      selected: true,
                      compact: true,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: <Widget>[
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionLabel('Source'),
                          Text(
                            controller.sourceName ?? 'No file selected',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            controller.sourceContent == null
                                ? 'Only .srt and .txt are accepted. Video and '
                                      'audio are rejected before inference.'
                                : '${controller.sourceContent!.length} '
                                      'characters · ${SubtitleFormats.extensionOf(controller.sourcePath ?? '').toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: PillButton(
                                  label: 'Pick SRT/TXT',
                                  icon: Icons.upload_file_rounded,
                                  onTap: controller.isRunning
                                      ? null
                                      : _pickFile,
                                ),
                              ),
                              if (widget.editor != null) ...<Widget>[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: PillButton(
                                    label: 'Project track',
                                    icon: Icons.subtitles_outlined,
                                    onTap: controller.isRunning
                                        ? null
                                        : _useProjectSubtitles,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionLabel('Model'),
                          if (installed.isEmpty)
                            InfoNote(
                              message: installed.isEmpty
                                  ? 'No translation model installed. Download '
                                        'Hy-MT3 1.8B Q4 (≈1.35 GB) from the model '
                                        'library; it lists Burmese (`my`).'
                                  : '',
                              icon: Icons.memory_rounded,
                              color: AppColors.accent,
                            )
                          else
                            DropdownButtonFormField<String>(
                              initialValue: selected?.model.id,
                              dropdownColor: AppColors.surfaceHigh,
                              decoration: const InputDecoration(
                                labelText: 'Local model',
                              ),
                              items: <DropdownMenuItem<String>>[
                                for (final item in installed)
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
                                  : (String? value) =>
                                        models.selectTranslation(value),
                            ),
                          if (selected != null) ...<Widget>[
                            const SizedBox(height: 6),
                            Text(
                              '${selected.model.quantization} · '
                              '${selected.model.totalSizeLabel} · '
                              '${selected.model.licenseLabel}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                                fontFamily: AppFonts.mono,
                              ),
                            ),
                            if (selected.model.burmeseEvidence)
                              const InfoNote(
                                message:
                                    'Upstream model card lists Burmese '
                                    '(`my`). Subtitle quality still depends on '
                                    'the model; review every cue before export.',
                                icon: Icons.verified_outlined,
                                color: AppColors.mint,
                              )
                            else
                              const InfoNote(
                                message:
                                    'Burmese support is not verified for '
                                    'this model. Treat the output as a draft.',
                                icon: Icons.warning_amber_rounded,
                                color: AppColors.danger,
                              ),
                          ],
                          const SizedBox(height: 8),
                          PillButton(
                            label: 'Model library',
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
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionLabel('Instructions (optional)'),
                          TextField(
                            maxLines: 2,
                            onChanged: controller.setContext,
                            decoration: const InputDecoration(
                              hintText: 'Names, tone, or glossary hints for the model',
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Cue timing, cue count and SRT structure are '
                            'preserved. Only the text of each cue is sent to '
                            'the model.',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (controller.isRunning)
                      OutlinedButton.icon(
                        onPressed: controller.cancel,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: const Text('Cancel translation'),
                      )
                    else
                      GradientButton(
                        label: controller.sourceContent == null
                            ? 'Choose a file first'
                            : 'Translate offline',
                        icon: Icons.translate_rounded,
                        onPressed:
                            controller.sourceContent == null || selected == null
                            ? null
                            : () => _start(models),
                      ),
                    _progress(),
                    if (controller.error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      InfoNote(
                        message: controller.error!,
                        icon: Icons.error_outline,
                        color: AppColors.danger,
                      ),
                    ],
                    if (controller.status == TranslationStatus.cancelled)
                      const InfoNote(
                        message:
                            'Cancelled. Completed cues below can still be '
                            'saved as a partial subtitle file.',
                        icon: Icons.pause_circle_outline,
                        color: AppColors.accent,
                      ),
                    if (controller.effectiveOutput.trim().isNotEmpty)
                      _outputCard(isSrt),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress() {
    if (controller.status == TranslationStatus.idle) {
      return const SizedBox.shrink();
    }
    final stageLabel = switch (controller.stage) {
      TranslationStage.validating => 'Validating source file',
      TranslationStage.loadingModel => 'Loading GGUF model',
      TranslationStage.translating => 'Translating cues',
      TranslationStage.completed => 'Translation complete',
      TranslationStage.cancelled => 'Cancelled',
      TranslationStage.failed => 'Failed',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GlassCard(
        highlight: controller.status == TranslationStatus.running,
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                ProgressRing(
                  value: controller.progress,
                  size: 58,
                  strokeWidth: 5,
                  color: controller.status == TranslationStatus.failed
                      ? AppColors.danger
                      : AppColors.accent,
                  center: Text(
                    '${(controller.progress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFonts.mono,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        stageLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (controller.totalBatches > 0)
                        Text(
                          '${controller.completedBatches} / '
                          '${controller.totalBatches} batches',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontFamily: AppFonts.mono,
                          ),
                        ),
                      Text(
                        'Model runs on this device; no network requests.',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (controller.status == TranslationStatus.running)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: ShimmerBar(),
              ),
            if (controller.preview != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Text(
                  controller.preview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontFamily: AppFonts.myanmar,
                    color: AppColors.textPrimary,
                  ),
                ),
              ).animate().fadeIn(duration: 220.ms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _outputCard(bool isSrt) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(child: SectionLabel('Review & export')),
                Text(
                  isSrt
                      ? '${controller.reviewedCues.length} cues'
                      : '${controller.effectiveOutput.length} chars',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            if (isSrt)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: controller.reviewedCues.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (BuildContext context, int index) {
                    final cue = controller.reviewedCues[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${TimeUtils.timecode(cue.start)} → '
                          '${TimeUtils.timecode(cue.end)}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.textMuted,
                            fontFamily: AppFonts.mono,
                          ),
                        ),
                        TextFormField(
                          initialValue: cue.text,
                          maxLines: 2,
                          minLines: 1,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: AppFonts.myanmar,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (String value) =>
                              controller.updateReviewedCue(index, value),
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              SelectableText(
                controller.effectiveOutput,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: AppFonts.myanmar,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: PillButton(
                    label: 'Save file',
                    icon: Icons.save_alt_rounded,
                    onTap: () async {
                      try {
                        final path = await controller.saveResult();
                        if (!mounted) return;
                        showAppSnack(context, 'Saved to $path');
                      } catch (error) {
                        if (!mounted) return;
                        showAppSnack(context, '$error', error: true);
                      }
                    },
                  ),
                ),
                if (widget.editor != null && isSrt) ...<Widget>[
                  const SizedBox(width: 6),
                  Expanded(
                    child: PillButton(
                      label: 'Apply to project',
                      icon: Icons.check_circle_outline_rounded,
                      selected: true,
                      onTap: () {
                        final message = controller.applyToEditor(
                          widget.editor!,
                        );
                        showAppSnack(context, message);
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Every cue stays editable. Save writes UTF-8 SRT/TXT into the '
              'app exports folder; nothing is uploaded.',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
