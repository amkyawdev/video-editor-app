import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class GgufFormatException implements Exception {
  GgufFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GgufInfo {
  const GgufInfo({
    required this.version,
    required this.tensorCount,
    required this.metadataCount,
    required this.fileSizeBytes,
    this.architecture,
    this.name,
  });

  final int version;
  final int tensorCount;
  final int metadataCount;
  final int fileSizeBytes;
  final String? architecture;
  final String? name;

  String get summary {
    final parts = <String>[
      'GGUF v$version',
      '$tensorCount tensors',
      ?architecture,
    ];
    return parts.join(' · ');
  }
}

/// Reads only the GGUF header and scalar metadata needed to validate a
/// download. Tensor data is never loaded, so a 20 GB model costs a few KB.
class GgufInspector {
  const GgufInspector._();

  static const int _magic = 0x46554747; // "GGUF" little endian

  static Future<GgufInfo> inspect(File file) async {
    final length = await file.length();
    if (length < 32) {
      throw GgufFormatException('File is too small to be a GGUF model.');
    }
    final raf = await file.open();
    try {
      final magic = await _readUint32(raf);
      if (magic != _magic) {
        throw GgufFormatException(
          'Not a GGUF file: missing the "GGUF" header magic.',
        );
      }
      final version = await _readUint32(raf);
      final tensorCount = await _readUint64(raf);
      final metadataCount = await _readUint64(raf);
      String? architecture;
      String? name;
      for (var i = 0; i < metadataCount; i++) {
        final key = await _readString(raf);
        final type = await _readUint32(raf);
        if (key == 'general.architecture') {
          architecture = await _readString(raf);
        } else if (key == 'general.name') {
          name = await _readString(raf);
        } else {
          await _skipValue(raf, type);
        }
      }
      return GgufInfo(
        version: version,
        tensorCount: tensorCount,
        metadataCount: metadataCount,
        fileSizeBytes: length,
        architecture: architecture,
        name: name,
      );
    } finally {
      await raf.close();
    }
  }

  static Future<int> _readUint32(RandomAccessFile raf) async =>
      ByteData.sublistView(await raf.read(4)).getUint32(0, Endian.little);

  static Future<int> _readUint64(RandomAccessFile raf) async =>
      ByteData.sublistView(await raf.read(8)).getUint64(0, Endian.little);

  static Future<String> _readString(RandomAccessFile raf) async {
    final len = await _readUint64(raf);
    if (len > 32 * 1024 * 1024) {
      throw GgufFormatException('Metadata string is too large.');
    }
    final bytes = await raf.read(len);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<void> _skipValue(RandomAccessFile raf, int type) async {
    switch (type) {
      case 0:
      case 1:
      case 7:
        await raf.read(1);
      case 2:
      case 3:
        await raf.read(2);
      case 4:
      case 5:
      case 6:
        await raf.read(4);
      case 10:
      case 11:
      case 12:
        await raf.read(8);
      case 8:
        await _readString(raf);
      case 9:
        final elementType = await _readUint32(raf);
        final count = await _readUint64(raf);
        if (count > 50000000) {
          throw GgufFormatException('Metadata array is too large.');
        }
        for (var i = 0; i < count; i++) {
          await _skipValue(raf, elementType);
        }
      default:
        throw GgufFormatException('Unknown GGUF metadata type $type.');
    }
  }

  static bool hasMagic(Uint8List head) {
    if (head.length < 4) return false;
    return ByteData.sublistView(head).getUint32(0, Endian.little) == _magic;
  }
}
