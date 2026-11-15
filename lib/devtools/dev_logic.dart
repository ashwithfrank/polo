import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

// Pure text tools. Each takes the input and returns the result, or throws a
// FormatException whose message is shown to the user.

// ---------- JSON ----------

String jsonFormat(String s) =>
    const JsonEncoder.withIndent('  ').convert(jsonDecode(s));

String jsonMinify(String s) => jsonEncode(jsonDecode(s));

String jsonValidate(String s) {
  final v = jsonDecode(s);
  final kind = v is Map
      ? 'an object with ${v.length} ${v.length == 1 ? 'key' : 'keys'}'
      : v is List
      ? 'an array with ${v.length} ${v.length == 1 ? 'item' : 'items'}'
      : v == null
      ? 'null'
      : v is String
      ? 'a string'
      : v is num
      ? 'a number'
      : 'a boolean';
  return 'Valid JSON: $kind';
}

// ---------- Encoding ----------

String base64EncodeText(String s) => base64.encode(utf8.encode(s));

String base64DecodeText(String s) {
  var t = s
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll('-', '+')
      .replaceAll('_', '/');
  t = t.padRight(t.length + (4 - t.length % 4) % 4, '=');
  final List<int> bytes;
  try {
    bytes = base64.decode(t);
  } on FormatException {
    throw const FormatException('That is not valid Base64');
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const FormatException('The decoded data is not text');
  }
}

String urlEncodeText(String s) => Uri.encodeComponent(s);

String urlDecodeText(String s) {
  try {
    return Uri.decodeComponent(s);
  } on ArgumentError {
    throw const FormatException('That is not a valid encoded URL text');
  }
}

String hexEncodeText(String s) => utf8
    .encode(s)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join(' ');

String hexDecodeText(String s) {
  final t = s.replaceAll(RegExp(r'0x|[\s,:]', caseSensitive: false), '');
  if (!RegExp(r'^[0-9a-fA-F]*$').hasMatch(t)) {
    throw const FormatException('Hex can only contain 0-9 and A-F');
  }
  if (t.length.isOdd) {
    throw const FormatException('Hex needs an even number of digits');
  }
  final bytes = <int>[
    for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16),
  ];
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const FormatException('The decoded data is not text');
  }
}

String htmlEncodeText(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'copy': '©',
  'reg': '®',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'euro': '€',
};

String htmlDecodeText(String s) {
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (m) {
    final e = m[1]!;
    if (e.startsWith('#')) {
      final code = e.startsWith('#x') || e.startsWith('#X')
          ? int.tryParse(e.substring(2), radix: 16)
          : int.tryParse(e.substring(1));
      if (code == null || code < 0 || code > 0x10FFFF) return m[0]!;
      return String.fromCharCode(code);
    }
    return _namedEntities[e] ?? m[0]!;
  });
}

// ---------- JWT ----------

String jwtDecode(String s) {
  final parts = s.trim().split('.');
  if (parts.length != 3) {
    throw const FormatException('A JWT has three parts separated by dots');
  }
  const pretty = JsonEncoder.withIndent('  ');
  Object? part(String p) {
    try {
      return jsonDecode(base64DecodeText(p));
    } on FormatException {
      throw const FormatException('Could not read this token');
    }
  }

  final header = part(parts[0]);
  final payload = part(parts[1]);

  final out = StringBuffer()
    ..writeln('HEADER')
    ..writeln(pretty.convert(header))
    ..writeln()
    ..writeln('PAYLOAD')
    ..writeln(pretty.convert(payload));

  if (payload is Map) {
    final times = <String>[];
    for (final key in const ['iat', 'nbf', 'exp']) {
      final v = payload[key];
      if (v is num) {
        final d = DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000, isUtc: true);
        var line = '$key: ${_stamp(d)} UTC';
        if (key == 'exp') {
          line += d.isBefore(DateTime.now().toUtc()) ? '  (expired)' : '  (still valid)';
        }
        times.add(line);
      }
    }
    if (times.isNotEmpty) {
      out
        ..writeln()
        ..writeln('TIMES')
        ..writeln(times.join('\n'));
    }
  }

  out
    ..writeln()
    ..writeln('SIGNATURE (not verified)')
    ..write(parts[2]);
  return out.toString();
}

// ---------- Hashing ----------

String hashText(String s) {
  final bytes = utf8.encode(s);
  return 'MD5\n${crypto.md5.convert(bytes)}\n\n'
      'SHA-1\n${crypto.sha1.convert(bytes)}\n\n'
      'SHA-256\n${crypto.sha256.convert(bytes)}\n\n'
      'SHA-512\n${crypto.sha512.convert(bytes)}';
}

// ---------- Numbers and units ----------

String numberBases(String s) {
  var t = s.trim().toLowerCase().replaceAll(RegExp(r'[_\s]'), '');
  var negative = false;
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  }
  var radix = 10;
  if (t.startsWith('0x')) {
    radix = 16;
    t = t.substring(2);
  } else if (t.startsWith('0b')) {
    radix = 2;
    t = t.substring(2);
  } else if (t.startsWith('0o')) {
    radix = 8;
    t = t.substring(2);
  }
  final n = BigInt.tryParse(t, radix: radix);
  if (n == null) throw const FormatException('That is not a valid number');
  final v = negative ? -n : n;
  return 'Decimal\n$v\n\n'
      'Binary\n${v.toRadixString(2)}\n\n'
      'Octal\n${v.toRadixString(8)}\n\n'
      'Hex\n${v.toRadixString(16).toUpperCase()}\n\n'
      'Tip: start with 0x, 0b or 0o to type hex, binary or octal.';
}

String textToCodes(String s) {
  final runes = s.runes.toList();
  return 'Decimal\n${runes.join(' ')}\n\n'
      'Hex\n${runes.map((r) => r.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ')}\n\n'
      'Binary\n${runes.map((r) => r.toRadixString(2).padLeft(8, '0')).join(' ')}';
}

String codesToText(String s) {
  final tokens = s.trim().split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty);
  final codes = <int>[];
  for (final t in tokens) {
    final lower = t.toLowerCase();
    final code = lower.startsWith('0x')
        ? int.tryParse(lower.substring(2), radix: 16)
        : int.tryParse(lower);
    if (code == null || code < 0 || code > 0x10FFFF) {
      throw FormatException('"$t" is not a valid character code');
    }
    codes.add(code);
  }
  return String.fromCharCodes(codes);
}

String _num(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

String dataSize(String s) {
  final m = RegExp(r'^([0-9]*\.?[0-9]+)\s*([a-zA-Z]*)$').firstMatch(s.trim());
  if (m == null) throw const FormatException('Try something like 1536 MB');
  final value = double.parse(m[1]!);
  final unit = m[2]!.toLowerCase();
  const steps = {'': 0, 'b': 0, 'kb': 1, 'kib': 1, 'mb': 2, 'mib': 2, 'gb': 3, 'gib': 3, 'tb': 4, 'tib': 4};
  final power = steps[unit];
  if (power == null) throw FormatException('Unknown unit "${m[2]}". Use B, KB, MB, GB or TB');
  var bytes = value;
  for (var i = 0; i < power; i++) {
    bytes *= 1024;
  }
  const names = ['B', 'KB', 'MB', 'GB', 'TB'];
  final out = StringBuffer('Binary (1 KB = 1024 B)\n');
  for (var i = 0; i < names.length; i++) {
    var v = bytes;
    for (var j = 0; j < i; j++) {
      v /= 1024;
    }
    out.writeln('${_num(v)} ${names[i]}');
  }
  out.writeln('\nDecimal (1 KB = 1000 B)');
  for (var i = 0; i < names.length; i++) {
    var v = bytes;
    for (var j = 0; j < i; j++) {
      v /= 1000;
    }
    out.writeln('${_num(v)} ${names[i]}');
  }
  out.write('\nTip: sizes you type are read as 1024-based.');
  return out.toString();
}

// ---------- Time ----------

String _p2(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime d) =>
    '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}:${_p2(d.second)}';

String timestampToDate(String s) {
  final t = s.trim();
  final int ms;
  var heading = '';
  if (t.isEmpty) {
    ms = DateTime.now().millisecondsSinceEpoch;
    heading = 'Right now\n\n';
  } else {
    final n = int.tryParse(t);
    if (n == null) throw const FormatException('Enter a number of seconds or milliseconds');
    // 12+ digits means milliseconds.
    ms = n.abs() >= 100000000000 ? n : n * 1000;
  }
  final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  final local = utc.toLocal();
  return '${heading}UTC\n${_stamp(utc)}\n\n'
      'Local (${local.timeZoneName})\n${_stamp(local)}\n\n'
      'Seconds\n${(ms / 1000).floor()}\n\n'
      'Milliseconds\n$ms';
}

String dateToTimestamp(String s) {
  final d = DateTime.tryParse(s.trim());
  if (d == null) {
    throw const FormatException('Use a date like 2026-11-15 18:30 (add Z for UTC)');
  }
  final ms = d.millisecondsSinceEpoch;
  return 'Seconds\n${(ms / 1000).floor()}\n\n'
      'Milliseconds\n$ms\n\n'
      'As UTC\n${_stamp(d.toUtc())}';
}