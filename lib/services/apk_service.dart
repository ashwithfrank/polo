import 'package:flutter/services.dart';

class ApkPermission {
  const ApkPermission(this.name, this.dangerous);

  final String name;

  /// True for permissions Android asks the person to approve (camera, location...).
  final bool dangerous;

  /// "android.permission.CAMERA" becomes "CAMERA".
  String get shortName => name.startsWith('android.permission.')
      ? name.substring('android.permission.'.length)
      : name;
}

class ApkCertificate {
  const ApkCertificate({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.sha256,
  });

  final String subject;
  final String issuer;
  final String validFrom;
  final String validTo;
  final String sha256;
}

class ApkInfo {
  const ApkInfo({
    required this.appName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    required this.size,
    required this.icon,
    required this.permissions,
    required this.activities,
    required this.services,
    required this.receivers,
    required this.providers,
    required this.certificate,
  });

  final String appName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final int? minSdk;
  final int? targetSdk;
  final int size;
  final Uint8List? icon;
  final List<ApkPermission> permissions;
  final List<String> activities;
  final List<String> services;
  final List<String> receivers;
  final List<String> providers;
  final ApkCertificate? certificate;
}

/// "Android 14 (API 34)".
String androidVersionLabel(int api) {
  const names = {
    21: '5.0',
    22: '5.1',
    23: '6',
    24: '7',
    25: '7.1',
    26: '8',
    27: '8.1',
    28: '9',
    29: '10',
    30: '11',
    31: '12',
    32: '12L',
    33: '13',
    34: '14',
    35: '15',
    36: '16',
  };
  final name = names[api];
  return name == null ? 'API $api' : 'Android $name (API $api)';
}

/// Reads details from an APK file using Android's own package parser.
class ApkService {
  static const _channel = MethodChannel('com.aos.polo/apk');

  static Future<ApkInfo> analyze(String path) async {
    final Map<String, dynamic>? m;
    try {
      m = await _channel.invokeMapMethod<String, dynamic>('analyze', {'path': path});
    } on PlatformException catch (e) {
      throw FormatException(e.message ?? "Couldn't read this APK");
    } on MissingPluginException {
      throw const FormatException('Fully close and reopen the app, then try again');
    }
    if (m == null) throw const FormatException("Couldn't read this APK");

    List<String> strings(Object? v) => [
      for (final x in (v as List? ?? const [])) x.toString(),
    ];

    final certMap = m['certificate'] as Map?;
    return ApkInfo(
      appName: (m['appName'] as String?) ?? '',
      packageName: (m['packageName'] as String?) ?? '',
      versionName: (m['versionName'] as String?) ?? '',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      minSdk: (m['minSdk'] as num?)?.toInt(),
      targetSdk: (m['targetSdk'] as num?)?.toInt(),
      size: (m['size'] as num?)?.toInt() ?? 0,
      icon: m['icon'] as Uint8List?,
      permissions: [
        for (final p in (m['permissions'] as List? ?? const []))
          ApkPermission(
            (p as Map)['name'] as String,
            (p['dangerous'] as bool?) ?? false,
          ),
      ],
      activities: strings(m['activities']),
      services: strings(m['services']),
      receivers: strings(m['receivers']),
      providers: strings(m['providers']),
      certificate: certMap == null
          ? null
          : ApkCertificate(
        subject: certMap['subject'] as String? ?? '',
        issuer: certMap['issuer'] as String? ?? '',
        validFrom: certMap['validFrom'] as String? ?? '',
        validTo: certMap['validTo'] as String? ?? '',
        sha256: certMap['sha256'] as String? ?? '',
      ),
    );
  }
}