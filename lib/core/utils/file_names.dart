/// Makes a user supplied title safe to use as a file name on Android/iOS.
String sanitizeFileName(String input, {String fallback = 'untitled'}) {
  final cleaned = input
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return fallback;
  return cleaned.length > 64 ? cleaned.substring(0, 64).trim() : cleaned;
}

String withExtension(String base, String extension) {
  final ext = extension.startsWith('.') ? extension : '.$extension';
  return base.toLowerCase().endsWith(ext.toLowerCase()) ? base : '$base$ext';
}
