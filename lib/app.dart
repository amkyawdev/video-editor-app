import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/services/ffmpeg/ffmpeg_capabilities.dart';
import 'features/home/home_screen.dart';
import 'state/app_services.dart';
import 'state/models_controller.dart';
import 'state/projects_controller.dart';

class AmkyawApp extends StatelessWidget {
  const AmkyawApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        ChangeNotifierProvider<ValueNotifier<FfmpegCapabilities>>.value(
          value: services.capabilities,
        ),
        ChangeNotifierProvider<ProjectsController>(
          create: (_) => ProjectsController(services)..refresh(),
        ),
        ChangeNotifierProvider<ModelsController>(
          create: (_) => ModelsController(services),
        ),
      ],
      child: MaterialApp(
        title: 'Amkyaw Studio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const HomeScreen(),
      ),
    );
  }
}

class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: AppColors.ink,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  size: 42,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Amkyaw Studio could not start',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
