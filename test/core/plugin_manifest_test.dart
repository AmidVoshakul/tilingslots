import 'dart:io';

import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('PluginManifest', () {
    test('parses valid manifest', () {
      final manifest = PluginManifest.fromJson({
        'id': 'clock',
        'name': 'Clock',
        'version': '1.0.0',
        'slotId': 'clock',
      });
      expect(manifest.id, 'clock');
      expect(manifest.slotId, 'clock');
    });

    test('rejects invalid manifest', () {
      expect(
        () => PluginManifest.fromJson({'id': '', 'name': 'x', 'version': '1'}),
        throwsA(isA<PluginConfigValidationError>()),
      );
    });

    test('round-trips through json', () {
      final manifest = PluginManifest.fromJson({
        'id': 'a',
        'name': 'A',
        'version': '0.1.0',
      });
      expect(PluginManifest.fromJson(manifest.toJson()).id, 'a');
    });
  });

  group('PluginManifestLoader', () {
    test('loads manifests from directory', () {
      final dir = Directory.systemTemp.createTempSync('manifests');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a.json').writeAsStringSync(
        '{"id":"a","name":"A","version":"0.1.0"}',
      );
      File('${dir.path}/bad.json').writeAsStringSync('{not json');
      final loaded = PluginManifestLoader.loadFromDirectory(dir);
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'a');
    });
  });
}
