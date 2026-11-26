import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/local_model.dart';
import '../data/services/models/model_catalog.dart';
import '../data/services/models/model_library_service.dart';
import 'app_services.dart';

class ModelsController extends ChangeNotifier {
  ModelsController(this.services) {
    translationModelId = services.settings.lastTranslationModelId;
    recapModelId = services.settings.lastRecapModelId;
    asrModelId = services.settings.lastAsrModelId;
    unawaited(refresh());
  }

  final AppServices services;

  Map<String, InstalledModel> installed = <String, InstalledModel>{};
  final Map<String, ModelDownloadProgress> downloads =
      <String, ModelDownloadProgress>{};
  final Map<String, ModelDownloadToken> _tokens =
      <String, ModelDownloadToken>{};
  final Map<String, String> errors = <String, String>{};

  bool loading = true;
  int installedBytes = 0;
  int? freeBytes;
  String? translationModelId;
  String? recapModelId;
  String? asrModelId;

  List<LocalModel> get models => ModelCatalog.all;

  LocalModel? get translationModel => ModelCatalog.byId(translationModelId);
  LocalModel? get recapModel => ModelCatalog.byId(recapModelId);
  LocalModel? get asrModel => ModelCatalog.byId(asrModelId);

  InstalledModel? get installedTranslation =>
      translationModelId == null ? null : installed[translationModelId];
  InstalledModel? get installedRecap =>
      recapModelId == null ? null : installed[recapModelId];
  InstalledModel? get installedAsr =>
      asrModelId == null ? null : installed[asrModelId];

  bool isInstalled(LocalModel model) => installed.containsKey(model.id);

  bool isDownloading(LocalModel model) => downloads.containsKey(model.id);

  double progressOf(LocalModel model) => downloads[model.id]?.fraction ?? 0;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      installed = await services.models.installedById();
      installedBytes = await services.models.installedBytes();
      freeBytes = await services.models.availableBytes(
        services.repository.modelsRoot,
      );
      // Auto-select a sensible installed default when nothing is chosen.
      if (translationModelId == null ||
          !installed.containsKey(translationModelId)) {
        final candidate = installed.values.cast<InstalledModel?>().firstWhere(
          (InstalledModel? m) =>
              m?.model.capabilities.contains(ModelCapability.translation) ??
              false,
          orElse: () => null,
        );
        if (candidate != null) translationModelId = candidate.model.id;
      }
      if (recapModelId == null || !installed.containsKey(recapModelId)) {
        final candidate = installed.values.cast<InstalledModel?>().firstWhere(
          (InstalledModel? m) =>
              m?.model.capabilities.contains(ModelCapability.vision) ?? false,
          orElse: () => null,
        );
        if (candidate != null) recapModelId = candidate.model.id;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> download(LocalModel model) async {
    if (isDownloading(model)) return;
    errors.remove(model.id);
    final token = ModelDownloadToken();
    _tokens[model.id] = token;
    notifyListeners();
    try {
      await for (final progress in services.models.download(
        model,
        token: token,
      )) {
        downloads[model.id] = progress;
        notifyListeners();
      }
      downloads.remove(model.id);
      await refresh();
      if (model.capabilities.contains(ModelCapability.translation) &&
          translationModelId == null) {
        await selectTranslation(model.id);
      }
      if (model.capabilities.contains(ModelCapability.vision) &&
          recapModelId == null) {
        await selectRecap(model.id);
      }
    } on ModelDownloadCancelled {
      downloads.remove(model.id);
      notifyListeners();
    } on ModelLibraryException catch (error) {
      errors[model.id] = error.message;
      downloads.remove(model.id);
      notifyListeners();
    } catch (error) {
      errors[model.id] = 'Download failed: $error';
      downloads.remove(model.id);
      notifyListeners();
    } finally {
      _tokens.remove(model.id);
    }
  }

  void cancelDownload(LocalModel model) {
    _tokens[model.id]?.cancel();
  }

  Future<void> remove(LocalModel model) async {
    await services.models.delete(model);
    errors.remove(model.id);
    await refresh();
  }

  Future<void> selectTranslation(String? id) async {
    translationModelId = id;
    await services.settings.setLastTranslationModelId(id);
    notifyListeners();
  }

  Future<void> selectRecap(String? id) async {
    recapModelId = id;
    await services.settings.setLastRecapModelId(id);
    notifyListeners();
  }

  Future<void> selectAsr(String? id) async {
    asrModelId = id;
    await services.settings.setLastAsrModelId(id);
    notifyListeners();
  }

  List<InstalledModel> get installedTranslationModels => installed.values
      .where(
        (InstalledModel m) =>
            m.model.capabilities.contains(ModelCapability.translation),
      )
      .toList();

  List<InstalledModel> get installedRecapModels => installed.values
      .where(
        (InstalledModel m) =>
            m.model.capabilities.contains(ModelCapability.vision) ||
            m.model.capabilities.contains(ModelCapability.chat),
      )
      .toList();

  List<InstalledModel> get installedAsrModels => installed.values
      .where(
        (InstalledModel m) =>
            m.model.capabilities.contains(ModelCapability.speechToText),
      )
      .toList();
}
