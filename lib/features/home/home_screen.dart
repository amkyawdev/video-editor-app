import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/models/local_model.dart';
import '../../data/models/project.dart';
import '../../data/services/ffmpeg/ffmpeg_capabilities.dart';
import '../../data/services/models/model_catalog.dart';
import '../../state/models_controller.dart';
import '../../state/projects_controller.dart';
import '../../widgets/common.dart';
import '../editor/editor_screen.dart';
import '../models/model_library_screen.dart';
import '../recap/recap_screen.dart';
import '../settings/settings_screen.dart';
import '../subtitles/translate_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectsController>().refresh();
    });
  }

  Future<void> _openProject(Project project, {bool pickMedia = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EditorScreen(project: project, openMediaPickerOnStart: pickMedia),
      ),
    );
    if (mounted) await context.read<ProjectsController>().refresh();
  }

  Future<void> _openExisting(ProjectSummary summary) async {
    final repository = context.read<ProjectsController>().services.repository;
    final project = await repository.load(summary.id);
    if (!mounted) return;
    if (project == null) {
      showAppSnack(context, 'That project could not be opened.', error: true);
      return;
    }
    await _openProject(project);
  }

  Future<void> _newProject() async {
    final controller = TextEditingController(text: 'Untitled project');
    var preset = _CanvasPreset.landscape;
    final created = await showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: const BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadii.xl),
                  ),
                  border: Border(top: BorderSide(color: AppColors.stroke)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: AppColors.stroke,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Text(
                      'New project',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Everything stays on this device.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Project name',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    const SectionLabel('Canvas'),
                    Row(
                      children: <Widget>[
                        for (final option in _CanvasPreset.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: PillButton(
                                label: option.label,
                                icon: option.icon,
                                selected: preset == option,
                                onTap: () =>
                                    setSheetState(() => preset = option),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preset.blurb,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 22),
                    GradientButton(
                      label: 'Create project',
                      icon: Icons.add_rounded,
                      onPressed: () async {
                        final projects = context.read<ProjectsController>();
                        final project = await projects.create(
                          name: controller.text,
                          width: preset.width,
                          height: preset.height,
                        );
                        if (context.mounted) Navigator.pop(context, project);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
    if (created != null && mounted) {
      await _openProject(created);
    }
  }

  Future<void> _quickImport() async {
    final projects = context.read<ProjectsController>();
    final project = await projects.create(name: 'Quick import');
    if (!mounted) return;
    await _openProject(project, pickMedia: true);
  }

  Future<void> _deleteProject(ProjectSummary summary) async {
    final ok = await confirmAction(
      context,
      title: 'Delete project?',
      message:
          'The project file, its imported media copies and thumbnails will be '
          'removed from this device.',
    );
    if (!ok || !mounted) return;
    await context.read<ProjectsController>().delete(summary.id);
    if (mounted) showAppSnack(context, 'Project deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final projectsController = context.watch<ProjectsController>();
    final models = context.watch<ModelsController>();
    final capabilities = context
        .watch<ValueNotifier<FfmpegCapabilities>>()
        .value;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _newProject,
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF1A1204),
        child: const Icon(Icons.add_rounded),
      ),
      body: AppBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            onRefresh: projectsController.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  sliver: SliverToBoxAdapter(child: _header(context)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                  sliver: SliverToBoxAdapter(child: _hero(models)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  sliver: SliverToBoxAdapter(child: _quickTools(models)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: <Widget>[
                        const Expanded(child: SectionLabel('Your projects')),
                        if (projectsController.projects.isNotEmpty)
                          Text(
                            '${projectsController.projects.length} local',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ..._projectSlivers(projectsController),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  sliver: SliverToBoxAdapter(
                    child: _footer(models, capabilities),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _projectSlivers(ProjectsController projectsController) {
    if (projectsController.loading) {
      return const <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
      ];
    }
    if (projectsController.error != null) {
      return <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          sliver: SliverToBoxAdapter(
            child: GlassCard(
              child: Text(
                projectsController.error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ),
        ),
      ];
    }
    if (projectsController.projects.isEmpty) {
      return <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          sliver: SliverToBoxAdapter(
            child: GlassCard(
              child: EmptyState(
                icon: Icons.movie_filter_outlined,
                title: 'No projects yet',
                message:
                    'Create a project, import a video, then trim, caption '
                    'and export — entirely offline.',
                action: GradientButton(
                  label: 'Create a project',
                  icon: Icons.add_rounded,
                  expand: false,
                  onPressed: _newProject,
                ),
              ),
            ),
          ),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((
            BuildContext context,
            int index,
          ) {
            final summary = projectsController.projects[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  _ProjectCard(
                        summary: summary,
                        onTap: () => _openExisting(summary),
                        onLongPress: () => _deleteProject(summary),
                      )
                      .animate()
                      .fadeIn(delay: (index * 45).ms, duration: 320.ms)
                      .slideY(begin: 0.06, end: 0),
            );
          }, childCount: projectsController.projects.length),
        ),
      ),
    ];
  }

  Widget _header(BuildContext context) {
    return Row(
      children: <Widget>[
        const BrandMark(),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'AMKYAW',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.2,
                ),
              ),
              Text(
                'STUDIO',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 4.2,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _IconGlassButton(
          icon: Icons.download_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ModelLibraryScreen()),
          ),
        ),
        const SizedBox(width: 8),
        _IconGlassButton(
          icon: Icons.tune_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _hero(ModelsController models) {
    final installed = models.installed.length;
    return GestureDetector(
      onTap: _newProject,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF1D1A12), Color(0xFF0F1015)],
          ),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: AppColors.alpha(AppColors.accent, 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.alpha(AppColors.accent, 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.offline_bolt_rounded,
                        size: 13,
                        color: AppColors.accent,
                      ),
                      SizedBox(width: 5),
                      Text(
                        '100% on-device',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '$installed model${installed == 1 ? '' : 's'} installed',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Cut. Caption.\nTranslate.',
              style: TextStyle(
                fontSize: 34,
                height: 1.05,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.4,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'A full multi-track editor with a subtitle studio, Myanmar '
              'typography and offline GGUF translation. No cloud, no accounts, '
              'no TTS.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                GradientButton(
                  label: 'New project',
                  icon: Icons.add_rounded,
                  expand: false,
                  onPressed: _newProject,
                ),
                const SizedBox(width: 10),
                PillButton(
                  label: 'Import media',
                  icon: Icons.folder_open_rounded,
                  onTap: _quickImport,
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 380.ms).slideY(begin: 0.05);
  }

  Widget _quickTools(ModelsController models) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Studio tools'),
        Row(
          children: <Widget>[
            Expanded(
              child: _ToolCard(
                icon: Icons.subtitles_rounded,
                title: 'Subtitles',
                subtitle: 'SRT / VTT studio',
                accent: AppColors.mint,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const TranslateScreen(startInTranslation: false),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ToolCard(
                icon: Icons.translate_rounded,
                title: 'Translate',
                subtitle: 'Offline GGUF',
                accent: AppColors.violet,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TranslateScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _ToolCard(
                icon: Icons.auto_awesome_motion_rounded,
                title: 'Movie recap',
                subtitle: 'Evidence-first AI',
                accent: AppColors.sky,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RecapScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ToolCard(
                icon: Icons.memory_rounded,
                title: 'Model library',
                subtitle: '${ModelCatalog.all.length} verified entries',
                accent: AppColors.accent,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ModelLibraryScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footer(ModelsController models, FfmpegCapabilities capabilities) {
    final free = models.freeBytes;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: capabilities.available ? AppColors.mint : AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              capabilities.available
                  ? 'FFmpeg ready · ${capabilities.encoders.contains('libx264') ? 'H.264 / H.265 / AV1 / VP9' : 'limited codecs'}'
                  : 'FFmpeg is still starting…',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (free != null)
            Text(
              '${LocalModelFile.formatBytes(free)} free',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _CanvasPreset {
  const _CanvasPreset(
    this.label,
    this.icon,
    this.width,
    this.height,
    this.blurb,
  );

  static const landscape = _CanvasPreset(
    '16:9',
    Icons.crop_landscape_rounded,
    1920,
    1080,
    'Landscape 1920 × 1080 — YouTube, films, TV.',
  );
  static const portrait = _CanvasPreset(
    '9:16',
    Icons.crop_portrait_rounded,
    1080,
    1920,
    'Portrait 1080 × 1920 — Shorts, Reels, TikTok.',
  );
  static const square = _CanvasPreset(
    '1:1',
    Icons.crop_square_rounded,
    1080,
    1080,
    'Square 1080 × 1080 — feeds and posts.',
  );

  static const List<_CanvasPreset> values = <_CanvasPreset>[
    landscape,
    portrait,
    square,
  ];

  final String label;
  final IconData icon;
  final int width;
  final int height;
  final String blurb;
}

class _IconGlassButton extends StatelessWidget {
  const _IconGlassButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.alpha(accent, 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.summary,
    required this.onTap,
    required this.onLongPress,
  });

  final ProjectSummary summary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(microseconds: summary.durationUs);
    return GestureDetector(
      onLongPress: onLongPress,
      child: GlassCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 128,
              height: 84,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ThumbnailImage(path: summary.coverPath),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: <Color>[Color(0x00000000), Color(0x99000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.alpha(Colors.black, 0.7),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        TimeUtils.timecode(duration),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        StatChip(
                          icon: Icons.movie_outlined,
                          label: '${summary.clipCount} clips',
                        ),
                        const SizedBox(width: 10),
                        StatChip(
                          icon: Icons.subtitles_outlined,
                          label: '${summary.cueCount} cues',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Edited ${DateFormat.yMMMd().add_Hm().format(summary.updatedAt)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
