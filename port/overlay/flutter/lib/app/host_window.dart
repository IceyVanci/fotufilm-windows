// The window the editor runs in. On macOS the toolbar shares the titlebar, so the toolbar drags
// and zooms the window and leaves room for the traffic lights; photographs opened from the Finder
// arrive here. Elsewhere the system draws the titlebar, and in a browser the page is the window;
// there these are no-ops.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'host_windows_stub.dart' if (dart.library.io) 'host_windows.dart' as shell;

abstract final class HostWindow {
  static const _channel = MethodChannel('fotufilm/window');

  static bool get _macApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// The toolbar is the titlebar (macOS's full-size content view).
  static bool get toolbarIsTitlebar => _macApp;

  /// Commands are the system's menu bar.
  static bool get usesMenuBar => _macApp;

  /// Shortcuts use ⌘ rather than Ctrl: on a Mac, in the app or in a browser.
  static bool get commandKeyIsMeta => defaultTargetPlatform == TargetPlatform.macOS;

  static Future<void> startDrag() => _call('startDrag');
  static Future<void> zoom() => _call('zoom');

  /// Names the window (Window menu, Mission Control, the Dock).
  static Future<void> setTitle(String title) => _call('setTitle', title);

  /// Photographs the system asked the app to open, and from then on calls `open` as more come.
  /// `arguments` are main's: Linux and Windows runners pass the command line there.
  static Future<List<String>> takeOpenedFiles(Future<void> Function(List<String>) open,
      {List<String> arguments = const []}) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') await open((call.arguments as List).cast<String>());
    });
    final paths = [...arguments.where((a) => !a.startsWith('-'))];
    try {
      paths.addAll(await _channel.invokeListMethod<String>('takeOpenedFiles') ?? const []);
    } on MissingPluginException {
      // No native side on this platform.
    }
    return paths;
  }

  /// Files are on a disk the system can open and show; in a browser an export is a download.
  static bool get showsFiles => !kIsWeb;

  /// The Mac app generates a sample chart; other builds have nothing to open.
  static bool get hasSamplePhoto => _macApp;

  /// The system keeps the list of recently opened files; only the Mac app's runs do.
  static bool get hasRecentFiles => _macApp;

  /// What showing a file in the system's file manager is called.
  static String get revealLabel =>
      defaultTargetPlatform == TargetPlatform.macOS ? '在访达中显示' : '在资源管理器中显示';

  /// Where the file manager is, for a plug-in's Show… command.
  static String get fileManager =>
      defaultTargetPlatform == TargetPlatform.macOS ? '在访达中显示' : '在资源管理器中显示';

  /// Whether the system's own file manager and browser are reached through the Windows host.
  static bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Shows files in the Finder, or in Explorer on Windows.
  static Future<void> reveal(List<String> paths) async {
    if (_windows) {
      shell.reveal(paths);
      return;
    }
    await _call('reveal', paths);
  }

  /// Opens a file in the app the system chooses for it.
  static Future<bool> openFile(String path) async {
    if (_windows) return shell.openFile(path);
    return await _call('openFile', path) == true;
  }

  /// Opens a web address in the browser.
  static Future<bool> openUrl(String url) async {
    if (_windows) return shell.openUrl(url);
    return await _call('openURL', url) == true;
  }

  /// File › Use Sample Photo's picture, the generated chart in the app's resources.
  static Future<String?> samplePhoto() async => await _call('samplePhoto') as String?;

  /// Photographs opened from the Open panel join File › Open Recent.
  static Future<void> noteRecent(List<String> paths) => _call('noteRecent', paths);

  /// Moves files to the Trash, or to the Recycle Bin on Windows; answers the paths that went.
  static Future<List<String>> trash(List<String> paths) async {
    if (_windows) return shell.trash(paths);
    return ((await _call('trash', paths)) as List?)?.cast<String>() ?? const [];
  }

  static Future<Object?> _call(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod(method, arguments);
    } on MissingPluginException {
      // No native side on this platform.
      return null;
    }
  }
}
