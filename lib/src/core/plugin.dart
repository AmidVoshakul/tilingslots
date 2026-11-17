import 'event_bus.dart';
import 'plugin_scope.dart';
import 'service_container.dart';

/// Contract for a plugin managed by [PluginManager].
abstract class Plugin {
  const Plugin();

  String get id;
  String get name;
  String get version;
  List<Type> get providedServices => const [];
  List<Type> get consumedServices => const [];

  /// Optional slot id for plugins that render into a tiling slot.
  /// Defaults to `null` for non-visual plugins.
  String? get slotId => null;

  /// Called once when the plugin is enabled. Register long-lived resources on
  /// [scope] (subscriptions, timers) so they are disposed automatically.
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {}

  /// Called when the plugin is disabled or unregistered. Use it for cleanup
  /// that cannot be expressed as a scoped effect. [scope] is closed after
  /// this returns.
  Future<void> teardown(
      ServiceContainer container, EventBus bus, PluginScope scope) async {}
}
