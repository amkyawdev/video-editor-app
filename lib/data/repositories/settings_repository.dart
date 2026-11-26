import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/export_settings.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  static Future<SettingsRepository> open() async =>
      SettingsRepository(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kLastModel = 'ai.lastModelId';
  static const _kLastRecapModel = 'ai.lastRecapModelId';
  static const _kLastAsrModel = 'ai.lastAsrModelId';
  static const _kExport = 'export.defaultSettings';
  static const _kSeenIntro = 'ui.seenIntro';

  String? get lastTranslationModelId => _prefs.getString(_kLastModel);
  String? get lastRecapModelId => _prefs.getString(_kLastRecapModel);
  String? get lastAsrModelId =>
      _prefs.getString(_kLastAsrModel) ?? 'qwen3-asr-0.6b-q8';

  Future<void> setLastTranslationModelId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kLastModel);
    } else {
      await _prefs.setString(_kLastModel, id);
    }
  }

  Future<void> setLastRecapModelId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kLastRecapModel);
    } else {
      await _prefs.setString(_kLastRecapModel, id);
    }
  }

  Future<void> setLastAsrModelId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kLastAsrModel);
    } else {
      await _prefs.setString(_kLastAsrModel, id);
    }
  }

  ExportSettings get defaultExport {
    final raw = _prefs.getString(_kExport);
    if (raw == null) return ExportSettings.defaults;
    try {
      return ExportSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ExportSettings.defaults;
    }
  }

  Future<void> setDefaultExport(ExportSettings settings) =>
      _prefs.setString(_kExport, jsonEncode(settings.toJson()));

  bool get seenIntro => _prefs.getBool(_kSeenIntro) ?? false;

  Future<void> markIntroSeen() => _prefs.setBool(_kSeenIntro, true);
}
