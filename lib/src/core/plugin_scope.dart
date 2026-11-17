import 'dart:async';

import 'event_bus.dart';
import 'tail_event.dart';

/// An effect scope for plugin resources (modeled after the cordis fiber
/// effect scope).
///
/// A plugin receives a scope in [Plugin.setup]: every subscription, timer or
/// disposable resource registered here is torn down automatically when the
/// plugin is disabled, so `teardown` only needs to handle what cannot be
/// expressed as an effect.
class PluginScope {
  final List<FutureOr<void> Function()> _disposers = [];
  bool _closed = false;

  /// The zone this plugin's effects run in (bound by the [PluginManager]).
  /// Timers created through [every] are created inside it, so their uncaught
  /// async errors are contained by the plugin's zone instead of crashing the
  /// host.
  Zone? _zone;

  bool get isClosed => _closed;

  /// For the [PluginManager]: binds the zone that contains this plugin's
  /// uncaught async errors.
  void bindZone(Zone zone) => _zone = zone;

  /// Registers [disposer] to run when this scope closes. Disposers run in
  /// reverse registration order (LIFO), like nested `try/finally` blocks.
  void defer(FutureOr<void> Function() disposer) {
    if (_closed) throw StateError('PluginScope is closed');
    _disposers.add(disposer);
  }

  /// Registers [resource] with a matching [disposer] callback.
  void own<T>(T resource, FutureOr<void> Function(T resource) disposer) {
    defer(() => disposer(resource));
  }

  /// Subscribes [handler] to events of type [T] on [bus] and cancels the
  /// subscription when this scope closes.
  Subscription on<T extends TailEvent>(
      EventBus bus, void Function(T event) handler) {
    final subscription = bus.subscribe<T>(handler);
    own(subscription, (s) => s.cancel());
    return subscription;
  }

  /// Starts a periodic timer that is cancelled when this scope closes. The
  /// timer is created inside the plugin's zone, so an uncaught error in
  /// [onTick] is contained by that zone.
  Timer every(Duration duration, void Function(Timer timer) onTick) {
    final zone = _zone;
    final timer = zone == null
        ? Timer.periodic(duration, onTick)
        : zone.run(() => Timer.periodic(duration, onTick));
    own(timer, (t) => t.cancel());
    return timer;
  }

  /// Runs a long-running future and disposes the resource it completes with.
  /// A failing future is swallowed here (the app must not crash on a plugin's
  /// background failure); plugins that care should attach their own
  /// `catchError` before handing the future over.
  void ownFuture<T>(
      Future<T> future, FutureOr<void> Function(T resource) disposer) {
    future.then((resource) {
      if (_closed) {
        // The scope is gone: dispose now, guarding async rejections so they
        // cannot surface as unhandled errors.
        try {
          final result = disposer(resource);
          if (result is Future) result.catchError((Object _) {});
        } catch (_) {
          // A synchronous throw from the disposer must not escape.
        }
        return;
      }
      own(resource, disposer);
    }, onError: (Object error, StackTrace stackTrace) {});
  }

  /// Runs all registered disposers. Safe to call multiple times; a failing
  /// disposer never prevents the remaining ones from running.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final pending = _disposers.reversed.toList(growable: false);
    _disposers.clear();
    for (final disposer in pending) {
      try {
        await disposer();
      } catch (_) {
        // Effect teardown is best-effort: one failure must not strand the rest.
      }
    }
  }
}
