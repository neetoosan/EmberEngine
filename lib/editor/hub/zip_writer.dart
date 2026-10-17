import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Writes standard .zip files (deflate), e.g. a web game for itch.io or a
/// Windows game folder to share. No dependencies.
class ZipWriter {
  ZipWriter._();

  /// Zips every file under [folder] into [output]. Paths inside the zip are
  /// relative to [folder] (so `index.html` ends up at the root), optionally
  /// under [prefix]/. Files at [exclude] (relative, forward slashes) are left out.
  static Future<File> zipFolder(Directory folder, File output, {String prefix = '', Set<String> exclude = const {}}) async {
    final entries = <(String, File)>[];
    final root = folder.absolute.path;
    await for (final e in folder.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.absolute.path.substring(root.length + 1).replaceAll(Platform.pathSeparator, '/');
      if (exclude.contains(rel)) continue;
      entries.add((prefix.isEmpty ? rel : '$prefix/$rel', e));
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));
    final sink = output.openWrite();
    final central = BytesBuilder();
    var offset = 0;
    final now = DateTime.now();
    final dosTime = (now.hour << 11) | (now.minute << 5) | (now.second ~/ 2);
    final dosDate = ((now.year - 1980).clamp(0, 127) << 9) | (now.month << 5) | now.day;
    for (final (name, file) in entries) {
      final data = await file.readAsBytes();
      final crc = crc32(data);
      final deflated = Uint8List.fromList(ZLibEncoder(raw: true, level: 6).convert(data));
      final useDeflate = deflated.length < data.length;
      final body = useDeflate ? deflated : data;
      final nameBytes = Uint8List.fromList(utf8.encode(name));
      final flags = name.codeUnits.any((c) => c > 127) ? 0x0800 : 0; // UTF-8 names

      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, flags, Endian.little)
        ..setUint16(8, useDeflate ? 8 : 0, Endian.little)
        ..setUint16(10, dosTime, Endian.little)
        ..setUint16(12, dosDate, Endian.little)
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, body.length, Endian.little)
        ..setUint32(22, data.length, Endian.little)
        ..setUint16(26, nameBytes.length, Endian.little)
        ..setUint16(28, 0, Endian.little);
      sink
        ..add(local.buffer.asUint8List())
        ..add(nameBytes)
        ..add(body);

      final dir = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, flags, Endian.little)
        ..setUint16(10, useDeflate ? 8 : 0, Endian.little)
        ..setUint16(12, dosTime, Endian.little)
        ..setUint16(14, dosDate, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, body.length, Endian.little)
        ..setUint32(24, data.length, Endian.little)
        ..setUint16(28, nameBytes.length, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central
        ..add(dir.buffer.asUint8List())
        ..add(nameBytes);
      offset += 30 + nameBytes.length + body.length;
    }
    final centralBytes = central.toBytes();
    final endRecord = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, entries.length, Endian.little)
      ..setUint16(10, entries.length, Endian.little)
      ..setUint32(12, centralBytes.length, Endian.little)
      ..setUint32(16, offset, Endian.little);
    sink
      ..add(centralBytes)
      ..add(endRecord.buffer.asUint8List());
    await sink.close();
    return output;
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }
}
