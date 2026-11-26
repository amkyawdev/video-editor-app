import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../data/models/local_model.dart';
import '../../../data/models/media_asset.dart';
import '../../../state/editor_controller.dart';
import '../../../widgets/common.dart';
import 'panel_controls.dart';

class MediaPanel extends StatelessWidget {
  const MediaPanel({
    super.key,
    required this.editor,
    required this.busy,
    required this.onPickMedia,
    required this.onPickSubtitle,
    required this.onExportSubtitle,
    required this.onOpenStudio,
    required this.onTranslate,
  });

  final EditorController editor;
  final bool busy;
  final VoidCallback onPickMedia;
  final VoidCallback onPickSubtitle;
  final VoidCallback onExportSubtitle;
  final VoidCallback onOpenStudio;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    final project = editor.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PanelSection(
          title: 'Import',
          children: <Widget>[
            ActionTile(
              icon: Icons.add_photo_alternate_outlined,
              label: busy ? 'Importing…' : 'Import video, audio or image',
              subtitle:
                  'Copied into this project folder. MP4, MOV, MKV, WebM, '
                  'MP3, WAV, JPG, PNG, WebP.',
              onTap: busy ? null : onPickMedia,
              trailing: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
            ActionTile(
              icon: Icons.subtitles_outlined,
              label: 'Import SRT / VTT',
              subtitle:
                  'Replaces the subtitle track. UTF-8 and Myanmar '
                  'Unicode are preserved.',
              accent: AppColors.mint,
              onTap: onPickSubtitle,
            ),
          ],
        ),
        PanelSection(
          title: 'Project media · ${project.media.length}',
          children: <Widget>[
            if (project.media.isEmpty)
              const InfoNote(
                message: 'No media yet. Import a file to start the timeline.',
              ),
            for (final asset in project.media)
              _AssetRow(editor: editor, asset: asset),
          ],
        ),
        PanelSection(
          title: 'Subtitle track',
          trailing: Text(
            '${project.subtitles.cueCount} cues',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          children: <Widget>[
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
                    label: 'Export',
                    icon: Icons.file_download_outlined,
                    onTap: project.subtitles.cues.isEmpty
                        ? null
                        : onExportSubtitle,
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
            const InfoNote(
              message:
                  'Media and subtitles stay on this device. Nothing is '
                  'uploaded; translation runs on a local GGUF model.',
            ),
          ],
        ),
      ],
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.editor, required this.asset});

  final EditorController editor;
  final MediaAsset asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ThumbnailImage(
              path: asset.thumbnailPath,
              width: 54,
              height: 36,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${asset.kind.name} · ${TimeUtils.timecode(asset.duration)} · '
                  '${LocalModelFile.formatBytes(asset.sizeBytes)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    fontFamily: AppFonts.mono,
                  ),
                ),
              ],
            ),
          ),
          if (asset.isVisual)
            IconButton(
              tooltip: 'Add as overlay track',
              onPressed: () => editor.addAssetToTimeline(asset, overlay: true),
              icon: const Icon(Icons.layers_outlined, size: 17),
              color: AppColors.violet,
            ),
          IconButton(
            tooltip: asset.isAudio ? 'Add to audio track' : 'Add to timeline',
            onPressed: () => editor.addAssetToTimeline(asset),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
