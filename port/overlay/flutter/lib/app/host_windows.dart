// The Windows host: what the macOS app asks its native side for — a browser, Explorer, the app that
// owns a file, and the Recycle Bin — done here with ShellExecuteW and SHFileOperationW, so the
// Windows build needs no native plug-in for them.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ShellExecuteNative = IntPtr Function(
    IntPtr hwnd, Pointer<Utf16> operation, Pointer<Utf16> file,
    Pointer<Utf16> parameters, Pointer<Utf16> directory, Int32 show);
typedef _ShellExecuteDart = int Function(
    int hwnd, Pointer<Utf16> operation, Pointer<Utf16> file,
    Pointer<Utf16> parameters, Pointer<Utf16> directory, int show);

typedef _SHFileOperationNative = Int32 Function(Pointer<_ShFileOpStruct>);
typedef _SHFileOperationDart = int Function(Pointer<_ShFileOpStruct>);

/// SHFILEOPSTRUCTW, 56 bytes on x64.
final class _ShFileOpStruct extends Struct {
  external Pointer<Void> hwnd;
  @Uint32() external int wFunc;
  external Pointer<Utf16> pFrom;
  external Pointer<Utf16> pTo;
  @Uint16() external int fFlags;
  @Int32() external int anyOperationsAborted;
  external Pointer<Void> nameMappings;
  external Pointer<Utf16> progressTitle;
}

const int _foDelete = 3;
const int _fofSilent = 0x0004;
const int _fofNoConfirmation = 0x0010;
const int _fofAllowUndo = 0x0040;
const int _fofNoErrorUi = 0x0400;
const int _swShownormal = 1;

DynamicLibrary? _shell32Cache;
DynamicLibrary get _shell32 => _shell32Cache ??= DynamicLibrary.open('shell32.dll');

int _shellExecute(Pointer<Utf16> file, [Pointer<Utf16>? parameters]) {
  final function = _shell32.lookupFunction<_ShellExecuteNative, _ShellExecuteDart>('ShellExecuteW');
  final operation = 'open'.toNativeUtf16();
  try {
    return function(0, operation, file, parameters ?? nullptr, nullptr, _swShownormal);
  } finally {
    calloc.free(operation);
  }
}

/// Opens [url] in the browser the system has chosen.
bool openUrl(String url) {
  if (!Platform.isWindows) return false;
  final target = url.toNativeUtf16();
  try {
    return _shellExecute(target) > 32;
  } finally {
    calloc.free(target);
  }
}

/// Opens [path] in whichever app the system associates with it.
bool openFile(String path) {
  if (!Platform.isWindows) return false;
  final target = path.toNativeUtf16();
  try {
    return _shellExecute(target) > 32;
  } finally {
    calloc.free(target);
  }
}

/// Shows [paths] in Explorer, each with its file selected.
void reveal(List<String> paths) {
  if (!Platform.isWindows) return;
  final explorer = 'explorer.exe'.toNativeUtf16();
  try {
    for (final path in paths) {
      final parameters = '/select,"$path"'.toNativeUtf16();
      try {
        _shellExecute(explorer, parameters);
      } finally {
        calloc.free(parameters);
      }
    }
  } finally {
    calloc.free(explorer);
  }
}

/// Moves [paths] to the Recycle Bin, answering the ones that went.
List<String> trash(List<String> paths) {
  if (!Platform.isWindows || paths.isEmpty) return const [];
  final existing = [for (final path in paths) if (File(path).existsSync() || Directory(path).existsSync()) path];
  if (existing.isEmpty) return const [];

  // SHFileOperationW wants one double-NUL terminated list, not an array of strings.
  var units = 1;
  for (final path in existing) {
    units += path.length + 1;
  }
  final buffer = calloc<Uint16>(units + 1);
  try {
    var index = 0;
    for (final path in existing) {
      final code = path.codeUnits;
      for (final unit in code) {
        buffer[index++] = unit;
      }
      buffer[index++] = 0;
    }
    buffer[index] = 0;

    final operation = calloc<_ShFileOpStruct>();
    try {
      operation.ref
        ..hwnd = nullptr
        ..wFunc = _foDelete
        ..pFrom = buffer.cast<Utf16>()
        ..pTo = nullptr
        ..fFlags = _fofAllowUndo | _fofNoConfirmation | _fofSilent | _fofNoErrorUi
        ..anyOperationsAborted = 0
        ..nameMappings = nullptr
        ..progressTitle = nullptr;

      final run = _shell32.lookupFunction<_SHFileOperationNative, _SHFileOperationDart>('SHFileOperationW');
      if (run(operation) != 0) return const [];
    } finally {
      calloc.free(operation);
    }
  } finally {
    calloc.free(buffer);
  }
  return [for (final path in existing) if (!File(path).existsSync() && !Directory(path).existsSync()) path];
}
