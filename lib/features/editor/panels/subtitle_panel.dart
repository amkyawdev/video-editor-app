import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/subtitle.dart';
import '../../../state/editor_controller.dart';
import '../../../widgets/common.dart';
import 'panel_controls.dart';

class SubtitlePanel extends StatelessWidget {
  const SubtitlePanel({
    super.key,
    required this.editor,
    required this.onOpenStudio,
    required this.onImport,
    required this.onExport,
    required this.onTranslate,
  });

  final EditorController editor;
  final VoidCallback onOpenStudio;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    final document = editor.project.subtitles;
    final style = document.style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: 'Add cue at playhead',
                icon: Icons.add_rounded,
                selected: true,
                onTap: () => editor.addCueAtPlayhead(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: 'Studio',
                icon: Icons.open_in_full_rounded,
                onTap: onOpenStudio,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PillButton(
                label: 'Import',
                icon: Icons.file_upload_outlined,
                onTap: onImport,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PillButton(
                label: 'Translate',
                icon: Icons.translate_rounded,
                onTap: onTranslate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: 'Shift −0.5s',
                compact: true,
                onTap: () =>
                    editor.shiftCues(const Duration(milliseconds: -500)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PillButton(
                label: 'Shift +0.5s',
                compact: true,
                onTap: () =>
                    editor.shiftCues(const Duration(milliseconds: 500)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PillButton(
                label: 'Export SRT',
                compact: true,
                onTap: document.cues.isEmpty ? null : onExport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        PanelSection(
          title: 'Cues · ${document.cueCount}',
          children: <Widget>[
            if (document.cues.isEmpty)
              const InfoNote(
                message:
                    'No cues yet. Add one at the playhead, import SRT/VTT '
                    'or generate them in the studio.',
              ),
            for (final cue in document.cues.take(40))
              _CueRow(editor: editor, cue: cue),
            if (document.cues.length > 40)
              Text(
                '+${document.cues.length - 40} more cues in the studio',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
        PanelSection(
          title: 'Style',
          trailing: const Text(
            'Also used for burn-in',
            style: TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
          children: <Widget>[
            SegmentedRow<String>(
              options: const <String>[
                'NotoSansMyanmar',
                'Inter',
                'JetBrainsMono',
              ],
              labelOf: (String value) => switch (value) {
                'NotoSansMyanmar' => 'Myanmar',
                'JetBrainsMono' => 'Mono',
                _ => 'Inter',
              },
              selected: style.fontFamily,
              onSelected: (String value) =>
                  editor.applySubtitleStyle(style.copyWith(fontFamily: value)),
            ),
            const SizedBox(height: 8),
            SliderRow(
              label: 'Size',
              value: style.fontSize,
              min: 24,
              max: 96,
              divisions: 36,
              valueLabel: '${style.fontSize.round()}',
              onChanged: (double value) =>
                  editor.applySubtitleStyle(style.copyWith(fontSize: value)),
            ),
            SegmentedRow<SubtitleAlignment>(
              options: SubtitleAlignment.values,
              labelOf: (SubtitleAlignment value) => value.name,
              selected: style.alignment,
              onSelected: (SubtitleAlignment value) =>
                  editor.applySubtitleStyle(style.copyWith(alignment: value)),
            ),
            const SizedBox(height: 10),
            const Text(
              'Text colour',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            ColorSwatches(
              selected: style.primaryColor,
              onSelected: (int color) => editor.applySubtitleStyle(
                style.copyWith(primaryColor: color),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Outline colour',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            ColorSwatches(
              selected: style.outlineColor,
              options: const <int>[
                0xFF000000,
                0xFFFFFFFF,
                0xFFF2B24A,
                0xFF8B7BFF,
                0xFF4FE0B0,
              ],
              onSelected: (int color) => editor.applySubtitleStyle(
                style.copyWith(outlineColor: color),
              ),
            ),
            const SizedBox(height: 6),
            SliderRow(
              label: 'Outline',
              value: style.outlineWidth,
              min: 0,
              max: 8,
              divisions: 16,
              valueLabel: style.outlineWidth.toStringAsFixed(1),
              onChanged: (double value) => editor.applySubtitleStyle(
                style.copyWith(outlineWidth: value),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Background box',
                style: TextStyle(fontSize: 12),
              ),
              value: style.hasBackground,
              onChanged: (bool value) => editor.applySubtitleStyle(
                style.copyWith(
                  backgroundColor: value ? 0xB3000000 : 0x00000000,
                ),
              ),
            ),
            SliderRow(
              label: 'Vertical margin',
              value: style.marginVertical,
              min: 0,
              max: 30,
              divisions: 30,
              valueLabel: '${style.marginVertical.round()}%',
              onChanged: (double value) => editor.applySubtitleStyle(
                style.copyWith(marginVertical: value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CueRow extends StatelessWidget {
  const _CueRow({required this.editor, required this.cue});

  final EditorController editor;
  final SubtitleCue cue;

  Future<void> _edit(BuildContext context) async {
    final text = TextEditingController(text: cue.text);
    final start = TextEditingController(
      text: (cue.startUs / 1000000).toStringAsFixed(2),
    );
    final end = TextEditingController(
      text: (cue.endUs / 1000000).toStringAsFixed(2),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Edit cue'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: text,
                maxLines: 4,
                minLines: 2,
                style: const TextStyle(fontFamily: AppFonts.myanmar),
                decoration: const InputDecoration(labelText: 'Text'),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: start,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Start (s)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: end,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'End (s)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      final startUs = ((double.tryParse(start.text) ?? 0) * 1000000).round();
      final endUs = ((double.tryParse(end.text) ?? 0) * 1000000).round();
      editor.updateCue(
        cue.copyWith(text: text.text, startUs: startUs, endUs: endUs),
      );
    }
    text.dispose();
    start.dispose();
    end.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = editor.selectedCueId == cue.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.alpha(AppColors.violet, 0.12)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? AppColors.alpha(AppColors.violet, 0.5)
              : AppColors.stroke,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: () {
                editor.selectCue(cue.id);
                editor.setPlayhead(cue.start);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    cue.text.isEmpty ? '(empty)' : cue.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppFonts.myanmar,
                    ),
                  ),
                  Text(
                    '${TimeUtils.timecode(cue.start)} → '
                    '${TimeUtils.timecode(cue.end)}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textMuted,
                      fontFamily: AppFonts.mono,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit_outlined, size: 15),
            color: AppColors.textSecondary,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => editor.deleteCue(cue.id),
            icon: const Icon(Icons.close_rounded, size: 15),
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}
