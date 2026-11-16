// A scanned negative's Roll panel: what the frames of its roll share. The roll is the strip's
// negatives from the frame's folder; what they share is measured on all of them and kept with
// each, every frame still timed on its own highlights. A frame is balanced on its measured roll
// unless its Balance, with the light's white balance, says otherwise; an edit saved with an
// earlier reading is balanced on its roll while it keeps one.
import 'package:flutter/widgets.dart';

import '../kit/kit.dart';
import 'controls.dart';
import 'scan_controls.dart';

List<Widget> rollPanel(InspectorControls c) {
  final scans = c.editor.negatives;
  final negative = scans.negative;
  if (negative == null) return const [];
  final roll = negative['roll'] as Map?;
  final frames = scans.rollFrames;
  final measuring = scans.measuring;
  final disabled = measuring != null;
  final enough = frames.length >= 2;
  final current = scans.readsCurrent;
  return [
    Section(title: '整卷', children: [
      InfoRow('帧数', frames.isEmpty ? '不在文件夹中' : '${frames.length}'),
    ]),
    Section(title: '色彩平衡', children: [
      if (current)
        InfoRow('测量依据', roll != null ? '整卷 ${roll['frames']} 格' : '未测量')
      else
        InfoRow('平衡依据', roll != null ? '整卷 ${roll['frames']} 格' : '本帧'),
      if (measuring != null) ...[
        ScanProgress(
          label: '正在测量第 ${(measuring.done + 1).clamp(1, measuring.total)} / ${measuring.total} 格',
          value: measuring.done / measuring.total,
        ),
        ScanButton('取消', onPressed: scans.cancelMeasure),
      ] else
        ScanButton(roll != null ? '重新测量整卷' : '测量整卷',
            onPressed: disabled || !enough ? null : scans.measureRoll),
      if (current)
        ScanButton('清除整卷测量',
            onPressed: disabled || roll == null ? null : scans.clearRoll)
      else ...[
        ScanButton('仅平衡本帧',
            onPressed: disabled || roll == null ? null : scans.unrollFrame),
        ScanButton('逐帧独立平衡',
            onPressed: disabled || !enough ? null : scans.clearRoll),
      ],
      ScanHint(!enough
          ? '从负片库文件夹打开一帧：整卷即该文件夹中的所有负片。'
          : current
              ? '同一卷拍摄的画面共用其透明片基、共同呈现的画面内容，以及彼此之间的色彩陡度。每帧按这些平衡，除非其“平衡”连同白平衡设为“本帧”或“无”。陡度在六帧显示出后才会采用。每帧保持各自的曝光。裁剪或增减画幅后请重新测量。'
              : '同一卷、同一光源下拍摄的画面共用该卷高光的色彩。每帧保持各自的曝光。裁剪或增减画幅后请重新测量。'),
    ]),
  ];
}
