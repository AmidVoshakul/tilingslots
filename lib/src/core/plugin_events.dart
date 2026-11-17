import 'tail_event.dart';

/// Emitted when a plugin is registered.
class PluginRegisteredEvent extends TailEvent {
  PluginRegisteredEvent({required this.pluginId}) : super();
  final String pluginId;
}

/// Emitted when a plugin is enabled.
class PluginEnabledEvent extends TailEvent {
  PluginEnabledEvent({required this.pluginId}) : super();
  final String pluginId;
}

/// Emitted when an unhandled asynchronous error inside a plugin is contained
/// by its zone: the plugin is disabled, its scoped effects are disposed, and
/// the host keeps running.
class PluginCrashedEvent extends TailEvent {
  PluginCrashedEvent({
    required this.pluginId,
    required this.error,
    this.stackTrace,
  }) : super();

  final String pluginId;
  final Object error;
  final StackTrace? stackTrace;
}

/// Emitted when a plugin is disabled.
class PluginDisabledEvent extends TailEvent {
  PluginDisabledEvent({required this.pluginId, this.slotId}) : super();
  final String pluginId;

  /// Slot the plugin rendered into, when the plugin is slot-based.
  final String? slotId;
}

/// Emitted when a plugin implementation is swapped in place via
/// `PluginManager.replace`. Replacing is not a disable: the plugin stays
/// enabled and keeps its services contract.
class PluginReplacedEvent extends TailEvent {
  PluginReplacedEvent({required this.pluginId}) : super();
  final String pluginId;
}

/// Emitted when a plugin throws.
class PluginErrorEvent extends TailEvent {
  PluginErrorEvent(
      {required this.pluginId, required this.error, this.stackTrace});
  final String pluginId;
  final Object error;
  final StackTrace? stackTrace;
}

/// A lifecycle event emitted by [PluginManager].
class PluginLifecycleEvent extends TailEvent {
  PluginLifecycleEvent({required this.type, required this.pluginId}) : super();
  final String type;
  final String pluginId;
}
