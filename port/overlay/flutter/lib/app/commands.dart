// The editor's commands, listed once: the commands by their ids, which apply now and which are
// ticked, and the menu bar that holds them, with its order, separators and key equivalents.
//
// On macOS the menu bar is the system's, built natively from `mainMenu` (native_menu.dart and
// MainFlutterWindow.swift's MainMenu) rather than with Flutter's PlatformMenuBar: Flutter's menu
// items carry no checked state, and a ✓ in the title would shift the titles and say nothing to
// VoiceOver. The native menu ticks items with NSMenuItem.state, words them (Undo Light, Install as
// Reinstall) and greys them. On Linux and Windows, which have no menu bar here, the same key
// equivalents answer with Ctrl in place of ⌘.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/app_dialogs.dart';
import '../model/editor.dart';
import '../model/negative_document.dart';
import '../model/presets.dart' show pasteTitle;
import '../model/saved_edits.dart' show fixedStockSettings;
import '../ui/kit/popover.dart' show openModals;
import '../ui/workspace/film_pack_notice.dart';
import 'host_window.dart';

// ── Key equivalents ─────────────────────────────────────────────────────────────────────────

/// A menu item's key equivalent: ⌘ (Ctrl on Linux and Windows) with a character and the other
/// modifiers it names.
class KeyEquivalent {
  const KeyEquivalent(this.key, {this.shift = false, this.alt = false, this.control = false});

  /// The character, lower case: 'e', '+', ',', '\\', '1'.
  final String key;
  final bool shift, alt, control;

  /// ⌃⌘ shortcuts have no Ctrl form: Ctrl is already ⌘ there.
  bool get offeredWithCtrl => !control;

  /// The shortcut as the platform writes it: ⌥⇧⌘Z on a Mac, Ctrl+Alt+Shift+Z elsewhere.
  String label({bool? mac}) {
    final shown = key.length == 1 ? key.toUpperCase() : key;
    if (mac ?? HostWindow.commandKeyIsMeta) {
      return '${control ? '⌃' : ''}${alt ? '⌥' : ''}${shift ? '⇧' : ''}⌘$shown';
    }
    return ['Ctrl', if (alt) 'Alt', if (shift) 'Shift', shown].join('+');
  }

  /// Whether `event` types this shortcut with the modifiers `keys` holds. A character that takes
  /// Shift to type (⌘+, ⌘?) matches with or without it.
  bool matches(KeyEvent event, HardwareKeyboard keys, {bool? mac}) {
    final isMac = mac ?? HostWindow.commandKeyIsMeta;
    if (!isMac && control) return false;
    final command = isMac ? keys.isMetaPressed : keys.isControlPressed;
    final ctrl = isMac ? keys.isControlPressed : false;
    if (!command || keys.isAltPressed != alt || ctrl != control) return false;
    if (!isMac && keys.isMetaPressed) return false;
    final typed = typedCharacter(event);
    if (typed == null || typed != key) return false;
    final letter = RegExp(r'^[a-z]$').hasMatch(key);
    return !letter || keys.isShiftPressed == shift;
  }

  /// The character a key types without modifiers, as menus compare it; null for keys that type
  /// none.
  static String? typedCharacter(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd) return '+';
    if (key == LogicalKeyboardKey.equal) return '+';
    if (key == LogicalKeyboardKey.numpadSubtract) return '-';
    if (key == LogicalKeyboardKey.question) return '?';
    if (key == LogicalKeyboardKey.slash && HardwareKeyboard.instance.isShiftPressed) return '?';
    final label = key.keyLabel;
    return label.length == 1 ? label.toLowerCase() : null;
  }

  Json toJson() => {
        'key': key,
        'modifiers': [if (control) 'control', if (alt) 'option', if (shift) 'shift', 'command'],
      };
}

// ── The menu bar's structure ────────────────────────────────────────────────────────────────

sealed class MenuNode {
  const MenuNode();
  Json toJson();
}

/// An item that runs one of the editor's commands (main_menu.mm `Command`).
class CommandNode extends MenuNode {
  const CommandNode(this.id, this.title, [this.key]);
  final String id, title;
  final KeyEquivalent? key;

  @override
  Json toJson() => {'command': id, 'title': title, if (key != null) ...key!.toJson()};
}

class SeparatorNode extends MenuNode {
  const SeparatorNode();

  @override
  Json toJson() => {'separator': true};
}

/// A submenu. One the editor fills (`list`: films, presets, history) is built as it is pulled
/// down, from the latest state, above its fixed items; `empty` stands in when the list is.
class SubmenuNode extends MenuNode {
  const SubmenuNode(this.title, this.items, {this.list, this.empty, this.role});
  final String title;
  final List<MenuNode> items;
  final String? list, empty;

  /// The system's own menu: services, window, help.
  final String? role;

  @override
  Json toJson() => {
        'title': title,
        'items': [for (final item in items) item.toJson()],
        'list': ?list,
        'empty': ?empty,
        'role': ?role,
      };
}

/// An item the system answers (About, Hide, Quit, Minimize, Open Recent, the Help pages…);
/// macOS only.
class NativeNode extends MenuNode {
  const NativeNode(this.role, this.title, {this.key, this.page});
  final String role, title;
  final KeyEquivalent? key;

  /// A Help page on fotufilm.com.
  final String? page;

  @override
  Json toJson() =>
      {'native': role, 'title': title, 'page': ?page, if (key != null) ...key!.toJson()};
}

const _separator = SeparatorNode();

/// The inspector's tabs in the order ⌘1…⌘6 choose them (`MENU_PANELS`), with their menu titles.
const menuPanels = [
  ('film', '胶片'),
  ('light', '曝光'),
  ('develop', '显影'),
  ('print', '印放'),
  ('selective', '选择性'),
  ('crop', '裁剪'),
];

/// The menu bar (main_menu.mm `FotufilmMainMenu`): `plugins` are the engine's {id, name}.
List<SubmenuNode> mainMenu(List<Json> plugins) => [
      SubmenuNode('Fotufilm', [
        // The Mac app has the system's About panel; elsewhere the editor draws its own.
        if (HostWindow.usesMenuBar)
          NativeNode('about', '关于 Fotufilm')
        else
          const CommandNode('about', '关于 Fotufilm'),
        _separator,
        CommandNode('checkForUpdates', '检查更新…'),
        CommandNode('autoUpdates', '自动检查更新'),
        _separator,
        CommandNode('settings', '设置…', KeyEquivalent(',')),
        _separator,
        NativeNode('services', '服务'),
        _separator,
        NativeNode('hide', '隐藏 Fotufilm', key: KeyEquivalent('h')),
        NativeNode('hideOthers', '隐藏其他', key: KeyEquivalent('h', alt: true)),
        NativeNode('showAll', '显示全部'),
        _separator,
        NativeNode('quit', '退出 Fotufilm', key: KeyEquivalent('q')),
      ]),
      SubmenuNode('文件', [
        CommandNode('open', '打开…', KeyEquivalent('o')),
        CommandNode('importNegative', '导入扫描负片…'),
        CommandNode('importTrichromatic', '导入三色分光扫描…'),
        // A dead menu entry is worse than a missing one: these two need the Mac app's host.
        if (HostWindow.hasRecentFiles) NativeNode('openRecent', '最近打开'),
        if (HostWindow.hasSamplePhoto) CommandNode('useSamplePhoto', '使用示例照片'),
        _separator,
        CommandNode('importFilmPack', '导入胶片包…', KeyEquivalent('i', shift: true)),
        _separator,
        CommandNode('export', '导出…', KeyEquivalent('e')),
        _separator,
        CommandNode('closePhoto', '关闭照片', KeyEquivalent('w', shift: true)),
        NativeNode('closeWindow', '关闭窗口', key: KeyEquivalent('w')),
      ]),
      // Undo, Redo and the clipboard belong to a focused text field, or Undo and Redo to the
      // photograph's history, named after the step they change.
      const SubmenuNode('编辑', [
        CommandNode('undo', '撤销', KeyEquivalent('z')),
        CommandNode('redo', '重做', KeyEquivalent('z', shift: true)),
        SubmenuNode('编辑历史', [], list: 'history', empty: '没有打开的编辑'),
        _separator,
        CommandNode('autoAdjust', '自动调整', KeyEquivalent('a', shift: true)),
        CommandNode('sampleSelection', '取样选区', KeyEquivalent('s', shift: true)),
        _separator,
        CommandNode('cut', '剪切', KeyEquivalent('x')),
        CommandNode('copy', '复制', KeyEquivalent('c')),
        CommandNode('paste', '粘贴', KeyEquivalent('v')),
        CommandNode('selectAll', '全选', KeyEquivalent('a')),
        _separator,
        CommandNode('copyPhoto', '复制照片', KeyEquivalent('c', shift: true)),
        _separator,
        CommandNode('copySettings', '复制设置…', KeyEquivalent('c', alt: true)),
        CommandNode('pasteSettings', '粘贴设置', KeyEquivalent('v', alt: true)),
        SubmenuNode('预设', [
          CommandNode('savePreset', '保存预设…'),
          CommandNode('managePresets', '管理预设…'),
          CommandNode('importLooks', '导入风格…'),
        ], list: 'presets', empty: '没有预设'),
      ]),
      const SubmenuNode('胶片', [
        SubmenuNode('选择胶片', [], list: 'films', empty: '无胶片'),
        _separator,
        CommandNode('newGrainPattern', '新建颗粒图案', KeyEquivalent('g', shift: true)),
        SubmenuNode('颗粒模型', [
          CommandNode('grainModel:clump', '标准'),
          CommandNode('grainModel:film', '胶片'),
        ]),
        CommandNode('estimatedHalation', '光晕形状估计（高级）'),
        _separator,
        CommandNode('autoFilm', '为每张照片选择胶片'),
        CommandNode('forgetFilms', '忘记我教过它的内容'),
        _separator,
        CommandNode('resetEdits', '重置全部调整', KeyEquivalent('r', shift: true)),
      ]),
      SubmenuNode('视图', [
        // ⌘+ rather than ⌘=: the menu shows characters, as the Mac app's does.
        const CommandNode('zoomIn', '放大', KeyEquivalent('+')),
        const CommandNode('zoomOut', '缩小', KeyEquivalent('-')),
        const CommandNode('zoomToFit', '适合窗口', KeyEquivalent('0')),
        _separator,
        const CommandNode('showOriginal', '显示原图', KeyEquivalent('\\')),
        const CommandNode('showNegative', '显示负片', KeyEquivalent('n', alt: true)),
        const CommandNode('histogram', '显示直方图', KeyEquivalent('h', control: true)),
        const CommandNode('play', '播放'),
        _separator,
        const CommandNode('filmSidebar', '胶片库', KeyEquivalent('s', control: true)),
        const CommandNode('inspector', '检查器', KeyEquivalent('i', alt: true)),
        // The inspector's tabs, numbered as they are stacked.
        _separator,
        for (final (i, (id, title)) in menuPanels.indexed)
          CommandNode('panel:$id', title, KeyEquivalent('${i + 1}')),
        _separator,
        const NativeNode('fullScreen', '进入全屏', key: KeyEquivalent('f', control: true)),
      ]),
      // Two items per editor, named after it; Install reads Reinstall once the plug-in is there.
      if (plugins.isNotEmpty)
        SubmenuNode('插件', [
          for (final (i, p) in plugins.indexed) ...[
            if (i > 0) _separator,
            CommandNode('installPlugin:${p['id']}', 'Install ${p['name']} Plug-in…'),
            CommandNode('revealPlugin:${p['id']}', 'Show ${p['name']} Plug-in ${HostWindow.fileManager}'),
          ],
        ]),
      const SubmenuNode('窗口', [
        NativeNode('minimize', '最小化', key: KeyEquivalent('m')),
        NativeNode('zoom', '缩放'),
        _separator,
        NativeNode('bringAllToFront', '前置全部窗口'),
      ], role: 'window'),
      // The same pages the native Mac app opens.
      const SubmenuNode('帮助', [
        NativeNode('help', 'Fotufilm 帮助', page: 'support', key: KeyEquivalent('?')),
        _separator,
        NativeNode('help', '第三方声明', page: 'third-party'),
        NativeNode('help', '使用条款', page: 'terms'),
        NativeNode('help', '隐私政策', page: 'privacy'),
      ], role: 'help'),
    ];

/// Every command item of `menus`, submenus included.
Iterable<CommandNode> commandNodes(List<MenuNode> menus) sync* {
  for (final node in menus) {
    if (node is CommandNode) yield node;
    if (node is SubmenuNode) yield* commandNodes(node.items);
  }
}

// ── What applies now ────────────────────────────────────────────────────────────────────────

/// Which commands apply and which are ticked, what the changing ones are called, the Edit
/// History's steps and the lists the editor fills (films, presets), with whether a text field
/// has the keys.
class CommandState {
  CommandState({
    required this.enabled,
    required this.checked,
    required this.titles,
    required this.toolTips,
    required this.history,
    required this.menus,
    required this.textInput,
  });

  final Set<String> enabled, checked;
  final Map<String, String> titles, toolTips;
  final List<String> history;

  /// [command, title] pairs: `films` and `presets`.
  final Map<String, List<(String, String)>> menus;
  final bool textInput;

  bool isEnabled(String id) => enabled.contains(id);
  bool isChecked(String id) => checked.contains(id);
  String title(String id, String fallback) => titles[id] ?? fallback;

  /// The items of a list the editor fills: [command, title] pairs.
  List<(String, String)> list(String name) => name == 'history'
      ? [for (final (i, t) in history.indexed) ('history:$i', t)]
      : menus[name] ?? const [];

  Json toJson() => {
        'enabled': (enabled.toList()..sort()),
        'checked': (checked.toList()..sort()),
        'titles': titles,
        'toolTips': toolTips,
        'history': history,
        'menus': {
          for (final MapEntry(:key, :value) in menus.entries)
            key: [for (final (id, title) in value) [id, title]],
        },
        'textInput': textInput,
      };
}

/// What commands open that need the window: the file chooser, the export and settings dialogs.
class CommandActions {
  const CommandActions({
    required this.open,
    required this.export,
    required this.copySettings,
    required this.savePreset,
    required this.managePresets,
    required this.importLooks,
  });
  final VoidCallback open, export, copySettings, savePreset, managePresets, importLooks;
}

/// Commands that edit a focused text field rather than the photograph.
const textCommands = {'undo', 'redo', 'cut', 'copy', 'paste', 'selectAll'};

/// Whether a text field has the keys.
bool textFieldFocused() {
  final focus = FocusManager.instance.primaryFocus?.context;
  return focus != null &&
      (focus.widget is EditableText || focus.findAncestorWidgetOfExactType<EditableText>() != null);
}

class EditorCommands {
  EditorCommands(this.editor, this.actions) {
    shown = this;
  }
  final EditorModel editor;
  final CommandActions actions;

  /// The commands of the window on show, for the driver.
  static EditorCommands? shown;

  /// The menu bar, for the plug-ins this engine installs.
  List<SubmenuNode> get menus => mainMenu(editor.plugins.catalogue);

  // ── State ───────────────────────────────────────────────────────────────────────────────

  /// A dialog covers the photo.
  bool get _dialog => openModals.value > 0;

  /// A photo is open on a film whose model its settings may change.
  bool get _filmModelled =>
      !editor.exporting &&
      !editor.library.open &&
      !_dialog &&
      editor.active != null &&
      editor.edit['stock'] != null &&
      !fixedStockSettings(editor.selectedStock);

  /// What the Film Model items show: the open photo's, else what a new photo starts with.
  String get _grainModelShown => _filmModelled
      ? ((editor.edit['profile'] as Map?)?['grainModel'] as String? ?? 'clump')
      : editor.settings.get<String>('grainModel') ?? 'clump';
  bool get _estimatedHalationShown => _filmModelled
      ? ((editor.edit['profile'] as Map?)?['estimatedHalation']) == true
      : editor.settings.get<bool>('estimatedHalation') == true;

  /// The view's zoom against fit and the largest.
  String get _reach => !editor.zoomed
      ? 'fit'
      : editor.scale >= ViewState.maxZoom * .999
          ? 'max'
          : 'zoomed';

  CommandState state() {
    final e = editor;
    final settings = e.settings;
    // A dialog or the library covers the photo, as it does for the editor's own shortcuts.
    final free = !e.exporting && !e.library.open && !_dialog;
    final photo = free && e.active != null;
    final still = photo && e.active?.isMovie != true;
    final reach = _reach;
    final cropMode = e.crop.showing;
    final history = e.active?.history;
    final suggestion = e.filmSuggestion;
    final enabled = <String, bool>{
      'open': !e.exporting,
      'useSamplePhoto': !e.exporting,
      'importNegative': e.negatives.canImport && !_dialog,
      'importTrichromatic': e.negatives.canMerge && !_dialog,
      'export': photo && e.stocks.isNotEmpty,
      'closePhoto': photo,
      'undo': free && (history?.past.isNotEmpty ?? false),
      'redo': free && (history?.future.isNotEmpty ?? false),
      'autoAdjust': photo && e.auto.available,
      'sampleSelection': still && e.selective.canSample,
      'copyPhoto': still && e.exporter.canCopy,
      'copySettings': photo,
      'pasteSettings': photo && e.presets.copied != null,
      'savePreset': photo,
      'managePresets': free && e.presets.list.isNotEmpty,
      'importLooks': free,
      'resetEdits': photo,
      'newGrainPattern': photo && e.edit['stock'] != null,
      'settings': true,
      'checkForUpdates': e.updates.available,
      'autoUpdates': e.updates.available,
      'plugins': e.plugins.available && !e.exporting,
      'importFilmPack': e.filmPacks.available && !e.exporting,
      'autoFilm': suggestion.available,
      // Greyed with nothing learned, as the Mac app's is.
      'forgetFilms': suggestion.available && suggestion.learned != 0,
      'zoomIn': photo && !cropMode && reach != 'max',
      'zoomOut': photo && !cropMode && reach != 'fit',
      'zoomToFit': photo && reach != 'fit',
      'showOriginal': photo,
      'histogram': photo,
      'play': photo && e.active?.isMovie == true,
      'showNegative': photo && e.negatives.canShowNegativeNow,
      'filmSidebar': !e.library.open,
      'inspector': !e.library.open,
      for (final (id, _) in menuPanels)
        'panel:$id': offersPanel(e.edit, id) &&
            (id == 'selective' ? still : id == 'crop' ? photo : !e.library.open),
    };
    final checked = <String>{
      if (suggestion.available && settings.get<bool>('autoFilm') == true) 'autoFilm',
      if (e.updates.available && settings.get('updateChecksAutomatically') != false) 'autoUpdates',
      if (e.auto.active) 'autoAdjust',
      if (e.comparing) 'showOriginal',
      if (e.histogramOpen) 'histogram',
      if (e.negatives.showNegative) 'showNegative',
      if (e.filmOpen) 'filmSidebar',
      if (e.inspectorOpen) 'inspector',
      if (e.inspectorOpen) 'panel:${e.panel.id}',
    };

    // The film list, and the film model of the one loaded, where its settings are not fixed.
    final films = [
      ('film:none', '正常'),
      for (final s in e.stocks) ('film:${s['id']}', s['name'] as String),
    ];
    for (final (id, _) in films) {
      enabled[id] = photo;
    }
    final presets = [for (final p in e.presets.list) ('preset:${p.id}', p.name)];
    for (final (id, _) in presets) {
      enabled[id] = photo;
    }
    checked.add('film:${e.edit['stock'] ?? 'none'}');
    // App-wide, as the Mac app's Film Model items are: available with or without a photo.
    final grainModel = _grainModelShown;
    for (final model in ['clump', 'film']) {
      enabled['grainModel:$model'] = !e.exporting;
      if (grainModel == model) checked.add('grainModel:$model');
    }
    enabled['estimatedHalation'] = true;
    if (_estimatedHalationShown) checked.add('estimatedHalation');

    // The Edit History of the photograph shown, as the Mac app's Edit menu lists it.
    final timeline = e.history.timeline;
    for (var step = 0; step < timeline.titles.length; step++) {
      enabled['history:$step'] = free;
    }
    if (timeline.titles.isNotEmpty) checked.add('history:${timeline.index}');

    final titles = <String, String>{
      'undo': e.history.undo,
      'redo': e.history.redo,
      // What it will do next, as the Mac app names it.
      'play': e.video.playing ? '暂停' : '播放',
      'pasteSettings': pasteTitle(e.selection.chosen.length),
    };
    final toolTips = <String, String>{};
    _pluginState(enabled, titles, toolTips);

    // Undo, Redo and the clipboard go to a focused text field, plainly named (host_window.mm
    // `validateMenuItem`).
    final text = textFieldFocused();
    if (text) {
      titles.remove('undo');
      titles.remove('redo');
    }
    for (final id in textCommands) {
      enabled[id] = text || (enabled[id] ?? false);
    }
    return CommandState(
      enabled: {for (final MapEntry(:key, :value) in enabled.entries) if (value) key},
      checked: checked,
      titles: titles,
      toolTips: toolTips,
      history: timeline.titles,
      menus: {'films': films, 'presets': presets},
      textInput: text,
    );
  }

  /// Install reads Reinstall once the plug-in is there, and each item says why it is grey, as the
  /// Mac app's Plugins menu does.
  void _pluginState(Map<String, bool> enabled, Map<String, String> titles, Map<String, String> toolTips) {
    final plugins = editor.plugins;
    for (final p in plugins.catalogue) {
      final id = p['id'] as String, name = p['name'] as String;
      final status = plugins.status(id);
      final state = status?['state'];
      final installed = status != null && state != 'notInstalled' && state != 'notBundled';
      final bundled = status?['bundledVersion'] != null;
      enabled['installPlugin:$id'] = bundled && plugins.busy == null && !editor.exporting;
      enabled['revealPlugin:$id'] = installed;
      titles['installPlugin:$id'] = '${installed ? 'Reinstall' : '安装'} $name Plug-in…';
      if (status != null && !bundled) {
        toolTips['installPlugin:$id'] = '此 Fotufilm 副本不包含 $name 插件。';
      }
      toolTips['revealPlugin:$id'] = installed
          ? '${status['location'] ?? ''}'
          : '尚未安装 $name 插件。请先选择「安装 $name 插件…」。';
    }
  }

  // ── Running ─────────────────────────────────────────────────────────────────────────────

  /// Runs a command if it applies now; the menu's copy of the state may be a frame old.
  bool run(String id) {
    final action = _action(id);
    if (action == null || !state().isEnabled(id)) return false;
    action();
    return true;
  }

  /// Whether `id` names a command this editor runs.
  bool handles(String id) => _action(id) != null;

  VoidCallback? _action(String id) {
    final e = editor;
    final settings = e.settings;
    final fixed = _fixed[id];
    if (fixed != null) return () => fixed(this);
    final step = RegExp(r'^history:(\d+)$').firstMatch(id);
    if (step != null) return () => e.history.goTo(int.parse(step[1]!));
    final colon = id.indexOf(':');
    if (colon < 0) return null;
    final kind = id.substring(0, colon), value = id.substring(colon + 1);
    if (value.isEmpty) return null;
    return switch (kind) {
      'preset' => () => e.presets.applyPreset(value),
      'film' => () => e.chooseStock(value == 'none' ? null : value),
      'grainModel' => () {
          settings.set('grainModel', value);
          if (_filmModelled) e.setProfile('grainModel', value, grouped: false);
        },
      'panel' => () {
          final panel = Panel.values.where((p) => p.id == value).firstOrNull;
          if (panel != null) e.layout.choosePanel(panel);
        },
      // An install shows its progress and its answer in the plug-ins dialog.
      'installPlugin' => () {
          e.dialogs.request(AppDialog.plugins);
          e.plugins.install(value);
        },
      'revealPlugin' => () => e.plugins.reveal(value),
      _ => null,
    };
  }

  static final Map<String, void Function(EditorCommands c)> _fixed = {
    'open': (c) => c.actions.open(),
    'useSamplePhoto': (c) => HostWindow.samplePhoto().then((path) {
          if (path != null) c.editor.openPaths([path]);
        }),
    'undo': (c) => c._text(const UndoTextIntent(SelectionChangedCause.keyboard), c.editor.undo),
    'redo': (c) => c._text(const RedoTextIntent(SelectionChangedCause.keyboard), c.editor.redo),
    'cut': (c) => c._text(CopySelectionTextIntent.cut(SelectionChangedCause.keyboard), null),
    'copy': (c) => c._text(CopySelectionTextIntent.copy, null),
    'paste': (c) => c._text(const PasteTextIntent(SelectionChangedCause.keyboard), null),
    'selectAll': (c) => c._text(const SelectAllTextIntent(SelectionChangedCause.keyboard), null),
    'importNegative': (c) => c.editor.negatives.chooseNegatives(),
    'importTrichromatic': (c) => c.editor.negatives.chooseExposures(),
    'importFilmPack': (c) => chooseFilmPacks(c.editor),
    'export': (c) => c.actions.export(),
    'about': (c) => c.editor.dialogs.request(AppDialog.about),
    'settings': (c) => c.editor.dialogs.request(AppDialog.settings),
    'plugins': (c) => c.editor.dialogs.request(AppDialog.plugins),
    'closePhoto': (c) => c._closePhoto(),
    'autoAdjust': (c) => c.editor.auto.toggle(),
    'sampleSelection': (c) => c.editor.selective.startSampling(),
    'copyPhoto': (c) => c.editor.exporter.copyPhoto(),
    'copySettings': (c) => c.actions.copySettings(),
    'pasteSettings': (c) => c.editor.presets.paste(),
    'savePreset': (c) => c.actions.savePreset(),
    'managePresets': (c) => c.actions.managePresets(),
    'importLooks': (c) => c.actions.importLooks(),
    'resetEdits': (c) => c.editor.resetEdit(),
    'newGrainPattern': (c) => c.editor.newGrainPattern(),
    'autoFilm': (c) => c.editor.settings.set('autoFilm', c.editor.settings.get<bool>('autoFilm') != true),
    'checkForUpdates': (c) => c.editor.updates.check(),
    'autoUpdates': (c) => c.editor.settings
        .set('updateChecksAutomatically', c.editor.settings.get('updateChecksAutomatically') == false),
    'forgetFilms': (c) => c.editor.filmSuggestion.forget(),
    'zoomIn': (c) => c.editor.zoomIn(),
    'zoomOut': (c) => c.editor.zoomOut(),
    'zoomToFit': (c) => c.editor.setZoom(null),
    'showOriginal': (c) => c.editor.setComparing(!c.editor.comparing),
    'histogram': (c) => c.editor.toggleHistogram(),
    'showNegative': (c) => c.editor.negatives.toggleShowNegative(),
    // The same toggle as the player's Space.
    'play': (c) {
      if (!c.editor.video.disabled) c.editor.video.toggle();
    },
    // App-wide on the Mac, and so here: the setting new photos start with, and the open photo.
    'estimatedHalation': (c) {
      final on = !c._estimatedHalationShown;
      c.editor.settings.set('estimatedHalation', on);
      if (c._filmModelled) c.editor.setProfile('estimatedHalation', on, grouped: false);
    },
    'filmSidebar': (c) {
      c.editor.endEdit();
      c.editor.toggleFilm();
    },
    'inspector': (c) => c.editor.layout.toggleInspector(),
  };

  /// A text field's own edit when one has the keys, else the photograph's.
  void _text(Intent intent, VoidCallback? otherwise) {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (textFieldFocused() && focus != null) {
      Actions.maybeInvoke(focus, intent);
    } else {
      otherwise?.call();
    }
  }

  void _closePhoto() {
    final doc = editor.active;
    if (doc == null) return;
    final item = editor.strip.items.where((i) => i.doc == doc).firstOrNull;
    if (item != null) {
      editor.strip.close(item);
    } else {
      editor.closeDocument(editor.activeIndex);
    }
  }

  // ── Keys ────────────────────────────────────────────────────────────────────────────────

  /// The command whose key equivalent `event` types, if any.
  CommandNode? commandForKey(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    for (final node in commandNodes(menus)) {
      if (node.key?.matches(event, keys) ?? false) return node;
    }
    return null;
  }

  /// A key equivalent pressed: its command runs if it applies; one that does not goes nowhere. A
  /// focused text field keeps its own editing keys.
  KeyEventResult handleKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final node = commandForKey(event);
    if (node == null) return KeyEventResult.ignored;
    if (textCommands.contains(node.id) && textFieldFocused()) return KeyEventResult.ignored;
    run(node.id);
    return KeyEventResult.handled;
  }
}
