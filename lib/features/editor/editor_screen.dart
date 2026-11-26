import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/project.dart';
import '../../data/models/subtitle.dart';
import '../../state/app_services.dart';
import '../../state/editor_controller.dart';
import '../../widgets/common.dart';
import '../subtitles/subtitle_studio_screen.dart';
import '../subtitles/translate_screen.dart';
import 'panels/audio_panel.dart';
import 'panels/clip_panel.dart';
import 'panels/effects_panel.dart';
import 'panels/export_sheet.dart';
import 'panels/media_panel.dart';
import 'panels/subtitle_panel.dart';
import 'widgets/preview_stage.dart';
import 'fullscreen_preview_screen.dart';
import 'widgets/timeline_view.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.project,
    this.openMediaPickerOnStart = false,
  });

  final Project project;
  final bool openMediaPickerOnStart;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController controller;
  int _panel = 0;
  bool _busy = false;

  static const List<String> _mediaExtensions = <String>[
    'mp4',
    'mov',
    'mkv',
    'webm',
    'm4v',
    'avi',
    '3gp',
    'mp3',
    'm4a',
    'wav',
    'aac',
    'flac',
    'ogg',
    'opus',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  @override
  void initState() {
    super.initState();
    controller = EditorController(
      project: widget.project,
      services: context.read<AppServices>(),
    );
    if (widget.openMediaPickerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickMedia());
    }
  }

  @override
  void dispose() {
    unawaited(controller.flush());
    controller.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _mediaExtensions,
    );
    if (!mounted) return;
    if (files.isEmpty) return;
    setState(() => _busy = true);
    var added = 0;
    final failures = <String>[];
    for (final file in files) {
      final path = await _materialize(file);
      if (path == null) {
        failures.add('${file.name}: no readable path from the picker.');
        continue;
      }
      try {
        final asset = await controller.importMedia(File(path));
        if (mounted) controller.addAssetToTimeline(asset);
        added++;
      } catch (error) {
        failures.add('${path.split('/').last}: $error');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (added > 0) {
      showAppSnack(context, 'Imported $added file${added == 1 ? '' : 's'}.');
    }
    if (failures.isNotEmpty) {
      showAppSnack(context, failures.first, error: true);
    }
  }

  Future<String?> _materialize(PlatformFile file) async {
    final existing = file.path;
    if (existing != null) return existing;
    final dir = Directory('${controller.services.cacheDir.path}/imports');
    await dir.create(recursive: true);
    final target = File(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_${file.name}',
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

  Future<void> _pickSubtitle() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['srt', 'vtt'],
    );
    if (file == null || !mounted) return;
    try {
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      controller.importSubtitleText(file.name, content);
      if (mounted) {
        showAppSnack(
          context,
          'Imported ${controller.project.subtitles.cueCount} cues.',
        );
      }
    } catch (error) {
      if (mounted) showAppSnack(context, '$error', error: true);
    }
  }

  Future<void> _exportSubtitle() async {
    try {
      final path = await controller.exportSubtitles(SubtitleFormat.srt);
      if (mounted) showAppSnack(context, 'Saved SRT: $path');
    } catch (error) {
      if (mounted) showAppSnack(context, '$error', error: true);
    }
  }

  void _openStudio() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubtitleStudioScreen(editor: controller),
      ),
    );
  }

  void _openTranslate() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TranslateFromEditorScreen(editor: controller),
      ),
    );
  }

  Future<void> _openExport() async {
    await controller.flush();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportSheet(project: controller.project),
    );
  }

  Future<void> _rename() async {
    final text = TextEditingController(text: controller.project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Project name'),
        content: TextField(controller: text, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name != null) controller.renameProject(name);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EditorController>.value(
      value: controller,
      child: PopScope(
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) unawaited(controller.flush());
        },
        child: Scaffold(
          backgroundColor: AppColors.ink,
          body: SafeArea(
            child: Consumer<EditorController>(
              builder: (BuildContext context, EditorController editor, _) {
                return LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final wide = constraints.maxWidth >= 640;
                    final previewHeight = wide
                        ? (constraints.maxHeight * 0.55).clamp(240.0, 520.0)
                        : (constraints.maxHeight * 0.40).clamp(200.0, 430.0);
                    final timelineHeight =
                        (constraints.maxHeight * (wide ? 0.28 : 0.20))
                            .clamp(130.0, 210.0);
                    final timeline = SizedBox(
                      height: timelineHeight,
                      child: TimelineView(
                        onCueTap: (_) => setState(() => _panel = 3),
                      ),
                    );
                    final panel = Column(
                      children: <Widget>[
                        _toolBar(editor),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                            child: _panelBody(editor),
                          ),
                        ),
                      ],
                    );
                    return Column(
                      children: <Widget>[
                        _header(editor),
                        Expanded(
                          child: wide
                              ? Row(
                                  children: <Widget>[
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        children: <Widget>[
                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      12, 2, 12, 0),
                                              child: PreviewStage(
                                                onExpand: _openFullscreen,
                                              ),
                                            ),
                                          ),
                                          timeline,
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 340,
                                      decoration: const BoxDecoration(
                                        color: AppColors.panel,
                                        border: Border(
                                          left:
                                              BorderSide(color: AppColors.stroke),
                                        ),
                                      ),
                                      child: panel,
                                    ),
                                  ],
                                )
                              : Column(
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 2, 14, 0),
                                      child: SizedBox(
                                        height: previewHeight,
                                        child: PreviewStage(
                                          onExpand: _openFullscreen,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _toolBar(editor),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(
                                            14, 8, 14, 4),
                                        child: _panelBody(editor),
                                      ),
                                    ),
                                    timeline,
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<EditorController>.value(
          value: controller,
          child: FullscreenPreviewScreen(editor: controller),
        ),
      ),
    );
  }

  Widget _header(EditorController editor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 2),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () async {
              await editor.flush();
              if (mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _rename,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          editor.project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.edit_outlined,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  Text(
                    editor.isSaving
                        ? 'Saving…'
                        : editor.isDirty
                        ? 'Unsaved changes'
                        : 'Saved locally',
                    style: TextStyle(
                      fontSize: 10,
                      color: editor.isDirty
                          ? AppColors.accent
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: editor.canUndo ? editor.undo : null,
            icon: const Icon(Icons.undo_rounded, size: 19),
            color: editor.canUndo ? AppColors.textSecondary : AppColors.stroke,
          ),
          IconButton(
            onPressed: editor.canRedo ? editor.redo : null,
            icon: const Icon(Icons.redo_rounded, size: 19),
            color: editor.canRedo ? AppColors.textSecondary : AppColors.stroke,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Import media',
            onPressed: _busy ? null : _pickMedia,
            icon: const Icon(Icons.download_rounded, size: 19),
            color: AppColors.textSecondary,
          ),
          GestureDetector(
            onTap: _openExport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.ios_share_rounded,
                    size: 15,
                    color: Color(0xFF1A1204),
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Export',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1204),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBar(EditorController editor) {
    const groups = <_ToolGroup>[
      _ToolGroup('Media', Icons.perm_media_outlined),
      _ToolGroup('Trim & Clip', Icons.content_cut_rounded),
      _ToolGroup('Audio', Icons.graphic_eq_rounded),
      _ToolGroup('Subtitles', Icons.subtitles_outlined),
      _ToolGroup('Effects', Icons.auto_fix_high_rounded),
    ];
    final current = groups[_panel];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 0),
      child: Row(
        children: <Widget>[
          PopupMenuButton<int>(
            initialValue: _panel,
            color: AppColors.surfaceHigh,
            onSelected: (int index) => setState(() => _panel = index),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
              for (var i = 0; i < groups.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        groups[i].icon,
                        size: 16,
                        color: i == _panel
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        groups[i].label,
                        style: TextStyle(
                          fontSize: 12,
                          color: i == _panel
                              ? AppColors.accent
                              : AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (i == _panel)
                        const Icon(Icons.check_rounded,
                            size: 15, color: AppColors.accent),
                    ],
                  ),
                ),
            ],
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.alpha(AppColors.accent, 0.14),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: AppColors.alpha(AppColors.accent, 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(current.icon, size: 15, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    current.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _QuickTool(
                  icon: Icons.download_rounded,
                  tooltip: 'Import media',
                  onTap: _busy ? null : _pickMedia,
                ),
                _QuickTool(
                  icon: Icons.content_cut_rounded,
                  tooltip: 'Split at playhead',
                  onTap: editor.canSplit ? editor.splitAtPlayhead : null,
                ),
                _QuickTool(
                  icon: Icons.subtitles_outlined,
                  tooltip: 'Add subtitle cue',
                  onTap: () => editor.addCueAtPlayhead(),
                ),
                _QuickTool(
                  icon: Icons.ios_share_rounded,
                  tooltip: 'Export',
                  onTap: _openExport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelBody(EditorController editor) {
    switch (_panel) {
      case 0:
        return MediaPanel(
          editor: editor,
          busy: _busy,
          onPickMedia: _pickMedia,
          onPickSubtitle: _pickSubtitle,
          onExportSubtitle: _exportSubtitle,
          onOpenStudio: _openStudio,
          onTranslate: _openTranslate,
        );
      case 1:
        return ClipPanel(editor: editor);
      case 2:
        return AudioPanel(editor: editor);
      case 3:
        return SubtitlePanel(
          editor: editor,
          onOpenStudio: _openStudio,
          onImport: _pickSubtitle,
          onExport: _exportSubtitle,
          onTranslate: _openTranslate,
        );
      default:
        return EffectsPanel(editor: editor);
    }
  }
}

class _ToolGroup {
  const _ToolGroup(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _QuickTool extends StatelessWidget {
  const _QuickTool({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppColors.textSecondary : AppColors.stroke,
          ),
        ),
      ),
    );
  }
}
