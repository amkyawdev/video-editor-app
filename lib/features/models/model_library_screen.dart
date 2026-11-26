import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/local_model.dart';
import '../../data/services/models/model_library_service.dart';
import '../../state/models_controller.dart';
import '../../widgets/common.dart';
import '../editor/panels/panel_controls.dart';

class ModelLibraryScreen extends StatefulWidget {
  const ModelLibraryScreen({super.key});

  @override
  State<ModelLibraryScreen> createState() => _ModelLibraryScreenState();
}

class _ModelLibraryScreenState extends State<ModelLibraryScreen> {
  String _filter = 'All';

  static const List<String> _filters = <String>[
    'All',
    'Translation',
    'Recap',
    'Speech',
    'Server',
  ];

  bool _matches(LocalModel model) {
    switch (_filter) {
      case 'Translation':
        return model.capabilities.contains(ModelCapability.translation) &&
            model.tier != ModelTier.serverOnly;
      case 'Recap':
        return model.capabilities.contains(ModelCapability.vision) ||
            model.capabilities.contains(ModelCapability.chat);
      case 'Speech':
        return model.capabilities.contains(ModelCapability.speechToText);
      case 'Server':
        return model.tier == ModelTier.serverOnly;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelsController>();
    final list = models.models.where(_matches).toList();
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Model library',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Verified GGUF entries · downloaded on demand',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: models.refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.sd_storage_outlined,
                        size: 16,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${models.installed.length} installed · '
                          '${LocalModelFile.formatBytes(models.installedBytes)}'
                          '${models.freeBytes != null ? ' · ${LocalModelFile.formatBytes(models.freeBytes!)} free' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (BuildContext context, int index) {
                    final filter = _filters[index];
                    return PillButton(
                      label: filter,
                      compact: true,
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
                    );
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int index) {
                    final model = list[index];
                    return _ModelCard(
                      model: model,
                      installed: models.installed[model.id],
                      downloading: models.isDownloading(model),
                      progress: models.progressOf(model),
                      error: models.errors[model.id],
                      selected:
                          models.translationModelId == model.id ||
                          models.recapModelId == model.id ||
                          models.asrModelId == model.id,
                      onDownload: () => models.download(model),
                      onCancel: () => models.cancelDownload(model),
                      onDelete: () => _delete(models, model),
                      onSelect: () => _select(models, model),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(ModelsController models, LocalModel model) async {
    final ok = await confirmAction(
      context,
      title: 'Delete ${model.title}?',
      message:
          '${model.totalSizeLabel} of GGUF files will be removed from this '
          'device. You can download the model again later.',
    );
    if (!ok) return;
    await models.remove(model);
    if (mounted) showAppSnack(context, 'Model deleted.');
  }

  Future<void> _select(ModelsController models, LocalModel model) async {
    if (model.capabilities.contains(ModelCapability.speechToText)) {
      await models.selectAsr(model.id);
    } else if (model.capabilities.contains(ModelCapability.vision)) {
      await models.selectRecap(model.id);
    } else {
      await models.selectTranslation(model.id);
      await models.selectRecap(model.id);
    }
    if (mounted) {
      showAppSnack(context, '${model.title} selected.');
    }
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.installed,
    required this.downloading,
    required this.progress,
    required this.error,
    required this.selected,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.onSelect,
  });

  final LocalModel model;
  final InstalledModel? installed;
  final bool downloading;
  final double progress;
  final String? error;
  final bool selected;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onSelect;

  Color get _tierColor => switch (model.tier) {
    ModelTier.recommended => AppColors.mint,
    ModelTier.capable => AppColors.accent,
    ModelTier.heavy => AppColors.violet,
    ModelTier.serverOnly => AppColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final isInstalled = installed != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: selected
              ? AppColors.alpha(AppColors.accent, 0.55)
              : AppColors.stroke,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      model.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      model.vendor,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.alpha(_tierColor, 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.alpha(_tierColor, 0.35)),
                ),
                child: Text(
                  model.tierLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _tierColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: <Widget>[
              StatChip(
                icon: Icons.memory_rounded,
                label: model.totalSizeLabel,
                color: AppColors.textSecondary,
              ),
              StatChip(
                icon: Icons.straighten_rounded,
                label: model.quantization,
              ),
              StatChip(
                icon: Icons.data_object_rounded,
                label: '${model.contextLength} ctx',
              ),
              StatChip(
                icon: model.licenseVerified
                    ? Icons.verified_outlined
                    : Icons.help_outline_rounded,
                label: model.licenseLabel,
                color: model.licenseVerified
                    ? AppColors.mint
                    : AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            model.capabilityLabel,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          if (model.burmeseEvidence)
            InfoNote(
              message: 'Burmese evidence: ${model.burmeseEvidenceNote}',
              icon: Icons.translate_rounded,
              color: AppColors.mint,
            )
          else
            InfoNote(
              message: model.burmeseEvidenceNote.isEmpty
                  ? 'Burmese support is not claimed for this model.'
                  : 'Burmese note: ${model.burmeseEvidenceNote}',
              icon: Icons.info_outline_rounded,
              color: AppColors.textMuted,
            ),
          const SizedBox(height: 8),
          Text(
            model.notes,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            model.repo,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textMuted,
              fontFamily: AppFonts.mono,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Needs about ${model.minRamGb} GB free RAM when loaded.',
            style: TextStyle(
              fontSize: 10,
              color: model.minRamGb >= 8
                  ? AppColors.accent
                  : AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (installed?.info != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Installed · ${installed!.info!.summary}',
              style: const TextStyle(fontSize: 10, color: AppColors.mint),
            ),
          ],
          if (error != null) ...<Widget>[
            const SizedBox(height: 8),
            InfoNote(
              message: error!,
              icon: Icons.error_outline,
              color: AppColors.danger,
            ),
          ],
          const SizedBox(height: 10),
          if (!model.downloadable)
            Row(
              children: <Widget>[
                const Icon(
                  Icons.desktop_windows_outlined,
                  size: 15,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Not downloadable on Android. Run this multi-shard '
                    '${model.parameters} model on a PC/server with llama.cpp.',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.danger,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            )
          else if (downloading)
            Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress == 0 ? null : progress,
                          minHeight: 5,
                          backgroundColor: AppColors.strokeSoft,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.accent,
                        fontFamily: AppFonts.mono,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                PillButton(
                  label: 'Cancel download',
                  icon: Icons.stop_rounded,
                  compact: true,
                  danger: true,
                  onTap: onCancel,
                ),
              ],
            )
          else if (isInstalled)
            Row(
              children: <Widget>[
                Expanded(
                  child: PillButton(
                    label: selected ? 'Selected' : 'Use this model',
                    icon: selected
                        ? Icons.check_circle_outline_rounded
                        : Icons.touch_app_outlined,
                    selected: selected,
                    onTap: selected ? null : onSelect,
                  ),
                ),
                const SizedBox(width: 8),
                PillButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  compact: true,
                  danger: true,
                  onTap: onDelete,
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: GradientButton(
                    label: 'Download ${model.totalSizeLabel}',
                    icon: Icons.download_rounded,
                    onPressed: onDownload,
                  ),
                ),
                const SizedBox(width: 8),
                PillButton(
                  label: 'Details',
                  icon: Icons.open_in_new_rounded,
                  compact: true,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (BuildContext context) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            model.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hugging Face: ${model.modelPageUrl}\n'
                            'File: ${model.files.map((LocalModelFile f) => f.fileName).join(', ')}\n'
                            'Licence: ${model.licenseLabel}\n'
                            'Context: ${model.contextLength} tokens\n'
                            'Quantisation: ${model.quantization}',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              fontFamily: AppFonts.mono,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
