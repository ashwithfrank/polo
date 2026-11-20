/// What a scanned code holds, worked out from its text.
enum QrKind { link, wifi, contact, email, phone, sms, location, text }

class QrField {
  const QrField(this.label, this.value);

  final String label;
  final String value;
}

class QrContent {
  const QrContent({
    required this.kind,
    required this.title,
    required this.raw,
    this.fields = const [],
  });

  final QrKind kind;

  /// A short name such as "Link" or "Wi-Fi network".
  final String title;

  /// The exact text in the code.
  final String raw;

  /// The parts worth showing and copying one by one.
  final List<QrField> fields;
}

QrContent parseQr(String raw) {
  final text = raw.trim();
  final lower = text.toLowerCase();

  if (lower.startsWith('wifi:')) return _wifi(raw, text.substring(5));
  if (lower.startsWith('begin:vcard')) return _vcard(raw, text);
  if (lower.startsWith('mailto:')) return _mailto(raw, text.substring(7));
  if (lower.startsWith('tel:')) {
    return QrContent(
      kind: QrKind.phone,
      title: 'Phone number',
      raw: raw,
      fields: [QrField('Number', text.substring(4))],
    );
  }
  if (lower.startsWith('smsto:') || lower.startsWith('sms:')) {
    final body = text.substring(lower.startsWith('smsto:') ? 6 : 4);
    final at = body.indexOf(':');
    return QrContent(
      kind: QrKind.sms,
      title: 'Text message',
      raw: raw,
      fields: [
        QrField('To', at < 0 ? body : body.substring(0, at)),
        if (at >= 0) QrField('Message', body.substring(at + 1)),
      ],
    );
  }
  if (lower.startsWith('geo:')) {
    return QrContent(
      kind: QrKind.location,
      title: 'Location',
      raw: raw,
      fields: [QrField('Coordinates', text.substring(4).split('?').first)],
    );
  }
  if (RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(text) ||
      RegExp(r'^www\.\S+\.\S+$', caseSensitive: false).hasMatch(text)) {
    return QrContent(
      kind: QrKind.link,
      title: 'Link',
      raw: raw,
      fields: [QrField('Address', text)],
    );
  }
  return QrContent(kind: QrKind.text, title: 'Text', raw: raw);
}

/// Splits on ";" but not on "\;". Removes the backslash escapes.
List<String> _splitEscaped(String s) {
  final parts = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      cur.write(s[++i]);
    } else if (c == ';') {
      parts.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  if (cur.isNotEmpty) parts.add(cur.toString());
  return parts;
}

QrContent _wifi(String raw, String body) {
  final map = <String, String>{};
  for (final part in _splitEscaped(body)) {
    final at = part.indexOf(':');
    if (at > 0) map[part.substring(0, at).toUpperCase()] = part.substring(at + 1);
  }
  final security = map['T'] ?? '';
  return QrContent(
    kind: QrKind.wifi,
    title: 'Wi-Fi network',
    raw: raw,
    fields: [
      QrField('Name', map['S'] ?? ''),
      if ((map['P'] ?? '').isNotEmpty) QrField('Password', map['P']!),
      QrField('Security', security.isEmpty || security.toLowerCase() == 'nopass' ? 'None' : security),
    ],
  );
}

QrContent _mailto(String raw, String body) {
  final q = body.indexOf('?');
  final address = q < 0 ? body : body.substring(0, q);
  final fields = <QrField>[QrField('To', Uri.decodeComponent(address))];
  if (q >= 0) {
    final params = Uri.splitQueryString(body.substring(q + 1));
    if (params['subject'] != null) fields.add(QrField('Subject', params['subject']!));
    if (params['body'] != null) fields.add(QrField('Message', params['body']!));
  }
  return QrContent(kind: QrKind.email, title: 'Email', raw: raw, fields: fields);
}

QrContent _vcard(String raw, String text) {
  String? name, org, url;
  final phones = <String>[], emails = <String>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final at = line.indexOf(':');
    if (at < 0) continue;
    final key = line.substring(0, at).split(';').first.toUpperCase();
    final value = line.substring(at + 1).trim();
    if (value.isEmpty) continue;
    switch (key) {
      case 'FN':
        name = value;
      case 'N':
        name ??= value.split(';').where((p) => p.isNotEmpty).toList().reversed.join(' ');
      case 'ORG':
        org = value.replaceAll(';', ' ');
      case 'TEL':
        phones.add(value);
      case 'EMAIL':
        emails.add(value);
      case 'URL':
        url = value;
    }
  }
  return QrContent(
    kind: QrKind.contact,
    title: 'Contact',
    raw: raw,
    fields: [
      if (name != null) QrField('Name', name),
      if (org != null) QrField('Company', org),
      for (final p in phones) QrField('Phone', p),
      for (final e in emails) QrField('Email', e),
      if (url != null) QrField('Website', url),
    ],
  );
}