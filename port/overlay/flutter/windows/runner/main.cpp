#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <string>

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

// A crash the user can send: the exception, the faulting address as an offset inside its own
// module, and when. Without symbols an address is a coordinate, but a module-relative one names
// the build that faulted, which is what separates a driver fault from ours.
std::wstring CrashLogPath() {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD length = ::GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, MAX_PATH);
  std::wstring path =
      length > 0 && length < MAX_PATH ? std::wstring(buffer, length) : std::wstring(L".");
  path += L"\\Fotufilm";
  ::CreateDirectoryW(path.c_str(), nullptr);
  path += L"\\crash.log";
  return path;
}

LONG WINAPI RecordCrash(EXCEPTION_POINTERS *info) {
  const EXCEPTION_RECORD *record = info != nullptr ? info->ExceptionRecord : nullptr;
  if (record == nullptr) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  const uintptr_t address = reinterpret_cast<uintptr_t>(record->ExceptionAddress);
  std::wstring module_name = L"(unknown)";
  uintptr_t offset = address;
  HMODULE module = nullptr;
  if (::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(record->ExceptionAddress), &module) &&
      module != nullptr) {
    wchar_t name[MAX_PATH] = {};
    if (::GetModuleFileNameW(module, name, MAX_PATH) != 0) {
      module_name = name;
      const std::wstring::size_type slash = module_name.find_last_of(L"\\/");
      if (slash != std::wstring::npos) {
        module_name = module_name.substr(slash + 1);
      }
    }
    offset = address - reinterpret_cast<uintptr_t>(module);
  }
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  wchar_t line[1024] = {};
  ::swprintf_s(line, L"%04u-%02u-%02u %02u:%02u:%02u exception 0x%08X at %s+0x%llX"
                     L" (0x%llX), process %lu\r\n",
               now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
               static_cast<unsigned>(record->ExceptionCode), module_name.c_str(),
               static_cast<unsigned long long>(offset),
               static_cast<unsigned long long>(address), ::GetCurrentProcessId());
  const std::wstring path = CrashLogPath();
  HANDLE file = ::CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    const int bytes = ::WideCharToMultiByte(CP_UTF8, 0, line, -1, nullptr, 0, nullptr, nullptr);
    if (bytes > 0) {
      std::string utf8(static_cast<size_t>(bytes - 1), '\0');
      ::WideCharToMultiByte(CP_UTF8, 0, line, -1, utf8.data(), bytes, nullptr, nullptr);
      DWORD written = 0;
      ::WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr);
    }
    ::CloseHandle(file);
  }
  return EXCEPTION_CONTINUE_SEARCH;
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


// Whether a Vulkan device is there to develop on. The engine develops without one, on the CPU
// kernels this port adds, so this only decides which notice the editor shows. Read through the
// loader alone, before Flutter starts, so the editor can say so without touching the engine.
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
  ::SetUnhandledExceptionFilter(RecordCrash);

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