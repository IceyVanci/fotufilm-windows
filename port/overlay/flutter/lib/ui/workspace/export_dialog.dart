// The Export dialog: this photograph or all of them, the format (or the original RAW), the size the
// engine can develop, quality, metadata and HDR, what the file will be, and Cancel that stops an
// export in flight. A movie offers its formats, sizes, HDR, frame rate, processing and file
// size instead.
import 'package:flutter/widgets.dart';

import '../../model/editor.dart';
import '../../model/export.dart';
import '../kit/kit.dart';
import '../theme/theme.dart';
import 'dialogs.dart';
import 'video_controls.dart' show videoLabel;

void showExportDialog(BuildContext context, EditorModel editor) =>
    showModal(context, (close) => ExportDialog(editor: editor, onClose: close));

class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, required this.editor, required this.onClose});
  final EditorModel editor;
  final VoidCallback onClose;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  EditorModel get editor => widget.editor;
  ExportTool get exporter => editor.exporter;

  /// This Photo or All N Photos; each opening starts on the photo, or on the photos chosen in the
  /// strip when there are several.
  late String _scope = exporter.batchChosen ? 'all' : 'photo';

  @override
  void initState() {
    super.initState();
    exporter.loadOptions();
  }

  /// The dialog closes once the export is under way in the background, or when it is saved
  /// where the editor waits for it.
  Future<void> _export(bool batch) async {
    final saved = batch
        ? await exporter.exportAll(onStarted: _close)
        : await exporter.exportPhoto(onStarted: _close);
    if (saved != null) _close();
  }

  void _close() {
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: editor, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final doc = editor.active;
    if (doc == null) return const SizedBox.shrink();
    if (doc.isMovie) return _buildMovie(context, doc);
    final x = exporter;
    final exporting = editor.exporting;
    final count = x.batchCount;
    final batch = count > 1 && _scope == 'all';
    final originalAvailable = !batch && x.originalAvailable(doc);
    // A photograph with no camera RAW behind it has no original to export.
    if (x.type == originalType && !originalAvailable) x.type = x.types.first.$1;
    // DPX is one Cineon Log photograph's scan: not offered for a batch, or once the medium changes.
    final types = [for (final t in x.types) if (!batch || t.$1 != dpxType) t];
    if (x.type != originalType && !types.any((t) => t.$1 == x.type)) x.type = types.first.$1;
    final dpx = x.type == dpxType;
    final original = x.type == originalType;
    final sizes = x.sizes(batch: batch);
    final unavailable = x.unavailable(batch: batch);
    // The largest size it can develop stands in for one it cannot, as the Mac app selects.
    final sizeId = x.sizeId(batch: batch);
    if (x.size != sizeId) x.size = sizeId;
    final warning = resolutionLimitWarning(sizes, sizeId, unavailable);
    final hdrOffered = batch ? x.batchHDR : x.options?.hdr == true;
    final hdr = x.type == 'image/heic' && hdrOffered && x.hdr;
    final last = x.last;
    final delivered = x.delivered(doc);
    final metadata = x.options?.metadata;
    final palette = Palette.of(context);

    return DialogCard(
      title: batch ? '导出 $count 张照片' : '导出图片',
      width: 480,
      actions: [
        PillButton('取消', onPressed: exporting ? x.cancel : widget.onClose),
        PillButton(
          exporting
              ? '正在导出…'
              : original
                  ? '导出原始文件'
                  : batch
                      ? '导出 $count 张照片'
                      : '导出',
          variant: ButtonVariant.accent,
          onPressed: exporting || (!original && unavailable.contains(sizeId))
              ? null
              : () => _export(batch),
        ),
      ],
      children: [
        // The fieldset: nothing changes while an export runs.
        IgnorePointer(
          ignoring: exporting,
          child: Opacity(
            opacity: exporting ? .45 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (count > 1)
                _SelectRow('导出', PickerField<String>(
                  value: _scope,
                  options: [
                    const PickerOption('photo', '本张照片'),
                    PickerOption('all', x.batchChosen ? '已选 $count 张照片' : '全部 $count 张照片'),
                  ],
                  onChanged: (v) => setState(() => _scope = v),
                )),
              if (last != null && !_same(last, x.current))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  // In a row, so the button keeps its own width.
                  child: Row(children: [
                    PillButton('沿用上次导出设置', onPressed: x.applyLast),
                  ]),
                ),
              _SelectRow('画幅', PickerField<String>(
                value: x.type,
                options: [
                  for (final (id, label) in types) PickerOption(id, label),
                  if (originalAvailable) const PickerOption(originalType, '原始 RAW'),
                ],
                onChanged: (v) => setState(() => x.type = v),
              )),
              if (original)
                const _Detail('复制原始相机 RAW 文件。不包含 Fotufilm 编辑与分辨率设置。')
              else ...[
                _SelectRow('尺寸', PickerField<String>(
                  value: sizeId,
                  options: [
                    for (final s in sizes)
                      PickerOption(
                        s.id,
                        [s.label, ?s.detail, if (unavailable.contains(s.id)) '超出安全内存上限']
                            .join(' · '),
                        enabled: !unavailable.contains(s.id),
                      ),
                  ],
                  onChanged: (v) => setState(() => x.size = v),
                )),
                if (warning != null) _Detail(warning),
                if (lossyTypes.contains(x.type))
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: AdjustmentRow(
                      label: '质量',
                      value: x.quality.toDouble(),
                      range: const SliderRange(min: 1, max: 100, step: 1, def: 95),
                      onChanged: (v) => setState(() => x.quality = v.round()),
                    ),
                  ),
                if (metadata != null && !dpx)
                  _SelectRow('元数据', PickerField<String>(
                    value: x.metadata,
                    options: [
                      for (final id in metadata) PickerOption(id, metadataLabels[id] ?? id),
                    ],
                    onChanged: (v) => setState(() => x.metadata = v),
                  )),
                if (x.type == 'image/heic' && hdrOffered)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: SwitchRow(label: 'HDR', value: x.hdr, onChanged: (v) => x.hdr = v),
                  ),
                // The desktop engine writes Display P3, and a Cineon Log scan printing density.
                _Detail('${batch ? '$count photos' : '${delivered.width} × ${delivered.height} '
                    'pixels'} · '
                    '${dpx ? 'Cineon log · 10-bit' : 'Display P3 · '
                        '${x.type == 'image/tiff' ? '16-bit' : hdr ? 'HDR' : '8-bit'}'}'),
                if (dpx)
                  const _Detail('用于调色的印片密度。在 DaVinci Resolve 中按 Cineon Film Log 解读。'),
                _Detail(batch
                    ? '把每张照片按各自的胶片、裁剪与调整导出到同一文件夹。'
                    : '按当前裁剪与调整导出成片。'),
              ],
            ]),
          ),
        ),
        if (exporting)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(editor.status ?? '正在准备导出',
                style: editorText(context, color: palette.text)),
          ),
      ],
    );
  }

  /// A movie's export.
  Widget _buildMovie(BuildContext context, PhotoDocument doc) {
    final x = exporter;
    final exporting = editor.exporting;
    final palette = Palette.of(context);
    final type = x.videoType;
    final sizes = x.sizes(batch: false);
    final sizeId = x.sizeId(batch: false);
    if (x.size != sizeId) x.size = sizeId;
    final last = x.last;
    final delivered = x.delivered(doc);
    final hdr = type?['hdr'] == true;
    final rates = x.videoFrameRates;
    String label(String key) => videoLabel(editor, key);
    return DialogCard(
      title: label('export'),
      width: 480,
      actions: [
        PillButton('取消', onPressed: exporting ? x.cancel : widget.onClose),
        PillButton(
          exporting ? '正在导出…' : '导出',
          variant: ButtonVariant.accent,
          onPressed: exporting || type == null ? null : () => _export(false),
        ),
      ],
      children: [
        IgnorePointer(
          ignoring: exporting,
          child: Opacity(
            opacity: exporting ? .45 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (last != null && !_same(last, x.current))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    PillButton('沿用上次导出设置', onPressed: x.applyLast),
                  ]),
                ),
              _SelectRow('画幅', PickerField<String>(
                value: type?['id'] as String? ?? x.videoFormat,
                options: [
                  for (final t in x.videoTypes)
                    PickerOption(t['id'] as String, t['label'] as String),
                ],
                onChanged: (v) => setState(() => x.videoFormat = v),
              )),
              _SelectRow('尺寸', PickerField<String>(
                value: sizeId,
                options: [
                  for (final s in sizes) PickerOption(s.id, [s.label, ?s.detail].join(' · ')),
                ],
                onChanged: (v) => setState(() => x.size = v),
              )),
              if (hdr)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SwitchRow(
                      label: 'HDR', value: x.videoHDR, onChanged: (v) => x.videoHDR = v),
                ),
              if (rates.isNotEmpty)
                _SelectRow(label('frameRate'), PickerField<int?>(
                  value: x.videoFrameRate,
                  options: [
                    PickerOption(null, label('frameRateSource')),
                    for (final rate in rates) PickerOption(rate, '$rate fps'),
                  ],
                  onChanged: (v) => x.videoFrameRate = v,
                )),
              if (x.videoProcessingOffered)
                _SelectRow('处理中', PickerField<String>(
                  value: x.videoProcessing,
                  options: const [PickerOption('full', '全'), PickerOption('fast', '快速')],
                  onChanged: (v) => x.videoProcessing = v,
                )),
              if (type?['quality'] != false && x.videoBitrates.isNotEmpty)
                _SelectRow('文件大小', PickerField<String>(
                  value: x.videoBitrate,
                  options: [
                    for (final b in x.videoBitrates)
                      PickerOption(b['id'] as String, b['label'] as String),
                  ],
                  onChanged: (v) => x.videoBitrate = v,
                )),
              _Detail('${delivered.width} × ${delivered.height} pixels · '
                  '${type?['colorSpace'] == 'display-p3' ? 'Display P3' : 'sRGB'} · '
                  '${type?['bits'] ?? 8}-bit${hdr && x.videoHDR ? ' HLG' : ''}'),
              const _Detail('Exports every frame in the trim range with the current film, crop, '
                  'and adjustments. Writes directly to disk; no upload. Odd dimensions are '
                  'padded by one pixel.'),
            ]),
          ),
        ),
        if (exporting)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(editor.status ?? '正在准备导出',
                style: editorText(context, color: palette.text)),
          ),
      ],
    );
  }

  /// The last settings equal the dialog's.
  static bool _same(Json a, Json b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

/// A name on the left and its picker on the right (`[role=dialog] .select-row`); in a narrow
/// dialog the picker gives way so the name keeps a line of its own.
class _SelectRow extends StatelessWidget {
  const _SelectRow(this.label, this.control);
  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            SizedBox(
                width: (constraints.maxWidth - 96).clamp(120, 260).toDouble(), child: control),
          ]),
        ),
      );
}

/// A muted line under the controls (`.export-detail`).
class _Detail extends StatelessWidget {
  const _Detail(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text,
            style: editorText(context,
                size: TextSizes.label, color: Palette.of(context).muted, height: 1.6)),
      );
}
