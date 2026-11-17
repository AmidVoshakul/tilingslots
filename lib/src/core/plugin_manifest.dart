import 'exceptions.dart';

/// Metadata describing a plugin that can be loaded dynamically.
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.slotId,
    this.entrypoint,
  });

  final String id;
  final String name;
  final String version;
  final String? slotId;
  final String? entrypoint;

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final version = json['version'];
    if (id is! String || id.isEmpty) {
      throw PluginConfigValidationError('manifest: invalid id');
    }
    if (name is! String || name.isEmpty) {
      throw PluginConfigValidationError('manifest: invalid name');
    }
    if (version is! String || version.isEmpty) {
      throw PluginConfigValidationError('manifest: invalid version');
    }
    final slotId = json['slotId'];
    final entrypoint = json['entrypoint'];
    return PluginManifest(
      id: id,
      name: name,
      version: version,
      slotId: slotId is String ? slotId : null,
      entrypoint: entrypoint is String ? entrypoint : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'version': version,
        if (slotId != null) 'slotId': slotId,
        if (entrypoint != null) 'entrypoint': entrypoint,
      };
}
