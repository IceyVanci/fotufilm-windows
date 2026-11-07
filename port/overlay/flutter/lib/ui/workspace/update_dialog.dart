// Check for Updates' answers, as the Mac app's alerts give them: a notice, a release on offer, or
// its download with progress.
import 'package:flutter/widgets.dart';

import '../../model/editor.dart';
import '../../model/updates.dart';
import '../kit/kit.dart';
import '../theme/theme.dart';
import 'app_dialogs.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.editor, required this.onClose});
  final EditorModel editor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: editor.updates,
        builder: (context, _) => switch (editor.updates.update) {
          null => const SizedBox.shrink(),
          final UpdateNotice notice => AlertCard(
              title: notice.title,
              message: notice.message,
              warning: notice.warning,
              primary: '确定',
              onPrimary: onClose,
            ),
          final UpdateDownloading download => _downloading(context, download),
          final UpdateAvailable offer => _offer(offer),
        },
      );

  Widget _downloading(BuildContext context, UpdateDownloading download) {
    final known = download.total > 0;
    return AppDialogCard(
      title: '正在下载 Fotufilm ${download.version}…',
      width: 400,
      actions: [PillButton('取消', onPressed: editor.updates.cancel)],
      children: [
        const Text('下载文件与其发布时公布的校验值一致后，安装程序就会打开。'),
        const SizedBox(height: 14),
        ProgressBar(value: known ? download.bytes / download.total : null),
        const SizedBox(height: 6),
        Text(
          known
              ? '${formatBytes(download.bytes)} / ${formatBytes(download.total)}'
              : '正在连接…',
          style: editorText(context, size: TextSizes.label, color: Palette.of(context).muted),
        ),
      ],
    );
  }

  Widget _offer(UpdateAvailable offer) => AppDialogCard(
        title: 'Fotufilm ${offer.version} 可更新',
        width: 640,
        actions: [
          if (offer.notes != null) PillButton('发行说明', onPressed: editor.updates.openNotes),
          if (offer.allowSkip) PillButton('跳过此版本', onPressed: editor.updates.skip),
          PillButton('以后再说', onPressed: onClose),
          PillButton('下载并安装…',
              variant: ButtonVariant.accent, onPressed: editor.updates.install),
        ],
        children: [
          Text('您当前是 Fotufilm ${offer.current}。更新以已签名的安装程序形式发布，与本副本的安装方式相同。安装时可能会要求管理员密码。'),
        ],
      );
}
