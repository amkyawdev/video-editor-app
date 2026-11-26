import 'package:material_ui/material_ui.dart';

import '../../../data/models/clip.dart';
import '../../../state/editor_controller.dart';
import '../../../widgets/common.dart';
import 'panel_controls.dart';

class EffectsPanel extends StatelessWidget {
  const EffectsPanel({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final clip = editor.selectedClip;
    if (clip == null) {
      return const InfoNote(
        message:
            'Select a clip to grade it, add effects, crop or set a '
            'transition into the next cut.',
      );
    }
    final grade = clip.grade;
    final effects = clip.effects;
    final crop = clip.crop;
    final transition = clip.transitionIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PanelSection(
          title: 'Colour grade',
          children: <Widget>[
            SliderRow(
              label: 'Brightness',
              value: grade.brightness,
              min: -1,
              max: 1,
              valueLabel: grade.brightness.toStringAsFixed(2),
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(grade: grade.copyWith(brightness: value)),
              ),
              onReset: () => editor.updateClip(
                clip.copyWith(grade: grade.copyWith(brightness: 0)),
              ),
            ),
            SliderRow(
              label: 'Contrast',
              value: grade.contrast,
              min: 0,
              max: 2,
              valueLabel: grade.contrast.toStringAsFixed(2),
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(grade: grade.copyWith(contrast: value)),
              ),
              onReset: () => editor.updateClip(
                clip.copyWith(grade: grade.copyWith(contrast: 1)),
              ),
            ),
            SliderRow(
              label: 'Saturation',
              value: grade.saturation,
              min: 0,
              max: 3,
              valueLabel: grade.saturation.toStringAsFixed(2),
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(grade: grade.copyWith(saturation: value)),
              ),
              onReset: () => editor.updateClip(
                clip.copyWith(grade: grade.copyWith(saturation: 1)),
              ),
            ),
          ],
        ),
        PanelSection(
          title: 'Effects',
          children: <Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Black & white',
                style: TextStyle(fontSize: 12),
              ),
              value: effects.grayscale,
              onChanged: (bool value) => editor.updateClip(
                clip.copyWith(effects: effects.copyWith(grayscale: value)),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Mirror horizontally',
                style: TextStyle(fontSize: 12),
              ),
              value: effects.mirror,
              onChanged: (bool value) => editor.updateClip(
                clip.copyWith(effects: effects.copyWith(mirror: value)),
              ),
            ),
            SliderRow(
              label: 'Vignette',
              value: effects.vignette,
              min: 0,
              max: 1,
              valueLabel: '${(effects.vignette * 100).round()}%',
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(effects: effects.copyWith(vignette: value)),
              ),
              onReset: () => editor.updateClip(
                clip.copyWith(effects: effects.copyWith(vignette: 0)),
              ),
            ),
          ],
        ),
        PanelSection(
          title: 'Transition into the next cut',
          children: <Widget>[
            SegmentedRow<TransitionType>(
              options: TransitionType.values,
              labelOf: (TransitionType value) => value.label,
              selected: transition.type,
              onSelected: (TransitionType value) => editor.updateClip(
                clip.copyWith(transitionIn: transition.copyWith(type: value)),
              ),
            ),
            const SizedBox(height: 6),
            SliderRow(
              label: 'Transition length',
              value: transition.durationUs / 1000000,
              min: 0.1,
              max: 2,
              divisions: 19,
              valueLabel:
                  '${(transition.durationUs / 1000000).toStringAsFixed(1)}s',
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(
                  transitionIn: transition.copyWith(
                    durationUs: (value * 1000000).round(),
                  ),
                ),
              ),
            ),
            const InfoNote(
              message:
                  'Transitions use FFmpeg xfade, so the two clips overlap '
                  'by the chosen duration. Audio crossfades with acrossfade.',
            ),
          ],
        ),
        PanelSection(
          title: 'Crop & reframe',
          children: <Widget>[
            SliderRow(
              label: 'Crop left (${(crop.left * 100).round()}%)',
              value: crop.left,
              min: 0,
              max: 0.45,
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(crop: crop.copyWith(left: value)),
              ),
              valueLabel: '',
            ),
            SliderRow(
              label: 'Crop right (${(crop.right * 100).round()}%)',
              value: crop.right,
              min: 0,
              max: 0.45,
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(crop: crop.copyWith(right: value)),
              ),
              valueLabel: '',
            ),
            SliderRow(
              label: 'Crop top (${(crop.top * 100).round()}%)',
              value: crop.top,
              min: 0,
              max: 0.45,
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(crop: crop.copyWith(top: value)),
              ),
              valueLabel: '',
            ),
            SliderRow(
              label: 'Crop bottom (${(crop.bottom * 100).round()}%)',
              value: crop.bottom,
              min: 0,
              max: 0.45,
              onChanged: (double value) => editor.updateClip(
                clip.copyWith(crop: crop.copyWith(bottom: value)),
              ),
              valueLabel: '',
            ),
            SliderRow(
              label: 'Zoom',
              value: clip.scale,
              min: 1,
              max: 3,
              valueLabel: '${clip.scale.toStringAsFixed(2)}x',
              onChanged: (double value) =>
                  editor.updateClip(clip.copyWith(scale: value)),
              onReset: () => editor.updateClip(clip.copyWith(scale: 1)),
            ),
            SliderRow(
              label: 'Pan X',
              value: clip.offsetX,
              min: -1,
              max: 1,
              valueLabel: clip.offsetX.toStringAsFixed(2),
              onChanged: (double value) =>
                  editor.updateClip(clip.copyWith(offsetX: value)),
              onReset: () => editor.updateClip(clip.copyWith(offsetX: 0)),
            ),
            SliderRow(
              label: 'Pan Y',
              value: clip.offsetY,
              min: -1,
              max: 1,
              valueLabel: clip.offsetY.toStringAsFixed(2),
              onChanged: (double value) =>
                  editor.updateClip(clip.copyWith(offsetY: value)),
              onReset: () => editor.updateClip(clip.copyWith(offsetY: 0)),
            ),
            SliderRow(
              label: 'Opacity',
              value: clip.opacity,
              min: 0,
              max: 1,
              valueLabel: '${(clip.opacity * 100).round()}%',
              onChanged: (double value) =>
                  editor.updateClip(clip.copyWith(opacity: value)),
              onReset: () => editor.updateClip(clip.copyWith(opacity: 1)),
            ),
            PillButton(
              label: 'Reset crop',
              compact: true,
              onTap: () =>
                  editor.updateClip(clip.copyWith(crop: CropRect.full)),
            ),
          ],
        ),
      ],
    );
  }
}
