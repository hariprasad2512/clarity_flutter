import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

/// Red overdue-count badge on the app icon, all desktop/mobile platforms.
///
/// * Android/macOS: `flutter_app_badger` (system-red badge; Android launchers
///   vary — some show dots only).
/// * Windows: taskbar overlay icon painted natively (red circle, white
///   number) via the `clarity.windows.badge` channel in the runner.
/// * Web/Linux: no-op.
/// Never throws: a badge must never crash the app.
class AppBadgeService {
  static const _windowsChannel = MethodChannel('clarity.windows.badge');

  /// Max number drawn on the Windows overlay; beyond shows "99+".
  static const windowsMaxCount = 99;

  /// Applies [overdue] (strictly overdue, incomplete). Zero clears.
  static Future<void> updateBadge(int overdue) async {
    final count = overdue < 0 ? 0 : overdue;
    try {
      if (Platform.isWindows) {
        if (count == 0) {
          await _windowsChannel.invokeMethod('remove');
        } else {
          await _windowsChannel.invokeMethod('setCount', {'count': count});
        }
        return;
      }
      if (Platform.isAndroid || Platform.isMacOS || Platform.isIOS) {
        if (count == 0) {
          await FlutterAppBadger.removeBadge();
        } else {
          await FlutterAppBadger.updateBadgeCount(count);
        }
      }
    } catch (_) {
      // Best-effort: unsupported launcher, missing plugin, headless test.
    }
  }
}
