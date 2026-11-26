import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/utils/cancellation.dart';
import '../data/models/recap.dart';
import '../data/services/ai/recap_service.dart';
import '../data/services/models/model_library_service.dart';
import 'app_services.dart';

enum RecapStatus { idle, running, ready, cancelled, failed }

class RecapController extends ChangeNotifier {
  RecapController(this.services);

  final AppServices services;

  RecapStatus status = RecapStatus.idle;
  RecapStage stage = RecapStage.preparing;
  double progress = 0;
  String message = '';
  String? error;
  String? videoPath;
  String? videoName;
  String? transcriptName;
  String? transcriptText;
  RecapSettings settings = const RecapSettings();
  RecapEvidence? evidence;
  RecapScript? script;
  List<String> warnings = <String>[];
  Directory? workDir;
  String? savedPath;
  CancellationToken? _token;

  bool get isRunning => status == RecapStatus.running;

  bool get canExportSrt => script?.isNarrative == true;

  void setVideo({required String path, required String name}) {
    videoPath = path;
    videoName = name;
    script = null;
    evidence = null;
    warnings = <String>[];
    error = null;
    status = RecapStatus.idle;
    notifyListeners();
  }

  void setTranscript({String? name, String? text}) {
    transcriptName = name;
    transcriptText = text;
    notifyListeners();
  }

  void updateSettings(RecapSettings next) {
    settings = next;
    notifyListeners();
  }

  Future<void> start({
    InstalledModel? analysisModel,
    InstalledModel? asrModel,
  }) async {
    final path = videoPath;
    if (path == null) {
      error = 'Import a video first.';
      status = RecapStatus.failed;
      notifyListeners();
      return;
    }
    if (!await File(path).exists()) {
      error = 'The video file is no longer available.';
      status = RecapStatus.failed;
      notifyListeners();
      return;
    }
    if (services.runner.isBusy) {
      error = 'Another local AI job is running. Wait for it to finish.';
      status = RecapStatus.failed;
      notifyListeners();
      return;
    }
    _token = CancellationToken();
    status = RecapStatus.running;
    stage = RecapStage.preparing;
    progress = 0;
    error = null;
    warnings = <String>[];
    script = null;
    evidence = null;
    savedPath = null;
    notifyListeners();

    final dir = Directory(
      p.join(
        services.cacheDir.path,
        'recap_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    workDir = dir;

    try {
      final result = await services.runner.exclusive(
        () => services.recap.run(
          video: File(path),
          workDir: dir,
          settings: settings,
          analysisModel: analysisModel,
          asrModel: settings.useAsr ? asrModel : null,
          importedTranscript: transcriptText,
          importedTranscriptName: transcriptName,
          token: _token,
          onProgress: (RecapProgress value) {
            stage = value.stage;
            progress = value.fraction;
            message = value.message;
            notifyListeners();
          },
        ),
      );
      evidence = result.evidence;
      script = result.script;
      warnings = result.script.warnings;
      status = RecapStatus.ready;
    } on RecapCancelled {
      status = RecapStatus.cancelled;
    } on RecapException catch (e) {
      status = RecapStatus.failed;
      error = e.message;
    } catch (e) {
      status = RecapStatus.failed;
      error = 'Recap failed: $e';
    } finally {
      notifyListeners();
    }
  }

  void cancel() => _token?.cancel();

  void updateScript({String? title, String? logline, String? body}) {
    final current = script;
    if (current == null) return;
    script = current.copyWith(
      title: title ?? current.title,
      logline: logline ?? current.logline,
      body: body ?? current.body,
    );
    notifyListeners();
  }

  Future<String> exportTxt() async {
    final current = script;
    if (current == null) throw StateError('Generate a recap first.');
    final base = p.basenameWithoutExtension(videoName ?? 'recap');
    final file = File(
      p.join(
        services.repository.exportsRoot.path,
        'recap',
        '${base}_recap.txt',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(current.plainText, flush: true);
    savedPath = file.path;
    notifyListeners();
    return file.path;
  }

  Future<String> exportSrt() async {
    final current = script;
    final ev = evidence;
    if (current == null || ev == null) {
      throw StateError('Generate a recap first.');
    }
    if (!current.isNarrative) {
      throw StateError(
        'This is an evidence report, not a narrative recap. SRT export is only '
        'available for model-written recaps.',
      );
    }
    final content = current.toSrt(ev.durationUs);
    if (content.trim().isEmpty) {
      throw StateError('The recap has no sentences to place on the timeline.');
    }
    final base = p.basenameWithoutExtension(videoName ?? 'recap');
    final file = File(
      p.join(
        services.repository.exportsRoot.path,
        'recap',
        '${base}_recap.srt',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    savedPath = file.path;
    notifyListeners();
    return file.path;
  }
}
