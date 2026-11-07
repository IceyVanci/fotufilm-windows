// Browser support, as the More menu opens it, and the menu's Legal links (the catalogue's
// LEGAL_MENU), which open in the browser.
import 'package:flutter/widgets.dart';

import '../../app/host_window.dart';
import '../../model/catalogue.dart';
import '../kit/kit.dart';
import '../theme/theme.dart';
import 'app_dialogs.dart';

class SupportDialog extends StatelessWidget {
  const SupportDialog({super.key, required this.onClose});
  final VoidCallback onClose;

  static const _copy = [
    'Photos and videos are processed on this device. WebGPU is used when available, with '
        'WebAssembly CPU 回退。',
    '较小的预览可让拖动更流畅。操作停下后，可见画面会按显示器像素分辨率显影；导出则按所选尺寸显影整幅图像。',
    'The browser supports film selection and format, ageing, halation, grain models, push/pull, '
        'bleach bypass, colour separation, print viewing, a simulated printer, an ordered '
        'lens-filter stack, automatic and manual lens correction, Auto Adjust, photo frames, '
        'light and color adjustments, three-way grading, color and light selections, crop, '
        'rotation and flip. Camera RAW files use as-shot white balance. RAW, linear EXR and '
        'supported HDR JPEG gain maps preserve decoded highlight detail before film exposure.',
    'Scanned-negative conversion, automatic subject selections, custom packs, and HDR export are '
        'available in the Mac app. Still previews and exports use Display P3 where supported; '
        'TIFF preserves 16-bit Display P3 precision. Other browsers use sRGB for canvas output.',
  ];

  @override
  Widget build(BuildContext context) => AppDialogCard(
        title: '浏览器支持',
        onDismiss: onClose,
        children: [
          for (final p in _copy)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(p,
                  style: editorText(context, color: Palette.of(context).muted, height: 1.7)),
            ),
        ],
      );
}

/// The More menu's Legal section: each link opens in the browser.
List<MenuItem> legalMenuItems(Catalogue catalogue) => [
      for (final link in ((catalogue.module['LEGAL_MENU'] as Map?)?['links'] as List? ?? const [])
          .cast<Json>())
        MenuItem(
          label: link['title'] as String,
          icon: link['icon'] as String?,
          link: true,
          onSelected: () => HostWindow.openUrl(link['href'] as String),
        ),
    ];
