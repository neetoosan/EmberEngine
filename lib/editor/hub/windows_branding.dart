import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// What a game's .exe says about itself (Explorer → Properties → Details,
/// Task Manager, the taskbar and the window's title-bar icon).
class ExeIdentity {
  final String productName;
  final String description;
  final String company;
  final String copyright;
  final String version; // 1.2.3
  final int build;
  final String originalFilename;

  const ExeIdentity({
    required this.productName,
    required this.description,
    required this.company,
    required this.copyright,
    required this.version,
    required this.build,
    required this.originalFilename,
  });

  /// The four numbers Windows shows as the file version.
  List<int> get versionParts {
    final p = version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (p.length < 3) {
      p.add(0);
    }
    return [p[0], p[1], p[2], build].map((n) => n.clamp(0, 65535)).toList();
  }
}

/// Rewrites the icon and version information inside a Windows executable
/// (the copied game player), so each exported game looks like itself.
/// Uses the Win32 resource update API; Windows only.
class WindowsBranding {
  WindowsBranding._();

  /// Resource ids used by the Flutter runner (windows/runner/resource.h, Runner.rc).
  static const int iconGroupId = 101;
  static const int versionId = 1;
  static const int langEnUs = 0x0409;

  static const int _rtIcon = 3, _rtGroupIcon = 14, _rtVersion = 16;

  /// Writes [identity] (and [ico], a .ico file, if given) into [exe]. Throws on failure.
  static void brand(File exe, {Uint8List? ico, required ExeIdentity identity}) {
    if (!Platform.isWindows) throw UnsupportedError('Branding a Windows executable needs Windows');
    final images = ico == null ? const <IcoImage>[] : parseIco(ico);
    final k32 = DynamicLibrary.open('kernel32.dll');
    final begin = k32.lookupFunction<IntPtr Function(Pointer<Utf16>, Int32), int Function(Pointer<Utf16>, int)>('BeginUpdateResourceW');
    final update = k32.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint16, Pointer<Uint8>, Uint32),
        int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint8>, int)>('UpdateResourceW');
    final end = k32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('EndUpdateResourceW');
    final lastError = k32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

    final path = exe.absolute.path.toNativeUtf16();
    final handle = begin(path, 0);
    calloc.free(path);
    if (handle == 0) throw FileSystemException('Could not open the game executable for branding (error ${lastError()})', exe.path);

    var ok = true;
    void put(int type, int id, Uint8List data) {
      final buf = calloc<Uint8>(data.length);
      buf.asTypedList(data.length).setAll(0, data);
      if (update(handle, Pointer.fromAddress(type), Pointer.fromAddress(id), langEnUs, buf, data.length) == 0) ok = false;
      calloc.free(buf);
    }

    if (images.isNotEmpty) {
      for (var i = 0; i < images.length; i++) {
        put(_rtIcon, i + 1, images[i].data);
      }
      put(_rtGroupIcon, iconGroupId, groupIconDirectory(images));
    }
    put(_rtVersion, versionId, versionInfo(identity));

    if (end(handle, ok ? 0 : 1) == 0 || !ok) {
      throw FileSystemException('Writing the icon and name into the game failed (error ${lastError()})', exe.path);
    }
  }

  // ---------------------------------------------------------------------------
  // Resource formats

  /// The images inside a .ico file.
  static List<IcoImage> parseIco(Uint8List ico) {
    final d = ByteData.sublistView(ico);
    if (ico.length < 6 || d.getUint16(2, Endian.little) != 1) throw const FormatException('Not a .ico file');
    final count = d.getUint16(4, Endian.little);
    return [
      for (var i = 0; i < count; i++)
        () {
          final e = 6 + i * 16;
          final size = d.getUint32(e + 8, Endian.little), offset = d.getUint32(e + 12, Endian.little);
          return IcoImage(
            width: d.getUint8(e),
            height: d.getUint8(e + 1),
            colors: d.getUint8(e + 2),
            planes: d.getUint16(e + 4, Endian.little),
            bitCount: d.getUint16(e + 6, Endian.little),
            data: Uint8List.sublistView(ico, offset, offset + size),
          );
        }(),
    ];
  }

  /// GRPICONDIR: the icon group pointing at RT_ICON resources 1..n.
  static Uint8List groupIconDirectory(List<IcoImage> images) {
    final d = ByteData(6 + 14 * images.length)
      ..setUint16(0, 0, Endian.little)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, images.length, Endian.little);
    for (var i = 0; i < images.length; i++) {
      final e = 6 + i * 14, img = images[i];
      d
        ..setUint8(e, img.width)
        ..setUint8(e + 1, img.height)
        ..setUint8(e + 2, img.colors)
        ..setUint8(e + 3, 0)
        ..setUint16(e + 4, img.planes, Endian.little)
        ..setUint16(e + 6, img.bitCount, Endian.little)
        ..setUint32(e + 8, img.data.length, Endian.little)
        ..setUint16(e + 12, i + 1, Endian.little);
    }
    return d.buffer.asUint8List();
  }

  /// VS_VERSIONINFO with US-English Unicode strings.
  static Uint8List versionInfo(ExeIdentity id) {
    final v = id.versionParts;
    final fixed = ByteData(52)
      ..setUint32(0, 0xFEEF04BD, Endian.little) // signature
      ..setUint32(4, 0x00010000, Endian.little) // structure version
      ..setUint32(8, (v[0] << 16) | v[1], Endian.little) // file version
      ..setUint32(12, (v[2] << 16) | v[3], Endian.little)
      ..setUint32(16, (v[0] << 16) | v[1], Endian.little) // product version
      ..setUint32(20, (v[2] << 16) | v[3], Endian.little)
      ..setUint32(24, 0x3F, Endian.little) // flags mask
      ..setUint32(28, 0, Endian.little) // flags
      ..setUint32(32, 0x00040004, Endian.little) // VOS_NT_WINDOWS32
      ..setUint32(36, 1, Endian.little) // VFT_APP
      ..setUint32(40, 0, Endian.little)
      ..setUint32(44, 0, Endian.little)
      ..setUint32(48, 0, Endian.little);
    final versionText = '${v[0]}.${v[1]}.${v[2]}.${v[3]}';
    final strings = {
      'CompanyName': id.company,
      'FileDescription': id.description,
      'FileVersion': versionText,
      'InternalName': id.productName,
      'LegalCopyright': id.copyright,
      'OriginalFilename': id.originalFilename,
      'ProductName': id.productName,
      'ProductVersion': id.version,
    };
    final table = _node('040904B0', type: 1, children: [
      for (final e in strings.entries) _node(e.key, type: 1, text: e.value),
    ]);
    final translation = Uint8List.fromList([0x09, 0x04, 0xB0, 0x04]); // 0x0409, code page 1200
    return _node('VS_VERSION_INFO', type: 0, value: fixed.buffer.asUint8List(), children: [
      _node('StringFileInfo', type: 1, children: [table]),
      _node('VarFileInfo', type: 1, children: [_node('Translation', type: 0, value: translation)]),
    ]);
  }

  /// One version-resource block: header, key, value and children, each 32-bit aligned.
  static Uint8List _node(String key, {required int type, Uint8List? value, String? text, List<Uint8List> children = const []}) {
    final b = BytesBuilder();
    void pad() {
      while (b.length % 4 != 0) {
        b.addByte(0);
      }
    }

    final valueBytes = text != null ? _utf16z(text) : (value ?? Uint8List(0));
    final valueLength = text != null ? text.length + 1 : valueBytes.length; // text: in WCHARs
    b.add(Uint8List(6)); // wLength, wValueLength, wType filled in below
    b.add(_utf16z(key));
    pad();
    b.add(valueBytes);
    for (final c in children) {
      pad();
      b.add(c);
    }
    final out = b.toBytes();
    ByteData.sublistView(out)
      ..setUint16(0, out.length, Endian.little)
      ..setUint16(2, valueBytes.isEmpty ? 0 : valueLength, Endian.little)
      ..setUint16(4, type, Endian.little);
    return out;
  }

  static Uint8List _utf16z(String s) {
    final units = [...s.codeUnits, 0];
    final d = ByteData(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      d.setUint16(i * 2, units[i], Endian.little);
    }
    return d.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // Reading back (tests, export checks)

  /// The string [name] (e.g. "ProductName") from [exe]'s version information.
  static String? readVersionString(File exe, String name) {
    if (!Platform.isWindows) return null;
    final ver = DynamicLibrary.open('version.dll');
    final size = ver.lookupFunction<Uint32 Function(Pointer<Utf16>, Pointer<Uint32>), int Function(Pointer<Utf16>, Pointer<Uint32>)>(
        'GetFileVersionInfoSizeW');
    final getInfo = ver.lookupFunction<Int32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>), int Function(Pointer<Utf16>, int, int, Pointer<Uint8>)>(
        'GetFileVersionInfoW');
    final query = ver.lookupFunction<Int32 Function(Pointer<Uint8>, Pointer<Utf16>, Pointer<Pointer<Utf16>>, Pointer<Uint32>),
        int Function(Pointer<Uint8>, Pointer<Utf16>, Pointer<Pointer<Utf16>>, Pointer<Uint32>)>('VerQueryValueW');
    final path = exe.absolute.path.toNativeUtf16();
    final dummy = calloc<Uint32>();
    final n = size(path, dummy);
    if (n == 0) {
      calloc.free(path);
      calloc.free(dummy);
      return null;
    }
    final buf = calloc<Uint8>(n);
    final sub = '\\StringFileInfo\\040904B0\\$name'.toNativeUtf16();
    final out = calloc<Pointer<Utf16>>();
    final len = calloc<Uint32>();
    try {
      if (getInfo(path, 0, n, buf) == 0) return null;
      if (query(buf, sub, out, len) == 0 || len.value == 0) return null;
      return out.value.toDartString();
    } finally {
      for (final p in [path, dummy, buf, sub, out, len]) {
        calloc.free(p);
      }
    }
  }

  /// Copies the Visual C++ runtime DLLs a Flutter game needs next to [exe], so it
  /// starts on PCs without the VC++ Redistributable (Microsoft allows this
  /// "app-local" deployment). Returns the DLLs copied.
  static List<String> bundleVcRuntime(Directory gameDir) {
    if (!Platform.isWindows) return const [];
    final system = '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32';
    final copied = <String>[];
    for (final dll in ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']) {
      final target = File('${gameDir.path}\\$dll');
      final source = File('$system\\$dll');
      if (!target.existsSync() && source.existsSync()) {
        source.copySync(target.path);
        copied.add(dll);
      }
    }
    return copied;
  }
}

class IcoImage {
  final int width, height, colors, planes, bitCount;
  final Uint8List data;
  const IcoImage({required this.width, required this.height, required this.colors, required this.planes, required this.bitCount, required this.data});
}
