import 'dart:convert';
import 'dart:io';

import '../core/plugin_manifest.dart';

/// Loads [PluginManifest]s from a directory of JSON files.
class PluginManifestLoader {
  const PluginManifestLoader._();

  static List<PluginManifest> loadFromDirectory(Directory directory) {
    if (!directory.existsSync()) return const <PluginManifest>[];
    final manifests = <PluginManifest>[];
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(entity.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          manifests.add(PluginManifest.fromJson(decoded));
        }
      } on Object {
        // Skip malformed manifests; callers can log separately.
      }
    }
    return manifests;
  }
}
