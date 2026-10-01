import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Tray-app behavior: closing the last window (red button → Dart hide)
  // must NOT terminate the process — the menu-bar icon, global hotkey
  // (Cmd+Shift+T) and reminders keep running in the background.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Cmd+Q / Dock-Quit path. window_manager's prevent-close vetoes
  // windowShouldClose, which would otherwise cancel terminate: silently
  // (Cmd+Q appearing dead). Forcing terminateNow makes the menu Quit
  // item work; the red button still routes to windowShouldClose → Dart
  // hide. Safe: every edit is durable in Hive with needsSync, blur
  // flushes on hide, and the next launch pushes leftovers.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
