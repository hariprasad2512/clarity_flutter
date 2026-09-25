#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>
#include <string>

#include "flutter/generated_plugin_registrant.h"

// desktop_multi_window sub-windows (e.g. the Quick Add panel) run their
// own Flutter engine: plugins must be registered per-engine, or every
// method-channel call fails with MissingPluginException and the panel
// stays a blank native window. Mirrors the macOS
// setOnWindowCreatedCallback in MainFlutterWindow.swift.
#include "desktop_multi_window/desktop_multi_window_plugin.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    RegisterPlugins(flutter_view_controller->engine());
  });

  // Red overdue-count taskbar overlay, driven from Dart
  // (AppBadgeService via the clarity.windows.badge channel).
  badge_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "clarity.windows.badge",
          &flutter::StandardMethodCodec::GetInstance());
  badge_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "setCount") {
      int count = 0;
      if (const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments())) {
        const auto it = args->find(flutter::EncodableValue("count"));
        if (it != args->end()) {
          if (const auto* v = std::get_if<int>(&it->second)) count = *v;
        }
      }
      SetTaskbarBadge(count);
      result->Success();
    } else if (call.method_name() == "remove") {
      SetTaskbarBadge(0);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetTaskbarBadge(int count) {
  ITaskbarList3* taskbar = nullptr;
  if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_ITaskbarList3,
                              reinterpret_cast<void**>(&taskbar)))) {
    return;
  }
  if (FAILED(taskbar->HrInit())) {
    taskbar->Release();
    return;
  }
  if (count <= 0) {
    taskbar->SetOverlayIcon(GetHandle(), nullptr, L"");
    taskbar->Release();
    return;
  }
  HICON icon = CreateBadgeIcon(count);
  if (icon) {
    wchar_t desc[64];
    swprintf_s(desc, L"%d overdue tasks", count > 99 ? 99 : count);
    taskbar->SetOverlayIcon(GetHandle(), icon, desc);
    DestroyIcon(icon);
  }
  taskbar->Release();
}

HICON FlutterWindow::CreateBadgeIcon(int count) {
  // Rendered large: Windows downscales the overlay, and edge pixels blend
  // with the bitmap background — a red background (not black) keeps the
  // rim clean instead of fringing dark like WhatsApp comparisons showed.
  constexpr int kSize = 64;
  const std::wstring text = count > 99 ? L"99+" : std::to_wstring(count);

  HDC screen = GetDC(nullptr);
  if (!screen) return nullptr;
  HDC dc = CreateCompatibleDC(screen);
  HDC mask_dc = CreateCompatibleDC(screen);
  HBITMAP color = CreateCompatibleBitmap(screen, kSize, kSize);
  // 1bpp mask: white = transparent, black = opaque.
  HBITMAP mask = CreateBitmap(kSize, kSize, 1, 1, nullptr);
  ReleaseDC(nullptr, screen);
  if (!dc || !mask_dc || !color || !mask) {
    if (dc) DeleteDC(dc);
    if (mask_dc) DeleteDC(mask_dc);
    if (color) DeleteObject(color);
    if (mask) DeleteObject(mask);
    return nullptr;
  }
  HGDIOBJ old_color = SelectObject(dc, color);
  HGDIOBJ old_mask = SelectObject(mask_dc, mask);

  const RECT rc{0, 0, kSize, kSize};
  // Inset disc: a transparent margin reads rounder at 16px (WhatsApp-style
  // separation) than a full-bleed disc whose rim touches the bitmap edge.
  const int m = kSize / 12;
  HBRUSH white = static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH));
  HBRUSH black = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  HPEN noPen = static_cast<HPEN>(GetStockObject(NULL_PEN));
  // Mask: transparent everywhere except the badge disc. NULL_PEN: GDI
  // shapes otherwise get a 1px black outline (the dark rim in toasts).
  FillRect(mask_dc, &rc, white);
  SelectObject(mask_dc, black);
  SelectObject(mask_dc, noPen);
  Ellipse(mask_dc, m, m, kSize - m, kSize - m);
  // Color: iOS badge red everywhere, so downscaled rim pixels blend
  // red-on-red. The mask still clips everything outside the disc.
  HBRUSH red = CreateSolidBrush(RGB(255, 59, 48));
  FillRect(dc, &rc, red);
  SelectObject(dc, red);
  SelectObject(dc, noPen);
  Ellipse(dc, m, m, kSize - m, kSize - m);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(255, 255, 255));
  // iOS proportions: ultra-heavy digits ~55-60% of disc diameter, tiered so
  // two digits and "99+" still fit. Grayscale AA survives the downscale to
  // 16px; ClearType subpixels turn to color mush.
  const int fontHeight =
      text.length() > 2 ? 26 : (text.length() > 1 ? 34 : 44);
  HFONT font = CreateFontW(fontHeight, 0, 0, 0, FW_BLACK, FALSE,
                           FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                           DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  HGDIOBJ old_font = nullptr;
  if (font) old_font = SelectObject(dc, font);
  // Optical centering: DrawText VCenter sits digits slightly high.
  RECT text_rc{0, kSize / 16, kSize, kSize + kSize / 16};
  DrawTextW(dc, text.c_str(), -1, &text_rc,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  if (font) {
    SelectObject(dc, old_font);
    DeleteObject(font);
  }
  DeleteObject(red);

  ICONINFO info{};
  info.fIcon = TRUE;
  info.hbmMask = mask;
  info.hbmColor = color;
  HICON icon = CreateIconIndirect(&info);

  SelectObject(dc, old_color);
  SelectObject(mask_dc, old_mask);
  DeleteObject(color);
  DeleteObject(mask);
  DeleteDC(dc);
  DeleteDC(mask_dc);
  return icon;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
