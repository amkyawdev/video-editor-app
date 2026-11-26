import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/clip.dart';
import '../../../state/editor_controller.dart';
import '../../../widgets/common.dart';
import 'panel_controls.dart';

class ClipPanel extends StatelessWidget {
  const ClipPanel({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final clip = editor.selectedClip;
    final track = clip == null ? null : editor.project.trackOfClip(clip.id);
    final asset = editor.selectedClipAsset;
    if (clip == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const InfoNote(
            message:
                'Select a clip on the timeline to trim, split, retime or '
                'transform it.',
          ),
          const SizedBox(height: 10),
          PanelSection(
            title: 'Quick actions',
            children: <Widget>[
              ActionTile(
                icon: Icons.content_cut_rounded,
                label: 'Split at playhead',
                subtitle: editor.canSplit
                    ? 'Cuts the clip under the playhead into two clips.'
                    : 'Move the playhead inside a clip (not the first/last '
                          '200 ms) to enable split.',
                onTap: editor.canSplit ? editor.splitAtPlayhead : null,
              ),
              ActionTile(
                icon: Icons.library_add_outlined,
                label: 'Add overlay video track',
                subtitle: 'Picture-in-picture lane, composited on export.',
                accent: AppColors.violet,
                onTap: editor.addOverlayTrack,
              ),
              ActionTile(
                icon: Icons.graphic_eq_rounded,
                label: 'Add audio track',
                subtitle: 'Extra music or voice lane with volume mixing.',
                accent: AppColors.mint,
                onTap: editor.addAudioTrack,
              ),
            ],
          ),
          if (editor.project.primaryClips.isNotEmpty)
            PanelSection(
              title: 'Clips on the video track',
              children: <Widget>[
                for (final item in editor.project.primaryClips)
                  ActionTile(
                    icon: Icons.movie_outlined,
                    label:
                        item.label ??
                        editor.project.assetFor(item.assetId)?.name ??
                        'Clip',
                    subtitle:
                        '${TimeUtils.timecode(item.duration)} · ${item.speed}x',
                    onTap: () => editor.selectClip(item.id),
                  ),
              ],
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                clip.label ?? asset?.name ?? 'Selected clip',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              track == null ? '' : '${track.name} · ${clip.speed}x',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Source ${TimeUtils.timecode(clip.sourceIn)} → '
          '${TimeUtils.timecode(clip.sourceOut)} · '
          'Timeline ${TimeUtils.timecode(clip.duration)}',
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
            fontFamily: AppFonts.mono,
          ),
        ),
        const SizedBox(height: 12),
        PanelSection(
          title: 'Trim',
          children: <Widget>[
            _NudgeRow(
              label: 'Start',
              onMinus: () => editor.trimSelectedStart(-500000),
              onPlus: () => editor.trimSelectedStart(500000),
              minusLabel: '−0.5s',
              plusLabel: '+0.5s',
            ),
            const SizedBox(height: 6),
            _NudgeRow(
              label: 'End',
              onMinus: () => editor.trimSelectedEnd(-500000),
              onPlus: () => editor.trimSelectedEnd(500000),
              minusLabel: '−0.5s',
              plusLabel: '+0.5s',
            ),
            const SizedBox(height: 6),
            _NudgeRow(
              label: 'Fine',
              onMinus: () => editor.trimSelectedEnd(-100000),
              onPlus: () => editor.trimSelectedEnd(100000),
              minusLabel: '−0.1s',
              plusLabel: '+0.1s',
            ),
          ],
        ),
        PanelSection(
          title: 'Retime & mix',
          children: <Widget>[
            SliderRow(
              label: 'Speed',
              value: clip.speed,
              min: 0.25,
              max: 4,
              divisions: 15,
              valueLabel: '${clip.speed.toStringAsFixed(2)}x',
              onChanged: editor.setClipSpeed,
              onReset: () => editor.setClipSpeed(1),
            ),
            SliderRow(
              label: 'Clip volume',
              value: clip.volume,
              min: 0,
              max: 2,
              valueLabel: '${(clip.volume * 100).round()}%',
              onChanged: (double value) =>
                  editor.updateClip(clip.copyWith(volume: value)),
              onReset: () =>
                  editor.updateClip(clip.copyWith(volume: 1, muted: false)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Mute clip audio',
                style: TextStyle(fontSize: 12),
              ),
              value: clip.muted,
              onChanged: (bool value) =>
                  editor.updateClip(clip.copyWith(muted: value)),
            ),
          ],
        ),
        PanelSection(
          title: 'Frame',
          children: <Widget>[
            SegmentedRow<int>(
              options: const <int>[0, 90, 180, 270],
              labelOf: (int value) => '$value°',
              selected: clip.rotation,
              onSelected: (int value) =>
                  editor.updateClip(clip.copyWith(rotation: value)),
            ),
            const SizedBox(height: 10),
            SegmentedRow<MediaFit>(
              options: MediaFit.values,
              labelOf: (MediaFit value) => switch (value) {
                MediaFit.contain => 'Fit',
                MediaFit.cover => 'Fill',
                MediaFit.stretch => 'Stretch',
              },
              selected: clip.fit,
              onSelected: (MediaFit value) =>
                  editor.updateClip(clip.copyWith(fit: value)),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: 'Split',
                icon: Icons.content_cut_rounded,
                onTap: editor.canSplit ? editor.splitAtPlayhead : null,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PillButton(
                label: 'Merge next',
                icon: Icons.merge_type_rounded,
                onTap: editor.canMergeSelected
                    ? editor.mergeSelectedWithNext
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PillButton(
                label: 'Delete',
                icon: Icons.delete_outline_rounded,
                danger: true,
                onTap: editor.deleteSelectedClip,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NudgeRow extends StatelessWidget {
  const _NudgeRow({
    required this.label,
    required this.onMinus,
    required this.onPlus,
    required this.minusLabel,
    required this.plusLabel,
  });

  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final String minusLabel;
  final String plusLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: PillButton(label: minusLabel, onTap: onMinus),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: PillButton(label: plusLabel, onTap: onPlus),
        ),
      ],
    );
  }
}
