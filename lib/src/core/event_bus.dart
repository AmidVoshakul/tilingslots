import 'tail_event.dart';

/// Delivery mode for [EventBus.publish].
enum EventMode {
  /// Invoke every subscriber in priority order.
  serial,

  /// Invoke subscribers in priority order and stop at the first non-null
  /// result, returning it.
  bail,

  /// Pass each subscriber's result to the next subscriber.
  waterfall,
}

/// A handle to an active event subscription.
abstract class Subscription {
  void cancel();
}

class _SubscriptionHandle implements Subscription {
  _SubscriptionHandle(this._onCancel);
  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }

  bool get isCancelled => _cancelled;
}

class _Subscriber {
  _Subscriber(this.id, this.handler, this.prepend, this.global);
  final int id;
  final Object? Function(TailEvent event) handler;
  final bool prepend;
  final bool global;
  bool cancelled = false;
}

/// Typed synchronous event bus.
class EventBus {
  EventBus({this.onError});

  final void Function(Object error, StackTrace? stackTrace)? onError;
  final Map<Type, List<_Subscriber>> _subscribers = {};
  int _nextId = 0;

  /// Publishes [event] to subscribers of its runtime type (and to
  /// [TailEvent] subscribers). Delivery follows [mode].
  Object? publish<T extends TailEvent>(T event,
      {EventMode mode = EventMode.serial}) {
    final candidates = <_Subscriber>[];
    final exact = _subscribers[event.runtimeType];
    if (exact != null) candidates.addAll(exact);
    if (event.runtimeType != TailEvent) {
      final base = _subscribers[TailEvent];
      if (base != null) candidates.addAll(base);
    }
    candidates.sort((a, b) {
      if (a.prepend != b.prepend) return a.prepend ? -1 : 1;
      return a.id.compareTo(b.id);
    });

    switch (mode) {
      case EventMode.serial:
        for (final sub in candidates) {
          if (sub.cancelled) continue;
          try {
            sub.handler(event);
          } catch (error, stackTrace) {
            onError?.call(error, stackTrace);
          }
        }
        return null;
      case EventMode.bail:
        for (final sub in candidates) {
          if (sub.cancelled) continue;
          try {
            final result = sub.handler(event);
            if (result != null) return result;
          } catch (error, stackTrace) {
            onError?.call(error, stackTrace);
          }
        }
        return null;
      case EventMode.waterfall:
        dynamic current = event;
        for (final sub in candidates) {
          if (sub.cancelled) continue;
          try {
            final result = sub.handler(current is TailEvent ? current : event);
            if (result != null) current = result;
          } catch (error, stackTrace) {
            onError?.call(error, stackTrace);
          }
        }
        return current;
    }
  }

  /// Subscribes [handler] to events of type [T].
  Subscription subscribe<T extends TailEvent>(
    Object? Function(T event) handler, {
    bool prepend = false,
    bool global = false,
  }) {
    final type = global ? TailEvent : T;
    final subscriber = _Subscriber(
      _nextId++,
      (TailEvent event) => handler(event as T),
      prepend,
      global,
    );
    final list = _subscribers.putIfAbsent(type, () => <_Subscriber>[]);
    if (prepend) {
      list.insert(0, subscriber);
    } else {
      list.add(subscriber);
    }
    final handle = _SubscriptionHandle(() {
      subscriber.cancelled = true;
      list.remove(subscriber);
    });
    return handle;
  }

  /// Subscribes [handler] to all events (alias for subscribe<TailEvent>).
  Subscription subscribeAll(Object? Function(TailEvent event) handler,
      {bool prepend = false}) {
    return subscribe<TailEvent>(handler, prepend: prepend, global: true);
  }
}
