import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// Makes QR code pictures and the text that goes inside them.
class QrService {
  QrService._();

  /// A black and white PNG of [data]. Each dot is [dot] pixels wide, with a
  /// white border of four dots around the code, as the QR standard asks.
  /// Throws a [FormatException] if there is too much text for one code.
  static Uint8List png(String data, {int dot = 12}) {
    final QrCode code;
    try {
      code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
    } catch (_) {
      throw const FormatException('That is too much text for one QR code');
    }
    final qr = QrImage(code);
    const border = 4;
    final side = (qr.moduleCount + border * 2) * dot;

    final image = img.Image(width: side, height: side);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final black = img.ColorRgb8(0, 0, 0);
    for (var y = 0; y < qr.moduleCount; y++) {
      for (var x = 0; x < qr.moduleCount; x++) {
        if (!qr.isDark(y, x)) continue;
        final px = (x + border) * dot;
        final py = (y + border) * dot;
        img.fillRect(image, x1: px, y1: py, x2: px + dot - 1, y2: py + dot - 1, color: black);
      }
    }
    return img.encodePng(image);
  }

  static String _escape(String s) =>
      s.replaceAllMapped(RegExp(r'[\;,:"]'), (m) => '\\${m[0]}');

  /// The text that makes phones offer to join a Wi-Fi network.
  static String wifi(String name, String password, {required String security, bool hidden = false}) {
    final t = security == 'None' ? 'nopass' : security;
    final p = security == 'None' ? '' : 'P:${_escape(password)};';
    return 'WIFI:T:$t;S:${_escape(name)};$p${hidden ? 'H:true;' : ''};';
  }

  static String contact({
    required String name,
    String phone = '',
    String email = '',
    String company = '',
    String website = '',
  }) {
    return [
      'BEGIN:VCARD',
      'VERSION:3.0',
      'FN:$name',
      if (company.isNotEmpty) 'ORG:$company',
      if (phone.isNotEmpty) 'TEL:$phone',
      if (email.isNotEmpty) 'EMAIL:$email',
      if (website.isNotEmpty) 'URL:$website',
      'END:VCARD',
    ].join('\n');
  }

  static String email(String to, {String subject = '', String body = ''}) {
    final params = [
      if (subject.isNotEmpty) 'subject=${Uri.encodeComponent(subject)}',
      if (body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
    ];
    return 'mailto:$to${params.isEmpty ? '' : '?${params.join('&')}'}';
  }
}