// The catalogue is data the inspector reads by name, so a translated identifier silently empties a
// panel instead of failing. These tests hold the two ends together.
import 'package:flutter_test/flutter_test.dart';

import 'package:fotufilm_flutter/model/catalogue.dart';

/// The groups the inspector asks for by name (expose_panel.dart, develop_panel.dart).
const _groups = [
  'Light',
  'Source Illuminant',
  'White Balance',
  'Color',
  'Character',
  'Output Levels',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every group the inspector asks for has sliders', () async {
    final catalogue = await Catalogue.load();
    for (final group in _groups) {
      final sliders = catalogue.sliders.where((s) => s.group == group).toList();
      expect(sliders, isNotEmpty, reason: 'group "$group" would render an empty section');
    }
  });

  test('the grade deck builds the parameter keys the engine reads', () async {
    final catalogue = await Catalogue.load();
    final keys = {for (final s in catalogue.sliders) s.key};
    for (final band in ['Shadows', 'Midtones', 'Highlights']) {
      for (final axis in ['Warmth', 'Tint', 'Level']) {
        expect(keys.contains('grade$band$axis'), isTrue, reason: 'grade$band$axis missing');
      }
    }
  });

  test('the catalogue module keeps the keys the app indexes it with', () async {
    final catalogue = await Catalogue.load();
    for (final key in ['EDITOR_CONTROLS', 'FILM_FORMATS', 'PROFILE_MENUS', 'HISTOGRAM', 'SELECTION']) {
      expect(catalogue.module[key], isNotNull, reason: 'module["$key"] is missing');
    }
  });

  test('no slider label is left in English', () async {
    final catalogue = await Catalogue.load();
    for (final slider in catalogue.sliders) {
      expect(RegExp(r'[A-Za-z]{3,}').hasMatch(slider.label), isFalse,
          reason: 'untranslated label "${slider.label}"');
    }
  });
}
