import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'file_service.dart';

/// One locked file, as shown in the vault list.
class VaultEntry {
  const VaultEntry({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  /// Where the encrypted copy lives.
  final String path;

  /// The original file name.
  final String name;

  /// The original size in bytes.
  final int size;
  final DateTime modified;
}

/// An encrypted vault of files, stored in a hidden folder.
///
/// The password is stretched into a key with PBKDF2-HMAC-SHA256. Every file
/// is encrypted with AES-256-GCM in 1 MB pieces, so even large files never
/// need much memory, and any change or damage to a file is detected. The key
/// only ever exists in memory while the vault is open. Nothing leaves the
/// device.
class VaultService {
  VaultService._();

  static String get dir => '${FileService.rootPath}/.Polo_Vault';
  static File get _metaFile => File('$dir/vault.meta');

  static const _iterations = 120000;

  static Future<bool> exists() => _metaFile.exists();

  /// Creates a new vault protected by [password] and returns its key.
  static Future<Uint8List> create(String password) async {
    await Directory(dir).create(recursive: true);
    final salt = _random(16);
    final key = await Isolate.run(() => _derive(password, salt, _iterations));
    final blob = await Isolate.run(() => _sealCheck(key));
    await _metaFile.writeAsString(
      jsonEncode({
        'v': 1,
        'salt': base64Encode(salt),
        'iter': _iterations,
        'check': base64Encode(blob),
      }),
      flush: true,
    );
    return key;
  }

  /// Returns the key if [password] is right, otherwise null.
  static Future<Uint8List?> unlock(String password) async {
    final Map<String, dynamic> meta;
    try {
      meta = jsonDecode(await _metaFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException("The vault's settings file is damaged");
    }
    final salt = base64Decode(meta['salt'] as String);
    final iter = meta['iter'] as int;
    final check = base64Decode(meta['check'] as String);

    return Isolate.run(() async {
      final key = await _derive(password, salt, iter);
      final ok = await _openCheck(key, check);
      return ok ? key : null;
    });
  }

  /// Everything in the vault, newest first. Files that can't be read are left
  /// out.
  static Future<List<VaultEntry>> list(Uint8List key) async {
    final folder = Directory(dir);
    if (!await folder.exists()) return const [];

    final rows = await Isolate.run(() async {
      final out = <Map<String, Object>>[];
      final algo = AesGcm.with256bits();
      final secret = SecretKey(key);
      for (final e in Directory(dir).listSync()) {
        if (e is! File || !e.path.endsWith('.polo')) continue;
        try {
          final reader = await _Reader.open(e.path);
          try {
            final head = await reader.next(algo, secret);
            if (head == null) continue;
            final map = jsonDecode(utf8.decode(head)) as Map<String, dynamic>;
            out.add({
              'p': e.path,
              'n': map['n'] as String,
              's': map['s'] as int,
              'm': map['m'] as int,
            });
          } finally {
            await reader.close();
          }
        } catch (_) {
          // Skip anything unreadable.
        }
      }
      return out;
    });

    final entries = [
      for (final r in rows)
        VaultEntry(
          path: r['p']! as String,
          name: r['n']! as String,
          size: r['s']! as int,
          modified: DateTime.fromMillisecondsSinceEpoch(r['m']! as int),
        ),
    ];
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return entries;
  }

  /// Locks [sourcePath] into the vault. With [verify] the new copy is read
  /// back and checked before this returns. Returns an error message, or null
  /// on success.
  static Future<String?> add(Uint8List key, String sourcePath, {required bool verify}) async {
    await Directory(dir).create(recursive: true);
    final id = _hex(_random(16));
    final dest = '$dir/$id.polo';
    final temp = '$dest.tmp';
    final stat = await File(sourcePath).stat();
    final name = sourcePath.split('/').last;
    final modifiedMs = stat.modified.millisecondsSinceEpoch;

    final error = await Isolate.run(() async {
      try {
        await _encrypt(key, sourcePath, temp, name, modifiedMs);
        if (verify) await _decrypt(key, temp, null);
        return null;
      } on FormatException catch (e) {
        return e.message;
      } catch (e) {
        return "Couldn't lock $name";
      }
    });

    if (error != null) {
      try {
        await File(temp).delete();
      } catch (_) {}
      return error;
    }
    await File(temp).rename(dest);
    return null;
  }

  /// Decrypts [entry] into [destPath]. Returns an error message, or null.
  static Future<String?> restore(Uint8List key, VaultEntry entry, String destPath) async {
    final from = entry.path;
    final name = entry.name;
    final error = await Isolate.run(() async {
      try {
        await _decrypt(key, from, destPath);
        return null;
      } on FormatException catch (e) {
        return e.message;
      } catch (_) {
        return "Couldn't unlock $name";
      }
    });
    if (error != null) {
      try {
        await File(destPath).delete();
      } catch (_) {}
    }
    return error;
  }

  static Future<void> remove(VaultEntry entry) async {
    await File(entry.path).delete();
  }

  /// Deletes the whole vault, including everything in it.
  static Future<void> erase() async {
    final folder = Directory(dir);
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// Everything below runs inside isolates and only uses plain values.
// ---------------------------------------------------------------------------

const _magic = [0x50, 0x4F, 0x4C, 0x4F, 0x45, 0x4E, 0x43, 0x31]; // POLOENC1
const _pieceSize = 1 << 20;
const _macLength = 16;
const _check = 'polo-vault-ok';

Uint8List _random(int n) {
  final r = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]);
}

String _hex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

Future<Uint8List> _derive(String password, List<int> salt, int iterations) async {
  final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
  final key = await pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  return Uint8List.fromList(await key.extractBytes());
}

/// An encrypted known text, used to tell a right password from a wrong one.
Future<Uint8List> _sealCheck(Uint8List key) async {
  final algo = AesGcm.with256bits();
  final nonce = _random(12);
  final box = await algo.encrypt(utf8.encode(_check), secretKey: SecretKey(key), nonce: nonce);
  return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
}

Future<bool> _openCheck(Uint8List key, List<int> blob) async {
  if (blob.length < 12 + _macLength) return false;
  try {
    final algo = AesGcm.with256bits();
    final box = SecretBox(
      blob.sublist(12, blob.length - _macLength),
      nonce: blob.sublist(0, 12),
      mac: Mac(blob.sublist(blob.length - _macLength)),
    );
    final clear = await algo.decrypt(box, secretKey: SecretKey(key));
    return utf8.decode(clear) == _check;
  } catch (_) {
    return false;
  }
}

Uint8List _nonce(Uint8List prefix, int counter) {
  final n = Uint8List(12);
  n.setRange(0, 8, prefix);
  ByteData.sublistView(n).setUint32(8, counter);
  return n;
}

Future<void> _putPiece(
    RandomAccessFile out,
    AesGcm algo,
    SecretKey key,
    Uint8List prefix,
    int counter,
    List<int> clear,
    bool last,
    ) async {
  final box = await algo.encrypt(
    clear,
    secretKey: key,
    nonce: _nonce(prefix, counter),
    aad: [last ? 1 : 0],
  );
  final head = ByteData(4)..setUint32(0, box.cipherText.length + _macLength);
  await out.writeFrom(head.buffer.asUint8List());
  await out.writeFrom(box.cipherText);
  await out.writeFrom(box.mac.bytes);
}

Future<void> _encrypt(
    Uint8List keyBytes,
    String source,
    String dest,
    String name,
    int modifiedMs,
    ) async {
  final algo = AesGcm.with256bits();
  final key = SecretKey(keyBytes);
  final prefix = _random(8);

  final input = await File(source).open();
  final out = await File(dest).open(mode: FileMode.write);
  try {
    final length = await input.length();
    await out.writeFrom(_magic);
    await out.writeFrom(prefix);

    final header = utf8.encode(jsonEncode({'n': name, 's': length, 'm': modifiedMs}));
    await _putPiece(out, algo, key, prefix, 0, header, length == 0);

    var counter = 1;
    var done = 0;
    while (done < length) {
      final n = min(_pieceSize, length - done);
      final piece = await input.read(n);
      if (piece.length != n) {
        throw const FormatException('The file changed while it was being locked');
      }
      done += n;
      await _putPiece(out, algo, key, prefix, counter, piece, done == length);
      counter++;
    }
    await out.flush();
  } finally {
    await input.close();
    await out.close();
  }
}

/// Reads a locked file piece by piece.
class _Reader {
  _Reader._(this._file, this._length, this.prefix);

  final RandomAccessFile _file;
  final int _length;
  final Uint8List prefix;
  int _pos = 8 + 8;
  int _counter = 0;

  static Future<_Reader> open(String path) async {
    final f = await File(path).open();
    try {
      final length = await f.length();
      if (length < 16 + 4 + _macLength) {
        throw const FormatException('This is not a Polo vault file');
      }
      final head = await f.read(16);
      for (var i = 0; i < 8; i++) {
        if (head[i] != _magic[i]) {
          throw const FormatException('This is not a Polo vault file');
        }
      }
      return _Reader._(f, length, Uint8List.fromList(head.sublist(8, 16)));
    } catch (_) {
      await f.close();
      rethrow;
    }
  }

  Future<void> close() => _file.close();

  /// The next piece, or null at the end.
  Future<Uint8List?> next(AesGcm algo, SecretKey key) async {
    if (_pos >= _length) return null;
    const damaged = FormatException('This file is damaged or was changed');
    if (_pos + 4 > _length) throw damaged;

    await _file.setPosition(_pos);
    final head = await _file.read(4);
    final len = ByteData.sublistView(head).getUint32(0);
    if (len < _macLength || len > _pieceSize + _macLength + 64 || _pos + 4 + len > _length) {
      throw damaged;
    }
    final isLast = _pos + 4 + len == _length;
    final body = await _file.read(len);
    if (body.length != len) throw damaged;

    final box = SecretBox(
      body.sublist(0, len - _macLength),
      nonce: _nonce(prefix, _counter),
      mac: Mac(body.sublist(len - _macLength)),
    );
    try {
      final clear = await algo.decrypt(box, secretKey: key, aad: [isLast ? 1 : 0]);
      _pos += 4 + len;
      _counter++;
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong key, or this file is damaged');
    }
  }
}

/// Decrypts a whole locked file. With a null [dest] nothing is written, which
/// is used to check a file is intact.
Future<void> _decrypt(Uint8List keyBytes, String source, String? dest) async {
  final algo = AesGcm.with256bits();
  final key = SecretKey(keyBytes);
  final reader = await _Reader.open(source);
  RandomAccessFile? out;
  try {
    if (dest != null) out = await File(dest).open(mode: FileMode.write);
    final head = await reader.next(algo, key);
    if (head == null) throw const FormatException('This file is damaged or was changed');
    while (true) {
      final piece = await reader.next(algo, key);
      if (piece == null) break;
      await out?.writeFrom(piece);
    }
    await out?.flush();
  } finally {
    await reader.close();
    await out?.close();
  }
}