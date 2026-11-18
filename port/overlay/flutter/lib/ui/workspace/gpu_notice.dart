// A thin strip under the toolbar while the machine has no Vulkan device: the Windows engine has no
// CPU developer, so photographs cannot develop there until a Vulkan GPU and its driver are present.
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'gpu_probe_web.dart' if (dart.library.io) 'gpu_probe_io.dart';


class GpuNotice extends StatelessWidget {
  const GpuNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (!noVulkanDevice) return const SizedBox.shrink();
    final palette = Palette.of(context);
    return Container(
      height: 28,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Text(
        '未检测到支持 Vulkan 的显卡，Fotufilm 无法出图。请更新显卡驱动，或换用支持 Vulkan 的显卡。',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: palette.text),
      ),
    );
  }
}
