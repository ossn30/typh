import 'dart:convert';
import 'dart:typed_data';

class InstalledApp {
  final String appName;
  final String packageName;
  final String? iconBase64;
  final Uint8List? iconBytes;

  const InstalledApp({
    required this.appName,
    required this.packageName,
    this.iconBase64,
    this.iconBytes,
  });

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) {
    final rawBytes = map['iconBytes'] as Uint8List?;
    final b64 = map['iconBase64'] as String?;
    Uint8List? bytes = rawBytes;
    if (bytes == null && b64 != null && b64.isNotEmpty) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {}
    }

    return InstalledApp(
      appName: map['appName'] as String? ?? 'Unknown App',
      packageName: map['packageName'] as String? ?? '',
      iconBase64: b64,
      iconBytes: bytes,
    );
  }
}

