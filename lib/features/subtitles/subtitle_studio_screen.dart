import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/subtitle.dart';
import '../../state/editor_controller.dart';
import '../../widgets/common.dart';
import '../editor/panels/subtitle_panel.dart';
import 'translate_screen.dart';

class SubtitleStudioScreen extends StatefulWidget {
  const SubtitleStudioScreen({super.key, required this.editor});

  final EditorController editor;

  @override
  State<SubtitleStudioScreen> createState() => _SubtitleStudioScreenState();
}

class _SubtitleStudioScreenState extends State<SubtitleStudioScreen> {
  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['srt', 'vtt'],
    );
    if (file == null || !mounted) return;
    try {
      final content = utf8.decode(
        await file.readAsBytes(),
        allowMalformed: true,
      );
      widget.editor.importSubtitleText(file.name, content);
      if (mounted) {
        showAppSnack(
          context,
          'Imported ${widget.editor.project.subtitles.cueCount} cues.',
        );
      }
    } catch (error) {
      if (mounted) showAppSnack(context, '$error', error: true);
    }
  }

  Future<void> _export(SubtitleFormat format) async {
    try {
      final path = await widget.editor.exportSubtitles(format);
      if (mounted) showAppSnack(context, 'Saved ${format.label}: $path');
    } catch (error) {
      if (mounted) showAppSnack(context, '$error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EditorController>.value(
      value: widget.editor,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: Consumer<EditorController>(
          builder: (BuildContext context, EditorController editor, _) {
            final style = editor.project.subtitles.style;
            final cue =
                editor.selectedCue ??
                (editor.project.subtitles.cues.isEmpty
                    ? null
                    : editor.project.subtitles.cues.first);
            return SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 12, 0),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          color: AppColors.textSecondary,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Subtitle studio',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                '${editor.project.subtitles.cueCount} cues · '
                                'SRT / VTT · Myanmar Unicode',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _export(SubtitleFormat.srt),
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 20,
                          ),
                          color: AppColors.textSecondary,
                          tooltip: 'Export SRT',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Container(
                      width: double.infinity,
                      height: 108,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppColors.stageGradient,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.stroke),
                      ),
                      child: Align(
                        alignment: switch (style.alignment) {
                          SubtitleAlignment.bottom => Alignment.bottomCenter,
                          SubtitleAlignment.center => Alignment.center,
                          SubtitleAlignment.top => Alignment.topCenter,
                        },
                        child: Text(
                          cue?.text ?? 'Preview subtitle text',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: style.fontFamily == 'NotoSansMyanmar'
                                ? AppFonts.myanmar
                                : style.fontFamily,
                            fontSize: style.fontSize * 0.22,
                            fontWeight: style.bold
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: Color(style.primaryColor),
                            shadows: <Shadow>[
                              Shadow(
                                color: Color(style.outlineColor),
                                blurRadius: style.outlineWidth * 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: PillButton(
                            label: 'Import',
                            icon: Icons.file_upload_outlined,
                            onTap: _import,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: PillButton(
                            label: 'SRT',
                            icon: Icons.save_alt_rounded,
                            onTap: () => _export(SubtitleFormat.srt),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: PillButton(
                            label: 'VTT',
                            icon: Icons.save_alt_rounded,
                            onTap: () => _export(SubtitleFormat.vtt),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: PillButton(
                            label: 'AI',
                            icon: Icons.translate_rounded,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TranslateFromEditorScreen(editor: editor),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: SubtitlePanel(
                        editor: editor,
                        onOpenStudio: () => Navigator.of(context).pop(),
                        onImport: _import,
                        onExport: () => _export(SubtitleFormat.srt),
                        onTranslate: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                TranslateFromEditorScreen(editor: editor),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
