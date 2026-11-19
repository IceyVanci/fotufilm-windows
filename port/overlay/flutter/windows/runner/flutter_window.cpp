#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The window's name when no photograph is open, as main.cpp creates it. Escaped rather than
// literal: MSVC reads a BOM-less source in the system code page.
constexpr wchar_t kAppName[] = L"Fotufilm \u80F6\u7247\u6697\u623F";

// What lib/app/workspace.dart sends when no photograph is open.
constexpr char kNoPhoto[] = "Fotufilm";

// The editor sends UTF-8 (a photograph's name may be Chinese); the title bar wants UTF-16.
std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = static_cast<int>(utf8.size());
  const int size =
      ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), length, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring text(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), length, text.data(), size);
  return text;
}

// Releases the engine's Vulkan device while its loader is still loaded. Windows runs the Halide
// runtime's destructor during DLL detach, after the driver's loader may be gone, and NVIDIA's
// driver then calls a null pointer: the crash recorded just after the window closes. The
// controller is destroyed first, so no develop is in flight when this runs.
void ReleaseHalideDevice() {
  HMODULE engine = ::GetModuleHandleW(L"libfotufilm.dll");
  if (engine == nullptr) {
    return;
  }
  using Shutdown = void (*)();
  auto shutdown = reinterpret_cast<Shutdown>(
      ::GetProcAddress(engine, "fotufilm_halide_shutdown"));
  if (shutdown != nullptr) {
    shutdown();
  }
}

}  // namespace

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The editor names the window after the photograph open in it (lib/app/workspace.dart). The
  // toolbar is not the titlebar here and there is no document tab, so the system's title bar is
  // the only place that name can show.
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "fotufilm/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setTitle") {
          const auto* title = std::get_if<std::string>(call.arguments());
          NameWindow(title != nullptr ? *title : std::string());
          result->Success();
          return;
        }
        // The rest of the channel is the Mac app's: dragging and zooming the toolbar, recent
        // files and the sample chart, which this host does not have.
        result->NotImplemented();
      });

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
  // The channel belongs to the engine: it goes before the controller takes the engine with it,
  // or its destructor tells a freed messenger about itself.
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  ReleaseHalideDevice();

  Win32Window::OnDestroy();
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

void FlutterWindow::NameWindow(const std::string& title) {
  HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }
  // With a photograph open the title is its name and then the app's, as another Windows app
  // names its document; with none the app stands alone.
  if (title.empty() || title == kNoPhoto) {
    ::SetWindowTextW(window, kAppName);
    return;
  }
  std::wstring text = Wide(title);
  text += L" \u2014 ";
  text += kAppName;
  ::SetWindowTextW(window, text.c_str());
}
