// The Mac app's Settings window: what new photographs start on, how photos export, and the film
// model. Everything here is kept on this device; open photographs keep their own edits. Video's
// settings wait for video in this editor.
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../../model/editor.dart';
import '../../model/film_packs.dart';
import '../../model/film_suggestion.dart';
import '../../model/new_photo.dart';
import '../kit/kit.dart';
import '../theme/theme.dart';
import 'app_dialogs.dart';

enum SettingsPane { general, output, filmModel }

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.editor, required this.onClose});
  final EditorModel editor;
  final VoidCallback onClose;

  /// The pane a driver or a later opening asks for.
  static SettingsPane pane = SettingsPane.general;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsPane _pane = SettingsDialog.pane;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    return ListenableBuilder(
      listenable: Listenable.merge(
          [editor, editor.settings, editor.filmPacks, editor.filmSuggestion]),
      builder: (context, _) => AppDialogCard(
        title: '设置',
        onDismiss: widget.onClose,
        children: [
          SegmentedControl<SettingsPane>(
            items: const [
              (SettingsPane.general, '通用'),
              (SettingsPane.output, '输出'),
              (SettingsPane.filmModel, '胶片模型'),
            ],
            selected: _pane,
            onChanged: (p) => setState(() => _pane = SettingsDialog.pane = p),
          ),
          const SizedBox(height: 8),
          ...switch (_pane) {
            SettingsPane.general => _general(context),
            SettingsPane.output => _output(),
            SettingsPane.filmModel => _filmModel(),
          },
        ],
      ),
    );
  }

  AppSettings get _settings => widget.editor.settings;

  List<PickerOption<String?>> _choices(String field) => [
        for (final c in (widget.editor.catalogue.control(field)['choices'] as List).cast<Json>())
          PickerOption(c['id'] as String, c['label'] as String),
      ];

  // ── General ─────────────────────────────────────────────────────────────────────────────

  List<Widget> _general(BuildContext context) {
    final editor = widget.editor;
    final suggestion = editor.filmSuggestion;
    final learned = suggestion.learned == null || suggestion.learned! > 0;
    return [
      const PaneHeading('新照片'),
      _SettingPicker(
        label: '起始胶片',
        setting: 'startingFilm',
        settings: _settings,
        options: [
          const PickerOption(null, '当前胶片'),
          const PickerOption('none', '正常'),
          for (final s in editor.stocks) PickerOption(s['id'] as String, s['name'] as String),
        ],
      ),
      _SettingPicker(
        label: '胶片画幅',
        setting: 'startingFormat',
        settings: _settings,
        options: [
          const PickerOption(null, '匹配胶片'),
          for (final f in editor.catalogue.filmFormats)
            PickerOption(f['id'] as String, f['name'] as String),
        ],
      ),
      if (suggestion.available) ...[
        _SettingSwitch(label: '自动推荐胶片', setting: 'autoFilm', settings: _settings),
        const PaneNote('Suggests a film when you open a photo, based on your previous choices. '
            '你随时可以改选其他胶片。'),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: _ForgetButton(suggestion: suggestion, learned: learned),
        ),
      ],
      if (editor.filmPacks.available) _FilmPacksSection(packs: editor.filmPacks),
      if (editor.updates.available) ...[
        const PaneHeading('更新'),
        _SettingSwitch(
            label: '自动检查更新',
            setting: 'updateChecksAutomatically',
            settings: _settings),
        _SettingSwitch(label: '包含预发布版本', setting: 'updatePrereleases', settings: _settings),
      ],
      const PaneHeading('重置'),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton('重置全部设置',
            variant: ButtonVariant.negative, onPressed: () => _confirmReset(context)),
      ),
      const PaneNote('恢复 Fotufilm 的初始设置。您的照片与编辑不会改变。'),
    ];
  }

  void _confirmReset(BuildContext context) {
    showModal(
      context,
      (close) => AlertCard(
        title: '重置全部设置？',
        message: '恢复 Fotufilm 的初始设置。您的照片与编辑不会改变。',
        primary: '重置',
        variant: ButtonVariant.negative,
        cancel: '取消',
        onCancel: close,
        onPrimary: () {
          _settings.resetAll();
          close();
        },
      ),
    );
  }

  // ── Output ──────────────────────────────────────────────────────────────────────────────

  List<Widget> _output() {
    final exports =
        ((widget.editor.engine?.capabilities['imageExportTypes'] as List?) ?? const []).isNotEmpty;
    if (!exports) {
      return [
        const PaneHeading('照片'),
        const PaneNote('此引擎以标准动态范围导出照片。'),
        ..._video(),
      ];
    }
    return [
      const PaneHeading('照片'),
      const SizedBox(height: 4),
      _SettingSwitch(label: 'HDR', setting: 'photoHDR', settings: _settings),
      const PaneNote('HDR 可在兼容显示器上保留更亮的高光。若需更广兼容性请选择标准；它适用于会输出 HDR 的胶片的 HEIC 导出，且不带印相边框。'),
      _SettingPicker(
        label: '照片质量',
        setting: 'photoQuality',
        settings: _settings,
        options: const [PickerOption('accurate', '精确'), PickerOption('fast', '快速')],
      ),
      const PaneNote('精确模式使用真实胶片曲线；快速模式使用近似，以减少处理时间。'),
      ..._video(),
    ];
  }

  /// Video Quality, HDR and Video File Size where the engine's platform offers them, and the
  /// transport's Playback Quality where it plays movies.
  List<Widget> _video() {
    final exporter = widget.editor.exporter;
    final playable = widget.editor.engine?.capabilities['video'] == true;
    final hdr = exporter.videoTypes.any((t) => t['hdr'] == true);
    final bitrates = exporter.videoBitrates;
    if (!playable) return const [];
    return [
      const PaneHeading('视频'),
      _SettingPicker(
        label: '播放质量',
        setting: 'videoPlaybackQuality',
        settings: _settings,
        options: [for (final (id, name, _) in playbackQualities) PickerOption(id, name)],
      ),
      const PaneNote(playbackQualityHelp),
      if (exporter.videoProcessingOffered) ...[
        _SettingPicker(
          label: '视频质量',
          setting: 'videoProcessing',
          settings: _settings,
          options: const [PickerOption('full', '全'), PickerOption('fast', '快速')],
        ),
        const PaneNote('Video quality sets the processing resolution. Full uses the source '
            'resolution; Fast processes at up to 1080p.'),
      ],
      if (hdr) ...[
        _SettingSwitch(label: 'HDR', setting: 'videoHDR', settings: _settings),
        const PaneNote('HEVC and ProRes movies of films that deliver HDR are written as HLG; '
            'H.264 保持标准码率。'),
      ],
      if (bitrates.isNotEmpty) ...[
        _SettingPicker(
          label: '视频文件大小',
          setting: 'videoBitrate',
          settings: _settings,
          options: [
            for (final b in bitrates) PickerOption(b['id'] as String, b['label'] as String),
          ],
        ),
        const PaneNote('自动由编码器决定。ProRes 保持自身码率。'),
      ],
    ];
  }

  // ── Film Model ──────────────────────────────────────────────────────────────────────────

  /// The Mac app reads halation as a photo develops, so those settings reach the open photo.
  bool get _modelled => widget.editor.active != null && widget.editor.edit['stock'] != null;

  List<Widget> _filmModel() {
    final editor = widget.editor;
    String title(String field) => editor.catalogue.control(field)['title'] as String;
    return [
      const PaneHeading('颗粒'),
      _SettingPicker(
        label: title('grainModel'),
        setting: 'grainModel',
        settings: _settings,
        options: _choices('grainModel'),
      ),
      const PaneNote('标准模式使用快速校准的 RMS 噪点；胶片模式把该胶片的晶体按固定位置铺在乳剂上。'),
      const PaneHeading('光晕'),
      _SettingPicker(
        label: title('halationModel'),
        setting: 'halationModel',
        settings: _settings,
        options: _choices('halationModel'),
        onSet: (model) {
          if (_modelled) editor.change({'halationModel': model});
        },
      ),
      _SettingSwitch(
        label: title('estimatedHalation'),
        setting: 'estimatedHalation',
        settings: _settings,
        onSet: (on) {
          if (_modelled) editor.setProfile('estimatedHalation', on, grouped: false);
        },
      ),
      const PaneNote('Layered Transport simulates light moving through the film layers. In the '
          'browser, films with donor layers use Legacy. Estimated Halation Shape only affects '
          '经典。'),
      const PaneHeading('色彩分离'),
      _SettingSlider(label: title('couplerReach'), setting: 'couplerReach', settings: _settings),
      _SettingSlider(
          label: '红-绿', setting: 'couplerRedGreen', follows: 'couplerReach', settings: _settings),
      _SettingSlider(
          label: '绿-蓝', setting: 'couplerGreenBlue', follows: 'couplerReach', settings: _settings),
      _SettingSlider(label: title('couplerSelf'), setting: 'couplerSelf', settings: _settings),
      const PaneNote('分离度决定显影时相邻胶片层相互影响的强度，同时作用于两组色彩。红–绿与绿–蓝分别调整每一组。边缘反差控制显影带来的锐化。'),
      const PaneNote('Halation settings also change the open photo. The others apply to photos '
          'you open from now on; each open photo keeps its own.'),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton(
          '恢复胶片模型',
          variant: ButtonVariant.negative,
          onPressed: filmModelAdjusted(_settings)
              ? () {
                  for (final key in filmModelSettings) {
                    _settings.set(key, AppSettings.defaults[key]);
                  }
                }
              : null,
        ),
      ),
    ];
  }
}

/// A picker for a setting; null is its default choice. `onSet` also runs with each new value, for
/// a setting the open photo follows.
class _SettingPicker extends StatelessWidget {
  const _SettingPicker({
    required this.label,
    required this.setting,
    required this.settings,
    required this.options,
    this.onSet,
  });

  final String label, setting;
  final AppSettings settings;
  final List<PickerOption<String?>> options;
  final ValueChanged<String?>? onSet;

  @override
  Widget build(BuildContext context) {
    final value = settings.get<Object>(setting);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: editorText(context))),
        const SizedBox(width: 12),
        SizedBox(
          width: 220,
          child: PickerField<String?>(
            value: value is String ? value : null,
            options: options,
            onChanged: (next) {
              settings.set(setting, next);
              onSet?.call(next);
            },
          ),
        ),
      ]),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch(
      {required this.label, required this.setting, required this.settings, this.onSet});
  final String label, setting;
  final AppSettings settings;
  final ValueChanged<bool>? onSet;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SwitchRow(
          label: label,
          value: settings.get(setting) == true,
          onChanged: (next) {
            settings.set(setting, next);
            onSet?.call(next);
          },
        ),
      );
}

/// A slider from 0 to 3 in tenths. `follows`: the setting shown while this one has never been set
/// on its own.
class _SettingSlider extends StatelessWidget {
  const _SettingSlider(
      {required this.label, required this.setting, required this.settings, this.follows});
  final String label, setting;
  final String? follows;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final own = settings.get<num>(setting);
    final followed = settings.get<num>(follows ?? setting);
    final value = (own ?? followed ?? 1).toDouble();
    final rest = (AppSettings.defaults[setting] as num?) ?? followed ?? 1;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AdjustmentRow(
        label: label,
        value: value,
        range: SliderRange(min: 0, max: 3, step: .1, def: rest.toDouble()),
        onChanged: (next) => settings.set(setting, (next * 10).round() / 10),
      ),
    );
  }
}

/// Reset Film Suggestions: greyed with nothing learned, as the Mac app's is.
class _ForgetButton extends StatefulWidget {
  const _ForgetButton({required this.suggestion, required this.learned});
  final FilmSuggestion suggestion;
  final bool learned;

  @override
  State<_ForgetButton> createState() => _ForgetButtonState();
}

class _ForgetButtonState extends State<_ForgetButton> {
  bool _forgotten = false;

  @override
  void initState() {
    super.initState();
    widget.suggestion.refresh();
  }

  @override
  Widget build(BuildContext context) => PillButton(
        _forgotten ? '胶片推荐已重置' : '重置胶片推荐',
        onPressed: _forgotten || !widget.learned
            ? null
            : () => widget.suggestion.forget().then((_) {
                  if (mounted) setState(() => _forgotten = true);
                }).ignore(),
      );
}

/// The community packs installed where this person's films live: add more, or take one away with
/// its films.
class _FilmPacksSection extends StatefulWidget {
  const _FilmPacksSection({required this.packs});
  final FilmPacks packs;

  @override
  State<_FilmPacksSection> createState() => _FilmPacksSectionState();
}

class _FilmPacksSectionState extends State<_FilmPacksSection> {
  String? _notice;
  bool _busy = false;

  FilmPacks get packs => widget.packs;

  @override
  void initState() {
    super.initState();
    // Read afresh each time: another app may have added one since.
    packs.refresh().ignore();
  }

  Future<void> _run(Future<String?> Function() work, String failure) async {
    setState(() => _busy = true);
    String? notice;
    try {
      notice = await work();
    } catch (e) {
      notice = '$failure — $e';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _notice = notice;
      });
    }
  }

  Future<void> _import() => _run(() async {
        final files = await openFiles(acceptedTypeGroups: const [
          XTypeGroup(label: '胶片包', extensions: [filmPackExtension]),
        ]);
        if (files.isEmpty) return _notice;
        final notice = PackNotice.of(
            await packs.importPaths([for (final f in files) f.path], quiet: true));
        return '${notice.title} — ${notice.message}';
      }, '胶片包未添加');

  @override
  Widget build(BuildContext context) {
    final installed = packs.installed ?? const [];
    final disabled = _busy || packs.editor.exporting || packs.editor.exporter.busy;
    final muted = editorText(context, size: TextSizes.label, color: Palette.of(context).muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PaneHeading('胶片包'),
      if (installed.isEmpty)
        const PaneNote('未安装胶片包。')
      else
        for (final pack in installed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pack['version'] != null ? '${pack['name']} v${pack['version']}' : '${pack['name']}'),
                  Text(
                    pack['problem'] as String? ??
                        ((pack['films'] as List?) ?? const []).join(', '),
                    style: muted,
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              PillButton('移除',
                  onPressed: disabled
                      ? null
                      : () => _run(() async {
                            await packs.remove(pack['packID'] as String);
                            return null;
                          }, '胶片包未移除')),
            ]),
          ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton('导入胶片包…', onPressed: disabled ? null : _import),
      ),
      if (_notice != null) PaneNote(_notice!),
    ]);
  }
}
