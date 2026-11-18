import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Makes "fragmented" MP4 videos seekable.
///
/// Many downloaded MP4s are stored as a chain of small fragments with no index
/// and no total length. Android's player can play them from the start but
/// can't jump to a time, and it shows a length of 0:00. This rewrites such a
/// file with a normal index. The video and audio data themselves are copied
/// as they are, so nothing is re-encoded and nothing is lost.
class Mp4Repair {
  Mp4Repair._();

  /// True if [path] is a fragmented MP4 without a seek index.
  static Future<bool> needsRepair(String path) async {
    final f = await File(path).open();
    try {
      final length = await f.length();
      var pos = 0;
      var fragmented = false;
      while (pos + 8 <= length) {
        await f.setPosition(pos);
        final head = await f.read(16);
        if (head.length < 8) break;
        final bd = ByteData.sublistView(head);
        var size = bd.getUint32(0);
        final type = String.fromCharCodes(head.sublist(4, 8));
        if (size == 1 && head.length >= 16) {
          size = bd.getUint64(8);
        } else if (size == 0) {
          size = length - pos;
        }
        if (size < 8) break;
        if (type == 'sidx') return false;
        if (type == 'moof') return fragmented;
        if (type == 'moov') {
          if (size > 32 * 1024 * 1024) return false;
          await f.setPosition(pos);
          final raw = await f.read(size);
          final moov = _parse(raw, 0, raw.length).first;
          fragmented = moov.find('mvex') != null;
        }
        pos += size;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      await f.close();
    }
  }

  /// Writes a seekable copy of [source] to [dest]. Returns an error message,
  /// or null on success.
  static Future<String?> makeSeekable(String source, String dest) {
    return Isolate.run(() {
      try {
        _remux(source, dest);
        return null;
      } on FormatException catch (e) {
        _tryDelete(dest);
        return e.message;
      } catch (_) {
        _tryDelete(dest);
        return "Couldn't fix this video";
      }
    });
  }
}

void _tryDelete(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// MP4 boxes
// ---------------------------------------------------------------------------

const _containers = {'moov', 'trak', 'mdia', 'minf', 'stbl', 'edts'};

class _Box {
  _Box(this.type, {this.payload, this.kids});

  final String type;
  Uint8List? payload;
  List<_Box>? kids;

  _Box? find(String t) {
    for (final k in kids ?? const <_Box>[]) {
      if (k.type == t) return k;
    }
    return null;
  }

  List<_Box> findAll(String t) => [for (final k in kids ?? const <_Box>[]) if (k.type == t) k];

  Uint8List ser() {
    final body = BytesBuilder(copy: false);
    final k = kids;
    if (k != null) {
      for (final c in k) {
        body.add(c.ser());
      }
    } else {
      body.add(payload!);
    }
    final bytes = body.toBytes();
    final out = Uint8List(8 + bytes.length);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, out.length);
    for (var i = 0; i < 4; i++) {
      out[4 + i] = type.codeUnitAt(i);
    }
    out.setRange(8, out.length, bytes);
    return out;
  }
}

List<_Box> _parse(Uint8List data, int start, int end) {
  final out = <_Box>[];
  final bd = ByteData.sublistView(data);
  var pos = start;
  while (pos + 8 <= end) {
    var size = bd.getUint32(pos);
    var hdr = 8;
    final type = String.fromCharCodes(data.sublist(pos + 4, pos + 8));
    if (size == 1) {
      size = bd.getUint64(pos + 8);
      hdr = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < hdr || pos + size > end) throw const FormatException("This video's index is damaged");
    if (_containers.contains(type)) {
      out.add(_Box(type, kids: _parse(data, pos + hdr, pos + size)));
    } else {
      out.add(_Box(type, payload: Uint8List.sublistView(data, pos + hdr, pos + size)));
    }
    pos += size;
  }
  return out;
}

Uint8List _bytes(void Function(BytesBuilder b, ByteData scratch) write) {
  final b = BytesBuilder(copy: false);
  write(b, ByteData(8));
  return b.toBytes();
}

void _put32(BytesBuilder b, int v) {
  b.add([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
}

void _put64(BytesBuilder b, int v) {
  _put32(b, (v >> 32) & 0xFFFFFFFF);
  _put32(b, v & 0xFFFFFFFF);
}

// ---------------------------------------------------------------------------
// The conversion
// ---------------------------------------------------------------------------

class _Defaults {
  int dur = 0;
  int size = 0;
  int flags = 0;
}

class _Track {
  _Track(this.trak, this.timescale);

  final _Box trak;
  final int timescale;
  final durs = <int>[];
  final sizes = <int>[];
  final flags = <int>[];
  final ctos = <int>[];
  final chunkOffsets = <int>[];
  final chunkCounts = <int>[];
}

void _remux(String sourcePath, String destPath) {
  final f = File(sourcePath).openSync();
  RandomAccessFile? out;
  try {
    final length = f.lengthSync();

    // Top-level boxes, without reading the media data.
    final tops = <({String type, int pos, int size, int hdr})>[];
    var pos = 0;
    while (pos + 8 <= length) {
      f.setPositionSync(pos);
      final head = f.readSync(16);
      final bd = ByteData.sublistView(head);
      var size = bd.getUint32(0);
      var hdr = 8;
      final type = String.fromCharCodes(head.sublist(4, 8));
      if (size == 1 && head.length >= 16) {
        size = bd.getUint64(8);
        hdr = 16;
      } else if (size == 0) {
        size = length - pos;
      }
      if (size < hdr) throw const FormatException("This video can't be fixed");
      tops.add((type: type, pos: pos, size: size, hdr: hdr));
      pos += size;
    }

    final ftypBox = tops.where((t) => t.type == 'ftyp').firstOrNull;
    final moovBox = tops.where((t) => t.type == 'moov').firstOrNull;
    if (ftypBox == null || moovBox == null) {
      throw const FormatException("This video can't be fixed");
    }
    f.setPositionSync(moovBox.pos);
    final moovRaw = f.readSync(moovBox.size);
    final moov = _parse(moovRaw, 0, moovRaw.length).first;
    final mvex = moov.find('mvex');
    if (mvex == null) throw const FormatException('This video is already seekable');

    final trex = <int, _Defaults>{};
    for (final t in mvex.findAll('trex')) {
      final p = t.payload!;
      final bd = ByteData.sublistView(p);
      trex[bd.getUint32(4)] = _Defaults()
        ..dur = bd.getUint32(12)
        ..size = bd.getUint32(16)
        ..flags = bd.getUint32(20);
    }

    final tracks = <int, _Track>{};
    for (final trak in moov.findAll('trak')) {
      final tkhd = trak.find('tkhd')!.payload!;
      final mdhd = trak.find('mdia')!.find('mdhd')!.payload!;
      final tid = ByteData.sublistView(tkhd).getUint32(tkhd[0] == 0 ? 12 : 20);
      final ts = ByteData.sublistView(mdhd).getUint32(mdhd[0] == 0 ? 12 : 20);
      if (ts == 0) throw const FormatException("This video can't be fixed");
      tracks[tid] = _Track(trak, ts);
    }

    // Where each piece of media data will sit in the new file.
    final mdats = [
      for (final t in tops)
        if (t.type == 'mdat') (start: t.pos + t.hdr, end: t.pos + t.size, newStart: 0),
    ];
    var total = 0;
    for (final m in mdats) {
      total += m.end - m.start;
    }
    final big = total + 8 > 0xFFFFFFFF;
    final mdatHeader = big ? 16 : 8;
    f.setPositionSync(ftypBox.pos);
    final ftyp = f.readSync(ftypBox.size);
    final base = ftyp.length + mdatHeader;
    final starts = <int>[];
    final ends = <int>[];
    final news = <int>[];
    var acc = 0;
    for (final m in mdats) {
      starts.add(m.start);
      ends.add(m.end);
      news.add(base + acc);
      acc += m.end - m.start;
    }

    int newPos(int old) {
      var lo = 0;
      var hi = starts.length - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (old < starts[mid]) {
          hi = mid - 1;
        } else if (old >= ends[mid]) {
          lo = mid + 1;
        } else {
          return news[mid] + (old - starts[mid]);
        }
      }
      throw const FormatException("This video's data is damaged");
    }

    // Read every fragment's list of samples.
    for (final top in tops) {
      if (top.type != 'moof') continue;
      f.setPositionSync(top.pos);
      final raw = f.readSync(top.size);
      final bd = ByteData.sublistView(raw);
      var prevEnd = top.pos;
      var firstTraf = true;

      var q = top.hdr;
      while (q + 8 <= raw.length) {
        final sz = bd.getUint32(q);
        final ty = String.fromCharCodes(raw.sublist(q + 4, q + 8));
        if (sz < 8) throw const FormatException("This video's data is damaged");
        if (ty == 'traf') {
          Uint8List? tfhd;
          final truns = <Uint8List>[];
          var r = q + 8;
          while (r + 8 <= q + sz) {
            final s2 = bd.getUint32(r);
            final t2 = String.fromCharCodes(raw.sublist(r + 4, r + 8));
            if (s2 < 8) throw const FormatException("This video's data is damaged");
            final body = Uint8List.sublistView(raw, r + 8, r + s2);
            if (t2 == 'tfhd') tfhd = body;
            if (t2 == 'trun') truns.add(body);
            r += s2;
          }
          if (tfhd == null) throw const FormatException("This video's data is damaged");

          final hb = ByteData.sublistView(tfhd);
          final fl = hb.getUint32(0) & 0xFFFFFF;
          final tid = hb.getUint32(4);
          final track = tracks[tid];
          if (track == null) throw const FormatException("This video's data is damaged");
          final tx = trex[tid];
          var dDur = tx?.dur ?? 0;
          var dSize = tx?.size ?? 0;
          var dFlags = tx?.flags ?? 0;
          var o = 8;
          int? explicitBase;
          if (fl & 1 != 0) {
            explicitBase = hb.getUint64(o);
            o += 8;
          }
          if (fl & 2 != 0) o += 4;
          if (fl & 8 != 0) {
            dDur = hb.getUint32(o);
            o += 4;
          }
          if (fl & 0x10 != 0) {
            dSize = hb.getUint32(o);
            o += 4;
          }
          if (fl & 0x20 != 0) {
            dFlags = hb.getUint32(o);
            o += 4;
          }

          final int baseOffset;
          if (explicitBase != null) {
            baseOffset = explicitBase;
          } else if (fl & 0x20000 != 0) {
            baseOffset = top.pos;
          } else {
            baseOffset = firstTraf ? top.pos : prevEnd;
          }
          firstTraf = false;

          var cur = baseOffset;
          for (final tb in truns) {
            final tbd = ByteData.sublistView(tb);
            final version = tb[0];
            final tfl = tbd.getUint32(0) & 0xFFFFFF;
            final count = tbd.getUint32(4);
            var p = 8;
            if (tfl & 1 != 0) {
              cur = baseOffset + tbd.getInt32(p);
              p += 4;
            }
            int? firstFlags;
            if (tfl & 4 != 0) {
              firstFlags = tbd.getUint32(p);
              p += 4;
            }
            final chunkStart = cur;
            for (var j = 0; j < count; j++) {
              var dur = dDur;
              var size = dSize;
              var sflags = dFlags;
              var cto = 0;
              if (tfl & 0x100 != 0) {
                dur = tbd.getUint32(p);
                p += 4;
              }
              if (tfl & 0x200 != 0) {
                size = tbd.getUint32(p);
                p += 4;
              }
              if (tfl & 0x400 != 0) {
                sflags = tbd.getUint32(p);
                p += 4;
              } else if (j == 0 && firstFlags != null) {
                sflags = firstFlags;
              }
              if (tfl & 0x800 != 0) {
                cto = version == 1 ? tbd.getInt32(p) : tbd.getUint32(p);
                p += 4;
              }
              track.durs.add(dur);
              track.sizes.add(size);
              track.flags.add(sflags);
              track.ctos.add(cto);
              cur += size;
            }
            track.chunkOffsets.add(newPos(chunkStart));
            track.chunkCounts.add(count);
          }
          prevEnd = cur;
        }
        q += sz;
      }
    }

    // Build the index for each track.
    final mvhd = moov.find('mvhd')!;
    final mvp = Uint8List.fromList(mvhd.payload!);
    final mvb = ByteData.sublistView(mvp);
    final movieTs = mvb.getUint32(mvp[0] == 0 ? 12 : 20);
    var movieDuration = 0;

    for (final track in tracks.values) {
      final n = track.sizes.length;
      if (n == 0) throw const FormatException("This video can't be fixed");
      var trackDuration = 0;
      for (final d in track.durs) {
        trackDuration += d;
      }
      final inMovie = trackDuration * movieTs ~/ track.timescale;
      if (inMovie > movieDuration) movieDuration = inMovie;

      final trak = track.trak;
      final mdia = trak.find('mdia')!;
      final stbl = mdia.find('minf')!.find('stbl')!;
      final kids = <_Box>[stbl.find('stsd')!];

      // Sample durations.
      final stts = _runs(track.durs);
      kids.add(_Box('stts', payload: _bytes((b, _) {
        _put32(b, 0);
        _put32(b, stts.length);
        for (final r in stts) {
          _put32(b, r.$1);
          _put32(b, r.$2 & 0xFFFFFFFF);
        }
      })));

      // Frame reordering offsets (only if there are any).
      if (track.ctos.any((c) => c != 0)) {
        final negative = track.ctos.any((c) => c < 0);
        final ctts = _runs(track.ctos);
        kids.add(_Box('ctts', payload: _bytes((b, _) {
          _put32(b, negative ? 0x01000000 : 0);
          _put32(b, ctts.length);
          for (final r in ctts) {
            _put32(b, r.$1);
            _put32(b, r.$2 & 0xFFFFFFFF);
          }
        })));
      }

      // Key frames (only if not every sample is one).
      final syncs = <int>[
        for (var i = 0; i < n; i++)
          if ((track.flags[i] >> 16) & 1 == 0) i + 1,
      ];
      if (syncs.length != n) {
        kids.add(_Box('stss', payload: _bytes((b, _) {
          _put32(b, 0);
          _put32(b, syncs.length);
          for (final s in syncs) {
            _put32(b, s);
          }
        })));
      }

      // Samples per chunk.
      final stsc = <(int, int)>[];
      for (var i = 0; i < track.chunkCounts.length; i++) {
        if (stsc.isEmpty || stsc.last.$2 != track.chunkCounts[i]) {
          stsc.add((i + 1, track.chunkCounts[i]));
        }
      }
      kids.add(_Box('stsc', payload: _bytes((b, _) {
        _put32(b, 0);
        _put32(b, stsc.length);
        for (final e in stsc) {
          _put32(b, e.$1);
          _put32(b, e.$2);
          _put32(b, 1);
        }
      })));

      // Sample sizes.
      kids.add(_Box('stsz', payload: _bytes((b, _) {
        _put32(b, 0);
        _put32(b, 0);
        _put32(b, n);
        for (final s in track.sizes) {
          _put32(b, s);
        }
      })));

      // Where each chunk starts.
      final wide = track.chunkOffsets.any((o) => o > 0xFFFFFFFF);
      kids.add(_Box(wide ? 'co64' : 'stco', payload: _bytes((b, _) {
        _put32(b, 0);
        _put32(b, track.chunkOffsets.length);
        for (final o in track.chunkOffsets) {
          wide ? _put64(b, o) : _put32(b, o);
        }
      })));
      stbl.kids = kids;

      // Lengths.
      final mdhd = mdia.find('mdhd')!;
      final mp = Uint8List.fromList(mdhd.payload!);
      final mb = ByteData.sublistView(mp);
      if (mp[0] == 0) {
        mb.setUint32(16, trackDuration);
      } else {
        mb.setUint64(24, trackDuration);
      }
      mdhd.payload = mp;

      final tkhd = trak.find('tkhd')!;
      final tp = Uint8List.fromList(tkhd.payload!);
      final tb = ByteData.sublistView(tp);
      if (tp[0] == 0) {
        tb.setUint32(20, inMovie);
      } else {
        tb.setUint64(28, inMovie);
      }
      tkhd.payload = tp;

      trak.kids = [for (final k in trak.kids!) if (k.type != 'edts') k];
    }

    if (mvp[0] == 0) {
      mvb.setUint32(16, movieDuration);
    } else {
      mvb.setUint64(24, movieDuration);
    }
    mvhd.payload = mvp;
    moov.kids = [for (final k in moov.kids!) if (k.type != 'mvex') k];

    // Write: ftyp, all media data, then the new index.
    out = File(destPath).openSync(mode: FileMode.write);
    out.writeFromSync(ftyp);
    final header = ByteData(mdatHeader);
    if (big) {
      header.setUint32(0, 1);
      header.setUint32(4, 0x6D646174);
      header.setUint64(8, total + 16);
    } else {
      header.setUint32(0, total + 8);
      header.setUint32(4, 0x6D646174);
    }
    out.writeFromSync(header.buffer.asUint8List());
    for (final m in mdats) {
      f.setPositionSync(m.start);
      var left = m.end - m.start;
      while (left > 0) {
        final chunk = f.readSync(left < (1 << 20) ? left : (1 << 20));
        if (chunk.isEmpty) throw const FormatException('The video file ended unexpectedly');
        out.writeFromSync(chunk);
        left -= chunk.length;
      }
    }
    out.writeFromSync(moov.ser());
    out.flushSync();
  } finally {
    f.closeSync();
    out?.closeSync();
  }
}

/// Groups equal neighbours: [5,5,5,7] becomes [(3,5),(1,7)].
List<(int, int)> _runs(List<int> values) {
  final out = <(int, int)>[];
  for (final v in values) {
    if (out.isNotEmpty && out.last.$2 == v) {
      out[out.length - 1] = (out.last.$1 + 1, v);
    } else {
      out.add((1, v));
    }
  }
  return out;
}