import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/models/model_catalog.dart';
import '../../data/services/ffmpeg/ffmpeg_capabilities.dart';
import '../../state/app_services.dart';
import '../../state/models_controller.dart';
import '../../widgets/common.dart';
import '../editor/panels/panel_controls.dart';
import '../models/model_library_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _probing = false;

  Future<void> _probe() async {
    setState(() => _probing = true);
    final services = context.read<AppServices>();
    await services.ensureCapabilities(force: true);
    if (mounted) setState(() => _probing = false);
  }

  Future<void> _clearCache() async {
    final ok = await confirmAction(
      context,
      title: 'Clear temporary cache?',
      message:
          'Thumbnails, render scratch files and frame samples will be removed. '
          'Projects, media and downloaded models are kept.',
      confirmLabel: 'Clear',
    );
    if (!ok || !mounted) return;
    final services = context.read<AppServices>();
    try {
      if (await services.cacheDir.exists()) {
        await for (final entity in services.cacheDir.list()) {
          await entity.delete(recursive: true);
        }
      }
      if (mounted) showAppSnack(context, 'Temporary cache cleared.');
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Could not clear cache: $error', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = context.watch<AppServices>();
    final caps = context.watch<ValueNotifier<FfmpegCapabilities>>().value;
    final models = context.watch<ModelsController>();
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      color: AppColors.textSecondary,
                    ),
                    const Expanded(
                      child: Text(
                        'Settings & diagnostics',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: <Widget>[
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(child: SectionLabel('FFmpeg')),
                              PillButton(
                                label: _probing ? 'Probing…' : 'Probe again',
                                compact: true,
                                onTap: _probing ? null : _probe,
                              ),
                            ],
                          ),
                          Text(
                            caps.available
                                ? caps.version
                                : (caps.error ?? 'Not probed yet'),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: AppFonts.mono,
                              color: caps.available
                                  ? AppColors.mint
                                  : AppColors.danger,
                            ),
                          ),
                          if (caps.available) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              'Encoders: ${caps.encoders.length} · '
                              'Filters: ${caps.filters.length} · '
                              'Muxers: ${caps.muxers.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: <Widget>[
                                for (final codec in <String>[
                                  'libx264',
                                  'libx265',
                                  'libaom-av1',
                                  'libvpx-vp9',
                                  'aac',
                                  'libopus',
                                  'libmp3lame',
                                ])
                                  StatChip(
                                    icon: caps.hasEncoder(codec)
                                        ? Icons.check_circle_outline
                                        : Icons.remove_circle_outline,
                                    label: codec,
                                    color: caps.hasEncoder(codec)
                                        ? AppColors.mint
                                        : AppColors.textMuted,
                                  ),
                                StatChip(
                                  icon: caps.hasFilter('subtitles')
                                      ? Icons.check_circle_outline
                                      : Icons.remove_circle_outline,
                                  label: 'libass burn-in',
                                  color: caps.hasFilter('subtitles')
                                      ? AppColors.mint
                                      : AppColors.danger,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionLabel('Local AI'),
                          Text(
                            '${models.installed.length} models installed · '
                            '${ModelCatalog.all.length} catalog entries',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          PillButton(
                            label: 'Open model library',
                            icon: Icons.memory_rounded,
                            compact: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ModelLibraryScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const InfoNote(
                            message:
                                'GGUF models run through llama.cpp on this '
                                'device. Translation is limited to SRT/TXT; '
                                'movie recap uses FFmpeg evidence plus local '
                                'ASR/vision when installed.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionLabel('Storage'),
                          Text(
                            services.repository.root.path,
                            style: const TextStyle(
                              fontSize: 9,
                              fontFamily: AppFonts.mono,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          PillButton(
                            label: 'Clear temporary cache',
                            icon: Icons.cleaning_services_outlined,
                            compact: true,
                            onTap: _clearCache,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionLabel('Privacy'),
                          InfoNote(
                            message:
                                'Projects, media copies, subtitles, model '
                                'files and exports stay in app-private storage. '
                                'There is no account, no cloud sync and no '
                                'telemetry. The app contains no text-to-speech '
                                'engine: no Piper, VieNeu or TTS feature.',
                            icon: Icons.lock_outline_rounded,
                            color: AppColors.mint,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionLabel('About'),
                          Text(
                            'Amkyaw Studio 1.0.0\n'
                            'Flutter 3.50 · FFmpegKit 8 · llama.cpp (llamadart)',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'FFmpeg is GPL-licensed; model licences are shown '
                            'per entry in the model library. Bundled fonts: '
                            'Inter, JetBrains Mono, Noto Sans Myanmar (OFL).',
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
