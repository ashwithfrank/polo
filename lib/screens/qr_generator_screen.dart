import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/file_service.dart';
import '../services/qr_service.dart';
import '../widgets/polo_message.dart';
import '../services/output_location.dart';

enum _Type { text, wifi, contact, email, phone }

/// Makes QR codes for text, links, Wi-Fi, contacts, emails and phone numbers.
class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  _Type _type = _Type.text;
  String _security = 'WPA';
  bool _hidden = false;

  final _text = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _website = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();

  Uint8List? _png;
  String? _problem;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _text, _ssid, _password, _name, _phone, _email, _company, _website, _subject, _body,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The text for the code, or null while the form is not filled in.
  String? _data() {
    String t(TextEditingController c) => c.text.trim();
    switch (_type) {
      case _Type.text:
        return t(_text).isEmpty ? null : _text.text;
      case _Type.wifi:
        return t(_ssid).isEmpty
            ? null
            : QrService.wifi(_ssid.text, _password.text, security: _security, hidden: _hidden);
      case _Type.contact:
        return t(_name).isEmpty
            ? null
            : QrService.contact(
                name: t(_name),
                phone: t(_phone),
                email: t(_email),
                company: t(_company),
                website: t(_website),
              );
      case _Type.email:
        return t(_email).isEmpty
            ? null
            : QrService.email(t(_email), subject: t(_subject), body: _body.text.trim());
      case _Type.phone:
        return t(_phone).isEmpty ? null : 'tel:${t(_phone)}';
    }
  }

  void _update() {
    final data = _data();
    setState(() {
      _problem = null;
      if (data == null) {
        _png = null;
        return;
      }
      try {
        _png = QrService.png(data);
      } on FormatException catch (e) {
        _png = null;
        _problem = e.message;
      }
    });
  }

  Future<String> _save() async {
    final dir = await OutputLocation.resolve(
      '${FileService.rootPath}/Pictures/QR codes',
      OutputKind.qr,
      fromScratch: true,
    );
    await Directory(dir).create(recursive: true);
    final path = await FileService().uniquePath(dir, 'QR code.png');
    await File(path).writeAsBytes(_png!, flush: true);
    OutputLocation.announce(path);
    return path;
  }

  Future<void> _saveClicked() async {
    setState(() => _saving = true);
    try {
      final path = await _save();
      if (mounted) showPoloMessage(context, 'Saved as ${path.split('/').last} in Pictures/QR codes');
    } catch (_) {
      if (mounted) showPoloMessage(context, "Couldn't save the picture");
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _shareClicked() async {
    setState(() => _saving = true);
    try {
      final path = await _save();
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (_) {
      if (mounted) showPoloMessage(context, "Couldn't share the picture");
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? type,
    int lines = 1,
    bool secret = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 2,
        obscureText: secret,
        onChanged: (_) => _update(),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  static const _labels = {
    _Type.text: 'Text or link',
    _Type.wifi: 'Wi-Fi',
    _Type.contact: 'Contact',
    _Type.email: 'Email',
    _Type.phone: 'Phone',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final png = _png;

    return Scaffold(
      appBar: AppBar(title: const Text('Make a QR code')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in _Type.values)
                ChoiceChip(
                  label: Text(_labels[t]!),
                  selected: _type == t,
                  onSelected: (_) {
                    _type = t;
                    _update();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_type == _Type.text)
            _field(_text, 'Text or link', lines: 3, type: TextInputType.multiline),
          if (_type == _Type.wifi) ...[
            _field(_ssid, 'Network name'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'WPA', label: Text('WPA/WPA2')),
                  ButtonSegment(value: 'WEP', label: Text('WEP')),
                  ButtonSegment(value: 'None', label: Text('None')),
                ],
                selected: {_security},
                onSelectionChanged: (s) {
                  _security = s.first;
                  _update();
                },
              ),
            ),
            if (_security != 'None') _field(_password, 'Password'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hidden network'),
              value: _hidden,
              onChanged: (v) {
                _hidden = v;
                _update();
              },
            ),
          ],
          if (_type == _Type.contact) ...[
            _field(_name, 'Name'),
            _field(_phone, 'Phone', type: TextInputType.phone),
            _field(_email, 'Email', type: TextInputType.emailAddress),
            _field(_company, 'Company'),
            _field(_website, 'Website', type: TextInputType.url),
          ],
          if (_type == _Type.email) ...[
            _field(_email, 'Email address', type: TextInputType.emailAddress),
            _field(_subject, 'Subject (optional)'),
            _field(_body, 'Message (optional)', lines: 2, type: TextInputType.multiline),
          ],
          if (_type == _Type.phone) _field(_phone, 'Phone number', type: TextInputType.phone),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              padding: const EdgeInsets.all(8),
              child: png == null
                  ? Center(
                      child: Text(
                        _problem ?? 'Fill in the details and your code appears here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _problem == null ? Colors.black54 : scheme.error,
                        ),
                      ),
                    )
                  : Image.memory(png, filterQuality: FilterQuality.none, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: png == null || _saving ? null : _saveClicked,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save picture'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: png == null || _saving ? null : _shareClicked,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Made on your phone. Nothing is uploaded.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
