import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_item.dart';
import '../services/qr_parse.dart';
import '../widgets/polo_message.dart';
import 'pick_files_screen.dart';

/// Scans QR codes and barcodes with the camera, or from a picture. Nothing
/// leaves the phone.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _showing = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _found(String raw) async {
    if (_showing || !mounted) return;
    _showing = true;
    HapticFeedback.mediumImpact();
    try {
      await _controller.stop();
    } catch (_) {}
    if (!mounted) return;

    await _showResult(context, parseQr(raw));

    _showing = false;
    if (!mounted) return;
    try {
      await _controller.start();
      _torch = false;
    } catch (_) {}
  }

  Future<void> _fromPicture() async {
    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => PickFilesScreen(
          title: 'Choose a picture with a code',
          accepts: (f) => !f.isDirectory && f.kind == FileKind.image,
          single: true,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    BarcodeCapture? capture;
    try {
      capture = await _controller.analyzeImage(picked.first.path);
    } catch (_) {}
    if (!mounted) return;

    final raw = capture?.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) {
      showPoloMessage(context, 'No code found in this picture');
      return;
    }
    await _found(raw);
  }

  Widget _error(BuildContext context, MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'Polo needs the camera to scan. Allow it in Android settings, or scan from a picture instead.'
                  : "The camera couldn't start. You can still scan from a picture.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scan code'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (context, error, [child]) => _error(context, error),
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _found(v);
                  return;
                }
              }
            },
          ),
          // A frame to aim with.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Point the camera at a QR code or barcode',
                        style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RoundButton(
                          icon: _torch ? Icons.flash_on : Icons.flash_off,
                          label: 'Light',
                          onTap: () async {
                            await _controller.toggleTorch();
                            if (mounted) setState(() => _torch = !_torch);
                          },
                        ),
                        const SizedBox(width: 28),
                        _RoundButton(
                          icon: Icons.image_outlined,
                          label: 'From picture',
                          onTap: _fromPicture,
                        ),
                        const SizedBox(width: 28),
                        _RoundButton(
                          icon: Icons.cameraswitch_outlined,
                          label: 'Flip',
                          onTap: () => _controller.switchCamera(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white24,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}

Future<void> _showResult(BuildContext context, QrContent content) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final scheme = Theme.of(sheet).colorScheme;

      Future<void> copy(String text, String what) async {
        await Clipboard.setData(ClipboardData(text: text));
        if (sheet.mounted) showPoloMessage(sheet, '$what copied');
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              Text(content.title, style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (content.fields.isEmpty)
                SelectableText(content.raw)
              else
                for (final f in content.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            f.label,
                            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                          ),
                        ),
                        Expanded(child: SelectableText(f.value)),
                        InkWell(
                          onTap: () => copy(f.value, f.label),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.copy_outlined, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => copy(content.raw, 'Text'),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => SharePlus.instance.share(ShareParams(text: content.raw)),
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Scan another'),
              ),
            ],
          ),
        ),
      );
    },
  );
}