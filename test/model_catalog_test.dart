import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/models/local_model.dart';
import 'package:video_editor_app/data/services/models/model_catalog.dart';

void main() {
  test(
    'catalog has at least 8 Android-downloadable entries plus server models',
    () {
      expect(ModelCatalog.all.length, greaterThanOrEqualTo(8));
      expect(ModelCatalog.androidDownloadable.length, greaterThanOrEqualTo(8));
      expect(
        ModelCatalog.all.any(
          (LocalModel m) => m.tier == ModelTier.serverOnly && !m.downloadable,
        ),
        isTrue,
      );
    },
  );

  test('ids are unique and every downloadable entry has a weights file', () {
    final ids = ModelCatalog.all.map((LocalModel m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final model in ModelCatalog.androidDownloadable) {
      expect(model.weights, isNotNull, reason: model.id);
      expect(model.files, isNotEmpty, reason: model.id);
      expect(model.totalBytes, greaterThan(0), reason: model.id);
      expect(model.minRamGb, greaterThan(0), reason: model.id);
      expect(model.contextLength, greaterThanOrEqualTo(1024));
    }
  });

  test('download URLs point at the verified Hugging Face repository', () {
    for (final model in ModelCatalog.all) {
      for (final file in model.files) {
        final uri = Uri.parse(model.downloadUrl(file));
        expect(uri.scheme, 'https', reason: model.id);
        expect(uri.host, 'huggingface.co', reason: model.id);
        expect(uri.path, contains(model.repo), reason: model.id);
        expect(uri.path, endsWith(file.fileName.split('/').last));
        expect(uri.path, contains('/resolve/main/'));
      }
    }
  });

  test('Hy-MT3 default carries explicit Burmese evidence and licence', () {
    final model = ModelCatalog.defaultTranslation;
    expect(model.repo, 'tencent/Hy-MT3-1.8B-GGUF');
    expect(model.quantization, 'Q4_K_M');
    expect(model.files.single.sizeBytes, 1348432160);
    expect(model.burmeseEvidence, isTrue);
    expect(model.burmeseEvidenceNote, contains('Burmese'));
    expect(model.licenseVerified, isTrue);
    expect(model.licenseLabel, 'Apache-2.0');
    expect(model.contextLength, 8192);
  });

  test('MiniMax is server-only, multi-shard and not offered for Android', () {
    final mini = ModelCatalog.byId('minimax-m2-ud-iq1s')!;
    expect(mini.tier, ModelTier.serverOnly);
    expect(mini.downloadable, isFalse);
    expect(mini.files.length, 2);
    expect(mini.totalBytes, greaterThan(60000000000));
    expect(mini.isAndroidFriendly, isFalse);
  });

  test('ASR entry documents that Burmese is not in its language list', () {
    final asr = ModelCatalog.defaultAsr;
    expect(asr.capabilities, contains(ModelCapability.speechToText));
    expect(asr.needsProjector, isTrue);
    expect(asr.burmeseEvidence, isFalse);
    expect(asr.burmeseEvidenceNote, contains('does NOT include Burmese'));
  });

  test('vision entry requires a projector and is flagged for recap', () {
    final vl = ModelCatalog.byId('qwen2.5-vl-3b-q4')!;
    expect(vl.capabilities, contains(ModelCapability.vision));
    expect(vl.needsProjector, isTrue);
    expect(vl.recommendedForRecap, isTrue);
    expect(vl.licenseVerified, isTrue);
  });

  test('unverified-licence entries are labelled honestly', () {
    final unverified = ModelCatalog.all
        .where((LocalModel m) => !m.licenseVerified)
        .toList();
    expect(unverified, isNotEmpty);
    for (final model in unverified) {
      expect(model.licenseLabel, 'Not declared');
    }
  });
}
