// The Edit History, named as the Mac app names it: each step is called after what it changed, so
// Undo and Redo say what they will undo, and the history can be read and jumped through (the More
// menu's Edit History, the Edit menu's).
import 'dart:convert';

import '../i18n/zh.dart';
import 'editor.dart';

/// A film id to the name the film list shows.
typedef FilmNamer = String? Function(String? id);

bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

Map _map(Json? edit, String key) => (edit?[key] as Map?) ?? const {};

bool _changed(Json? before, Json? after, List<String> keys) =>
    keys.any((key) => !_same(before?[key], after?[key]));

bool _paramsChanged(Json? before, Json? after, List<String> keys) =>
    keys.any((key) => !_same(_map(before, 'params')[key], _map(after, 'params')[key]));

bool _profileChanged(Json? before, Json? after, bool Function(String field) test) {
  final a = _map(before, 'profile'), b = _map(after, 'profile');
  return {...a.keys, ...b.keys}
      .cast<String>()
      .any((field) => test(field) && !_same(a[field], b[field]));
}

final _grade =
    RegExp(r'^(grade(Shadows|Midtones|Highlights)(Warmth|Tint|Level)|blackPoint|whitePoint)$');
final _filmGrain = RegExp(
    r'^(grainMottle|grainModel|film(GrainSize|ColourGrain|RedLayer|GreenLayer|BlueLayer|ScanSoftness))$');
final _bands = RegExp(r'^screen(Red|Green|Blue)Band$');

/// What a step changed: a title, or a film record for a change of film, named when it is shown.
sealed class _Kind {}

class _Titled extends _Kind {
  _Titled(this.title);
  final String title;
}

class _Film extends _Kind {
  _Film(this.id);
  final String? id;
}

/// Edits are never changed in place, so a step's kind is worked out once per pair of states: the
/// menus ask for the whole timeline on every change.
final _kinds = Expando<(Json?, _Kind)>('historyKind');

_Kind _cachedKind(Json? before, Json after) {
  final hit = _kinds[after];
  if (hit != null && identical(hit.$1, before)) return hit.$2;
  final kind = _stepKind(before, after);
  _kinds[after] = (before, kind);
  return kind;
}

_Kind _stepKind(Json? before, Json? after) {
  String? title() {
    if (!_same(before?['format'], after?['format'])) return '胶片画幅';
    if (_changed(before, after, const [
      'crop', 'cropShape', 'ratio', 'rotation', 'flip', 'straighten', 'perspectiveV', //
      'perspectiveH',
    ])) {
      return '裁剪与旋转';
    }
    if (_changed(before, after, const ['filters', 'filterMetering'])) return '镜头滤镜';
    if (_changed(before, after, const ['lens'])) return '镜头校正';
    if (_profileChanged(before, after, (f) => f.startsWith('hdr'))) return 'HDR 高光';
    if (_changed(before, after, const ['sceneLight']) ||
        _paramsChanged(before, after, const ['sceneLightKelvin'])) {
      return '光源色温';
    }
    if (_changed(before, after, const ['localTone']) ||
        _paramsChanged(before, after, const ['ev', 'highlights', 'shadows', 'cameraPreflash'])) {
      return '光';
    }
    if (_paramsChanged(before, after, const ['temperature', 'tint'])) return 'Undertone';
    if (_paramsChanged(before, after, const ['saturation', 'vibrance'])) return '颜色';
    if (_paramsChanged(before, after, const ['grain']) ||
        _profileChanged(before, after, _filmGrain.hasMatch)) {
      return '颗粒';
    }
    if (_changed(before, after, const ['seed'])) return '颗粒图案';
    if (_changed(before, after, const ['halationModel']) ||
        _profileChanged(
            before, after, (f) => f.startsWith('halation') || f == 'estimatedHalation')) {
      return '光晕';
    }
    if (_profileChanged(before, after, (f) => f.startsWith('coupler'))) return '成色剂';
    if (_profileChanged(before, after, (f) => f.startsWith('chromaticFringe'))) {
      return '色边';
    }
    if (_profileChanged(
        before, after, (f) => const ['push', 'bleach', 'expired', 'shutter'].contains(f))) {
      return '实验室';
    }
    final params = {..._map(before, 'params').keys, ..._map(after, 'params').keys}.cast<String>();
    if (_changed(before, after, const ['gradeSpace']) ||
        params.any((key) => _grade.hasMatch(key) && _paramsChanged(before, after, [key]))) {
      return '调色';
    }
    if (_changed(before, after, const ['medium'])) return '输出介质';
    if (_profileChanged(before, after, (f) => f == 'printLight')) return '观片光源';
    if (_changed(before, after, const ['digitalReference'])) return '屏幕转换';
    if (_profileChanged(before, after, (f) => f == 'screenGrade')) return '相纸号数';
    if (_profileChanged(before, after, _bands.hasMatch)) return '接收波段';
    if (_profileChanged(before, after, (f) => f == 'screenExposure')) return '屏幕曝光';
    if (_profileChanged(before, after, (f) => f == 'enlarger' || f.startsWith('printer'))) {
      return '放大机';
    }
    if (_profileChanged(before, after, (f) => f == 'printCorrection')) {
      return '通道反差匹配';
    }
    if (_profileChanged(before, after, (f) => f == 'negativeViewing')) return '负片观看';
    if (_changed(before, after, const ['rawCorrections'])) return 'RAW 校正';
    if (_changed(before, after, const ['printFrame'])) return '印相边框';
    if (_changed(before, after, const ['printFrameEdgePrinting'])) return '片边字';
    if (_changed(before, after, const ['printFrameNumber'])) return '画幅编号';
    if (_changed(before, after, const ['printFrameFraming'])) return 'Framing';
    if (_changed(before, after, const ['printFrameCount'])) return '画幅数';
    if (_changed(before, after, const ['printFrameCamera'])) return '相机';
    if (_changed(before, after, const ['selective'])) return '选择性';
    if (_changed(before, after, const ['video'])) return '视频';
    return null;
  }

  if (!_same(before?['stock'], after?['stock'])) return _Film(after?['stock'] as String?);
  return _Titled(title() ?? '编辑');
}

/// The name of the step from `before` to `after`, checked in the Mac app's order, and translated
/// for the interface: the kinds are named in English so the tables stay readable.
String historyTitle(Json? before, Json after, [FilmNamer? filmName]) {
  final kind = _cachedKind(before, after);
  return switch (kind) {
    _Titled(:final title) => t(title),
    _Film(:final id) => id == null ? t('正常') : (filmName?.call(id) ?? t('胶片')),
  };
}

/// The whole timeline, oldest first, named step by step, and the step standing now.
({List<String> titles, int index}) editTimeline(History history, [FilmNamer? filmName]) {
  final states = [...history.past, history.present, ...history.future];
  return (
    titles: [
      for (final (i, state) in states.indexed)
        i == 0 ? t('Opened') : historyTitle(states[i - 1], state, filmName),
    ],
    index: history.past.length,
  );
}

/// "Undo Lens Correction", or plain "Undo" when there is nothing to undo; likewise Redo.
String undoTitle(History history, [FilmNamer? filmName]) => history.past.isEmpty
    ? t('撤销')
    : '撤销 ${historyTitle(history.past.last, history.present, filmName)}';

String redoTitle(History history, [FilmNamer? filmName]) => history.future.isEmpty
    ? t('重做')
    : '重做 ${historyTitle(history.present, history.future.first, filmName)}';

/// The shown photograph's Edit History, for the menus and the toolbar.
class EditHistory {
  EditHistory(this.editor);
  final EditorModel editor;

  String? _filmName(String? id) => editor.stockById(id)?['name'] as String?;

  String get undo {
    final doc = editor.active;
    return doc == null ? t('撤销') : undoTitle(doc.history, _filmName);
  }

  String get redo {
    final doc = editor.active;
    return doc == null ? t('重做') : redoTitle(doc.history, _filmName);
  }

  /// Every step's title and the one standing now; none without a photograph.
  ({List<String> titles, int index}) get timeline {
    final doc = editor.active;
    return doc == null ? (titles: const [], index: -1) : editTimeline(doc.history, _filmName);
  }

  /// Goes to a step: the timeline stays whole, as a run of undos or redos would leave it.
  void goTo(int index) {
    final doc = editor.active;
    if (doc == null) return;
    editor.endEdit();
    final h = doc.history;
    final states = [...h.past, h.present, ...h.future];
    if (index < 0 || index >= states.length || index == h.past.length) return;
    final before = h.present;
    h.past
      ..clear()
      ..addAll(states.sublist(0, index));
    h.present = states[index];
    h.future
      ..clear()
      ..addAll(states.sublist(index + 1));
    h.group = null;
    editor.historyChanged(doc, 'goTo', before);
  }
}
