import 'dart:async';

import 'tail_event.dart';

/// A handle to an active event subscription.
abstract class Subscription {
  void cancel();
}

class _StreamSubscriptionWrapper implements Subscription {
  _StreamSubscriptionWrapper(this._inner);
  final StreamSubscription<dynamic> _inner;

  @override
  void cancel() => _inner.cancel();
}

/// A typed asynchronous event bus.
/// Typed asynchronous event bus.
class EventBus {
  EventBus({this.onError});

  final void Function(Object error, StackTrace? stackTrace)? onError;
  final Map<Type, StreamController<dynamic>> _controllers = {};

  StreamController<T> _controllerFor<T extends TailEvent>() {
    return _controllers.putIfAbsent(T, () => StreamController<T>.broadcast())
        as StreamController<T>;
  }

  /// Publishes [event] to all subscribers of its runtime type.
  void publish<T extends TailEvent>(T event) {
    final exact = _controllers[event.runtimeType];
    if (exact != null) exact.add(event);
    final base = _controllers[TailEvent];
    if (base != null && event.runtimeType != TailEvent) base.add(event);
  }

  /// Subscribes [handler] to events of type [T]. Returns a [Subscription].
  Subscription subscribe<T extends TailEvent>(void Function(T) handler) {
    final controller = _controllerFor<T>();
    final sub = controller.stream.listen((event) {
      try {
        handler(event);
      } catch (e, st) {
        onError?.call(e, st);
        // Swallow handler errors to keep other subscribers alive.
      }
    });
    return _StreamSubscriptionWrapper(sub);
  }
}
