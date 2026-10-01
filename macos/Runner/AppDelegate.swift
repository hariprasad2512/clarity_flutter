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

  // Dock-click reopen. Red close → Dart hide leaves zero visible
  // windows; without this, clicking the Dock icon does nothing and the
  // app looks dead (tray icon still alive). Front the main window (and
  // de-miniaturize if minimized). Scoped to MainFlutterWindow so the
  // transient Quick Add panel is never fronted by accident — if the
  // panel is open, hasVisibleWindows is true and we do nothing.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      sender.activate(ignoringOtherApps: true)
      if let main = sender.windows.first(where: { $0 is MainFlutterWindow }) {
        if main.isMiniaturized {
          main.deminiaturize(self)
        }
        main.makeKeyAndOrderFront(self)
      } else {
        sender.windows.first?.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
