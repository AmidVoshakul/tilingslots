import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceContainer', () {
    test('registers and resolves singleton instance', () {
      final c = ServiceContainer();
      final instance = Object();
      c.registerSingleton<Object>(instance);
      expect(c.resolve<Object>(), same(instance));
      expect(c.contains<Object>(), isTrue);
    });

    test('factory returns new instance each resolve', () {
      final c = ServiceContainer();
      var counter = 0;
      c.registerFactory<int>(() => ++counter);
      expect(c.resolve<int>(), 1);
      expect(c.resolve<int>(), 2);
    });

    test('named registration resolves by name', () {
      final c = ServiceContainer();
      c.registerSingleton<String>('a', name: 'first');
      c.registerSingleton<String>('b', name: 'second');
      expect(c.resolve<String>(name: 'first'), 'a');
      expect(c.resolve<String>(name: 'second'), 'b');
    });

    test('unregister removes service', () {
      final c = ServiceContainer();
      c.registerSingleton<int>(42);
      c.unregister<int>();
      expect(c.contains<int>(), isFalse);
      expect(() => c.resolve<int>(), throwsStateError);
    });

    test('resolve missing throws StateError', () {
      final c = ServiceContainer();
      expect(() => c.resolve<int>(), throwsStateError);
    });

    test('duplicate registration overwrites (last-writer-wins)', () {
      final c = ServiceContainer();
      c.registerSingleton<int>(1);
      c.registerSingleton<int>(2);
      expect(c.resolve<int>(), 2);
    });
  });
  group('Convergence', () {
    test('unregister invokes dispose callback', () {
      final c = ServiceContainer();
      var disposed = false;
      c.registerSingleton<int>(42, dispose: (_) => disposed = true);
      c.unregister<int>();
      expect(disposed, isTrue);
    });
  });

  group('Convergence coverage', () {
    test('factory unregister does not invoke factory', () {
      final c = ServiceContainer();
      var calls = 0;
      c.registerFactory<int>(() => ++calls);
      c.unregister<int>();
      expect(calls, 0);
    });

    test('capture/restore round-trips registrations', () {
      final c = ServiceContainer();
      c.registerSingleton<int>(1);
      final snapshot = c.capture();
      c.registerSingleton<String>('two');
      expect(c.contains<String>(), isTrue);
      c.restore(snapshot);
      expect(c.contains<String>(), isFalse);
      expect(c.resolve<int>(), 1);
    });

    test('dispose invokes dispose callbacks for all singletons', () {
      final c = ServiceContainer();
      final disposed = <String>[];
      c.registerSingleton<int>(1, dispose: (_) => disposed.add('int'));
      c.registerSingleton<String>('s',
          name: 'x', dispose: (_) => disposed.add('str'));
      c.dispose();
      expect(disposed, containsAll(['int', 'str']));
      expect(c.contains<int>(), isFalse);
    });

    test('named factory registration resolves by name', () {
      final c = ServiceContainer();
      c.registerFactory<String>(() => 'made', name: 'f');
      expect(c.resolve<String>(name: 'f'), 'made');
    });

    test('resolve with name throws for unknown name', () {
      final c = ServiceContainer();
      c.registerSingleton<String>('only-unnamed');
      expect(() => c.resolve<String>(name: 'nope'), throwsStateError);
    });

    test('contains with name checks named registration', () {
      final c = ServiceContainer();
      c.registerSingleton<String>('named', name: 'n');
      expect(c.contains<String>(name: 'n'), isTrue);
      expect(c.contains<String>(), isFalse);
    });

    test('overwriting a singleton defers its disposal to the next mutation',
        () {
      final c = ServiceContainer();
      final disposed = <int>[];
      c.registerSingleton<int>(1, dispose: disposed.add);
      c.registerSingleton<int>(2, dispose: disposed.add);
      // Deferred, so a failed setup can roll the displaced entry back.
      expect(disposed, isEmpty);
      c.registerSingleton<String>('trigger');
      expect(disposed, [1]);
      expect(c.resolve<int>(), 2);
    });

    test('restore disposes entries dropped by the snapshot', () {
      final c = ServiceContainer();
      final disposed = <String>[];
      c.registerSingleton<String>('keep', dispose: disposed.add);
      final snapshot = c.capture();
      c.registerSingleton<String>('drop', name: 'temp', dispose: disposed.add);
      c.restore(snapshot);
      expect(c.contains<String>(name: 'temp'), isFalse);
      expect(disposed, ['drop']);
    });

    test('dispose is idempotent for the same instance', () {
      final c = ServiceContainer();
      final disposed = <String>[];
      c.registerSingleton<String>('svc', dispose: disposed.add);
      c.unregister<String>();
      c.dispose();
      expect(disposed, ['svc']);
    });

    test('rollback after failed setup disposes each instance exactly once', () {
      final c = ServiceContainer();
      final disposed = <String>[];
      c.registerSingleton<String>('base', dispose: disposed.add);
      final snapshot = c.capture();
      // Simulate a plugin setup that overwrites a key and then fails.
      c.registerSingleton<String>('replacement', dispose: disposed.add);
      c.restore(snapshot);
      expect(c.resolve<String>(), 'base');
      c.dispose();
      expect(disposed, ['replacement', 'base']);
    });

    test('reregister after restore keeps the restored instance alive', () {
      final c = ServiceContainer();
      final disposed = <String>[];
      c.registerSingleton<String>('original', dispose: disposed.add);
      final snapshot = c.capture();
      c.registerSingleton<String>('newer', dispose: disposed.add);
      c.restore(snapshot);
      expect(c.resolve<String>(), 'original');
      c.unregister<String>();
      expect(disposed, ['newer', 'original']);
    });
  });
}
