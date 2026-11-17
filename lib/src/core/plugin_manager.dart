import 'dart:async';
import 'event_bus.dart';
import 'logger.dart';
import 'plugin.dart';
import 'plugin_events.dart';
import 'plugin_scope.dart';
import 'service_container.dart';

/// Manages plugin lifecycle and failure isolation.
class PluginManager {
  PluginManager({
    required this.container,
    required this.bus,
    this.logger,
    this.slotResolver,
  });

  final ServiceContainer container;
  final EventBus bus;
  final TailLogger? logger;
  final String? Function(String pluginId)? slotResolver;

  final StreamController<PluginLifecycleEvent> _lifecycle =
      StreamController<PluginLifecycleEvent>.broadcast();

  Stream<PluginLifecycleEvent> get lifecycle => _lifecycle.stream;

  final Map<String, Plugin> _plugins = {};
  final Set<String> _enabled = {};
  final Set<String> _failed = {};
  final Map<String, PluginScope> _scopes = {};
  bool _disposed = false;

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('PluginManager is disposed');
  }

  void register(Plugin plugin) {
    _ensureNotDisposed();
    if (_plugins.containsKey(plugin.id)) {
      throw StateError('Plugin already registered: ${plugin.id}');
    }
    _plugins[plugin.id] = plugin;
    bus.publish(PluginRegisteredEvent(pluginId: plugin.id));
    _emitLifecycle(
        PluginLifecycleEvent(type: 'registered', pluginId: plugin.id));
  }

  Future<void> enable(String id) async {
    _ensureNotDisposed();
    final plugin = _plugins[id];
    if (plugin == null) throw StateError('Unknown plugin: $id');
    plugin.validateConfig();
    if (_enabled.contains(id)) return;
    final snapshot = container.capture();
    final scope = PluginScope();
    // Bind the plugin's zone: effects started inside setup (timers created
    // through scope.every) inherit it, so their uncaught async errors are
    // contained here instead of crashing the host. Setup itself runs outside
    // the zone: a synchronous setup failure must reach the rollback path.
    final zone = _zoneFor(id);
    scope.bindZone(zone);
    try {
      await plugin.setup(container, bus, scope);
      bus.publish(PluginEnabledEvent(pluginId: id));
      _emitLifecycle(PluginLifecycleEvent(type: 'enabled', pluginId: id));
      _enabled.add(id);
      _failed.remove(id);
      _scopes[id] = scope;
    } catch (e, st) {
      logger?.call(e, st);
      bus.publish(PluginErrorEvent(pluginId: id, error: e, stackTrace: st));
      _emitLifecycle(PluginLifecycleEvent(type: 'error', pluginId: id));
      // rollback any services registered during failed setup
      try {
        container.restore(snapshot);
      } catch (rollbackError, rollbackStack) {
        // A failed rollback must not vanish silently.
        logger?.call(rollbackError, rollbackStack);
        bus.publish(PluginErrorEvent(
          pluginId: id,
          error: StateError('rollback after failed setup: $rollbackError'),
          stackTrace: rollbackStack,
        ));
        _emitLifecycle(PluginLifecycleEvent(type: 'error', pluginId: id));
      }
      // dispose partial effects before rethrowing into error handling
      await scope.close();
    }
  }

  /// Emits a lifecycle event, tolerating a closed stream after [dispose].
  void _emitLifecycle(PluginLifecycleEvent event) {
    try {
      _lifecycle.add(event);
    } on StateError {
      // Stream closed by dispose(); lifecycle delivery is best-effort.
    }
  }

  Future<void> disable(String id, {String? slotId}) async {
    _ensureNotDisposed();
    final plugin = _plugins[id];
    if (plugin == null) throw StateError('Unknown plugin: $id');
    if (!_enabled.contains(id)) return;
    final scope = _scopes.remove(id) ?? PluginScope();
    try {
      await plugin.teardown(container, bus, scope);
    } catch (e, st) {
      logger?.call(e, st);
      bus.publish(PluginErrorEvent(pluginId: id, error: e, stackTrace: st));
      _emitLifecycle(PluginLifecycleEvent(type: 'error', pluginId: id));
    }
    // Scoped effects (subscriptions, timers) die with the plugin.
    await scope.close();
    _enabled.remove(id);
    bus.publish(
        PluginDisabledEvent(pluginId: id, slotId: slotId ?? plugin.slotId));
    _emitLifecycle(PluginLifecycleEvent(type: 'disabled', pluginId: id));
  }

  Future<void> unregister(String id) async {
    _ensureNotDisposed();
    if (_enabled.contains(id)) {
      await disable(id);
    }
    _plugins.remove(id);
    _emitLifecycle(PluginLifecycleEvent(type: 'unregistered', pluginId: id));
  }

  /// Swaps a plugin implementation in place. The replacement must use the same
  /// id. If the plugin was enabled, the old implementation is torn down
  /// (scoped effects included) and the new one is set up, keeping the plugin
  /// enabled. On a failed `setup` the previous implementation is restored and
  /// the container is rolled back to its pre-replace state.
  ///
  /// Note: consumers registered between the teardown and the failed setup are
  /// not tracked (no dependency graph yet) — a dependent service may briefly
  /// resolve the old implementation.
  Future<void> replace(String id, Plugin newPlugin) async {
    _ensureNotDisposed();
    final current = _plugins[id];
    if (current == null) throw StateError('Unknown plugin: $id');
    if (newPlugin.id != id) {
      throw StateError('Replacement must reuse the plugin id: $id');
    }
    final wasEnabled = _enabled.contains(id);
    if (!wasEnabled) {
      _plugins[id] = newPlugin;
      return;
    }
    final snapshot = container.capture();
    final previousScope = _scopes.remove(id);
    try {
      await current.teardown(container, bus, previousScope ?? PluginScope());
      await previousScope?.close();
    } catch (e, st) {
      logger?.call(e, st);
      bus.publish(PluginErrorEvent(pluginId: id, error: e, stackTrace: st));
      _emitLifecycle(PluginLifecycleEvent(type: 'error', pluginId: id));
    }
    final scope = PluginScope();
    final zone = _zoneFor(id);
    scope.bindZone(zone);
    try {
      await newPlugin.setup(container, bus, scope);
    } catch (e, st) {
      // Restore the previous implementation and container state.
      await scope.close();
      try {
        container.restore(snapshot);
      } catch (rollbackError, rollbackStack) {
        logger?.call(rollbackError, rollbackStack);
        bus.publish(PluginErrorEvent(
          pluginId: id,
          error: StateError('rollback after failed replace: $rollbackError'),
          stackTrace: rollbackStack,
        ));
      }
      final restoreScope = PluginScope();
      final restoreSnapshot = container.capture();
      try {
        await current.setup(container, bus, restoreScope);
        _scopes[id] = restoreScope;
        _plugins[id] = current;
      } catch (_) {
        _plugins[id] = current;
        _enabled.remove(id);
        await restoreScope.close();
        // Second failure: undo whatever the failed restore setup registered,
        // so the container returns to its pre-replace state.
        try {
          container.restore(restoreSnapshot);
        } catch (restoreError, restoreStack) {
          logger?.call(restoreError, restoreStack);
          bus.publish(PluginErrorEvent(
            pluginId: id,
            error: StateError('rollback after failed restore: $restoreError'),
            stackTrace: restoreStack,
          ));
        }
      }
      logger?.call(e, st);
      bus.publish(PluginErrorEvent(pluginId: id, error: e, stackTrace: st));
      _emitLifecycle(PluginLifecycleEvent(type: 'error', pluginId: id));
      return;
    }
    _plugins[id] = newPlugin;
    _scopes[id] = scope;
    _failed.remove(id);
    bus.publish(PluginReplacedEvent(pluginId: id));
    _emitLifecycle(PluginLifecycleEvent(type: 'replaced', pluginId: id));
  }

  List<Plugin> get plugins => _plugins.values.toList(growable: false);

  bool isEnabled(String id) => _enabled.contains(id);

  /// Plugins whose unhandled async errors were contained by their zone.
  Set<String> get failedPlugins => Set.unmodifiable(_failed);

  bool hasFailed(String id) => _failed.contains(id);

  /// Forks a zone that contains this plugin's uncaught async errors: the
  /// plugin is disabled, its scope disposed, and the failure is published.
  Zone _zoneFor(String id) => Zone.current.fork(
        specification: ZoneSpecification(
          handleUncaughtError: (Zone self, ZoneDelegate parent, Zone zone,
              Object error, StackTrace stackTrace) {
            _containCrash(id, error, stackTrace);
          },
        ),
      );

  void _containCrash(String id, Object error, StackTrace stackTrace) {
    logger?.call(error, stackTrace);
    if (_enabled.remove(id)) {
      final scope = _scopes.remove(id);
      // Resolve the active slot before any subscriber (e.g. SlotWorkspace)
      // mutates the active-slot mapping while handling PluginCrashedEvent.
      final crashedSlot = slotResolver?.call(id) ?? _plugins[id]?.slotId;
      if (scope != null) {
        // Zone handlers are synchronous; schedule teardown so async disposers
        // run to completion instead of being dropped.
        unawaited(scope.close().catchError((Object _) {}));
      }
      _failed.add(id);
      bus.publish(
          PluginErrorEvent(pluginId: id, error: error, stackTrace: stackTrace));
      bus.publish(PluginCrashedEvent(
          pluginId: id, error: error, stackTrace: stackTrace));
      bus.publish(PluginDisabledEvent(pluginId: id, slotId: crashedSlot));
      _emitLifecycle(PluginLifecycleEvent(type: 'crashed', pluginId: id));
    }
  }

  /// Disables every enabled plugin (running its `teardown`) and closes the
  /// lifecycle stream. After disposal the manager rejects register/enable/
  /// disable/unregister calls.
  Future<void> dispose() async {
    for (final id in _enabled.toList()) {
      await disable(id);
    }
    _disposed = true;
    _lifecycle.close();
  }
}
