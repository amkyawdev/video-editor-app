import 'package:flutter/foundation.dart';

import '../data/models/project.dart';
import 'app_services.dart';

class ProjectsController extends ChangeNotifier {
  ProjectsController(this.services);

  final AppServices services;
  List<ProjectSummary> projects = <ProjectSummary>[];
  bool loading = true;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      projects = await services.repository.list();
    } catch (e) {
      error = 'Could not read projects: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Project> create({
    required String name,
    int width = 1920,
    int height = 1080,
    double fps = 30,
  }) async {
    final project = Project.blank(
      name: name.trim().isEmpty ? 'Untitled project' : name.trim(),
      canvasWidth: width,
      canvasHeight: height,
      fps: fps,
    )..exportSettings = services.settings.defaultExport;
    await services.repository.save(project);
    await refresh();
    return project;
  }

  Future<Project?> load(String id) => services.repository.load(id);

  Future<void> delete(String id) async {
    await services.repository.delete(id);
    await refresh();
  }
}
