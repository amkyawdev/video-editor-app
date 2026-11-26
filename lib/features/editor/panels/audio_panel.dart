import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../state/editor_controller.dart';
import '../../../widgets/common.dart';
import 'panel_controls.dart';

class AudioPanel extends StatelessWidget {
  const AudioPanel({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final project = editor.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const InfoNote(
          message:
              'Every audio lane is mixed by FFmpeg on export. Preview '
              'plays the clip under the playhead; export is authoritative.',
        ),
        const SizedBox(height: 10),
        PanelSection(
          title: 'Audio tracks · ${project.audioTracks.length}',
          children: <Widget>[
            for (final track in project.audioTracks)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.graphic_eq_rounded,
                          size: 15,
                          color: AppColors.mint,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            track.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: !track.muted,
                          onChanged: (bool value) =>
                              editor.setTrackMuted(track.id, !value),
                        ),
                      ],
                    ),
                    SliderRow(
                      label: 'Lane volume',
                      value: track.volume,
                      min: 0,
                      max: 2,
                      valueLabel: '${(track.volume * 100).round()}%',
                      onChanged: (double value) =>
                          editor.setTrackVolume(track.id, value),
                      onReset: () => editor.setTrackVolume(track.id, 1),
                    ),
                    if (track.clips.isEmpty)
                      const Text(
                        'No clips on this lane. Add an audio file from the '
                        'Media tab.',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    for (final clip in track.clips)
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${editor.project.assetFor(clip.assetId)?.name ?? 'Clip'}'
                              ' · ${TimeUtils.timecode(Duration(microseconds: clip.timelineStartUs), withMillis: false)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontFamily: AppFonts.mono,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => editor.moveClipTo(
                              clip.id,
                              (clip.timelineStartUs - 500000).clamp(0, 1 << 50),
                            ),
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              size: 16,
                            ),
                            color: AppColors.textMuted,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => editor.moveClipTo(
                              clip.id,
                              clip.timelineStartUs + 500000,
                            ),
                            icon: const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                            ),
                            color: AppColors.textMuted,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              editor.selectClip(clip.id);
                              editor.deleteSelectedClip();
                            },
                            icon: const Icon(Icons.close_rounded, size: 15),
                            color: AppColors.danger,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            PillButton(
              label: 'Add audio track',
              icon: Icons.add_rounded,
              onTap: editor.addAudioTrack,
            ),
          ],
        ),
        PanelSection(
          title: 'Audio media',
          children: <Widget>[
            for (final asset in project.media.where((media) => media.isAudio))
              ActionTile(
                icon: Icons.music_note_outlined,
                label: asset.name,
                subtitle:
                    '${TimeUtils.timecode(asset.duration)} · tap to add at playhead',
                accent: AppColors.mint,
                onTap: () => editor.addAssetToTimeline(asset),
              ),
            if (!project.media.any((media) => media.isAudio))
              const Text(
                'No audio files imported yet.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
          ],
        ),
      ],
    );
  }
}
