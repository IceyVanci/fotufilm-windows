// A scanned negative's Roll panel: what the frames of its roll share. The roll is the strip's
// negatives from the frame's folder; its colour balance is measured on all of them and kept with
// each, every frame still timed on its own highlights.
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
  return [
    Section(title: '整卷', children: [
      InfoRow('帧数', frames.isEmpty ? '不在文件夹中' : '${frames.length}'),
    ]),
    Section(title: '色彩平衡', children: [
      InfoRow('平衡基准', roll != null ? 'Roll of ${roll['frames']} frames' : '本帧'),
      if (measuring != null) ...[
        ScanProgress(
          label: '正在测量第 ${(measuring.done + 1).clamp(1, measuring.total)} / ${measuring.total} 格',
          value: measuring.done / measuring.total,
        ),
        ScanButton('取消', onPressed: scans.cancelMeasure),
      ] else
        ScanButton(roll != null ? '重新测量整卷' : '测量整卷',
            onPressed: disabled || !enough ? null : scans.measureRoll),
      ScanButton('仅平衡本帧',
          onPressed: disabled || roll == null ? null : scans.unrollFrame),
      ScanButton('逐帧独立平衡',
          onPressed: disabled || !enough ? null : scans.clearRoll),
      ScanHint(enough
          ? '同一卷、同一光源下拍摄的画面共用该卷高光的色彩。每格保持各自的曝光。裁剪或增删画幅后请重新测量。'
          : '从负片库文件夹打开一格：整卷即该文件夹中的所有负片。'),
    ]),
  ];
}
