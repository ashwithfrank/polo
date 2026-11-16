import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

// Reading and removing the hidden data inside pictures (EXIF: camera, date,
// GPS location and so on). Everything here works on the file's bytes directly,
// so the picture itself is never re-encoded and loses no quality.

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

class Rational {
  const Rational(this.num, this.den);

  final int num;
  final int den;

  double get value => den == 0 ? 0 : num / den;
}

class InfoRow {
  const InfoRow(this.label, this.value);

  final String label;
  final String value;
}

class InfoSection {
  const InfoSection(this.title, this.rows);

  final String title;
  final List<InfoRow> rows;
}

class PhotoInfo {
  const PhotoInfo({
    required this.format,
    required this.bytes,
    required this.width,
    required this.height,
    required this.sections,
    required this.latitude,
    required this.longitude,
    required this.hasExif,
  });

  final String format;
  final int bytes;
  final int? width;
  final int? height;
  final List<InfoSection> sections;
  final double? latitude;
  final double? longitude;
  final bool hasExif;

  bool get hasLocation => latitude != null && longitude != null;
}

/// Reads size, format and EXIF data from the picture at [path].
Future<PhotoInfo> readPhotoInfo(String path) =>
    Isolate.run(() => _readPhotoInfoSync(path));

PhotoInfo _readPhotoInfoSync(String path) {
  final bytes = File(path).readAsBytesSync();
  final format = _formatOf(bytes);
  final size = imageSize(bytes);
  final exif = format == 'JPEG' ? _parseJpegExif(bytes) : null;

  double? lat;
  double? lon;
  final sections = <InfoSection>[];

  if (exif != null) {
    Object? at(Map<int, Object> m, int tag) => m[tag];

    String? str(Map<int, Object> m, int tag) {
      final v = at(m, tag);
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    num? number(Map<int, Object> m, int tag) {
      final v = at(m, tag);
      if (v is num) return v;
      if (v is Rational) return v.value;
      if (v is List && v.isNotEmpty) {
        final f = v.first;
        if (f is num) return f;
        if (f is Rational) return f.value;
      }
      return null;
    }

    void add(List<InfoRow> rows, String label, String? value) {
      if (value != null && value.isNotEmpty) rows.add(InfoRow(label, value));
    }

    final i0 = exif.ifd0;
    final ex = exif.exif;
    final gps = exif.gps;

    // Camera
    final camera = <InfoRow>[];
    add(camera, 'Make', str(i0, 0x010F));
    add(camera, 'Model', str(i0, 0x0110));
    add(camera, 'Lens', str(ex, 0xA434) ?? str(ex, 0xA433));
    add(camera, 'Software', str(i0, 0x0131));
    add(camera, 'Owner', str(ex, 0xA430) ?? str(i0, 0x013B));
    add(camera, 'Serial number', str(ex, 0xA431));
    add(camera, 'Copyright', str(i0, 0x8298));
    add(camera, 'Description', str(i0, 0x010E));
    if (camera.isNotEmpty) sections.add(InfoSection('Camera', camera));

    // Shot
    final shot = <InfoRow>[];
    add(shot, 'Taken', _date(str(ex, 0x9003)));
    add(shot, 'Digitized', _date(str(ex, 0x9004)));
    add(shot, 'Modified', _date(str(i0, 0x0132)));
    final exposure = at(ex, 0x829A);
    if (exposure is Rational && exposure.num > 0 && exposure.den != 0) {
      add(
        shot,
        'Exposure',
        exposure.value >= 1
            ? '${_trim(exposure.value)} s'
            : '1/${(1 / exposure.value).round()} s',
      );
    }
    final f = number(ex, 0x829D);
    if (f != null) add(shot, 'Aperture', 'f/${_trim(f.toDouble())}');
    final iso = number(ex, 0x8827);
    if (iso != null) add(shot, 'ISO', iso.round().toString());
    final focal = number(ex, 0x920A);
    if (focal != null) add(shot, 'Focal length', '${_trim(focal.toDouble())} mm');
    final focal35 = number(ex, 0xA405);
    if (focal35 != null && focal35 > 0) {
      add(shot, 'Focal length (35 mm)', '${focal35.round()} mm');
    }
    final bias = number(ex, 0x9204);
    if (bias != null) {
      add(shot, 'Exposure bias', '${bias >= 0 ? '+' : ''}${_trim(bias.toDouble())} EV');
    }
    final flash = number(ex, 0x9209);
    if (flash != null) add(shot, 'Flash', flash.toInt() & 1 == 1 ? 'Fired' : 'Did not fire');
    final orientation = number(i0, 0x0112);
    if (orientation != null) add(shot, 'Orientation', _orientation(orientation.toInt()));
    if (shot.isNotEmpty) sections.add(InfoSection('Shot', shot));

    // Location
    lat = _coordinate(gps[0x0002], gps[0x0001]);
    lon = _coordinate(gps[0x0004], gps[0x0003]);
    if (lat != null && lon != null) {
      final place = <InfoRow>[
        InfoRow('Latitude', lat.toStringAsFixed(6)),
        InfoRow('Longitude', lon.toStringAsFixed(6)),
      ];
      final alt = number(gps, 0x0006);
      if (alt != null) place.add(InfoRow('Altitude', '${alt.toStringAsFixed(0)} m'));
      sections.add(InfoSection('Location', place));
    } else {
      lat = null;
      lon = null;
    }
  }

  return PhotoInfo(
    format: format,
    bytes: bytes.length,
    width: size?.$1,
    height: size?.$2,
    sections: sections,
    latitude: lat,
    longitude: lon,
    hasExif: sections.isNotEmpty,
  );
}

String _trim(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

String? _date(String? raw) {
  if (raw == null) return null;
  // EXIF dates look like 2026:11:15 18:30:00
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}:\d{2}:\d{2})').firstMatch(raw);
  if (m == null) return raw;
  return '${m[1]}-${m[2]}-${m[3]} ${m[4]}';
}

String _orientation(int v) => switch (v) {
  1 => 'Normal',
  2 => 'Mirrored',
  3 => 'Rotated 180°',
  4 => 'Flipped vertically',
  5 => 'Mirrored, rotated 90°',
  6 => 'Rotated 90° clockwise',
  7 => 'Mirrored, rotated 270°',
  8 => 'Rotated 90° counter-clockwise',
  _ => '$v',
};

double? _coordinate(Object? dms, Object? ref) {
  if (dms is! List || dms.length < 3) return null;
  double part(Object? o) => o is Rational ? o.value : (o is num ? o.toDouble() : double.nan);
  final d = part(dms[0]);
  final m = part(dms[1]);
  final s = part(dms[2]);
  if (d.isNaN || m.isNaN || s.isNaN) return null;
  var value = d + m / 60 + s / 3600;
  if (ref is String && (ref.startsWith('S') || ref.startsWith('W'))) value = -value;
  return value;
}

String _formatOf(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'JPEG';
  if (_isPng(b)) return 'PNG';
  if (_isWebp(b)) return 'WebP';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'GIF';
  if (b.length > 2 && b[0] == 0x42 && b[1] == 0x4D) return 'BMP';
  return 'Image';
}

bool _isPng(Uint8List b) =>
    b.length > 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47;

bool _isWebp(Uint8List b) =>
    b.length > 12 &&
        b[0] == 0x52 && // R
        b[1] == 0x49 && // I
        b[2] == 0x46 && // F
        b[3] == 0x46 && // F
        b[8] == 0x57 && // W
        b[9] == 0x45 && // E
        b[10] == 0x42 && // B
        b[11] == 0x50; // P

/// Width and height in pixels, read from the file header. Null if unknown.
(int, int)? imageSize(Uint8List b) {
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        i += 2;
        continue;
      }
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        return (w, h);
      }
      final len = (b[i + 2] << 8) | b[i + 3];
      if (len < 2) return null;
      i += 2 + len;
    }
    return null;
  }
  if (_isPng(b) && b.length >= 24) {
    final bd = ByteData.sublistView(b);
    return (bd.getUint32(16), bd.getUint32(20));
  }
  if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    final bd = ByteData.sublistView(b);
    return (bd.getUint16(6, Endian.little), bd.getUint16(8, Endian.little));
  }
  if (b.length > 26 && b[0] == 0x42 && b[1] == 0x4D) {
    final bd = ByteData.sublistView(b);
    return (bd.getInt32(18, Endian.little).abs(), bd.getInt32(22, Endian.little).abs());
  }
  if (_isWebp(b) && b.length > 30) {
    final kind = String.fromCharCodes(b.sublist(12, 16));
    if (kind == 'VP8X') {
      final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return (w, h);
    }
    if (kind == 'VP8 ') {
      final w = (b[26] | (b[27] << 8)) & 0x3FFF;
      final h = (b[28] | (b[29] << 8)) & 0x3FFF;
      return (w, h);
    }
    if (kind == 'VP8L') {
      final b1 = b[21], b2 = b[22], b3 = b[23], b4 = b[24];
      final w = 1 + (((b2 & 0x3F) << 8) | b1);
      final h = 1 + (((b4 & 0x0F) << 10) | (b3 << 2) | ((b2 & 0xC0) >> 6));
      return (w, h);
    }
  }
  return null;
}

class _Exif {
  _Exif(this.ifd0, this.exif, this.gps);

  final Map<int, Object> ifd0;
  final Map<int, Object> exif;
  final Map<int, Object> gps;
}

/// The EXIF orientation (1-8) of a JPEG, or null.
int? _jpegOrientation(Uint8List b) {
  final v = _parseJpegExif(b)?.ifd0[0x0112];
  return v is int ? v : null;
}

_Exif? _parseJpegExif(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
      i += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) return null;
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2) return null;
    final end = math.min(i + 2 + len, b.length);
    if (marker == 0xE1 &&
        i + 10 <= b.length &&
        b[i + 4] == 0x45 && // E
        b[i + 5] == 0x78 && // x
        b[i + 6] == 0x69 && // i
        b[i + 7] == 0x66 && // f
        b[i + 8] == 0 &&
        b[i + 9] == 0) {
      return _parseTiff(b, i + 10, end);
    }
    i = end;
  }
  return null;
}

_Exif? _parseTiff(Uint8List b, int start, int end) {
  if (end - start < 8) return null;
  final bd = ByteData.sublistView(b, start, end);
  final Endian e;
  if (b[start] == 0x49 && b[start + 1] == 0x49) {
    e = Endian.little;
  } else if (b[start] == 0x4D && b[start + 1] == 0x4D) {
    e = Endian.big;
  } else {
    return null;
  }
  final total = bd.lengthInBytes;

  int u16(int o) => bd.getUint16(o, e);
  int u32(int o) => bd.getUint32(o, e);

  Object? readValue(int type, int count, int o) {
    switch (type) {
      case 2: // ASCII
        final bytes = <int>[for (var k = 0; k < count; k++) bd.getUint8(o + k)];
        final nul = bytes.indexOf(0);
        return String.fromCharCodes(nul >= 0 ? bytes.sublist(0, nul) : bytes);
      case 1: // BYTE
      case 7: // UNDEFINED
        final list = [for (var k = 0; k < count; k++) bd.getUint8(o + k)];
        return list.length == 1 ? list.first : list;
      case 3: // SHORT
        final list = [for (var k = 0; k < count; k++) u16(o + 2 * k)];
        return list.length == 1 ? list.first : list;
      case 4: // LONG
        final list = [for (var k = 0; k < count; k++) u32(o + 4 * k)];
        return list.length == 1 ? list.first : list;
      case 9: // SLONG
        final list = [for (var k = 0; k < count; k++) bd.getInt32(o + 4 * k, e)];
        return list.length == 1 ? list.first : list;
      case 5: // RATIONAL
        final list = [
          for (var k = 0; k < count; k++) Rational(u32(o + 8 * k), u32(o + 8 * k + 4)),
        ];
        return list.length == 1 ? list.first : list;
      case 10: // SRATIONAL
        final list = [
          for (var k = 0; k < count; k++)
            Rational(bd.getInt32(o + 8 * k, e), bd.getInt32(o + 8 * k + 4, e)),
        ];
        return list.length == 1 ? list.first : list;
    }
    return null;
  }

  int typeSize(int type) => switch (type) {
    1 || 2 || 7 => 1,
    3 => 2,
    4 || 9 => 4,
    5 || 10 => 8,
    _ => 0,
  };

  Map<int, Object> readIfd(int offset) {
    final out = <int, Object>{};
    if (offset <= 0 || offset + 2 > total) return out;
    final n = u16(offset);
    for (var k = 0; k < n; k++) {
      final o = offset + 2 + k * 12;
      if (o + 12 > total) break;
      final tag = u16(o);
      final type = u16(o + 2);
      final count = u32(o + 4);
      final unit = typeSize(type);
      if (unit == 0 || count == 0 || count > 4096) continue;
      final size = unit * count;
      final valueAt = size <= 4 ? o + 8 : u32(o + 8);
      if (valueAt < 0 || valueAt + size > total) continue;
      final v = readValue(type, count, valueAt);
      if (v != null) out[tag] = v;
    }
    return out;
  }

  final ifd0 = readIfd(u32(4));
  final exifPtr = ifd0[0x8769];
  final gpsPtr = ifd0[0x8825];
  return _Exif(
    ifd0,
    exifPtr is int ? readIfd(exifPtr) : <int, Object>{},
    gpsPtr is int ? readIfd(gpsPtr) : <int, Object>{},
  );
}

// ---------------------------------------------------------------------------
// Removing
// ---------------------------------------------------------------------------

class StripResult {
  const StripResult({required this.path, required this.before, required this.after});

  final String path;
  final int before;
  final int after;

  int get removed => before - after;
  String get name => path.split('/').last;
}

/// Extensions [stripMetadataBytes] can clean.
const strippableExtensions = {'jpg', 'jpeg', 'png', 'webp'};

/// Writes a copy of [path] without hidden data to [outPath].
/// Throws a [FormatException] if the file can't be cleaned.
Future<StripResult> stripMetadataFile(String path, String outPath) {
  return Isolate.run(() {
    final bytes = File(path).readAsBytesSync();
    final ext = path.split('.').last.toLowerCase();
    final cleaned = stripMetadataBytes(bytes, ext);
    if (cleaned == null) {
      throw const FormatException("This file can't be cleaned. Try JPG, PNG or WebP");
    }
    File(outPath).writeAsBytesSync(cleaned, flush: true);
    return StripResult(path: outPath, before: bytes.length, after: cleaned.length);
  });
}

/// Returns the picture without hidden data, or null if the format isn't
/// supported or the file looks damaged. The image data is copied untouched.
Uint8List? stripMetadataBytes(Uint8List b, String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return _stripJpeg(b);
    case 'png':
      return _stripPng(b);
    case 'webp':
      return _stripWebp(b);
  }
  return null;
}

Uint8List? _stripJpeg(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;

  // Keep the rotation, or photos taken sideways would show up sideways.
  final orientation = _jpegOrientation(b);
  var pending = orientation != null && orientation != 1 && orientation >= 2 && orientation <= 8;
  final orientationSegment = pending ? _orientationSegment(orientation) : Uint8List(0);

  final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
  var i = 2;
  var first = true;

  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
      out.add(b.sublist(i, i + 2));
      i += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) break;

    final len = (b[i + 2] << 8) | b[i + 3];
    final end = i + 2 + len;
    if (len < 2 || end > b.length) return null;

    // Remove EXIF/XMP (E1), other application data (E3-ED, EF) and comments.
    final drop = marker == 0xFE ||
        marker == 0xE1 ||
        (marker >= 0xE3 && marker <= 0xED) ||
        marker == 0xEF;

    if (!drop) {
      if (pending && !(first && marker == 0xE0)) {
        out.add(orientationSegment);
        pending = false;
      }
      out.add(b.sublist(i, end));
      if (pending && marker == 0xE0) {
        out.add(orientationSegment);
        pending = false;
      }
      first = false;
    }
    i = end;
  }

  if (pending) out.add(orientationSegment);
  out.add(b.sublist(i));
  return out.takeBytes();
}

Uint8List _orientationSegment(int orientation) {
  return Uint8List.fromList([
    0xFF, 0xE1, 0x00, 0x22, // APP1, length 34
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big-endian TIFF header
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, 1
    0x00, orientation, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ]);
}

Uint8List? _stripPng(Uint8List b) {
  if (!_isPng(b)) return null;
  const drop = {'tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME'};
  final bd = ByteData.sublistView(b);
  final out = BytesBuilder(copy: false)..add(b.sublist(0, 8));
  var i = 8;
  while (i + 12 <= b.length) {
    final length = bd.getUint32(i);
    final end = i + 12 + length;
    if (end > b.length) return null;
    final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
    if (!drop.contains(type)) out.add(b.sublist(i, end));
    i = end;
    if (type == 'IEND') break;
  }
  return out.takeBytes();
}

Uint8List? _stripWebp(Uint8List b) {
  if (!_isWebp(b)) return null;
  final bd = ByteData.sublistView(b);
  final chunks = <Uint8List>[];
  var i = 12;
  while (i + 8 <= b.length) {
    final type = String.fromCharCodes(b.sublist(i, i + 4));
    final size = bd.getUint32(i + 4, Endian.little);
    final padded = size + (size.isOdd ? 1 : 0);
    final end = math.min(i + 8 + padded, b.length);
    if (i + 8 + size > b.length) return null;
    if (type != 'EXIF' && type != 'XMP ') {
      final chunk = Uint8List.fromList(b.sublist(i, end));
      if (type == 'VP8X' && chunk.length > 8) {
        chunk[8] = chunk[8] & ~(0x08 | 0x04); // no EXIF, no XMP
      }
      chunks.add(chunk);
    }
    i = end;
  }
  final body = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final out = BytesBuilder(copy: false)
    ..add(b.sublist(0, 4))
    ..add(
      (ByteData(4)..setUint32(0, 4 + body, Endian.little)).buffer.asUint8List(),
    )
    ..add(b.sublist(8, 12));
  for (final c in chunks) {
    out.add(c);
  }
  return out.takeBytes();
}