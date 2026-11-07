// About: which build this is, which Fotufilm it is a port of, and the terms it ships under.
import 'package:flutter/widgets.dart';

import '../../app/build_info.dart';
import '../../app/host_window.dart';
import '../kit/kit.dart';
import '../theme/theme.dart';
import 'app_dialogs.dart';

class AboutDialog extends StatelessWidget {
  const AboutDialog({super.key, required this.onClose});
  final VoidCallback onClose;

  static const _upstream = 'https://fotufilm.com';

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    TextStyle body() => editorText(context, color: palette.muted, height: 1.7);
    return AppDialogCard(
      title: 'Fotufilm 胶片暗房',
      onDismiss: onClose,
      children: [
        Text('Windows 移植 $kBuildPortVersion', style: editorText(context, height: 1.6)),
        const SizedBox(height: 4),
        Text('基于 Fotufilm $kBuildUpstreamVersion · $_upstream', style: body()),
        if (kBuildDate.isNotEmpty) Text('构建于 $kBuildDate', style: body()),
        const SizedBox(height: 14),
        Text(
          '这是 Fotufilm 的非官方 Windows 移植，含简体中文界面。'
          '与 MUAStudio Inc. 无隶属、授权或赞助关系。',
          style: body(),
        ),
        const SizedBox(height: 10),
        Text(
          '程序代码按 Apache-2.0 授权；胶片配置与编辑器字形按 CC BY-SA 4.0 授权，'
          '版权归 MUAStudio Inc.，取自 $_upstream。',
          style: body(),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          PillButton('打开上游主页', onPressed: () => HostWindow.openUrl(_upstream)),
          PillButton('关闭', variant: ButtonVariant.accent, onPressed: onClose),
        ]),
      ],
    );
  }
}
