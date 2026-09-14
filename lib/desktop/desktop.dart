import 'dart:io';

import 'package:flutter/foundation.dart';

/// Desktop-only switches. All Phase 4 integrations (hotkey, tray, window
/// management, launch-at-login) no-op unless [isDesktopApp] is true.
///
/// Tests are excluded explicitly: `flutter test` runs on the macOS host,
/// where `Platform.isMacOS` is true but no window/plugins exist.
bool get isDesktopApp {
  if (kIsWeb) return false;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}
