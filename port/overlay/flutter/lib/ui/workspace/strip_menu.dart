// The photo strip's right-click menu, in the photo library's order: edits, export, rating, the
// file, closing. It acts on the photos chosen in the strip when the click is on one of them, and
// on the photo clicked otherwise. In a browser there are no files to show, rename or trash. An edit to one photo shows it first, importing a waiting one;
// its rating and its file are changed where it lies.
import 'package:flutter/widgets.dart';

import '../../app/host_window.dart';
import '../../model/editor.dart';
import '../../model/presets.dart' show pasteTitle;
import '../kit/kit.dart';
import 'editing_dialogs.dart';
import 'export_dialog.dart';
import 'library/library_dialogs.dart';

void showStripMenu(BuildContext context, EditorModel editor, StripItem item, Offset position) {
  final strip = editor.strip, library = editor.library, presets = editor.presets;
  final targets = strip.targetsOf(item);
  final single = targets.length == 1;
  final files = [for (final t in targets) t.path];
  final items = strip.items;

  // Edits go to the chosen photos, the shown one among them; one photo is shown first.
  Future<void> edit(VoidCallback action) async {
    if (single && (item.doc == null || item.doc != editor.active)) await strip.choose(item);
    if (context.mounted) action();
  }

  // Stars for photos of library folders; ratings are kept per folder.
  final keys = [for (final f in files) ?library.keyOf(f)];
  final rated = keys.length == files.length;
  final ratings = {for (final k in keys) library.ratingOf(k)};
  final rating = ratings.length == 1 ? ratings.single : null;

  showMenuAt(context, position, width: 220, [
    if (single)
      MenuItem(label: '复制设置…', onSelected: () => edit(() => showCopySettingsDialog(context, editor))),
    MenuItem(
      label: pasteTitle(targets.length),
      onSelected: presets.copied == null ? null : () => edit(presets.paste),
    ),
    MenuItem(label: '应用预设', submenu: [
      for (final preset in presets.list)
        MenuItem(label: preset.name, onSelected: () => edit(() => presets.applyPreset(preset.id))),
    ]),
    MenuItem(label: '重置调整', onSelected: () => edit(presets.reset)),
    const MenuItem.divider(),
    MenuItem(label: '导出…', onSelected: () => edit(() => showExportDialog(context, editor))),
    if (rated) ...[
      const MenuItem.divider(),
      MenuItem(label: '评分', submenu: [
        for (var stars = 5; stars >= 1; stars--)
          MenuItem(
            label: '$stars Star${stars > 1 ? 's' : ''}',
            checked: rating == stars,
            selection: MenuSelection.single,
            onSelected: () => library.rate(keys, stars),
          ),
        MenuItem(
          label: '无评分',
          checked: rating == 0,
          selection: MenuSelection.single,
          onSelected: () => library.rate(keys, 0),
        ),
      ]),
    ],
    // A browser holds the photos it was given, not files on a disk.
    if (HostWindow.showsFiles) ...[
      const MenuItem.divider(),
      MenuItem(label: HostWindow.revealLabel, onSelected: () => HostWindow.reveal(files)),
      if (single)
        MenuItem(
          label: '重命名…',
          onSelected: () => showRenameDialog(context, item.name, (name) => library.renameAt(item.path, name)),
        ),
      MenuItem(
        label: '移到回收站…',
        onSelected: () => showConfirmDialog(
          context,
          title: single ? '将「${item.name}」移到回收站？' : '将 ${files.length} 张照片移到回收站？',
          action: '移到回收站',
          onConfirm: () => library.trashFiles(files),
        ),
      ),
    ],
    const MenuItem.divider(),
    MenuItem(
      label: !single
          ? '关闭 ${targets.length} 张照片'
          : item.waiting
              ? '从底片条移除'
              : '关闭',
      onSelected: () => strip.closeAll(targets),
    ),
    MenuItem(
      label: '关闭其他',
      onSelected: items.length > targets.length
          ? () => strip.closeAll([for (final i in items) if (!files.contains(i.path)) i])
          : null,
    ),
    MenuItem(label: '全部关闭', onSelected: () => strip.closeAll(items)),
  ]);
}
