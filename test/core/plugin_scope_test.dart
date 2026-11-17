import 'dart:async';

import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('PluginScope', () {
    test('defer runs disposers in reverse registration order on close',
        () async {
      final scope = PluginScope();
      final log = <String>[];
      scope.defer(() => log.add('first'));
      scope.defer(() => log.add('second'));
      await scope.close();
      expect(log, ['second', 'first']);
    });

    test('own registers a disposer for a resource', () async {
      final scope = PluginScope();
      final resource = _Resource();
      scope.own(resource, (r) => r.disposed = true);
      await scope.close();
      expect(resource.disposed, isTrue);
    });

    test('on subscribes and cancels the subscription on close', () async {
      final scope = PluginScope();
      final bus = EventBus();
      var events = 0;
      scope.on<PluginEnabledEvent>(bus, (_) => events++);
      bus.publish(PluginEnabledEvent(pluginId: 'p'));
      await Future<void>.delayed(Duration.zero);
      expect(events, 1);
      await scope.close();
      bus.publish(PluginEnabledEvent(pluginId: 'p'));
      await Future<void>.delayed(Duration.zero);
      expect(events, 1);
    });

    test('every starts a timer cancelled on close', () async {
      final scope = PluginScope();
      var ticks = 0;
      scope.every(const Duration(milliseconds: 10), (_) => ticks++);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(ticks, greaterThan(0));
      await scope.close();
      final before = ticks;
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(ticks, before);
    });

    test('close is idempotent and tolerates failing disposers', () async {
      final scope = PluginScope();
      var secondRan = false;
      scope.defer(() => throw StateError('boom'));
      scope.defer(() => secondRan = true);
      await scope.close();
      await scope.close();
      expect(secondRan, isTrue);
    });

    test('registering on a closed scope throws', () {
      final scope = PluginScope();
      scope.close();
      expect(() => scope.defer(() {}), throwsStateError);
    });

    test('ownFuture disposes the completed resource on scope close', () async {
      final scope = PluginScope();
      final resource = _Resource();
      scope.ownFuture<_Resource>(
          Future.value(resource), (r) => r.disposed = true);
      await Future<void>.delayed(Duration.zero);
      await scope.close();
      expect(resource.disposed, isTrue);
    });

    test('ownFuture disposes a late arrival when the scope is already closed',
        () async {
      final scope = PluginScope();
      final resource = _Resource();
      final completer = Completer<_Resource>();
      scope.ownFuture<_Resource>(completer.future, (r) => r.disposed = true);
      await scope.close();
      completer.complete(resource);
      await Future<void>.delayed(Duration.zero);
      expect(resource.disposed, isTrue);
    });

    test('ownFuture failure does not surface as an unhandled error', () async {
      final scope = PluginScope();
      scope.ownFuture<_Resource>(
        Future<_Resource>.error(StateError('boom')),
        (r) => r.disposed = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await scope.close();
      // Reaching this line without an unhandled async error is the assertion.
      expect(scope.isClosed, isTrue);
    });
  });
}

class _Resource {
  bool disposed = false;
}
