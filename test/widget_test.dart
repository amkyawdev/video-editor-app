import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_editor_app/app.dart';
import 'package:video_editor_app/data/models/project.dart';
import 'package:video_editor_app/data/repositories/project_repository.dart';
import 'package:video_editor_app/data/repositories/settings_repository.dart';
import 'package:video_editor_app/data/services/ai/asr_service.dart';
import 'package:video_editor_app/data/services/ai/llama_runner.dart';
import 'package:video_editor_app/data/services/ai/recap_service.dart';
import 'package:video_editor_app/data/services/ai/translation_service.dart';
import 'package:video_editor_app/data/services/ffmpeg/media_extraction_service.dart';
import 'package:video_editor_app/data/services/ffmpeg/media_probe_service.dart';
import 'package:video_editor_app/data/services/ffmpeg/render_service.dart';
import 'package:video_editor_app/data/services/media_importer.dart';
import 'package:video_editor_app/data/services/models/model_library_service.dart';
import 'package:video_editor_app/state/app_services.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<AppServices> _services(Directory dir) async {
  final repository = ProjectRepository(dir);
  await repository.init();
  final settings = SettingsRepository(await SharedPreferences.getInstance());
  final runner = LlamaRunner();
  const extraction = MediaExtractionService();
  const probe = MediaProbeService();
  const asr = AsrService();
  return AppServices(
    repository: repository,
    settings: settings,
    cacheDir: dir,
    probe: probe,
    extraction: extraction,
    importer: const MediaImporterService(),
    render: RenderService(),
    models: ModelLibraryService(repository.modelsRoot),
    runner: runner,
    translation: SubtitleTranslationService(runner),
    recap: MovieRecapService(
      runner: runner,
      extraction: extraction,
      probe: probe,
      asr: asr,
    ),
    asr: asr,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'home renders, opens the new-project sheet and enters the editor',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final dir = await Directory.systemTemp.createTemp('amkyaw_widget');
      final services = await _services(dir);
      addTearDown(() async {
        await services.runner.dispose();
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      await tester.pumpWidget(AmkyawApp(services: services));
      await _settle(tester);

      expect(find.text('AMKYAW'), findsOneWidget);
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.text('Offline translation'), findsNothing);

      await tester.tap(find.text('Create a project'));
      await _settle(tester);
      expect(find.text('New project'), findsWidgets);

      await tester.enterText(
        find.byType(TextField).first,
        'Widget test project',
      );
      await tester.tap(find.text('Create project'));
      await _settle(tester);

      expect(find.text('Export'), findsOneWidget);
      expect(find.text('TIMELINE'), findsOneWidget);
      expect(find.text('Media'), findsOneWidget);
      expect(find.text('Clip'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);

      final summaries = await services.repository.list();
      expect(summaries.single.name, 'Widget test project');
    },
  );

  testWidgets('project browser lists an existing project', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final dir = await Directory.systemTemp.createTemp('amkyaw_widget2');
    final services = await _services(dir);
    addTearDown(() async {
      await services.runner.dispose();
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await services.repository.save(Project.blank(name: 'Existing project'));

    await tester.pumpWidget(AmkyawApp(services: services));
    await _settle(tester);

    expect(find.text('Existing project'), findsOneWidget);
    expect(find.text('0 clips'), findsOneWidget);
  });
}
