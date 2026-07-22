import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'share_intake.dart';

/// Android gets the real channel-backed port; the other dart:io
/// platforms have no share sheet and stay inert.
ShareIntakePort createShareIntakePort() =>
    defaultTargetPlatform == TargetPlatform.android
    ? const MethodChannelShareIntake()
    : const InertShareIntakePort();

/// Drains the share queue MainActivity keeps on the `waxdeck/share`
/// channel. The platform side already copied shared streams into the
/// app cache, so paths here are plain files.
class MethodChannelShareIntake implements ShareIntakePort {
  const MethodChannelShareIntake();

  static const _channel = MethodChannel('waxdeck/share');

  @override
  Future<SharedIntake?> consumeShared() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'consumeShared',
    );
    if (raw == null) return null;
    switch (raw['type']) {
      case 'url':
        final url = raw['url'];
        return url is String ? SharedUrlIntake(url) : null;
      case 'files':
        final entries = raw['files'];
        if (entries is! List) return null;
        final files = <SharedFile>[
          for (final entry in entries)
            if (entry is Map &&
                entry['path'] is String &&
                entry['name'] is String)
              SharedFile(
                path: entry['path'] as String,
                name: entry['name'] as String,
              ),
        ];
        return files.isEmpty ? null : SharedFilesIntake(files);
    }
    return null;
  }
}
