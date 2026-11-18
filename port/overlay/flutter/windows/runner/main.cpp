#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "resource.h"
#include "utils.h"

namespace {

// The engine's ahead-of-time kernels are compiled for AVX2 (Pipeline/Gpu.h), host code above
// the device with them. A processor without it dies on the first kernel with an illegal
// instruction, and the window never opens, so say so before Flutter or the engine loads.
bool CpuSupportsAvx2() {
  if (::GetEnvironmentVariableW(L"FOTUFILM_IGNORE_CPU_CHECK", nullptr, 0) != 0) {
    return true;
  }
  if (::GetEnvironmentVariableW(L"FOTUFILM_FORCE_UNSUPPORTED_CPU", nullptr, 0) != 0) {
    return false;
  }
  return ::IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE) != FALSE;
}

void TellCpuUnsupported() {
  wchar_t title[256] = {};
  wchar_t text[2048] = {};
  HINSTANCE module = ::GetModuleHandleW(nullptr);
  ::LoadStringW(module, IDS_CPU_UNSUPPORTED_TITLE, title,
                static_cast<int>(sizeof(title) / sizeof(title[0])));
  ::LoadStringW(module, IDS_CPU_UNSUPPORTED, text,
                static_cast<int>(sizeof(text) / sizeof(text[0])));
  ::MessageBoxW(nullptr, text, title, MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
}


// Whether a Vulkan device is there to develop on: the Windows engine has no CPU developer, so
// without one photographs cannot develop at all. Read through the loader alone, before Flutter
// starts, so the editor can say so without touching the engine.
bool VulkanDevicePresent() {
  if (::GetEnvironmentVariableW(L"FOTUFILM_FORCE_NO_VULKAN", nullptr, 0) != 0) {
    return false;
  }
  HMODULE loader = ::LoadLibraryW(L"vulkan-1.dll");
  if (loader == nullptr) {
    return false;
  }
  using CreateInstance = int32_t (*)(const void *, const void *, void **);
  using EnumerateDevices = int32_t (*)(void *, uint32_t *, void **);
  using DestroyInstance = void (*)(void *, const void *);
  auto create = reinterpret_cast<CreateInstance>(
      ::GetProcAddress(loader, "vkCreateInstance"));
  auto enumerate = reinterpret_cast<EnumerateDevices>(
      ::GetProcAddress(loader, "vkEnumeratePhysicalDevices"));
  auto destroy = reinterpret_cast<DestroyInstance>(
      ::GetProcAddress(loader, "vkDestroyInstance"));
  bool found = false;
  if (create != nullptr && enumerate != nullptr && destroy != nullptr) {
    struct ApplicationInfo {
      int32_t type;
      const void *next;
      const char *name;
      uint32_t version;
      const char *engine;
      uint32_t engine_version;
      uint32_t api;
    };
    struct InstanceInfo {
      int32_t type;
      const void *next;
      uint32_t flags;
      const ApplicationInfo *application;
      uint32_t layers;
      const char *const *layer_names;
      uint32_t extensions;
      const char *const *extension_names;
    };
    const ApplicationInfo application{0, nullptr, "Fotufilm", 1, "Fotufilm", 1,
                                      (1u << 22) | (2u << 12)};
    const InstanceInfo info{1, nullptr, 0, &application, 0, nullptr, 0, nullptr};
    void *instance = nullptr;
    if (create(&info, nullptr, &instance) == 0 && instance != nullptr) {
      uint32_t count = 0;
      found = enumerate(instance, &count, nullptr) >= 0 && count > 0;
      destroy(instance, nullptr);
    }
  }
  ::FreeLibrary(loader);
  return found;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (!CpuSupportsAvx2()) {
    TellCpuUnsupported();
    return EXIT_FAILURE;
  }

  if (!VulkanDevicePresent()) {
    ::SetEnvironmentVariableW(L"FOTUFILM_NO_VULKAN", L"1");
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1560, 980);
  // Escaped rather than literal: MSVC reads a BOM-less source in the system code page, so the
  // Chinese characters came out as mojibake in the title bar.
  if (!window.Create(L"Fotufilm \u80F6\u7247\u6697\u623F", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
