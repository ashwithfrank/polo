import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

class Checksums {
  const Checksums({required this.md5, required this.sha1, required this.sha256});

  final String md5;
  final String sha1;
  final String sha256;
}

class _Capture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class ChecksumService {
  /// Reads the file once and returns MD5, SHA-1 and SHA-256, off the UI thread.
  static Future<Checksums> compute(String path) => Isolate.run(() => _hashAll(path));
}

Future<Checksums> _hashAll(String path) async {
  final m = _Capture(), s1 = _Capture(), s256 = _Capture();
  final md5In = md5.startChunkedConversion(m);
  final sha1In = sha1.startChunkedConversion(s1);
  final sha256In = sha256.startChunkedConversion(s256);

  await for (final chunk in File(path).openRead()) {
    md5In.add(chunk);
    sha1In.add(chunk);
    sha256In.add(chunk);
  }
  md5In.close();
  sha1In.close();
  sha256In.close();

  return Checksums(
    md5: m.value.toString(),
    sha1: s1.value.toString(),
    sha256: s256.value.toString(),
  );
}