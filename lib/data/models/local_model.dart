enum ModelTier { recommended, capable, heavy, serverOnly }

enum ModelCapability { translation, chat, vision, speechToText }

enum ModelFileRole { weights, projector }

class LocalModelFile {
  const LocalModelFile({
    required this.fileName,
    required this.sizeBytes,
    this.role = ModelFileRole.weights,
  });

  final String fileName;
  final int sizeBytes;
  final ModelFileRole role;

  String get displaySize => formatBytes(sizeBytes);

  static String formatBytes(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) {
      return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1000 * 1000) {
      return '${(bytes / 1000000).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1000).toStringAsFixed(0)} KB';
  }
}

/// One verified catalog entry. Sizes come from the Hugging Face API
/// (`/api/models/<repo>?blobs=true`), not from estimates.
class LocalModel {
  const LocalModel({
    required this.id,
    required this.title,
    required this.vendor,
    required this.repo,
    required this.quantization,
    required this.parameters,
    required this.contextLength,
    required this.licenseLabel,
    required this.licenseUrl,
    required this.licenseVerified,
    required this.tier,
    required this.capabilities,
    required this.files,
    required this.notes,
    this.burmeseEvidence = false,
    this.burmeseEvidenceNote = '',
    this.downloadable = true,
    this.recommendedForTranslation = false,
    this.recommendedForRecap = false,
    this.recommendedForAsr = false,
  });

  final String id;
  final String title;
  final String vendor;
  final String repo;
  final String quantization;
  final String parameters;
  final int contextLength;
  final String licenseLabel;
  final String licenseUrl;
  final bool licenseVerified;
  final ModelTier tier;
  final Set<ModelCapability> capabilities;
  final List<LocalModelFile> files;
  final String notes;
  final bool burmeseEvidence;
  final String burmeseEvidenceNote;
  final bool downloadable;
  final bool recommendedForTranslation;
  final bool recommendedForRecap;
  final bool recommendedForAsr;

  String get modelPageUrl => 'https://huggingface.co/$repo';

  String downloadUrl(LocalModelFile file) =>
      'https://huggingface.co/$repo/resolve/main/'
      '${file.fileName.split('/').map(Uri.encodeComponent).join('/')}';

  int get totalBytes => files.fold<int>(
    0,
    (int sum, LocalModelFile file) => sum + file.sizeBytes,
  );

  String get totalSizeLabel => LocalModelFile.formatBytes(totalBytes);

  LocalModelFile? get weights => files.cast<LocalModelFile?>().firstWhere(
    (LocalModelFile? f) => f?.role == ModelFileRole.weights,
    orElse: () => null,
  );

  LocalModelFile? get projector => files.cast<LocalModelFile?>().firstWhere(
    (LocalModelFile? f) => f?.role == ModelFileRole.projector,
    orElse: () => null,
  );

  bool get needsProjector => projector != null;

  int get minRamGb {
    final weightsGb = totalBytes / 1000000000;
    final overhead =
        capabilities.contains(ModelCapability.vision) ||
            capabilities.contains(ModelCapability.speechToText)
        ? 2.0
        : 1.5;
    return (weightsGb * 1.15 + overhead).ceil();
  }

  String get tierLabel => switch (tier) {
    ModelTier.recommended => 'Android · recommended',
    ModelTier.capable => 'Android · capable',
    ModelTier.heavy => 'Android · high-end only',
    ModelTier.serverOnly => 'PC / server only',
  };

  bool get isAndroidFriendly => tier != ModelTier.serverOnly && downloadable;

  String get capabilityLabel => capabilities
      .map(
        (ModelCapability c) => switch (c) {
          ModelCapability.translation => 'Translation',
          ModelCapability.chat => 'Chat / script',
          ModelCapability.vision => 'Vision',
          ModelCapability.speechToText => 'Speech-to-text',
        },
      )
      .join(' · ');
}
