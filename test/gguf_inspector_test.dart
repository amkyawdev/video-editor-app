import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor_app/data/services/models/gguf_inspector.dart';

Uint8List _gguf() {
  final builder = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    builder.add(data.buffer.asUint8List());
  }

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    builder.add(data.buffer.asUint8List());
  }

  void str(String value) {
    final bytes = utf8.encode(value);
    u64(bytes.length);
    builder.add(bytes);
  }

  builder.add(ascii.encode('GGUF'));
  u32(3); // version
  u64(42); // tensor count
  u64(3); // metadata count
  str('general.architecture');
  u32(8); // string
  str('llama');
  str('general.name');
  u32(8);
  str('tiny-test');
  str('general.alignment');
  u32(4); // uint32
  u32(32);
  return builder.toBytes();
}

void main() {
  test('reads magic, version, tensor count and key metadata', () async {
    final dir = await Directory.systemTemp.createTemp('gguf_test');
    final file = File('${dir.path}/tiny.gguf');
    await file.writeAsBytes(_gguf());
    final info = await GgufInspector.inspect(file);
    expect(info.version, 3);
    expect(info.tensorCount, 42);
    expect(info.metadataCount, 3);
    expect(info.architecture, 'llama');
    expect(info.name, 'tiny-test');
    expect(info.fileSizeBytes, await file.length());
    expect(info.summary, contains('GGUF v3'));
    await dir.delete(recursive: true);
  });

  test('rejects a file without the GGUF magic', () async {
    final dir = await Directory.systemTemp.createTemp('gguf_bad');
    final file = File('${dir.path}/bad.gguf');
    await file.writeAsBytes(List<int>.filled(64, 7));
    await expectLater(
      GgufInspector.inspect(file),
      throwsA(isA<GgufFormatException>()),
    );
    expect(
      GgufInspector.hasMagic(Uint8List.fromList(ascii.encode('GGUF'))),
      isTrue,
    );
    expect(
      GgufInspector.hasMagic(Uint8List.fromList(<int>[1, 2, 3, 4])),
      isFalse,
    );
    await dir.delete(recursive: true);
  });

  test('rejects a truncated header', () async {
    final dir = await Directory.systemTemp.createTemp('gguf_short');
    final file = File('${dir.path}/short.gguf');
    await file.writeAsBytes(<int>[0x47, 0x47, 0x55]);
    await expectLater(
      GgufInspector.inspect(file),
      throwsA(isA<GgufFormatException>()),
    );
    await dir.delete(recursive: true);
  });
}
