import 'exceptions.dart';

/// A minimal schema for validating plugin configuration maps.
class PluginConfigSchema {
  const PluginConfigSchema({
    this.required = const <String, Type>{},
    this.optional = const <String, Type>{},
  });

  final Map<String, Type> required;
  final Map<String, Type> optional;

  void validate(Map<String, dynamic> config) {
    for (final entry in required.entries) {
      if (!config.containsKey(entry.key)) {
        throw PluginConfigValidationError(
            'missing required field: ${entry.key}');
      }
      final actual = config[entry.key].runtimeType;
      if (actual != entry.value) {
        throw PluginConfigValidationError(
            'field ${entry.key}: expected ${entry.value}, got $actual');
      }
    }
    for (final entry in config.entries) {
      final expected = required[entry.key] ?? optional[entry.key];
      if (expected == null) {
        throw PluginConfigValidationError('unknown field: ${entry.key}');
      }
      final actual = entry.value.runtimeType;
      if (actual != expected) {
        throw PluginConfigValidationError(
            'field ${entry.key}: expected $expected, got $actual');
      }
    }
  }
}
