import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// libass resolves fonts from a directory, not from Flutter assets. The bundled
/// Myanmar faces are copied to a cache folder before every burn-in render.
class FontAssets {
  const FontAssets._();

  static const List<String> files = <String>[
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
    'JetBrainsMono-Regular.ttf',
    'JetBrainsMono-SemiBold.ttf',
    'NotoSansMyanmar-Regular.ttf',
    'NotoSansMyanmar-SemiBold.ttf',
    'NotoSansMyanmar-Bold.ttf',
  ];

  static Future<Directory> materialize(Directory cacheDir) async {
    final dir = Directory(p.join(cacheDir.path, 'amkyaw_fonts'));
    await dir.create(recursive: true);
    for (final name in files) {
      final target = File(p.join(dir.path, name));
      if (await target.exists() && await target.length() > 1024) continue;
      final data = await rootBundle.load('assets/fonts/$name');
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return dir;
  }
}
