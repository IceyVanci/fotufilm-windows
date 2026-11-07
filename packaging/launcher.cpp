// Fotufilm single-file packaging: a self-extracting launcher and the packer that fills it.
//
// One source file builds two programs:
//   cl /DFOTUFILM_PACKER ...  -> fotufilm-pack.exe    (build machine)
//   cl ...                    -> fotufilm-launch.exe  (the stub the payload is appended to)
//
// Layout of a packed exe:
//   [stub PE image][ArchiveHeader][EntryRec + name UTF-16LE]*[blob]*[Trailer]
// The Trailer ends the file, so the launcher finds the archive by seeking back 32 bytes.

#define NOMINMAX
#include <windows.h>
#include <compressapi.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdio.h>
#include <string>
#include <vector>
#include <algorithm>
#include <thread>
#include <atomic>
#include <cstdarg>

#pragma comment(lib, "cabinet.lib")
#pragma comment(lib, "shell32.lib")

#define TRAILER_MAGIC "FOTOFILM-SFX\0\0\0\0"
#define ARCHIVE_MAGIC "FOTOARCH"
#define FLAG_NAME "complete.flag"

#pragma pack(push, 1)
struct ArchiveHeader {
  char magic[8];
  uint32_t version;
  uint32_t entryCount;
  uint64_t totalRaw;
  uint64_t payloadHash;
  wchar_t appExe[64];
  wchar_t displayName[96];
};

struct EntryRec {
  uint64_t offset;   // absolute offset of the blob inside the packed file
  uint64_t compSize;
  uint64_t rawSize;
  uint64_t rawHash;
  uint32_t nameChars;
  uint32_t algo;
};

struct Trailer {
  char magic[16];
  uint64_t archiveOffset;
  uint64_t archiveSize;
};
#pragma pack(pop)

enum : DWORD { ALGO_STORE = 0, ALGO_MSZIP = 2, ALGO_XPRESS_HUFF = 4, ALGO_LZMS = 5 };

static uint64_t Fnv1a(const void* data, size_t size, uint64_t seed = 1469598103934665603ull) {
  const unsigned char* p = static_cast<const unsigned char*>(data);
  uint64_t h = seed;
  for (size_t i = 0; i < size; ++i) { h ^= p[i]; h *= 1099511628211ull; }
  return h;
}

static std::wstring Join(const std::wstring& a, const std::wstring& b) {
  if (a.empty()) return b;
  if (a.back() == L'\\' || a.back() == L'/') return a + b;
  return a + L"\\" + b;
}

static void LogLine(const std::wstring& text) {
  const wchar_t* path = _wgetenv(L"FOTOFILM_LAUNCH_LOG");
  if (!path || !*path) return;
  FILE* file = nullptr;
  if (_wfopen_s(&file, path, L"a, ccs=UTF-8") != 0 || !file) return;
  SYSTEMTIME now{};
  GetLocalTime(&now);
  fwprintf(file, L"[%02d:%02d:%02d] %ls\n", now.wHour, now.wMinute, now.wSecond, text.c_str());
  fclose(file);
}

static DWORD MakeDirectories(const std::wstring& dir, bool verbose = false) {
  if (dir.size() < 3) return ERROR_INVALID_NAME;
  std::wstring partial;
  DWORD failure = 0;
  for (size_t i = 0; i < dir.size(); ++i) {
    partial += dir[i];
    if (dir[i] == L'\\' || dir[i] == L'/' || i + 1 == dir.size()) {
      std::wstring target = partial;
      if (target.size() > 3 && (target.back() == L'\\' || target.back() == L'/')) target.pop_back();
      if (target.size() == 3 && target[1] == L':') continue;  // the drive root always exists
      if (target.size() >= 3) {
        if (!CreateDirectoryW(target.c_str(), nullptr)) {
          const DWORD error = GetLastError();
          if (error != ERROR_ALREADY_EXISTS) {
            failure = error;
            if (verbose) LogLine(L"mkdir " + target + L" -> " + std::to_wstring(error));
          }
        } else if (verbose) {
          LogLine(L"mkdir " + target);
        }
      }
    }
  }
  return failure;
}


static bool RemoveTree(const std::wstring& path) {
  WIN32_FIND_DATAW data{};
  HANDLE find = FindFirstFileW(Join(path, L"*").c_str(), &data);
  if (find != INVALID_HANDLE_VALUE) {
    do {
      std::wstring name = data.cFileName;
      if (name == L"." || name == L"..") continue;
      std::wstring child = Join(path, name);
      if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        RemoveTree(child);
      } else {
        SetFileAttributesW(child.c_str(), FILE_ATTRIBUTE_NORMAL);
        DeleteFileW(child.c_str());
      }
    } while (FindNextFileW(find, &data));
    FindClose(find);
  }
  RemoveDirectoryW(path.c_str());
  return GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES;
}

#ifdef FOTUFILM_PACKER

static bool ReadWholeFile(const std::wstring& path, std::vector<uint8_t>& out) {
  HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(h, &size)) { CloseHandle(h); return false; }
  out.resize((size_t)size.QuadPart);
  size_t done = 0;
  while (done < out.size()) {
    DWORD chunk = (DWORD)std::min<size_t>(out.size() - done, 1u << 20);
    DWORD read = 0;
    if (!ReadFile(h, out.data() + done, chunk, &read, nullptr) || read == 0) { CloseHandle(h); return false; }
    done += read;
  }
  CloseHandle(h);
  return true;
}

static bool CompressBuffer(DWORD algo, const std::vector<uint8_t>& in, std::vector<uint8_t>& out) {
  COMPRESSOR_HANDLE c = nullptr;
  if (!CreateCompressor(algo, nullptr, &c)) return false;
  size_t cap = in.size() + (1u << 20);
  out.resize(cap);
  size_t produced = 0;
  BOOL ok = Compress(c, in.data(), in.size(), out.data(), cap, &produced);
  while (!ok && GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
    cap *= 2;
    out.resize(cap);
    ok = Compress(c, in.data(), in.size(), out.data(), cap, &produced);
  }
  CloseCompressor(c);
  if (!ok) return false;
  out.resize(produced);
  return true;
}

#else

static std::wstring Format(const wchar_t* fmt, ...) {
  wchar_t buf[2048];
  va_list args; va_start(args, fmt);
  _vsnwprintf_s(buf, _TRUNCATE, fmt, args);
  va_end(args);
  return buf;
}

static bool ValidRelativePath(const std::wstring& name) {
  if (name.empty()) return false;
  if (name.size() >= 2 && name[1] == L':') return false;
  if (name[0] == L'\\' || name[0] == L'/') return false;
  if (name.find(L"..") != std::wstring::npos) return false;
  return true;
}

static bool DecompressBuffer(DWORD algo, const uint8_t* in, size_t inSize, uint8_t* out, size_t outSize) {
  DECOMPRESSOR_HANDLE d = nullptr;
  if (!CreateDecompressor(algo, nullptr, &d)) return false;
  size_t produced = 0;
  BOOL ok = Decompress(d, in, inSize, out, outSize, &produced);
  CloseDecompressor(d);
  return ok && produced == outSize;
}

#endif // FOTUFILM_PACKER

// ── launcher ───────────────────────────────────────────────────────────────────
#ifndef FOTUFILM_PACKER

struct Splash {
  HWND window = nullptr;
  HWND label = nullptr;

  static LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_CLOSE) { DestroyWindow(hwnd); return 0; }
    if (message == WM_DESTROY) return 0;
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }

  void Show() {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = &Splash::Proc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = CreateSolidBrush(RGB(24, 24, 26));
    wc.lpszClassName = L"FotufilmPackProgress";
    RegisterClassExW(&wc);

    const int width = 460, height = 96;
    int x = (GetSystemMetrics(SM_CXSCREEN) - width) / 2;
    int y = (GetSystemMetrics(SM_CYSCREEN) - height) / 2;
    window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, wc.lpszClassName, L"Fotufilm",
                             WS_POPUP | WS_BORDER, x, y, width, height, nullptr, nullptr,
                             wc.hInstance, nullptr);
    if (!window) return;
    label = CreateWindowExW(0, L"STATIC", L"正在准备 Fotufilm…", WS_CHILD | WS_VISIBLE | SS_CENTER,
                            16, 34, width - 32, 28, window, nullptr, wc.hInstance, nullptr);
    HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
    SendMessageW(label, WM_SETFONT, (WPARAM)font, TRUE);
    ShowWindow(window, SW_SHOWNOACTIVATE);
    UpdateWindow(window);
    Pump();
  }

  void Update(int done, int total) {
    if (!label || !total) return;
    wchar_t text[128];
    swprintf_s(text, L"正在解包 Fotufilm… %d%%（%d / %d）", done * 100 / total, done, total);
    SetWindowTextW(label, text);
    Pump();
  }

  void Pump() {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }

  void Close() {
    if (window) { DestroyWindow(window); window = nullptr; }
  }
};

static Splash* gSplash = nullptr;



static void Die(const std::wstring& message) {
  LogLine(std::wstring(L"FATAL: ") + message);
  if (gSplash) gSplash->Close();
  MessageBoxW(nullptr, message.c_str(), L"Fotufilm", MB_OK | MB_ICONERROR);
  ExitProcess(1);
}

// A small window that says what the first run is doing. Extraction of a 300 MB payload takes a few
// seconds, and a silent start reads as a broken start.

static std::wstring ExeDirectory() {
  wchar_t buf[MAX_PATH * 2];
  DWORD n = GetModuleFileNameW(nullptr, buf, (DWORD)std::size(buf));
  std::wstring path(buf, n);
  size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"." : path.substr(0, slash);
}

static std::wstring Lower(std::wstring s) {
  for (auto& c : s) c = towlower(c);
  return s;
}

struct Args {
  bool portable = false;
  bool extractOnly = false;
  bool clean = false;
  bool wait = false;
  std::wstring runtimeDir;
  std::vector<std::wstring> appArgs;
};

static Args ParseArgs(int argc, wchar_t** argv) {
  Args a;
  bool passthrough = false;
  for (int i = 1; i < argc; ++i) {
    std::wstring arg = argv[i];
    if (passthrough) { a.appArgs.push_back(arg); continue; }
    if (arg == L"--") { passthrough = true; continue; }
    std::wstring low = Lower(arg);
    if (low == L"--portable") { a.portable = true; continue; }
    if (low == L"--extract-only") { a.extractOnly = true; continue; }
    if (low == L"--clean") { a.clean = true; continue; }
    if (low == L"--wait") { a.wait = true; continue; }
    if (low == L"--runtime-dir" && i + 1 < argc) { a.runtimeDir = argv[++i]; continue; }
    if (low == L"--help" || low == L"-h" || low == L"/?") {
      AttachConsole(ATTACH_PARENT_PROCESS);
      fwprintf(stdout,
               L"fotufilm-launch [--portable] [--extract-only] [--clean] [--wait] [--runtime-dir <path>] "
               L"[-- <app args>]\n");
      ExitProcess(0);
    }
    passthrough = true;
    a.appArgs.push_back(arg);
  }
  return a;
}

static bool ReadTrailer(std::wstring& selfPath, Trailer& trailer) {
  wchar_t buf[MAX_PATH * 2];
  DWORD n = GetModuleFileNameW(nullptr, buf, (DWORD)std::size(buf));
  selfPath.assign(buf, n);
  HANDLE h = CreateFileW(selfPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  GetFileSizeEx(h, &size);
  bool ok = false;
  if ((uint64_t)size.QuadPart >= sizeof(Trailer)) {
    LARGE_INTEGER pos{};
    pos.QuadPart = size.QuadPart - (LONGLONG)sizeof(Trailer);
    SetFilePointerEx(h, pos, nullptr, FILE_BEGIN);
    DWORD read = 0;
    if (ReadFile(h, &trailer, sizeof(Trailer), &read, nullptr) && read == sizeof(Trailer))
      ok = memcmp(trailer.magic, TRAILER_MAGIC, sizeof(trailer.magic)) == 0;
  }
  CloseHandle(h);
  return ok;
}

static int Launch(const Args& args) {
  std::wstring selfPath;
  Trailer trailer{};
  if (!ReadTrailer(selfPath, trailer)) Die(L"This program is not a packed Fotufilm build.");

  HANDLE self = CreateFileW(selfPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (self == INVALID_HANDLE_VALUE) Die(L"Could not reopen the executable.");

  ArchiveHeader header{};
  LARGE_INTEGER at{};
  at.QuadPart = (LONGLONG)trailer.archiveOffset;
  SetFilePointerEx(self, at, nullptr, FILE_BEGIN);
  DWORD read = 0;
  if (!ReadFile(self, &header, sizeof(header), &read, nullptr) || read != sizeof(header) ||
      memcmp(header.magic, ARCHIVE_MAGIC, 8) != 0 || header.version != 1) {
    Die(L"The embedded archive is damaged.");
  }

  std::vector<EntryRec> entries(header.entryCount);
  std::vector<std::wstring> names(header.entryCount);
  for (uint32_t i = 0; i < header.entryCount; ++i) {
    if (!ReadFile(self, &entries[i], sizeof(EntryRec), &read, nullptr) || read != sizeof(EntryRec))
      Die(L"The embedded archive is truncated.");
    std::wstring name(entries[i].nameChars, L'\0');
    if (entries[i].nameChars) {
      if (!ReadFile(self, name.data(), entries[i].nameChars * sizeof(wchar_t), &read, nullptr) ||
          read != entries[i].nameChars * sizeof(wchar_t))
        Die(L"The embedded archive is truncated.");
    }
    if (!ValidRelativePath(name)) Die(L"The embedded archive holds an unsafe path.");
    std::replace(name.begin(), name.end(), L'/', L'\\');
    names[i] = name;
  }

  uint64_t tableChain = 1469598103934665603ull;
  for (uint32_t i = 0; i < header.entryCount; ++i) {
    tableChain = Fnv1a(names[i].data(), names[i].size() * sizeof(wchar_t), tableChain);
    uint64_t meta[2] = { entries[i].rawSize, entries[i].rawHash };
    tableChain = Fnv1a(meta, sizeof(meta), tableChain);
  }
  if (tableChain != header.payloadHash) Die(L"The embedded archive does not match this build.");

  wchar_t hex[32];
  swprintf_s(hex, L"%016llx", (unsigned long long)header.payloadHash);

  std::vector<std::wstring> candidates;
  const wchar_t* envDir = _wgetenv(L"FOTOFILM_RUNTIME_DIR");
  if (!args.runtimeDir.empty()) candidates.push_back(args.runtimeDir);
  else if (envDir && *envDir) candidates.push_back(envDir);
  else if (args.portable) candidates.push_back(Join(Join(ExeDirectory(), L"Fotufilm.runtime"), hex));
  else {
    const wchar_t* local = _wgetenv(L"LOCALAPPDATA");
    if (local && *local) candidates.push_back(Join(Join(Join(local, L"Fotufilm"), L"runtime"), hex));
    candidates.push_back(Join(Join(ExeDirectory(), L"Fotufilm.runtime"), hex));
    const wchar_t* temp = _wgetenv(L"TEMP");
    if (temp && *temp) candidates.push_back(Join(Join(temp, L"Fotufilm"), hex));
  }

  // The user profile is the intended home; a locked-down profile, a read-only medium or a portable
  // stick moves the runtime beside the executable, and the temporary folder is the last resort.
  std::wstring runtimeRoot;
  for (const auto& candidate : candidates) {
    if (GetFileAttributesW(Join(candidate, L"" FLAG_NAME).c_str()) != INVALID_FILE_ATTRIBUTES) {
      runtimeRoot = candidate;
      break;
    }
  }
  if (runtimeRoot.empty()) {
    for (const auto& candidate : candidates) {
      const DWORD error = MakeDirectories(candidate, true);
      if (error == 0 || GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) {
        runtimeRoot = candidate;
        break;
      }
      LogLine(L"cannot use " + candidate + L" (" + std::to_wstring(error) + L")");
    }
  }
  if (runtimeRoot.empty()) {
    std::wstring tried;
    for (const auto& candidate : candidates) tried += L"\n" + candidate;
    Die(L"Could not find a folder to unpack into. Tried:" + tried);
  }

  if (args.clean) {
    size_t cut = runtimeRoot.find_last_of(L'\\');
    std::wstring parent = cut == std::wstring::npos ? runtimeRoot : runtimeRoot.substr(0, cut);
    int removed = 0;
    WIN32_FIND_DATAW data{};
    HANDLE find = FindFirstFileW(Join(parent, L"*").c_str(), &data);
    if (find != INVALID_HANDLE_VALUE) {
      do {
        std::wstring name = data.cFileName;
        if (name == L"." || name == L"..") continue;
        if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        std::wstring dir = Join(parent, name);
        if (dir == runtimeRoot) continue;
        if (RemoveTree(dir)) ++removed;
      } while (FindNextFileW(find, &data));
      FindClose(find);
    }
    AttachConsole(ATTACH_PARENT_PROCESS);
    fwprintf(stdout, L"Removed %d older runtime(s) under %ls\n", removed, parent.c_str());
    ExitProcess(0);
  }

  const std::wstring complete = Join(runtimeRoot, L"" FLAG_NAME);
  bool ready = GetFileAttributesW(complete.c_str()) != INVALID_FILE_ATTRIBUTES;
  LogLine(L"runtime: " + runtimeRoot);
  LogLine(std::wstring(L"ready: ") + (ready ? L"yes" : L"no"));

  if (!ready) {
    static Splash splash;
    gSplash = &splash;
    splash.Show();

    // The lock only keeps two first runs from unpacking at once. A copy that cannot take it waits a
    // moment, then unpacks anyway: each copy writes into its own temporary folder and renames it
    // into place, so both end up with the same bytes and neither can leave a half-written runtime.
    const std::wstring lockPath = runtimeRoot + L".lock";
    HANDLE lock = CreateFileW(lockPath.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS,
                              FILE_ATTRIBUTE_TEMPORARY, nullptr);
    if (lock == INVALID_HANDLE_VALUE) {
      const DWORD lockError = GetLastError();
      LogLine(Format(L"lock unavailable (error %lu)", lockError));
      for (int waited = 0; waited < 15000 && !ready; waited += 100) {
        Sleep(100);
        ready = GetFileAttributesW(complete.c_str()) != INVALID_FILE_ATTRIBUTES;
      }
      LogLine(std::wstring(L"after wait ready: ") + (ready ? L"yes" : L"no"));
    }

    if (!ready) {
      wchar_t pid[32];
      swprintf_s(pid, L"%u", (unsigned)GetCurrentProcessId());
      const std::wstring temp = runtimeRoot + L".tmp-" + pid;
      RemoveTree(temp);
      MakeDirectories(temp);
      LogLine(L"unpacking into " + temp);

      for (uint32_t i = 0; i < header.entryCount; ++i) {
        if (gSplash) gSplash->Update((int)i, (int)header.entryCount);
        std::vector<uint8_t> raw((size_t)entries[i].rawSize);
        std::vector<uint8_t> blob((size_t)entries[i].compSize);
        at.QuadPart = (LONGLONG)entries[i].offset;
        SetFilePointerEx(self, at, nullptr, FILE_BEGIN);
        DWORD got = 0;
        if (!blob.empty() && (!ReadFile(self, blob.data(), (DWORD)blob.size(), &got, nullptr) ||
                              got != blob.size())) {
          RemoveTree(temp);
          Die(L"The embedded archive is truncated.");
        }
        if (!raw.empty()) {
          if (entries[i].algo == ALGO_STORE) {
            memcpy(raw.data(), blob.data(), (size_t)blob.size());
          } else if (!DecompressBuffer(entries[i].algo, blob.data(), blob.size(), raw.data(), raw.size())) {
            RemoveTree(temp);
            Die(L"Could not unpack " + names[i] + L".");
          }
        }
        if (Fnv1a(raw.data(), raw.size()) != entries[i].rawHash) {
          RemoveTree(temp);
          Die(L"Checksum mismatch while unpacking " + names[i] + L".");
        }
        const std::wstring target = Join(temp, names[i]);
        const size_t cut = target.find_last_of(L'\\');
        if (cut != std::wstring::npos) MakeDirectories(target.substr(0, cut));
        HANDLE out = CreateFileW(target.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                 FILE_ATTRIBUTE_NORMAL, nullptr);
        if (out == INVALID_HANDLE_VALUE) {
          const DWORD writeError = GetLastError();
          RemoveTree(temp);
          Die(Format(L"Could not write a file (error %lu):\n%ls", writeError, target.c_str()));
        }
        size_t done = 0;
        while (done < raw.size()) {
          DWORD chunk = (DWORD)std::min<size_t>(raw.size() - done, 1u << 20);
          DWORD written = 0;
          if (!WriteFile(out, raw.data() + done, chunk, &written, nullptr) || written == 0) {
            const DWORD writeError = GetLastError();
            CloseHandle(out);
            RemoveTree(temp);
            Die(Format(L"Could not write a file (error %lu):\n%ls", writeError, target.c_str()));
          }
          done += written;
        }
        CloseHandle(out);
      }

      HANDLE flag = CreateFileW(Join(temp, L"" FLAG_NAME).c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
      if (flag != INVALID_HANDLE_VALUE) {
        char text[64];
        int len = sprintf_s(text, "%016llx\n", (unsigned long long)header.payloadHash);
        DWORD written = 0;
        WriteFile(flag, text, (DWORD)len, &written, nullptr);
        CloseHandle(flag);
      }
      RemoveTree(runtimeRoot);
      if (!MoveFileExW(temp.c_str(), runtimeRoot.c_str(), MOVEFILE_REPLACE_EXISTING)) {
        const DWORD moveError = GetLastError();
        RemoveTree(temp);
        Die(Format(L"Could not move the runtime into place (error %lu):\n%ls", moveError, runtimeRoot.c_str()));
      }
      LogLine(L"unpacked");
    }

    if (lock != INVALID_HANDLE_VALUE) {
      CloseHandle(lock);
      DeleteFileW(lockPath.c_str());
    }
  }

  CloseHandle(self);

  if (gSplash) { gSplash->Close(); gSplash = nullptr; }

  if (args.extractOnly) {
    AttachConsole(ATTACH_PARENT_PROCESS);
    fwprintf(stdout, L"%ls\n", runtimeRoot.c_str());
    ExitProcess(0);
  }

  std::wstring appPath = Join(runtimeRoot, header.appExe[0] ? header.appExe : L"fotufilm.exe");
  if (GetFileAttributesW(appPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
    Die(L"The editor is missing from\n" + runtimeRoot + L"\nRun this file again to repair the installation.");
  }

  std::wstring cmd = L"\"" + appPath + L"\"";
  for (const auto& a : args.appArgs) cmd += L" \"" + a + L"\"";
  std::vector<wchar_t> cmdLine(cmd.begin(), cmd.end());
  cmdLine.push_back(0);

  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  if (!CreateProcessW(appPath.c_str(), cmdLine.data(), nullptr, nullptr, TRUE, 0, nullptr,
                      runtimeRoot.c_str(), &si, &pi)) {
    Die(Format(L"The editor could not start (error %lu).", GetLastError()));
  }
  if (args.wait) {
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return 0;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return 1;
  Args args = ParseArgs(argc, argv);
  LocalFree(argv);
  return Launch(args);
}

// ── packer ─────────────────────────────────────────────────────────────────────
#else

struct FileItem {
  std::wstring relative;
  std::wstring absolute;
  std::vector<uint8_t> packed;
  uint64_t rawSize = 0;
  uint64_t hash = 0;
  DWORD algo = ALGO_STORE;
  bool ok = false;
};

static void Collect(const std::wstring& root, const std::wstring& dir, std::vector<FileItem>& items) {
  WIN32_FIND_DATAW data{};
  HANDLE find = FindFirstFileW(Join(dir, L"*").c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) return;
  do {
    std::wstring name = data.cFileName;
    if (name == L"." || name == L"..") continue;
    std::wstring full = Join(dir, name);
    if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      Collect(root, full, items);
    } else {
      FileItem item;
      item.absolute = full;
      item.relative = full.substr(root.size() + 1);
      std::replace(item.relative.begin(), item.relative.end(), L'/', L'\\');
      items.push_back(std::move(item));
    }
  } while (FindNextFileW(find, &data));
  FindClose(find);
}

class Writer {
 public:
  explicit Writer(const std::wstring& path) {
    handle_ = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  }
  ~Writer() { if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_); }
  bool valid() const { return handle_ != INVALID_HANDLE_VALUE; }
  bool Write(const void* data, size_t size) {
    const uint8_t* p = static_cast<const uint8_t*>(data);
    size_t done = 0;
    while (done < size) {
      DWORD chunk = (DWORD)std::min<size_t>(size - done, 1u << 20);
      DWORD written = 0;
      if (!WriteFile(handle_, p + done, chunk, &written, nullptr) || written == 0) return false;
      done += written;
    }
    position_ += size;
    return true;
  }
  uint64_t position() const { return position_; }

 private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
  uint64_t position_ = 0;
};

static bool AlgoFromName(const std::wstring& name, DWORD& algo) {
  if (name == L"lzms") { algo = ALGO_LZMS; return true; }
  if (name == L"xpress" || name == L"xpress-huff") { algo = ALGO_XPRESS_HUFF; return true; }
  if (name == L"mszip") { algo = ALGO_MSZIP; return true; }
  if (name == L"store" || name == L"none") { algo = ALGO_STORE; return true; }
  return false;
}

int wmain(int argc, wchar_t** argv) {
  std::wstring stub, input, output, displayName = L"Fotufilm", appExe = L"fotufilm.exe";
  DWORD algo = ALGO_LZMS;
  bool verbose = false;
  for (int i = 1; i < argc; ++i) {
    std::wstring a = argv[i];
    auto next = [&](std::wstring& target) { if (i + 1 < argc) target = argv[++i]; };
    if (a == L"--stub") next(stub);
    else if (a == L"--input") next(input);
    else if (a == L"--output") next(output);
    else if (a == L"--name") next(displayName);
    else if (a == L"--app") next(appExe);
    else if (a == L"--algo") { std::wstring v; next(v); if (!AlgoFromName(v, algo)) { fwprintf(stderr, L"unknown --algo\n"); return 2; } }
    else if (a == L"--no-compress") algo = ALGO_STORE;
    else if (a == L"--verbose") verbose = true;
    else if (a == L"--help" || a == L"-h") {
      fwprintf(stdout, L"fotufilm-pack --stub <launcher> --input <dir> --output <out.exe> "
                       L"[--name text] [--app fotufilm.exe] [--algo lzms|xpress|mszip|store] [--verbose]\n");
      return 0;
    } else { fwprintf(stderr, L"unknown argument %ls\n", a.c_str()); return 2; }
  }
  if (stub.empty() || input.empty() || output.empty()) {
    fwprintf(stderr, L"--stub, --input and --output are required\n");
    return 2;
  }

  LARGE_INTEGER freq{}, t0{};
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&t0);

  std::vector<uint8_t> stubBytes;
  if (!ReadWholeFile(stub, stubBytes)) { fwprintf(stderr, L"cannot read stub %ls\n", stub.c_str()); return 1; }

  std::vector<FileItem> items;
  Collect(input, input, items);
  std::sort(items.begin(), items.end(),
            [](const FileItem& a, const FileItem& b) { return a.relative < b.relative; });
  if (items.empty()) { fwprintf(stderr, L"input directory is empty\n"); return 1; }

  std::atomic<size_t> cursor{0};
  std::atomic<size_t> doneCount{0};
  unsigned workers = std::max(1u, std::thread::hardware_concurrency());
  workers = std::min<unsigned>(workers, 8u);
  workers = std::min<unsigned>(workers, (unsigned)items.size());
  std::vector<std::thread> pool;
  for (unsigned w = 0; w < workers; ++w) {
    pool.emplace_back([&]() {
      for (;;) {
        size_t index = cursor.fetch_add(1);
        if (index >= items.size()) return;
        FileItem& item = items[index];
        std::vector<uint8_t> raw;
        if (!ReadWholeFile(item.absolute, raw)) continue;
        item.rawSize = raw.size();
        item.hash = Fnv1a(raw.data(), raw.size());
        item.algo = ALGO_STORE;
        item.packed = raw;
        if (algo != ALGO_STORE && raw.size() > 4096) {
          std::vector<uint8_t> candidate;
          if (CompressBuffer(algo, raw, candidate) && candidate.size() < raw.size()) {
            item.packed.swap(candidate);
            item.algo = algo;
          }
        }
        item.ok = true;
        size_t n = ++doneCount;
        if (verbose && (n % 25 == 0 || n == items.size()))
          fwprintf(stdout, L"  packed %zu/%zu\n", n, items.size());
      }
    });
  }
  for (auto& t : pool) t.join();

  uint64_t totalRaw = 0, totalPacked = 0;
  uint64_t payloadHash = 1469598103934665603ull;
  for (const auto& item : items) {
    if (!item.ok) { fwprintf(stderr, L"cannot read %ls\n", item.absolute.c_str()); return 1; }
    totalRaw += item.rawSize;
    totalPacked += item.packed.size();
    payloadHash = Fnv1a(item.relative.data(), item.relative.size() * sizeof(wchar_t), payloadHash);
    uint64_t meta[2] = { item.rawSize, item.hash };
    payloadHash = Fnv1a(meta, sizeof(meta), payloadHash);
  }

  uint64_t entriesBytes = 0;
  for (const auto& item : items) entriesBytes += sizeof(EntryRec) + item.relative.size() * sizeof(wchar_t);

  Writer writer(output);
  if (!writer.valid()) { fwprintf(stderr, L"cannot write %ls\n", output.c_str()); return 1; }
  if (!writer.Write(stubBytes.data(), stubBytes.size())) return 1;

  ArchiveHeader header{};
  memcpy(header.magic, ARCHIVE_MAGIC, 8);
  header.version = 1;
  header.entryCount = (uint32_t)items.size();
  header.totalRaw = totalRaw;
  header.payloadHash = payloadHash;
  wcsncpy_s(header.appExe, appExe.c_str(), _TRUNCATE);
  wcsncpy_s(header.displayName, displayName.c_str(), _TRUNCATE);

  const uint64_t archiveOffset = writer.position();
  const uint64_t blobBase = archiveOffset + sizeof(ArchiveHeader) + entriesBytes;
  if (!writer.Write(&header, sizeof(header))) return 1;

  uint64_t cursorOffset = blobBase;
  for (const auto& item : items) {
    EntryRec rec{};
    rec.offset = cursorOffset;
    rec.compSize = item.packed.size();
    rec.rawSize = item.rawSize;
    rec.rawHash = item.hash;
    rec.nameChars = (uint32_t)item.relative.size();
    rec.algo = item.algo;
    if (!writer.Write(&rec, sizeof(rec))) return 1;
    if (rec.nameChars && !writer.Write(item.relative.data(), rec.nameChars * sizeof(wchar_t))) return 1;
    cursorOffset += rec.compSize;
  }
  for (const auto& item : items) {
    if (!item.packed.empty() && !writer.Write(item.packed.data(), item.packed.size())) return 1;
  }

  Trailer trailer{};
  memcpy(trailer.magic, TRAILER_MAGIC, sizeof(trailer.magic));
  trailer.archiveOffset = archiveOffset;
  trailer.archiveSize = writer.position() - archiveOffset;
  if (!writer.Write(&trailer, sizeof(trailer))) return 1;

  LARGE_INTEGER t1{};
  QueryPerformanceCounter(&t1);
  double ms = (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)freq.QuadPart;
  fwprintf(stdout, L"packed %zu files\n  raw      %llu bytes\n  archived %llu bytes (%.2fx)\n  wrote    %llu bytes\n  %.0f ms\n",
           items.size(), (unsigned long long)totalRaw,
           (unsigned long long)totalPacked,
           totalPacked ? (double)totalRaw / (double)totalPacked : 0.0,
           (unsigned long long)writer.position(), ms);
  return 0;
}
#endif
