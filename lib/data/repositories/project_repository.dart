import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/project.dart';

/// Local-first project storage:
/// `<documents>/amkyaw_studio/projects/<projectId>/project.json` with media,
/// thumbnails and exports kept beside it.
class ProjectRepository {
  ProjectRepository(this.root);

  final Directory root;

  static Future<ProjectRepository> open() async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(documents.path, 'amkyaw_studio'));
    await root.create(recursive: true);
    return ProjectRepository(root);
  }

  Directory get projectsRoot => Directory(p.join(root.path, 'projects'));
  Directory get modelsRoot => Directory(p.join(root.path, 'models'));
  Directory get exportsRoot => Directory(p.join(root.path, 'exports'));

  Future<void> init() async {
    await projectsRoot.create(recursive: true);
    await modelsRoot.create(recursive: true);
    await exportsRoot.create(recursive: true);
  }

  Directory projectDir(String id) => Directory(p.join(projectsRoot.path, id));
  Directory mediaDir(String id) =>
      Directory(p.join(projectDir(id).path, 'media'));
  Directory thumbDir(String id) =>
      Directory(p.join(projectDir(id).path, 'thumbnails'));
  Directory projectExportsDir(String id) =>
      Directory(p.join(projectDir(id).path, 'exports'));
  File projectFile(String id) =>
      File(p.join(projectDir(id).path, 'project.json'));

  Future<List<ProjectSummary>> list() async {
    await init();
    final summaries = <ProjectSummary>[];
    for (final entity in projectsRoot.listSync()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'project.json'));
      if (!await file.exists()) continue;
      try {
        final project = Project.decode(await file.readAsString());
        summaries.add(ProjectSummary.fromProject(project));
      } catch (_) {
        // A corrupt project must not break the browser.
      }
    }
    summaries.sort(
      (ProjectSummary a, ProjectSummary b) =>
          b.updatedAt.compareTo(a.updatedAt),
    );
    return summaries;
  }

  Future<Project?> load(String id) async {
    final file = projectFile(id);
    if (!await file.exists()) return null;
    return Project.decode(await file.readAsString());
  }

  Future<void> save(Project project) async {
    await projectDir(project.id).create(recursive: true);
    final target = projectFile(project.id);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(project.toJsonString(), flush: true);
    await temp.rename(target.path);
  }

  Future<void> delete(String id) async {
    final dir = projectDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<Directory> ensureMediaDir(String id) async {
    final dir = mediaDir(id);
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> uniqueMediaPath(String projectId, String fileName) async {
    final dir = await ensureMediaDir(projectId);
    var base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = p.join(dir.path, '$base$ext');
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(dir.path, '${base}_$counter$ext');
      counter++;
    }
    return candidate;
  }

  Future<String> writeExport(
    String projectId,
    String fileName,
    String content,
  ) async {
    final dir = Directory(p.join(exportsRoot.path, projectId));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content, flush: true);
    return file.path;
  }
}
