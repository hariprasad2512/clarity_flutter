#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

  private:
   // The project to run.
   flutter::DartProject project_;

   // The Flutter instance hosted by this window.
   std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

   // Taskbar overdue-badge channel (Dart: clarity.windows.badge).
   std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
       badge_channel_;

   // Applies (count > 0) or clears (count <= 0) the red taskbar overlay.
   void SetTaskbarBadge(int count);
   // Paints a red-circle / white-number HICON. Caller destroys it.
   static HICON CreateBadgeIcon(int count);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
