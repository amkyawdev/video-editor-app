import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../state/editor_controller.dart';
import 'widgets/preview_stage.dart';
import 'widgets/timeline_view.dart';

/// Large, distraction-free preview for live trimming and subtitle checking.
/// Rotating the phone to landscape gives the biggest picture.
class FullscreenPreviewScreen extends StatelessWidget {
  const FullscreenPreviewScreen({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Consumer<EditorController>(
          builder: (BuildContext context, EditorController controller, _) {
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 10, 0),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.textSecondary,
                      ),
                      Expanded(
                        child: Text(
                          controller.project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${controller.project.canvasWidth}×'
                        '${controller.project.canvasHeight}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontFamily: AppFonts.mono,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: const PreviewStage(),
                  ),
                ),
                SizedBox(height: 140, child: TimelineView(onCueTap: (_) {})),
              ],
            );
          },
        ),
      ),
    );
  }
}
